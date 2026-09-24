import AppKit
import Darwin
import LlamaScopeCore
import SwiftUI

/// Włącznik pośrednika (§12).
///
/// Uruchamia **osobny program**, a nie własny wątek. To nie jest wygoda
/// implementacyjna — to jedyny sposób, żeby „wyłączony" znaczyło coś
/// sprawdzalnego. Aplikacja nie linkuje ani grama kodu pośrednika (`nm` na
/// binarce tego dowodzi), więc dopóki tego procesu nie ma, obietnica z §9
/// trzyma się sama, bez proszenia nikogo o zaufanie.
@MainActor
final class ProxyControl: ObservableObject {
    @Published private(set) var presence: ProxyPresence = .off

    private let port: UInt16 = 11435
    private var process: Process?

    /// Program leży w `Contents/MacOS/` obok aplikacji — jest częścią
    /// pakietu, ale osobnym plikiem wykonywalnym.
    private var executable: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/LlamaScopeProxy")
    }

    init() {
        // Aplikacja mogła zostać ubita, a pośrednik przeżyć. Pytamy port,
        // zamiast zakładać, że zastaliśmy czysto.
        refreshWhenIdle()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func toggle() {
        presence.isRunning ? stop() : start()
    }

    func start() {
        // `process == nil`, a nie samo `!isRunning` — między kliknięciem
        // a zajęciem portu stan brzmi „startuje" i drugie wejście tutaj
        // uruchomiłoby drugi proces, o którym nic byśmy już nie wiedzieli.
        guard !presence.isRunning, process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            presence = .failed(reason: "nie znalazłem programu pośrednika w pakiecie aplikacji")
            return
        }
        if Self.somethingListens(on: port) {
            presence = .foreign(port: port)
            return
        }

        let process = Process()
        process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment["LLAMASCOPE_PORT"] = String(port)
        environment["LLAMASCOPE_OBSERVATIONS"] = AppLog.defaultDirectory
            .appendingPathComponent("obserwacje.jsonl").path
        process.environment = environment
        // Wyjście pośrednika idzie do jego własnego pliku; tutaj nie ma go
        // kto czytać, a nieczytana rura po kilkuset kilobajtach zatrzymuje
        // proces, który ją zapełnił.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in
                self?.process = nil
                self?.presence = status == 0 || status == SIGTERM
                    ? .off
                    : .failed(reason: "pośrednik zakończył się z kodem \(status)")
            }
        }

        do {
            try process.run()
            self.process = process
            presence = .starting
            AppLog.shared.write("pośrednik: uruchomiony, pid \(process.processIdentifier)")
            confirmListening()
        } catch {
            presence = .failed(reason: error.localizedDescription)
            AppLog.shared.write("pośrednik: nie udało się uruchomić — \(error)")
        }
    }

    func stop() {
        guard let process, process.isRunning else {
            // Nie „wyłączony" z rozpędu: jeżeli na porcie nadal coś siedzi,
            // to nie nasza rzecz i nie wolno o tym napisać uspokajająco.
            refreshWhenIdle()
            return
        }
        // SIGTERM, nie SIGKILL: pośrednik ma zdążyć domknąć plik obserwacji.
        process.terminate()

        // Czekamy, bo to jest cały sens tego przycisku — po powrocie z niego
        // procesu ma nie być. „Wyłączam, sprawdź za chwilę" byłoby obietnicą
        // bez pokrycia, a tego przycisku dotyczy §12 najdosłowniej.
        //
        // Ale czekamy **z terminem**. `waitUntilExit()` bez ograniczenia
        // zawiesiłby cały pasek menu, gdyby pośrednik kiedyś nie odszedł po
        // SIGTERM-ie; zawieszona aplikacja to gorsza awaria niż ta, przed
        // którą się bronimy. Mierzone: schodzi w kilkanaście milisekund.
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            AppLog.shared.write("pośrednik: nie odszedł po SIGTERM, wysyłam SIGKILL")
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }

        self.process = nil
        presence = .off
        AppLog.shared.write("pośrednik: zatrzymany")
    }

    /// Start nie jest natychmiastowy — port zajmuje się po chwili. Dopóki go
    /// nie zajmie, stan brzmi „startuje", a nie „słucha".
    private func confirmListening() {
        Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard process?.isRunning == true else { return }
                if Self.somethingListens(on: port) {
                    presence = .listening(port: port)
                    return
                }
            }
            if process?.isRunning == true {
                presence = .failed(reason: "proces działa, ale nie zajął portu \(port)")
            }
        }
    }

    private func refreshWhenIdle() {
        presence = Self.somethingListens(on: port) ? .foreign(port: port) : .off
    }

    /// Czy ktokolwiek słucha na tym porcie. Sprawdzamy próbą zajęcia go —
    /// pytanie „czy port jest wolny" ma dokładnie jedną uczciwą odpowiedź
    /// i jest nią wynik `bind`, a nie nasza pamięć o tym, co uruchomiliśmy.
    private static func somethingListens(on port: UInt16) -> Bool {
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        guard handle >= 0 else { return false }
        defer { close(handle) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result != 0 && errno == EADDRINUSE
    }
}
