import Foundation

/// Zebranie materiału na paczkę diagnostyczną: to, co `DiagnosticsReport`
/// dostaje gotowe.
///
/// Rozdział jest ten sam co w `Monitor`: tutaj siedzą źródła, tam czysta
/// funkcja. Dzięki temu treść paczki sprawdza test bez Ollamy, bez IOKitu
/// i bez cudzego logu na dysku, a ten plik odpowiada wyłącznie za to, skąd
/// się bierze każde pole.
public struct DiagnosticsCollector: Sendable {
    public struct Sources: Sendable {
        public var now: @Sendable () -> Date
        public var profile: @Sendable () -> HardwareProfile
        public var gpu: @Sendable () -> GPUReading
        public var ollamaHost: URL
        public var ollamaVersion: @Sendable () async -> OllamaVersion
        public var ollama: @Sendable () async -> OllamaStatus
        public var appLogPath: String
        public var entries: @Sendable () -> [AppLogArchive.Entry]
        public var ollamaLogPath: String?
        public var ollamaExcerpt: @Sendable () -> OllamaLogExcerpt

        public init(
            now: @escaping @Sendable () -> Date = { Date() },
            profile: @escaping @Sendable () -> HardwareProfile,
            gpu: @escaping @Sendable () -> GPUReading,
            ollamaHost: URL,
            ollamaVersion: @escaping @Sendable () async -> OllamaVersion,
            ollama: @escaping @Sendable () async -> OllamaStatus,
            appLogPath: String,
            entries: @escaping @Sendable () -> [AppLogArchive.Entry],
            ollamaLogPath: String?,
            ollamaExcerpt: @escaping @Sendable () -> OllamaLogExcerpt
        ) {
            self.now = now
            self.profile = profile
            self.gpu = gpu
            self.ollamaHost = ollamaHost
            self.ollamaVersion = ollamaVersion
            self.ollama = ollama
            self.appLogPath = appLogPath
            self.entries = entries
            self.ollamaLogPath = ollamaLogPath
            self.ollamaExcerpt = ollamaExcerpt
        }

        public static func live(
            appVersion: String,
            logPath: String? = OllamaLogLocation.find(),
            log: AppLog = .shared
        ) -> Sources {
            let client = OllamaClient()
            let archive = AppLogArchive(log: log)
            return Sources(
                profile: { HardwareProfileReader.read(appVersion: appVersion) },
                gpu: { GPUReader.utilization() },
                ollamaHost: client.baseURL,
                ollamaVersion: { await client.version() },
                ollama: { await client.processStatus() },
                appLogPath: log.currentFile.path,
                entries: { archive.entries() },
                ollamaLogPath: logPath,
                ollamaExcerpt: { OllamaLogExcerpt.take(fromFileAt: logPath) }
            )
        }
    }

    private let sources: Sources

    public init(sources: Sources) {
        self.sources = sources
    }

    /// Stan przychodzi z zewnątrz, a nie jest liczony tutaj od nowa. Paczka
    /// ma pokazać to, co użytkownik miał na ekranie, gdy nacisnął przycisk —
    /// stan policzony powtórnie mógłby być inny niż ten, o którym człowiek
    /// właśnie pisze zgłoszenie.
    public func collect(state: AppState) async -> DiagnosticsReport.Input {
        let now = sources.now()
        let entries = sources.entries()

        // Dwa żądania do serwera, sekwencyjnie i świadomie: serwer, który
        // nie odpowiada, jest częstym powodem zbierania diagnostyki, a dwa
        // równoległe żądania po dwie sekundy nie kończą się szybciej niż
        // jedno — kończą się tylko mniej czytelnie w logu.
        let version = await sources.ollamaVersion()
        let status = await sources.ollama()

        return DiagnosticsReport.Input(
            generatedAt: now,
            profile: sources.profile(),
            gpu: sources.gpu(),
            state: state,
            ollamaHost: sources.ollamaHost,
            ollamaVersion: version,
            ollama: status,
            appLogPath: sources.appLogPath,
            ollamaLogPath: sources.ollamaLogPath,
            recentEntries: entries.since(now.addingTimeInterval(-DiagnosticsReport.recentWindow)),
            unrecognized: entries.unrecognized,
            ollamaExcerpt: sources.ollamaExcerpt()
        )
    }
}
