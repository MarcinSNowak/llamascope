import Combine
import Foundation

/// Cztery źródła, z których składa się jeden stan. Wstrzykiwane, bo tylko
/// wtedy da się sprawdzić pętlę bez działającej Ollamy, bez GPU i bez swapu
/// — a §12 wymaga, żeby rdzeń dało się sprawdzić bez uruchamiania interfejsu.
public struct MonitorSources: Sendable {
    public var ollama: @Sendable () async -> OllamaStatus
    public var gpu: @Sendable () -> GPUReading
    public var swap: @Sendable () -> SwapUsage?
    public var log: @Sendable () -> [LogEvent]
    public var now: @Sendable () -> Date

    public init(
        ollama: @escaping @Sendable () async -> OllamaStatus,
        gpu: @escaping @Sendable () -> GPUReading,
        swap: @escaping @Sendable () -> SwapUsage?,
        log: @escaping @Sendable () -> [LogEvent],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.ollama = ollama
        self.gpu = gpu
        self.swap = swap
        self.log = log
        self.now = now
    }

    /// Źródła prawdziwe: serwer pod `OLLAMA_HOST`, IOKit, `sysctl`, log Ollamy.
    /// Gdy logu nie ma, zwracamy pustkę zamiast udawać, że nic się nie dzieje
    /// — o tym, że go nie znaleziono, mówi `MonitorReport` (§10).
    public static func live(logPath: String? = OllamaLogLocation.find()) -> MonitorSources {
        let client = OllamaClient()
        let reader = logPath.map { OllamaLogReader(path: $0) }
        return MonitorSources(
            ollama: { await client.processStatus() },
            gpu: { GPUReader.utilization() },
            swap: { SwapReader.read() },
            log: { reader?.readNew() ?? [] }
        )
    }
}

/// Pętla odświeżania. Trzyma to, co musi przetrwać między odczytami: stan
/// logu i punkt odniesienia swapu.
///
/// `@MainActor`, bo jedynym odbiorcą jest pasek menu, a stan ma się zmieniać
/// w jednym miejscu. Samo rozpoznawanie jest czystą funkcją i nie potrzebuje
/// aktora — dlatego testy stanów nie muszą dotykać tej klasy.
@MainActor
public final class Monitor: ObservableObject {
    @Published public private(set) var state: AppState = .ollamaNotResponding(reason: "jeszcze nie pytaliśmy")
    @Published public private(set) var lastRefresh: Date?

    /// Ile razy z rzędu nie udało się dostać do serwera. Do własnego logu:
    /// pojedyncza nieudana próba przy starcie Ollamy to norma, seria to coś
    /// innego i warto, żeby dało się je rozróżnić w zgłoszeniu.
    public private(set) var consecutiveFailures = 0

    private let sources: MonitorSources
    private let swapWatcher: SwapWatcher
    private var logState = OllamaLogState()
    private var ticker: Task<Void, Never>?

    public init(
        sources: MonitorSources = .live(),
        swapWatcher: SwapWatcher = SwapWatcher(store: FileSwapBaselineStore())
    ) {
        self.sources = sources
        self.swapWatcher = swapWatcher
    }

    deinit { ticker?.cancel() }

    /// Jedno przejście. Zwraca stan, żeby dało się go sprawdzić w teście
    /// bez zaglądania we właściwość.
    @discardableResult
    public func refresh() async -> AppState {
        let ollama = await sources.ollama()
        let now = sources.now()

        // Log czytamy zawsze, także przy martwym serwerze: ucięcie mogło
        // się zdarzyć chwilę przed tym, jak przestał odpowiadać.
        logState.apply(sources.log())

        let anythingLoaded: Bool
        switch ollama {
        case let .running(models):
            anythingLoaded = !models.isEmpty
            consecutiveFailures = 0
        case .notResponding:
            // Martwy serwer to nie jest chwila spokoju — nie wolno z niej
            // brać punktu odniesienia dla swapu, bo Ollama mogła właśnie
            // paść z modelem w pamięci.
            anythingLoaded = true
            consecutiveFailures += 1
        }

        let swap = swapWatcher.assess(
            usage: sources.swap(), anythingLoaded: anythingLoaded, now: now
        )

        state = StateRecognizer.recognize(StateInput(
            now: now, ollama: ollama, gpu: sources.gpu(), swap: swap, log: logState
        ))
        lastRefresh = now
        return state
    }

    /// Sekunda jak w wersji pythonowej. Odczyty są tanie: `sysctl` i IOKit
    /// to wywołania bez procesu potomnego, log czytamy przyrostowo,
    /// a `/api/ps` ma dwusekundowy limit czasu.
    public nonisolated static let defaultInterval: Duration = .seconds(1)

    public func start(every interval: Duration = Monitor.defaultInterval) {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
    }
}
