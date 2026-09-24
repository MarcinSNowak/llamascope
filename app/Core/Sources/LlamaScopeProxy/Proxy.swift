import Foundation
import LlamaScopeCore
import LlamaScopeProxyCore
import Network

/// Ustawienia pośrednika. Wyłącznie zmienne środowiska — pośrednik nie ma
/// pliku konfiguracyjnego, bo ma się dać uruchomić i zabić jedną linią.
struct Settings {
    var port: UInt16 = 11435
    var upstream = URL(string: "http://127.0.0.1:11434")!
    var observations: URL?
    var toTerminal = true

    static func fromEnvironment() -> Settings {
        var settings = Settings()
        let environment = ProcessInfo.processInfo.environment
        if let port = environment["LLAMASCOPE_PORT"].flatMap(UInt16.init) {
            settings.port = port
        }
        if let upstream = environment["LLAMASCOPE_UPSTREAM"].flatMap(URL.init(string:)) {
            settings.upstream = upstream
        }
        if let path = environment["LLAMASCOPE_OBSERVATIONS"] {
            settings.observations = URL(fileURLWithPath: path)
        }
        return settings
    }
}

/// Pamięć między żądaniami: pasmo znaków na token i sufity modeli.
actor ProxyState {
    private var calibrator = Calibrator()
    private var maximums: [String: Int] = [:]
    private var asked: Set<String> = []

    func analyse(
        path: String, body: JSONValue, window: ContextWindow?, reportedTokens: Int?
    ) -> RequestReport? {
        RequestAnalyst.analyse(
            path: path, body: body, window: window,
            reportedTokens: reportedTokens, calibrator: &calibrator
        )
    }

    /// Sufit modelu pytamy raz. Nie zmienia się w trakcie pracy, a każde
    /// `/api/show` to kolejne żądanie do serwera, którego nikt nas nie prosił
    /// o wysyłanie.
    func maximum(for model: String, from upstream: Upstream) async -> Int? {
        if let known = maximums[model] { return known }
        guard !asked.contains(model) else { return nil }
        asked.insert(model)
        let maximum = await upstream.maximum(model: model)
        if let maximum { maximums[model] = maximum }
        return maximum
    }
}

struct Proxy {
    let settings: Settings
    let upstream: Upstream
    let state: ProxyState
    let log: ObservationLog

    /// Ile ostatnich bajtów odpowiedzi trzymamy, żeby odczytać liczniki
    /// tokenów. Liczniki są na samym końcu strumienia, więc ogon wystarcza —
    /// a odpowiedź może mieć megabajty i trzymanie jej w całości byłoby
    /// kupowaniem pamięci za nic.
    static let tailBytes = 64 * 1024

    func serve(_ connection: NWConnection) async {
        let client = ClientConnection(connection)
        defer { Task { await client.close() } }
        // Jedno połączenie, wiele żądań — klienci Ollamy trzymają je otwarte.
        while true {
            do {
                guard try await handleOne(on: client) else { return }
            } catch {
                return
            }
        }
    }

    /// `false` znaczy: to połączenie się skończyło.
    private func handleOne(on client: ClientConnection) async throws -> Bool {
        guard let (box, rest) = try await client.readHead(),
              let head = HTTPRequestHead.parse(box.text)
        else { return false }

        var body = Data()
        if head.contentLength > 0 {
            body = try await client.readBody(length: head.contentLength, alreadyRead: rest)
        } else if head.isChunked {
            // Żaden znany klient Ollamy tak nie wysyła; zgadywanie byłoby
            // gorsze niż szczere „nie umiem".
            try await refuse(on: client, status: "501 Not Implemented",
                             message: "pośrednik nie przyjmuje żądań w kodowaniu chunked")
            return false
        }

        let analysed = head.method == "POST" && ProxyPaths.analysed.contains(head.path)
        let parsed = analysed ? JSONValue.parse(body) : nil

        var window: ContextWindow?
        if let parsed {
            let model = parsed["model"]?.stringValue ?? ""
            // Jawne `num_ctx` wygrywa: to ono zadecyduje o przeładowaniu
            // modelu, więc to ono jest oknem tego żądania.
            if let declared = ContextWindow.declared(in: parsed) {
                window = declared
            } else if !model.isEmpty {
                window = await upstream.loadedWindow(model: model)
            }
        }

        let forwarded = analysed
            ? RequestRewrite.withUsageRequested(body: body, path: head.path)
            : body

        let answer: (status: Int, headers: [String: String], bytes: URLSession.AsyncBytes)
        do {
            answer = try await upstream.forward(
                method: head.method, path: head.target,
                headers: head.forwardableHeaders, body: forwarded
            )
        } catch {
            await log.say(["nie mogę się połączyć z \(upstream.base.absoluteString): "
                           + error.localizedDescription], alarming: true)
            try await refuse(on: client, status: "502 Bad Gateway",
                             message: "pośrednik nie dosięgnął Ollamy pod "
                                 + upstream.base.absoluteString)
            return false
        }

        let tail = try await stream(answer, to: client, keepingTail: parsed != nil)

        if let parsed {
            let reported = ResponseSummary.tokens(in: tail)?.prompt
            if let report = await state.analyse(
                path: head.path, body: parsed, window: window, reportedTokens: reported
            ) {
                let maximum = await state.maximum(for: report.model, from: upstream)
                await log.record(report, modelMaximum: maximum)
            }
        }
        return true
    }

    /// Przepisuje odpowiedź do klienta **w locie**, kawałek po kawałku.
    /// Zawsze kodowaniem chunked, bo długości z góry nie znamy i znać
    /// nie chcemy — czekanie na całość zabrałoby klientowi strumień.
    private func stream(
        _ answer: (status: Int, headers: [String: String], bytes: URLSession.AsyncBytes),
        to client: ClientConnection,
        keepingTail: Bool
    ) async throws -> Data {
        var head = "HTTP/1.1 \(answer.status) \(Self.reason(answer.status))\r\n"
        for (name, value) in answer.headers
        where !HTTPRequestHead.hopByHop.contains(name.lowercased())
            // URLSession rozpakowuje treść sam, więc przepisany nagłówek
            // o kompresji byłby kłamstwem.
            && name.lowercased() != "content-encoding" {
            head += "\(name): \(value)\r\n"
        }
        head += "Transfer-Encoding: chunked\r\nConnection: keep-alive\r\n\r\n"
        try await client.send(Data(head.utf8))

        var buffer = Data()
        var tail = Data()
        func flush() async throws {
            guard !buffer.isEmpty else { return }
            try await client.send(Data(String(format: "%X\r\n", buffer.count).utf8)
                + buffer + Data("\r\n".utf8))
            buffer.removeAll(keepingCapacity: true)
        }

        for try await byte in answer.bytes {
            buffer.append(byte)
            if keepingTail {
                tail.append(byte)
                if tail.count > Self.tailBytes * 2 {
                    tail = Data(tail.suffix(Self.tailBytes))
                }
            }
            // Strumienie Ollamy są liniowe: pełna linia to pełny token
            // u klienta.
            if byte == 0x0A || buffer.count >= 4096 { try await flush() }
        }
        try await flush()
        try await client.send(Data("0\r\n\r\n".utf8))
        return tail
    }

    private func refuse(on client: ClientConnection, status: String, message: String) async throws {
        let body = Data(message.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        try await client.send(Data(head.utf8) + body)
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return ""
        }
    }
}
