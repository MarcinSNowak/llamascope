import Foundation

/// Odpowiedź serwera na pytanie „co teraz trzymasz".
///
/// Dwa przypadki, nie tablica z pustką. „Nic nie jest załadowane" i „nie ma
/// z kim rozmawiać" wyglądają tak samo tylko dla kogoś, kto patrzy na długość
/// listy — a dla użytkownika to różnica między spokojem a awarią. Ta sama
/// zasada co przy nieudanym odczycie GPU (§10).
public enum OllamaStatus: Sendable, Equatable {
    case running(models: [LoadedModel])
    case notResponding(reason: String)
}

/// Klient `/api/ps`. Jedno wywołanie, bez stanu, bez zależności.
///
/// Adres bierzemy z `OLLAMA_HOST`, bo kto przestawił port serwera, ten
/// przestawił go też dla nas — inaczej aplikacja mówiłaby „Ollama nie
/// odpowiada" o serwerze działającym obok.
public struct OllamaClient: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    public let baseURL: URL
    private let fetch: Fetch

    public static func hostFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let raw = environment["OLLAMA_HOST"] ?? "http://127.0.0.1:11434"
        // OLLAMA_HOST bywa podane bez schematu — „localhost:11434" jest
        // w dokumentacji Ollamy formą zalecaną i URL(string:) łyka to jako
        // adres ze schematem „localhost". Stąd ta poprawka.
        let withScheme = raw.contains("://") ? raw : "http://\(raw)"
        return URL(string: withScheme) ?? URL(string: "http://127.0.0.1:11434")!
    }

    public init(baseURL: URL? = nil, fetch: Fetch? = nil) {
        self.baseURL = baseURL ?? Self.hostFromEnvironment()
        self.fetch = fetch ?? { url in
            var request = URLRequest(url: url)
            // Dwie sekundy jak w wersji pythonowej. Pasek menu odświeża się
            // co sekundę; czekanie dłużej zamraża odczyt na dobre.
            request.timeoutInterval = 2
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw OllamaError.badStatus(http.statusCode)
            }
            return data
        }
    }

    public enum OllamaError: Error, Equatable {
        case badStatus(Int)
    }

    public func processStatus() async -> OllamaStatus {
        do {
            let data = try await fetch(baseURL.appendingPathComponent("api/ps"))
            return .running(models: try Self.decodeModels(from: data))
        } catch let error as OllamaError {
            if case let .badStatus(code) = error {
                return .notResponding(reason: "serwer odpowiedział kodem \(code)")
            }
            return .notResponding(reason: "\(error)")
        } catch let error as DecodingError {
            // Odróżnione od braku połączenia świadomie: zmiana kształtu
            // odpowiedzi jest naszym błędem do naprawienia, a nie sprawą
            // użytkownika, i musi dać się odróżnić w zgłoszeniu (§10).
            return .notResponding(reason: "odpowiedź w nieznanym kształcie: \(error)")
        } catch {
            return .notResponding(reason: (error as NSError).localizedDescription)
        }
    }

    static func decodeModels(from data: Data) throws -> [LoadedModel] {
        let decoder = JSONDecoder()
        return try decoder.decode(ProcessList.self, from: data).models.map(\.asLoadedModel)
    }

    private struct ProcessList: Decodable {
        let models: [Entry]

        // `/api/ps` bez załadowanego modelu zwraca `{"models": []}`, ale
        // starsze wersje zwracały `{"models": null}`. Jedno i drugie znaczy
        // to samo i nie może być błędem rozbioru.
        //
        // Brak samego klucza to co innego i **musi** być błędem. Przez chwilę
        // nie był — i wtedy odpowiedź o zupełnie obcym kształcie, na przykład
        // z serwera stojącego na tym porcie po czymś innym, była czytana jako
        // „nic nie jest załadowane". Czyli spokój. Złapane testem.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.models) else {
                throw DecodingError.keyNotFound(CodingKeys.models, DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "odpowiedź bez klucza „models” — to nie jest /api/ps"
                ))
            }
            models = try container.decodeIfPresent([Entry].self, forKey: .models) ?? []
        }

        enum CodingKeys: String, CodingKey { case models }
    }

    private struct Entry: Decodable {
        let name: String
        let size: UInt64
        let sizeVRAM: UInt64
        let contextLength: Int?
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case name, size
            case sizeVRAM = "size_vram"
            case contextLength = "context_length"
            case expiresAt = "expires_at"
        }

        var asLoadedModel: LoadedModel {
            LoadedModel(
                name: name,
                sizeBytes: size,
                sizeVRAMBytes: sizeVRAM,
                contextTokens: contextLength,
                expiresAt: expiresAt.flatMap(Self.parseDate)
            )
        }

        /// `expires_at` przychodzi jako „2026-09-21T09:54:35.520333+02:00" —
        /// sześć cyfr po kropce, czyli mikrosekundy. `ISO8601DateFormatter`
        /// z `.withFractionalSeconds` radzi sobie z tym na macOS, ale
        /// zapasowe przejście bez ułamka zostaje, bo Ollama pomija kropkę,
        /// gdy ułamek wypadnie zerowy.
        static func parseDate(_ text: String) -> Date? {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        }
    }
}
