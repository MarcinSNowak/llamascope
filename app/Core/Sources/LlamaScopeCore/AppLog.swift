import Foundation
import os

/// Własny log aplikacji (§10) — osobny od logu Ollamy, o tym, co aplikacja
/// robiła i **czego nie zrozumiała**.
///
/// Powstaje przed pierwszym wydaniem, a nie po nim, i to nie jest kwestia
/// porządku. Mamy jedną maszynę (M2 Pro, 32 GB), a pytanie z §15 o M1, M3,
/// M4 i warianty Pro/Max/Ultra da się zamknąć wyłącznie zgłoszeniami od
/// ludzi. Pole dopisane po zebraniu pierwszych zgłoszeń unieważnia te
/// zgłoszenia — dlatego komplet pól musi być od pierwszego dnia.
///
/// Zgodność z §9 zostaje nienaruszona: **to się tylko zapisuje lokalnie.**
/// Ta klasa nie ma ani jednego połączenia sieciowego i mieć nie będzie.
public final class AppLog: @unchecked Sendable {
    /// Zwyczajowe miejsce na macOS: widoczne w Console.app i kasowalne przez
    /// użytkownika bez naszej pomocy.
    public static let defaultDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/LlamaScope", isDirectory: true)

    /// Twardy limit z §10. Narzędzie do pilnowania cudzej pamięci nie może
    /// samo zapychać dysku — pięć plików po megabajcie i ani bajta więcej.
    public static let defaultMaxBytes = 1_000_000
    public static let defaultKeep = 5

    public let directory: URL
    /// Nazwa pliku bez rozszerzenia. Pośrednik (§12) jest osobnym procesem
    /// i pisze do osobnego pliku — dwa procesy dopisujące do jednego pliku
    /// dałyby log, w którym nie da się dojść, kto co zrobił.
    public let name: String
    private let maxBytes: Int
    /// Liczba plików razem z bieżącym. Jawna, bo paczka diagnostyczna (§10)
    /// czyta log z powrotem i musi wiedzieć, ile plików w ogóle istnieje.
    public let keep: Int
    private let fileManager: FileManager
    private let clock: @Sendable () -> Date
    private let lock = NSLock()

    /// Kanał do `os_log`, czyli bieżąca diagnostyka w Console.app. Plik jest
    /// do eksportu, ten kanał do patrzenia na żywo (§10).
    private let live: Logger

    public static let shared = AppLog()

    public init(
        directory: URL = AppLog.defaultDirectory,
        name: String = "llamascope",
        maxBytes: Int = AppLog.defaultMaxBytes,
        keep: Int = AppLog.defaultKeep,
        fileManager: FileManager = .default,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.name = name
        self.live = Logger(
            subsystem: "com.qshmobile.LlamaScope",
            category: name == "llamascope" ? "monitor" : name
        )
        self.maxBytes = maxBytes
        self.keep = keep
        self.fileManager = fileManager
        self.clock = clock
    }

    public var currentFile: URL { directory.appendingPathComponent("\(name).log") }

    /// Plik numer `index` po rotacji. Zero to plik bieżący.
    public func file(_ index: Int) -> URL {
        index == 0 ? currentFile : directory.appendingPathComponent("\(name).\(index).log")
    }

    public func write(_ message: String) {
        live.log("\(message, privacy: .public)")

        let line = "\(Self.stamp.string(from: clock())) \(message)\n"
        lock.lock()
        defer { lock.unlock() }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            rotateIfNeeded(adding: line.utf8.count)
            if let handle = try? FileHandle(forWritingTo: currentFile) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } else {
                try Data(line.utf8).write(to: currentFile)
            }
        } catch {
            // Świadomie po cichu. Aplikacja, która nie może zapisać własnego
            // logu, nie ma prawa z tego powodu przestać pokazywać stanu
            // Ollamy — log jest narzędziem do zgłoszeń, a nie celem.
            live.error("nie udało się zapisać do pliku logu: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rotateIfNeeded(adding bytes: Int) {
        let size = (try? fileManager.attributesOfItem(atPath: currentFile.path)[.size] as? NSNumber)??.intValue ?? 0
        guard size > 0, size + bytes > maxBytes else { return }

        // Najstarszy wypada. `keep` to liczba plików razem z bieżącym.
        try? fileManager.removeItem(at: file(keep - 1))
        for index in stride(from: keep - 2, through: 0, by: -1) {
            let from = file(index)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            try? fileManager.moveItem(at: from, to: file(index + 1))
        }
    }

    /// Czas lokalny, sekundowo. Bez ułamków — to jest log do czytania
    /// ludzkim okiem w zgłoszeniu, nie ślad do korelacji maszynowej.
    ///
    /// Nie `private`, bo ten sam format służy do czytania logu z powrotem
    /// (`AppLogArchive`). Drugi opis tego samego znacznika czasu rozjechałby
    /// się z pierwszym przy pierwszej zmianie i paczka diagnostyczna po cichu
    /// przestałaby znajdować „ostatnią godzinę".
    static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

/// Wiersze, od których zaczyna się każdy log — dokładnie tabela z §10.
///
/// Osobno od `AppLog`, bo to jest **treść**, a nie zapisywanie, i jako treść
/// ma swój test. Brak choćby jednego z tych pól kosztuje przy zgłoszeniu
/// dwie tury korespondencji, a połowa zgłoszeń urywa się po pierwszej.
public enum StartupReport {
    public static func lines(
        profile: HardwareProfile,
        gpu: GPUReading,
        logPath: String?,
        searchedPaths: [String] = OllamaLogLocation.knownPaths,
        ollamaHost: URL
    ) -> [String] {
        var lines = ["LlamaScope startuje", profile.logLine, gpu.logLine]

        // Skąd bierzemy log Ollamy i **jak** go znaleźliśmy — Homebrew
        // kontra instalator .app to dwa różne miejsca i różnica bywa
        // powodem zgłoszenia.
        switch logPath {
        case let .some(path):
            lines.append("log Ollamy: \(path)")
        case .none:
            // Nie to samo co „nie widzę ucięć” i musi się różnić
            // w zgłoszeniu: jedno jest ograniczeniem, drugie awarią.
            lines.append("log Ollamy: NIE ZNALEZIONY — szukano w \(searchedPaths.joined(separator: ", "))")
        }

        lines.append("serwer Ollamy: \(ollamaHost.absoluteString)")
        return lines
    }
}

/// Przygotowanie logu do wysłania **ręką użytkownika** (§9, §10).
///
/// Nic tu nie wysyła. To jest tylko czyszczenie tekstu, który człowiek
/// zobaczy, zanim zdecyduje, czy wkleić go do zgłoszenia — a zobaczyć musi,
/// bo inaczej „zbierz diagnostykę” byłoby prośbą o zaufanie w ciemno.
public enum DiagnosticsText {
    /// Ścieżki domowe zawierają imię i nazwisko częściej, niż ludzie o tym
    /// pamiętają w chwili wklejania logu do publicznego zgłoszenia.
    public static func anonymized(_ text: String) -> String {
        // Bez ukośnika na końcu: wzorzec go nie zjada, więc dopisany
        // zrobiłby „/Users/<użytkownik>//Library".
        text.replacing(#//Users/[^/\s]+/#, with: "/Users/<użytkownik>")
    }

    /// Linie z cudzego logu bywają długie i nie wiemy z góry, co w nich
    /// jest. Przycinamy, bo log aplikacji ma nieść **kształt** linii, której
    /// nie zrozumieliśmy, a nie jej całą zawartość.
    public static let quotedLineLimit = 300

    public static func shortened(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > quotedLineLimit else { return trimmed }
        return trimmed.prefix(quotedLineLimit) + "… [przycięte]"
    }
}
