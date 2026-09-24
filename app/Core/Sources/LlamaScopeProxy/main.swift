import Foundation
import LlamaScopeCore
import LlamaScopeProxyCore
import LlamaScopeText
import Network

// Pośrednik z §12 — osobny proces, uruchamiany ręcznie.
//
// Osobny, bo obietnica z §9 („tryb domyślny nie ma technicznej możliwości
// zobaczenia treści promptów") ma być sprawdzalna, a nie deklarowana.
// Wyłączony pośrednik to proces, którego **nie ma** w Monitorze aktywności
// ani w `lsof -i`. Aplikacja z paska menu nie linkuje ani tego programu, ani
// jego rdzenia — nie jest to kwestia zaufania, tylko tego, co w ogóle jest
// w binarce.

let settings = Settings.fromEnvironment()
let polish = settings.language == .polish
let text = AppLog(name: "proxy")
let observations = ObservationLog(
    file: settings.observations, text: text, toTerminal: settings.toTerminal,
    language: settings.language
)

let listener: NWListener
do {
    let parameters = NWParameters.tcp
    // Wyłącznie pętla zwrotna. Pośrednik widzi treści promptów, więc nie ma
    // stanu, w którym wolno mu słuchać na adresie z sieci.
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .init(
        rawValue: settings.port
    )!)
    listener = try NWListener(using: parameters)
} catch {
    let message = polish
        ? "nie mogę otworzyć portu: \(error)"
        : "cannot open the port: \(error)"
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let upstream = Upstream(base: settings.upstream)
let proxy = Proxy(
    settings: settings, upstream: upstream,
    state: ProxyState(language: settings.language), log: observations
)

listener.stateUpdateHandler = { state in
    switch state {
    case .ready:
        let lines = polish ? [
            "pośrednik słucha na http://127.0.0.1:\(settings.port)",
            "przekazuje do \(settings.upstream.absoluteString)",
            "log pośrednika: \(text.currentFile.path)",
            settings.observations.map { "obserwacje: \($0.path)" }
                ?? "obserwacje: nigdzie (ustaw LLAMASCOPE_OBSERVATIONS=…)",
            "ustaw w kliencie OLLAMA_HOST=http://127.0.0.1:\(settings.port) "
                + "albo base_url .../v1",
            "Ctrl-C kończy — wtedy tego procesu po prostu nie ma.",
        ] : [
            "proxy listening on http://127.0.0.1:\(settings.port)",
            "forwarding to \(settings.upstream.absoluteString)",
            "proxy log: \(text.currentFile.path)",
            settings.observations.map { "observations: \($0.path)" }
                ?? "observations: nowhere (set LLAMASCOPE_OBSERVATIONS=…)",
            "point your client at OLLAMA_HOST=http://127.0.0.1:\(settings.port) "
                + "or base_url .../v1",
            "Ctrl-C ends it — and then this process simply does not exist.",
        ]
        Task { await observations.say(lines) }

    case let .failed(error):
        // Zajęty port jest najczęstszym powodem i ma jedną konkretną radę,
        // a nie kod błędu do wyszukania.
        var message = polish
            ? "pośrednik nie wystartował: \(error)"
            : "the proxy did not start: \(error)"
        if case let .posix(code) = error, code == .EADDRINUSE {
            message = polish
                ? "port \(settings.port) jest zajęty — sprawdź, kto go trzyma:\n"
                    + "   lsof -nP -iTCP:\(settings.port) -sTCP:LISTEN\n"
                    + "   (albo wskaż inny: LLAMASCOPE_PORT=11436)"
                : "port \(settings.port) is taken — find out who holds it:\n"
                    + "   lsof -nP -iTCP:\(settings.port) -sTCP:LISTEN\n"
                    + "   (or pick another one: LLAMASCOPE_PORT=11436)"
        }
        FileHandle.standardError.write(Data((message + "\n").utf8))
        text.write(message)
        exit(1)

    default:
        break
    }
}

listener.newConnectionHandler = { connection in
    Task { await proxy.serve(connection) }
}

listener.start(queue: .global(qos: .userInitiated))
dispatchMain()
