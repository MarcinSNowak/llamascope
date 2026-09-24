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
    /// Linie logu Ollamy, które wyglądały na nasze, a nie dały się rozebrać.
    /// Osobne źródło, bo to nie jest stan — to materiał do zgłoszenia (§10).
    public var unparsedLog: @Sendable () -> [String]
    /// Dokąd trafia własny log aplikacji. Domyślnie donikąd, żeby testy
    /// i sonda nie zapisywały niczego na dysk bez proszenia.
    public var record: @Sendable (String) -> Void
    public var now: @Sendable () -> Date
    /// Jedyna akcja pisząca (§7). Osobno od odczytów, bo tylko ona zmienia
    /// cudzy stan — i żeby w teście dało się sprawdzić, że nie wywołujemy
    /// jej przypadkiem w pętli odświeżania.
    public var unload: @Sendable (String) async -> OllamaClient.ActionOutcome
    public var load: @Sendable (String) async -> OllamaClient.ActionOutcome

    public init(
        ollama: @escaping @Sendable () async -> OllamaStatus,
        gpu: @escaping @Sendable () -> GPUReading,
        swap: @escaping @Sendable () -> SwapUsage?,
        log: @escaping @Sendable () -> [LogEvent],
        unparsedLog: @escaping @Sendable () -> [String] = { [] },
        record: @escaping @Sendable (String) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() },
        unload: @escaping @Sendable (String) async -> OllamaClient.ActionOutcome = { _ in
            .failed(reason: "to źródło nie umie zwalniać modeli")
        },
        load: @escaping @Sendable (String) async -> OllamaClient.ActionOutcome = { _ in
            .failed(reason: "to źródło nie umie ładować modeli")
        }
    ) {
        self.ollama = ollama
        self.gpu = gpu
        self.swap = swap
        self.log = log
        self.unparsedLog = unparsedLog
        self.record = record
        self.now = now
        self.unload = unload
        self.load = load
    }

    /// Źródła prawdziwe: serwer pod `OLLAMA_HOST`, IOKit, `sysctl`, log Ollamy.
    /// Gdy logu nie ma, zwracamy pustkę zamiast udawać, że nic się nie dzieje
    /// — o tym, że go nie znaleziono, mówi `MonitorReport` (§10).
    public static func live(
        logPath: String? = OllamaLogLocation.find(),
        record: @escaping @Sendable (String) -> Void = { AppLog.shared.write($0) }
    ) -> MonitorSources {
        let client = OllamaClient()
        let reader = logPath.map { OllamaLogReader(path: $0) }
        return MonitorSources(
            ollama: { await client.processStatus() },
            gpu: { GPUReader.utilization() },
            swap: { SwapReader.read() },
            log: { reader?.readNew() ?? [] },
            unparsedLog: { reader?.takeUnrecognized() ?? [] },
            record: record,
            unload: { await client.unload(model: $0) },
            load: { await client.load(model: $0) }
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

    /// Ostatnie dwie minuty obciążenia GPU — z tego rysuje się ikona (§7).
    @Published public private(set) var history = GPUHistory()

    /// Co widzi `/api/ps` w tej chwili. Stan mówi o **jednym** modelu, tym
    /// najważniejszym; szczegóły w popoverze pokazują wszystkie.
    @Published public private(set) var models: [LoadedModel] = []

    /// Tempo ostatniej skończonej odpowiedzi. Świadomie **poza** stanem:
    /// Ollama zapisuje szybkość dopiero po odpowiedzi, więc w trakcie pracy
    /// ta liczba opisuje poprzednią. W panelu jest podpisana; w zdaniu
    /// o stanie wyglądałaby na bieżącą.
    @Published public private(set) var lastGeneration: EvalSpeed?

    /// Zajętość okna z ostatniego żądania. Osobno od stanu, bo to liczba do
    /// panelu szczegółów, a nie powód do zapalenia ikony.
    @Published public private(set) var lastPrompt: PromptAccepted?

    /// Model zwolniony ostatnim kliknięciem. Tylko po to, żeby „Załaduj
    /// ponownie" mogło być cofnięciem akcji, a nie ogólną listą modeli (§7).
    @Published public private(set) var lastUnloaded: String?

    /// Powód, dla którego ostatnia akcja pisząca się nie udała, do pokazania
    /// przy przycisku. Zostaje do następnej akcji — nie chowamy go po
    /// sekundzie, bo kto nacisnął przycisk, ten ma prawo przeczytać, czemu
    /// nic się nie stało.
    @Published public private(set) var lastActionProblem: String?

    /// Ile razy z rzędu nie udało się dostać do serwera. Do własnego logu:
    /// pojedyncza nieudana próba przy starcie Ollamy to norma, seria to coś
    /// innego i warto, żeby dało się je rozróżnić w zgłoszeniu.
    public private(set) var consecutiveFailures = 0

    private let sources: MonitorSources
    private let swapWatcher: SwapWatcher
    private var logState = OllamaLogState()
    private var ticker: Task<Void, Never>?
    private var gate = ActivityGate()
    private var lastLoggedKind: String?

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
        let events = sources.log()
        logState.apply(events)

        for event in events {
            // Ucięcie zapisujemy zawsze, także gdy stan się przez nie nie
            // zmienił — to jedyne zdarzenie, dla którego całe narzędzie
            // powstało, i w zgłoszeniu musi być z liczbami.
            guard case let .inputTruncated(truncation) = event else { continue }
            sources.record(
                "UCIĘCIE: okno \(truncation.limitTokens), prompt \(truncation.promptTokens), "
                + "przeczytane \(truncation.readTokens), przepadło \(truncation.lostTokens)"
            )
        }

        for line in sources.unparsedLog() {
            // Najcenniejsza rzecz w tym logu (§10): linia, która wygląda na
            // naszą, a której nie rozumiemy. Po zmianie formatu w Ollamie to
            // ona powie, co się stało — zanim ktoś zgłosi „nic nie pokazuje”.
            sources.record("NIEROZPOZNANA LINIA LOGU OLLAMY: \(line)")
        }

        let anythingLoaded: Bool
        switch ollama {
        case let .running(models):
            anythingLoaded = !models.isEmpty
            if consecutiveFailures > 0 {
                sources.record("serwer Ollamy znowu odpowiada po \(consecutiveFailures) nieudanych próbach")
            }
            consecutiveFailures = 0
        case let .notResponding(reason):
            // Martwy serwer to nie jest chwila spokoju — nie wolno z niej
            // brać punktu odniesienia dla swapu, bo Ollama mogła właśnie
            // paść z modelem w pamięci.
            anythingLoaded = true
            consecutiveFailures += 1
            // Tylko pierwsza z serii. Przy wyłączonej Ollamie zapisywanie
            // tego co sekundę wypełniłoby megabajt w kwadrans i wypchnęło
            // z logu wszystko, co naprawdę było warte zapisania.
            if consecutiveFailures == 1 {
                sources.record("serwer Ollamy nie odpowiada: \(reason)")
            }
        }

        let swap = swapWatcher.assess(
            usage: sources.swap(), anythingLoaded: anythingLoaded, now: now
        )

        let gpu = sources.gpu()
        history.append(gpu)

        if case let .running(models) = ollama {
            self.models = models
            // Nie ma modelu — nie ma czego podtrzymywać. Bez tego bramka
            // trzymałaby „pracuje" jeszcze pięć sekund po zwolnieniu
            // pamięci, czyli dokładnie wtedy, gdy użytkownik patrzy, czy
            // jego kliknięcie zadziałało.
            if models.isEmpty { gate.reset() }
        } else {
            self.models = []
            gate.reset()
        }
        lastPrompt = logState.lastPrompt
        lastGeneration = logState.lastGeneration

        let working = gate.update(percent: gpu.percent, now: now)

        let fresh = StateRecognizer.recognize(StateInput(
            now: now, ollama: ollama, gpu: gpu, swap: swap, log: logState, working: working
        ))

        // Zmiany, nie odczyty. Stan zmienia się kilkanaście razy dziennie,
        // odczyt zdarza się 86 400 razy — zapisywanie każdego zamieniłoby
        // log w wykres, po którym nie da się niczego znaleźć.
        let kind = StateText.shortLabel(fresh)
        if kind != lastLoggedKind {
            sources.record("stan: \(StateText.sentence(fresh))")
            // Przy każdym przejściu do niewiedzy zapisujemy, na czym
            // dokładnie stanął odczyt GPU — bez tego zgłoszenie „pokazuje
            // znak zapytania” jest nie do odróżnienia od żadnego innego.
            if case .loadedActivityUnknown = fresh { sources.record(gpu.logLine) }
            lastLoggedKind = kind
        }

        state = fresh
        lastRefresh = now
        return state
    }

    /// „Zwolnij teraz" z §7. Jedyna akcja, po której maszyna wygląda inaczej
    /// niż przed kliknięciem.
    ///
    /// Potwierdzenia nie pilnujemy tutaj, tylko w interfejsie — ta metoda ma
    /// robić to, o co ją poproszono. Po niej odświeżamy od razu, bo skutek
    /// widać w `/api/ps` natychmiast i czekanie sekundy wyglądałoby jak
    /// przycisk, który nie zadziałał.
    @discardableResult
    public func releaseNow(model name: String) async -> OllamaClient.ActionOutcome {
        let outcome = await sources.unload(name)
        switch outcome {
        case .done:
            lastUnloaded = name
            lastActionProblem = nil
            // Jedyna akcja, po której maszyna wygląda inaczej — więc jedyna,
            // którą trzeba umieć odtworzyć, gdy ktoś zapyta, czemu jego model
            // zniknął z pamięci.
            sources.record("zwolniono model \(name) na żądanie")
        case let .failed(reason):
            lastActionProblem = reason
            sources.record("nie udało się zwolnić \(name): \(reason)")
        }
        await refresh()
        return outcome
    }

    /// Cofnięcie poprzedniego zwolnienia i nic więcej (§7).
    @discardableResult
    public func loadAgain() async -> OllamaClient.ActionOutcome {
        guard let name = lastUnloaded else {
            return .failed(reason: "nie ma czego ładować ponownie")
        }
        let outcome = await sources.load(name)
        switch outcome {
        case .done:
            lastUnloaded = nil
            lastActionProblem = nil
            sources.record("załadowano ponownie \(name)")
        case let .failed(reason):
            lastActionProblem = reason
            sources.record("nie udało się załadować \(name): \(reason)")
        }
        await refresh()
        return outcome
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
