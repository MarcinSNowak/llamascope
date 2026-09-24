import Foundation

/// Nagłówek żądania HTTP, rozebrany na tyle, na ile pośrednik potrzebuje.
///
/// Własny rozbiór zamiast biblioteki, bo zależność w narzędziu, którego
/// jedynym argumentem jest „nie łączy się z niczym poza Twoim 127.0.0.1",
/// kosztuje więcej niż sto linii kodu: każda zależność to kod, którego
/// użytkownik nie sprawdzi, a którym każemy mu ufać.
public struct HTTPRequestHead: Sendable, Equatable {
    public let method: String
    public let target: String
    public let headers: [(name: String, value: String)]

    public init(method: String, target: String, headers: [(name: String, value: String)]) {
        self.method = method
        self.target = target
        self.headers = headers
    }

    public static func == (lhs: HTTPRequestHead, rhs: HTTPRequestHead) -> Bool {
        lhs.method == rhs.method && lhs.target == rhs.target
            && lhs.headers.map { [$0.name, $0.value] } == rhs.headers.map { [$0.name, $0.value] }
    }

    /// Ścieżka bez części zapytania.
    public var path: String { String(target.split(separator: "?", maxSplits: 1)[0]) }

    public func value(for name: String) -> String? {
        let wanted = name.lowercased()
        return headers.first { $0.name.lowercased() == wanted }?.value
    }

    public var contentLength: Int { value(for: "Content-Length").flatMap(Int.init) ?? 0 }

    public var isChunked: Bool {
        (value(for: "Transfer-Encoding") ?? "").lowercased().contains("chunked")
    }

    /// Nagłówki, których nie wolno przepisywać między połączeniami —
    /// dotyczą pojedynczego skoku, a nie treści.
    public static let hopByHop: Set<String> = [
        "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
        "te", "trailers", "transfer-encoding", "upgrade", "content-length",
    ]

    public var forwardableHeaders: [(name: String, value: String)] {
        headers.filter { !HTTPRequestHead.hopByHop.contains($0.name.lowercased()) }
    }

    /// Rozbiera nagłówek. `nil` znaczy, że to nie jest żądanie HTTP, którym
    /// umiemy się zająć — wtedy połączenie zamykamy, zamiast zgadywać.
    public static func parse(_ text: String) -> HTTPRequestHead? {
        var lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        lines.removeFirst()

        var headers: [(name: String, value: String)] = []
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers.append((
                name: String(line[line.startIndex..<colon]),
                value: String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
            ))
        }
        return HTTPRequestHead(
            method: String(parts[0]), target: String(parts[1]), headers: headers
        )
    }
}

/// Zmiana, którą pośrednik wprowadza do cudzego żądania — jedna jedyna.
public enum RequestRewrite {
    /// Dopisuje `stream_options.include_usage` do strumieniowanych żądań
    /// po `/v1`.
    ///
    /// Zmierzone 2026-09-18 na Ollamie 0.32.14: w strumieniu po `/v1`
    /// `usage` nie przychodzi **ani razu**, dopóki klient o nie nie
    /// poprosi. Wykrywanie ucięcia to przeżywa, bo porównuje szacunek
    /// z oknem i odpowiedzi nie potrzebuje — ale kalibrator zostaje bez
    /// próbek, czyli na startowym paśmie, i ostrzega od ~55% okna **bez
    /// końca**, zamiast przez pierwsze kilka żądań.
    ///
    /// To jest jedyne miejsce, w którym pośrednik zmienia cudzy ruch, i ma
    /// takie pozostać. Parametr dotyczy wyłącznie tego, co serwer **dopisze
    /// do swojej odpowiedzi**; nie zmienia promptu, modelu ani wyniku.
    public static func withUsageRequested(body: Data, path: String) -> Data {
        guard path.hasPrefix("/v1/"),
              let value = JSONValue.parse(body),
              case let .object(fields) = value,
              case .bool(true) = fields["stream"] ?? .null
        else { return body }

        var options: [String: JSONValue]
        if case let .object(existing) = fields["stream_options"] ?? .null {
            // Klient, który sam o to poprosił, ma zostać przy swoim.
            guard existing["include_usage"] == nil else { return body }
            options = existing
        } else {
            options = [:]
        }
        options["include_usage"] = .bool(true)

        var updated = fields
        updated["stream_options"] = .object(options)
        return Data(JSONValue.object(updated).compactJSON.utf8)
    }
}

/// Wyciąga z odpowiedzi ostatni obiekt niosący liczniki tokenów.
///
/// Dwa kształty: własny Ollamy (`prompt_eval_count` w ostatniej linii JSON)
/// i OpenAI-owy (`usage`, w strumieniu jako linie `data: {...}`).
public enum ResponseSummary {
    public static func tokens(in data: Data) -> (prompt: Int?, generated: Int?)? {
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n").reversed() {
            var candidate = line.trimmingCharacters(in: .whitespaces)
            if candidate.hasPrefix("data:") {
                candidate = String(candidate.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
            guard !candidate.isEmpty, candidate != "[DONE]",
                  let value = JSONValue.parse(Data(candidate.utf8))
            else { continue }

            if let usage = value["usage"], case .object = usage {
                return (usage["prompt_tokens"]?.intValue, usage["completion_tokens"]?.intValue)
            }
            if value["prompt_eval_count"] != nil || value["done"] != nil {
                return (value["prompt_eval_count"]?.intValue, value["eval_count"]?.intValue)
            }
        }
        return nil
    }
}
