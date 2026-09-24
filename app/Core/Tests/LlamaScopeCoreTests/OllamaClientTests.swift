import XCTest
@testable import LlamaScopeCore

final class OllamaClientTests: XCTestCase {
    /// Odpowiedź przepisana z żywego `/api/ps` (2026-09-21, llama3.2
    /// załadowany z `num_ctx: 512`), a nie ułożona pod dekoder.
    private let liveResponse = Data("""
    {"models":[{"name":"llama3.2:latest","model":"llama3.2:latest",
    "size":2112555580,"digest":"a80c4f17acd5",
    "details":{"parent_model":"","format":"gguf","family":"llama",
    "families":["llama"],"parameter_size":"3.2B","quantization_level":"Q4_K_M"},
    "expires_at":"2026-09-21T09:54:35.520333+02:00",
    "size_vram":2112555580,"context_length":512}]}
    """.utf8)

    private func client(returning data: Data) -> OllamaClient {
        OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!, fetch: { _ in data })
    }

    private func client(throwing error: Error) -> OllamaClient {
        OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!, fetch: { _ in throw error })
    }

    func testDecodesTheLiveResponse() async throws {
        guard case let .running(models) = await client(returning: liveResponse).processStatus() else {
            return XCTFail("spodziewana działająca Ollama")
        }
        let model = try XCTUnwrap(models.first)
        XCTAssertEqual(model.name, "llama3.2:latest")
        XCTAssertEqual(model.sizeBytes, 2_112_555_580)
        XCTAssertEqual(model.sizeVRAMBytes, 2_112_555_580)
        XCTAssertEqual(model.contextTokens, 512)
        XCTAssertEqual(model.bytesOutsideGPU, 0)
    }

    /// `expires_at` ma sześć cyfr po kropce. Gdyby nie przeszło, odliczanie
    /// „zwolni za 3 min" zniknęłoby po cichu — a to jedyna treść stanu 4.
    func testParsesTheMicrosecondTimestamp() async throws {
        guard case let .running(models) = await client(returning: liveResponse).processStatus(),
              let expires = models.first?.expiresAt
        else { return XCTFail("nie odczytano expires_at") }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 3600)!
        let parts = calendar.dateComponents([.hour, .minute, .second], from: expires)
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 54)
        XCTAssertEqual(parts.second, 35)
    }

    func testEmptyListMeansNothingLoadedNotAnError() async {
        guard case let .running(models) = await client(returning: Data(#"{"models":[]}"#.utf8)).processStatus() else {
            return XCTFail("pusta lista to nie jest awaria")
        }
        XCTAssertTrue(models.isEmpty)
    }

    /// Starsze wersje Ollamy zwracały `null` zamiast pustej tablicy. Jedno
    /// i drugie znaczy „nic nie trzymam" i nie może wyglądać jak awaria.
    func testNullListMeansTheSameAsEmpty() async {
        guard case let .running(models) = await client(returning: Data(#"{"models":null}"#.utf8)).processStatus() else {
            return XCTFail("null to nie jest awaria")
        }
        XCTAssertTrue(models.isEmpty)
    }

    func testServerDownIsNamedNotSilent() async {
        let down = URLError(.cannotConnectToHost)
        guard case let .notResponding(reason) = await client(throwing: down).processStatus() else {
            return XCTFail("brak połączenia ma dać „nie odpowiada”")
        }
        XCTAssertFalse(reason.isEmpty, "powód ma trafić do zgłoszenia, więc nie może być pusty")
    }

    /// Zmiana kształtu odpowiedzi to nasz błąd do naprawienia, a brak
    /// połączenia to sprawa użytkownika. W zgłoszeniu muszą się różnić.
    func testBrokenShapeIsToldApartFromNoConnection() async {
        guard case let .notResponding(reason) = await client(returning: Data(#"{"co":"innego"}"#.utf8)).processStatus() else {
            return XCTFail("nieznany kształt ma być zgłoszony")
        }
        XCTAssertTrue(reason.contains("nieznanym kształcie"), "dostaliśmy: \(reason)")
    }

    func testHTTPErrorCarriesTheCode() async {
        guard case let .notResponding(reason) = await client(throwing: OllamaClient.OllamaError.badStatus(503)).processStatus() else {
            return XCTFail("kod błędu ma być zgłoszony")
        }
        XCTAssertTrue(reason.contains("503"), "dostaliśmy: \(reason)")
    }

    func testHostComesFromTheEnvironment() {
        XCTAssertEqual(
            OllamaClient.hostFromEnvironment(["OLLAMA_HOST": "http://192.168.0.5:11434"]).absoluteString,
            "http://192.168.0.5:11434"
        )
        XCTAssertEqual(
            OllamaClient.hostFromEnvironment([:]).absoluteString,
            "http://127.0.0.1:11434"
        )
    }

    /// Dokumentacja Ollamy zaleca `OLLAMA_HOST` bez schematu. Bez tej
    /// poprawki `URL(string:)` czyta „localhost" jako schemat i aplikacja
    /// twierdzi „nie odpowiada" o serwerze działającym obok.
    func testHostWithoutSchemeStillWorks() {
        XCTAssertEqual(
            OllamaClient.hostFromEnvironment(["OLLAMA_HOST": "localhost:11434"]).absoluteString,
            "http://localhost:11434"
        )
    }

    /// Na żywej maszynie. Nie sprawdzamy, czy Ollama działa — sprawdzamy,
    /// że każda z dwóch odpowiedzi jest nazwana, a nie zgadnięta.
    func testAsksTheRealServer() async {
        switch await OllamaClient().processStatus() {
        case let .running(models):
            print("Ollama → odpowiada, modeli: \(models.count)")
            for model in models {
                print("  \(model.name), poza GPU: \(model.bytesOutsideGPU) B")
            }
        case let .notResponding(reason):
            print("Ollama → nie odpowiada: \(reason)")
        }
    }
}

/// Akcja pisząca. Sprawdzamy, co naprawdę idzie na drut — `keep_alive: 0`
/// to cała różnica między zwolnieniem pamięci a wygenerowaniem czegoś.
final class OllamaClientActionTests: XCTestCase {
    private let host = URL(string: "http://127.0.0.1:11434")!

    private func client(
        recording sent: Box<[(URL, Data)]>,
        answer: @escaping @Sendable () throws -> Data = { Data("{}".utf8) }
    ) -> OllamaClient {
        OllamaClient(baseURL: host, fetch: { _ in Data(#"{"models":[]}"#.utf8) }, post: { url, body in
            sent.value.append((url, body))
            return try answer()
        })
    }

    private func body(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func testUnloadAsksTheServerToDropTheModelNow() async {
        let sent = Box<[(URL, Data)]>([])
        let outcome = await client(recording: sent).unload(model: "qwen2.5-coder:14b")

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(sent.value.count, 1)
        XCTAssertEqual(sent.value[0].0.path, "/api/generate")
        let payload = body(sent.value[0].1)
        XCTAssertEqual(payload["model"] as? String, "qwen2.5-coder:14b")
        XCTAssertEqual(payload["keep_alive"] as? Int, 0, "bez keep_alive: 0 to nie jest zwolnienie")
        XCTAssertEqual(payload["stream"] as? Bool, false)
        // Żadnego promptu — nie prosimy o generowanie, tylko o wyrzucenie
        // modelu z pamięci.
        XCTAssertNil(payload["prompt"])
    }

    func testLoadAsksForTheSameModelWithoutDroppingIt() async {
        let sent = Box<[(URL, Data)]>([])
        let outcome = await client(recording: sent).load(model: "qwen2.5-coder:14b")

        XCTAssertEqual(outcome, .done)
        let payload = body(sent.value[0].1)
        XCTAssertEqual(payload["model"] as? String, "qwen2.5-coder:14b")
        XCTAssertNil(payload["keep_alive"], "ładowanie z keep_alive: 0 zwolniłoby model w tej samej chwili")
    }

    /// Nieudana akcja ma powiedzieć, czemu się nie udała. Milczenie po
    /// kliknięciu przycisku jest gorsze niż komunikat o błędzie.
    func testFailedActionCarriesTheReason() async {
        let sent = Box<[(URL, Data)]>([])
        let failing = client(recording: sent, answer: { throw OllamaClient.OllamaError.badStatus(500) })
        let outcome = await failing.unload(model: "qwen2.5-coder:14b")
        XCTAssertEqual(outcome, .failed(reason: "serwer odpowiedział kodem 500"))
    }
}
