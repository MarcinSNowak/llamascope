import Foundation
import LlamaScopeProxyCore

/// Rozmowa z prawdziwą Ollamą.
struct Upstream {
    let base: URL
    private let session: URLSession

    init(base: URL) {
        self.base = base
        let configuration = URLSessionConfiguration.ephemeral
        // Generowanie długiej odpowiedzi na dużym modelu potrafi trwać
        // minutami; limit liczony od ostatniego bajtu, nie od początku.
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 3600
        configuration.httpShouldUsePipelining = false
        session = URLSession(configuration: configuration)
    }

    /// Przekazuje żądanie i oddaje odpowiedź **strumieniem**. Pośrednik nie
    /// może czekać na całość: klient ma widzieć tokeny wtedy, kiedy widziałby
    /// je bez pośrednika.
    func forward(
        method: String, path: String, headers: [(name: String, value: String)], body: Data
    ) async throws -> (status: Int, headers: [String: String], bytes: URLSession.AsyncBytes) {
        guard let url = URL(string: path, relativeTo: base) else {
            throw ProxyError.upstreamUnreachable("nie umiem złożyć adresu dla \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        for header in headers where header.name.lowercased() != "host" {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if !body.isEmpty {
            request.httpBody = body
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        }

        let (bytes, response) = try await session.bytes(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            guard let key = key as? String, let value = value as? String else { continue }
            headers[key] = value
        }
        return (http?.statusCode ?? 502, headers, bytes)
    }

    private func ask(_ path: String, body: Data? = nil) async -> JSONValue? {
        guard let url = URL(string: path, relativeTo: base) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return JSONValue.parse(data)
    }

    /// Okno **załadowanego** modelu. Nie stała z Modelfile — Ollama dobiera
    /// okno przy ładowaniu do wolnej pamięci (§14), więc jedyna prawda jest
    /// w tym, co właśnie siedzi w pamięci.
    func loadedWindow(model: String) async -> ContextWindow? {
        guard let models = await ask("/api/ps")?["models"]?.arrayValue else { return nil }
        let match = models.first { $0["name"]?.stringValue == model }
            ?? models.first { ($0["model"]?.stringValue ?? "").hasPrefix(model) }
        guard let tokens = match?["context_length"]?.intValue, tokens > 0 else { return nil }
        return ContextWindow(tokens: tokens, source: .loadedModel)
    }

    /// Sufit modelu — ile najwyżej da się ustawić. Potrzebny, żeby nie radzić
    /// komuś okna, którego model nie przyjmie.
    func maximum(model: String) async -> Int? {
        let body = Data(JSONValue.object(["model": .string(model)]).compactJSON.utf8)
        guard case let .object(info)? = await ask("/api/show", body: body)?["model_info"]
        else { return nil }
        for (key, value) in info where key.hasSuffix(".context_length") {
            if let tokens = value.intValue, tokens > 0 { return tokens }
        }
        return nil
    }
}
