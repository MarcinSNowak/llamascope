import XCTest
@testable import LlamaScopeCore

/// Paczka diagnostyczna z §10 — treść, nie zapisywanie.
///
/// Te testy pilnują trzech obietnic złożonych w specyfikacji, w kolejności
/// od najdroższej do złamania: że w pliku nie ma treści promptów, że ścieżki
/// są zanonimizowane i że do zgłoszenia na GitHubie idą **same metadane**.
final class DiagnosticsTests: XCTestCase {
    // MARK: - Fragment cudzego logu

    /// Zdanie, które udaje wpis debugowy Ollamy. `OLLAMA_DEBUG=1` naprawdę
    /// wypisuje treść żądań, a użytkownik z włączonym debugiem to dokładnie
    /// ten sam człowiek, który przysyła zgłoszenie.
    private let secret = "moje hasło do banku i numer PESEL"

    func testExcerptQuotesOnlyLinesItCanName() {
        let text = """
        time=2026-09-25T08:00:00.000+02:00 level=INFO msg="truncating input prompt" limit=4096 prompt=7260 keep=5 new=258
        time=2026-09-25T08:00:01.000+02:00 level=DEBUG msg="\(secret)"
        time=2026-09-25T08:00:02.000+02:00 level=INFO msg="request" body="\(secret)"
        """

        let excerpt = OllamaLogExcerpt.take(fromText: text)
        XCTAssertEqual(excerpt.lines.count, 1)
        XCTAssertTrue(excerpt.lines[0].contains("truncating input prompt"))
        XCTAssertEqual(excerpt.skipped, 2)
    }

    /// Druga siatka: linia ze znanym markerem, ale długa. Przycięcie
    /// zostawiłoby trzysta znaków cudzej treści, więc odrzucamy w całości.
    func testKnownMarkerOnAnOverlongLineIsRejectedRatherThanCut() {
        let line = "msg=\"truncating input prompt\" "
            + String(repeating: "x", count: OllamaLogExcerpt.maxSafeLength)

        let excerpt = OllamaLogExcerpt.take(fromText: line)
        XCTAssertTrue(excerpt.lines.isEmpty)
        XCTAssertEqual(excerpt.skipped, 1)
    }

    /// Brak logu i log bez ciekawych linii to dwie różne diagnozy i nie mogą
    /// wyglądać tak samo (§10).
    func testMissingLogIsSaidOutLoudRatherThanComingBackEmpty() {
        let missing = OllamaLogExcerpt.take(fromFileAt: nil)
        XCTAssertTrue(missing.lines.isEmpty)
        XCTAssertNotNil(missing.problem)

        let quiet = OllamaLogExcerpt.take(fromText: "nic o nas\n")
        XCTAssertTrue(quiet.lines.isEmpty)
        XCTAssertNil(quiet.problem)
        XCTAssertEqual(quiet.skipped, 1)
    }

    // MARK: - Plik

    private func input(
        unrecognized: [AppLogArchive.Entry] = [],
        recent: [AppLogArchive.Entry] = [],
        excerpt: OllamaLogExcerpt = OllamaLogExcerpt(lines: [], skipped: 0)
    ) -> DiagnosticsReport.Input {
        DiagnosticsReport.Input(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            profile: HardwareProfile(
                chipName: "Apple M2 Pro", family: .apple(generation: 2, variant: .pro), cpuCores: 12, gpuCores: 19,
                memoryBytes: 34_359_738_368, macOSVersion: "Version 27.0",
                appVersion: "0.9.1 (3)"
            ),
            gpu: .reading(percent: 4, serviceClass: "AGXAccelerator", key: "Device Utilization %"),
            state: .asleep,
            ollamaHost: URL(string: "http://127.0.0.1:11434")!,
            ollamaVersion: .known("0.12.0"),
            ollama: .running(models: []),
            appLogPath: "/Users/marcin/Library/Logs/LlamaScope/llamascope.log",
            ollamaLogPath: "/opt/homebrew/var/log/ollama.log",
            recentEntries: recent,
            unrecognized: unrecognized,
            ollamaExcerpt: excerpt
        )
    }

    private func entry(_ message: String) -> AppLogArchive.Entry {
        AppLogArchive.Entry(time: Date(timeIntervalSince1970: 1_800_000_000), message: message)
    }

    func testFileCarriesEveryRowFromTheTableInSectionTen() {
        let text = DiagnosticsReport.text(input())

        XCTAssertTrue(text.contains("Apple M2 Pro"))
        XCTAssertTrue(text.contains("macOS Version 27.0"))
        XCTAssertTrue(text.contains("LlamaScope 0.9.1 (3)"))
        XCTAssertTrue(text.contains("wersja Ollamy: 0.12.0"))
        XCTAssertTrue(text.contains("http://127.0.0.1:11434"))
        XCTAssertTrue(text.contains("Ostatnia godzina"))
        XCTAssertTrue(text.contains("Linie nierozpoznane"))
        XCTAssertTrue(text.contains("Fragment logu Ollamy"))
    }

    func testAccountNameIsGoneFromEveryPathInTheFile() {
        let text = DiagnosticsReport.text(input(
            recent: [entry("log Ollamy: /Users/marcin/.ollama/logs/server.log")]
        ))

        XCTAssertFalse(text.contains("/Users/marcin/"))
        XCTAssertTrue(text.contains("/Users/<użytkownik>/Library/Logs/LlamaScope"))
        XCTAssertTrue(text.contains("/Users/<użytkownik>/.ollama/logs/server.log"))
    }

    /// Obietnica z tabeli §10 postawiona tam, gdzie da się ją sprawdzić:
    /// treść, której nie umiemy nazwać, nie wchodzi do pliku żadną drogą.
    func testPromptContentDoesNotReachTheFile() {
        let text = DiagnosticsReport.text(input(
            excerpt: OllamaLogExcerpt.take(
                fromText: "time=2026-09-25T08:00:01.000+02:00 level=DEBUG msg=\"\(secret)\"\n"
            )
        ))

        XCTAssertFalse(text.contains(secret))
        // Pominięcie ma być powiedziane liczbą, a nie przemilczane.
        XCTAssertTrue(text.contains("pominięto 1"))
    }

    /// Sekcja nierozpoznanych linii istnieje także wtedy, gdy jest pusta —
    /// „nic nie znalazłem" i „nie patrzyłem" mają się różnić w zgłoszeniu.
    func testUnrecognizedSectionExistsEvenWhenEmpty() {
        XCTAssertTrue(DiagnosticsReport.text(input()).contains("Linie nierozpoznane"))
    }

    func testOnlyTheLastUnrecognizedLinesAreQuotedAndTheRestAreCounted() {
        let many = (1...(DiagnosticsReport.unrecognizedQuoted + 5)).map {
            entry("\(AppLogArchive.unrecognizedPrefix) linia \($0)")
        }
        let text = DiagnosticsReport.text(input(unrecognized: many))

        XCTAssertTrue(text.contains("(pokazano ostatnie \(DiagnosticsReport.unrecognizedQuoted) z \(many.count))"))
        XCTAssertTrue(text.contains("linia \(many.count)"))
        XCTAssertFalse(text.contains("linia 1\n"))
    }

    // MARK: - Dokąd to idzie

    /// §10 stawia granicę wprost: treść zgłoszenia na GitHubie jest publiczna,
    /// więc idą tam **same metadane**, a plik użytkownik dołącza sam albo nie.
    func testIssueLinkCarriesMetadataOnlyAndNeverTheLog() throws {
        let leaky = entry("\(AppLogArchive.unrecognizedPrefix) \(secret)")
        let url = try XCTUnwrap(DiagnosticsReport.issueURL(input(
            unrecognized: [leaky],
            recent: [entry("/Users/marcin/tajne")],
            excerpt: OllamaLogExcerpt(lines: [secret], skipped: 0)
        )))
        let link = url.absoluteString.removingPercentEncoding ?? url.absoluteString

        XCTAssertFalse(link.contains(secret))
        XCTAssertFalse(link.contains("/Users/marcin"))
        XCTAssertTrue(link.contains("Apple M2 Pro"))
        // Sama liczba nierozpoznanych linii to metadana i ma tam być: mówi,
        // czy w ogóle warto prosić o plik.
        XCTAssertTrue(link.contains("unrecognized lines: 1"))
        XCTAssertTrue(link.hasPrefix("\(DiagnosticsReport.repository)/issues/new"))
    }

    func testMailFallbackGoesToTheCompanyAddress() throws {
        let url = try XCTUnwrap(DiagnosticsReport.mailtoURL(input()))
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:\(DiagnosticsReport.email)"))
    }

    func testFileNameCarriesTheHourSoASecondReportDoesNotOverwriteTheFirst() {
        let morning = DiagnosticsReport.fileName(at: Date(timeIntervalSince1970: 1_800_000_000))
        let later = DiagnosticsReport.fileName(at: Date(timeIntervalSince1970: 1_800_007_200))
        XCTAssertNotEqual(morning, later)
        XCTAssertTrue(morning.hasSuffix(".txt"))
    }

    // MARK: - Zbieranie

    func testCollectorTakesTheStateItWasGivenRatherThanComputingItAgain() async {
        let collector = DiagnosticsCollector(sources: DiagnosticsCollector.Sources(
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            profile: { self.input().profile },
            gpu: { .classNotFound(searched: ["AGXAccelerator"]) },
            ollamaHost: URL(string: "http://127.0.0.1:11434")!,
            ollamaVersion: { .unavailable(reason: "serwer odpowiedział kodem 404") },
            ollama: { .notResponding(reason: "połączenie odrzucone") },
            appLogPath: "/tmp/llamascope.log",
            entries: {
                [AppLogArchive.Entry(
                    time: Date(timeIntervalSince1970: 1_799_000_000), message: "dawno temu"
                )]
            },
            ollamaLogPath: nil,
            ollamaExcerpt: { OllamaLogExcerpt.take(fromFileAt: nil) }
        ))

        let collected = await collector.collect(state: .ollamaNotResponding(reason: "test"))
        let text = DiagnosticsReport.text(collected)

        XCTAssertTrue(text.contains("stan w chwili zbierania"))
        XCTAssertTrue(text.contains("wersja Ollamy: NIEZNANA"))
        XCTAssertTrue(text.contains("BRAK ODCZYTU"))
        XCTAssertTrue(text.contains("log Ollamy: NIE ZNALEZIONY"))
        // Wpis sprzed dziewięciu dni nie jest „ostatnią godziną”.
        XCTAssertFalse(text.contains("dawno temu"))
    }
}
