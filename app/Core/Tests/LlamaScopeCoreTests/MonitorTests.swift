import XCTest
@testable import LlamaScopeCore

/// Pudełko na wartość zmienianą w trakcie testu. Źródła Monitora są
/// domknięciami `@Sendable`, więc zwykła zmienna lokalna nie przejdzie.
final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor
final class MonitorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func sources(
        ollama: OllamaStatus,
        gpu: GPUReading = .reading(percent: 0, serviceClass: "AGXAccelerator", key: "Device Utilization %"),
        swap: SwapUsage? = SwapUsage(usedGB: 10, freeGB: 1.4),
        log: [LogEvent] = [],
        at time: Date? = nil
    ) -> MonitorSources {
        let moment = time ?? now
        return MonitorSources(
            ollama: { ollama }, gpu: { gpu }, swap: { swap }, log: { log }, now: { moment }
        )
    }

    private func model(vram: UInt64 = 9_000_000_000) -> LoadedModel {
        LoadedModel(name: "qwen2.5-coder:14b", sizeBytes: 9_000_000_000, sizeVRAMBytes: vram)
    }

    func testBeforeTheFirstRefreshItDoesNotPretendToKnow() {
        let monitor = Monitor(sources: sources(ollama: .running(models: [])),
                              swapWatcher: SwapWatcher(store: InMemorySwapBaselineStore()))
        guard case .ollamaNotResponding = monitor.state else {
            return XCTFail("przed pierwszym odczytem nie wolno pokazywać spokoju, mamy \(monitor.state)")
        }
    }

    func testPutsTheFourSourcesTogether() async {
        let monitor = Monitor(
            sources: sources(
                ollama: .running(models: [model()]),
                gpu: .reading(percent: 96, serviceClass: "AGXAccelerator", key: "Device Utilization %"),
                log: [.generationEval(EvalSpeed(tokens: 209, tokensPerSecond: 54.31))]
            ),
            swapWatcher: SwapWatcher(store: InMemorySwapBaselineStore())
        )
        guard case .working = await monitor.refresh() else {
            return XCTFail("spodziewana praca, dostaliśmy \(monitor.state)")
        }
        // Tempo jest, ale obok stanu i podpisane jako ostatnia odpowiedź —
        // nie w zdaniu o trwającej pracy.
        XCTAssertEqual(monitor.lastGeneration?.tokensPerSecond ?? 0, 54.31, accuracy: 0.01)
        XCTAssertEqual(monitor.lastRefresh, now)
    }

    /// Stan logu musi przetrwać między odczytami. Ucięcie przychodzi raz,
    /// a ma pozostać stanem bieżącym przez kolejne odświeżenia — inaczej
    /// alarm mignąłby przez jedną sekundę i zniknął.
    func testTheTruncationSurvivesLaterRefreshes() async {
        let truncation = InputTruncation(
            time: now, limitTokens: 258, promptTokens: 7260, keptTokens: 4, readTokens: 258
        )
        let events = Box<[LogEvent]>([.inputTruncated(truncation)])
        let monitor = Monitor(
            sources: MonitorSources(
                ollama: { .running(models: []) },
                gpu: { .reading(percent: 0, serviceClass: "A", key: "B") },
                swap: { nil },
                log: { defer { events.value = [] }; return events.value },
                now: { self.now.addingTimeInterval(1) }
            ),
            swapWatcher: SwapWatcher(store: InMemorySwapBaselineStore())
        )

        guard case .promptTruncated = await monitor.refresh() else {
            return XCTFail("pierwsze przejście ma złapać ucięcie")
        }
        guard case .promptTruncated = await monitor.refresh() else {
            return XCTFail("ucięcie zniknęło po jednym odświeżeniu, mamy \(monitor.state)")
        }
    }

    /// Martwy serwer to nie jest chwila spokoju. Gdyby Monitor wziął z niej
    /// punkt odniesienia dla swapu, to po tym, jak Ollama padła z modelem
    /// w pamięci, odniesienie opisywałoby maszynę już dławiącą się swapem.
    func testADeadServerIsNotAQuietMoment() async {
        let store = InMemorySwapBaselineStore()
        let monitor = Monitor(
            sources: sources(ollama: .notResponding(reason: "brak połączenia"),
                             swap: SwapUsage(usedGB: 29, freeGB: 0.2)),
            swapWatcher: SwapWatcher(store: store)
        )
        guard case .ollamaNotResponding = await monitor.refresh() else {
            return XCTFail("spodziewany brak odpowiedzi, mamy \(monitor.state)")
        }
        XCTAssertNil(store.load(), "z martwego serwera nie wolno brać punktu odniesienia")
    }

    func testCountsConsecutiveFailures() async {
        let monitor = Monitor(
            sources: sources(ollama: .notResponding(reason: "brak połączenia")),
            swapWatcher: SwapWatcher(store: InMemorySwapBaselineStore())
        )
        await monitor.refresh()
        await monitor.refresh()
        XCTAssertEqual(monitor.consecutiveFailures, 2)
    }

    func testASuccessfulRefreshClearsTheFailureCount() async {
        let status = Box(OllamaStatus.notResponding(reason: "brak połączenia"))
        let monitor = Monitor(
            sources: MonitorSources(
                ollama: { status.value },
                gpu: { .reading(percent: 0, serviceClass: "A", key: "B") },
                swap: { nil }, log: { [] }, now: { self.now }
            ),
            swapWatcher: SwapWatcher(store: InMemorySwapBaselineStore())
        )
        await monitor.refresh()
        status.value = .running(models: [])
        await monitor.refresh()
        XCTAssertEqual(monitor.consecutiveFailures, 0)
        XCTAssertEqual(monitor.state, .asleep)
    }

    /// Pełne przejście na prawdziwych źródłach: serwer, IOKit, sysctl, log.
    /// Nie sprawdzamy, który stan wyjdzie — sprawdzamy, że wyjdzie jakiś
    /// i że nic po drodze nie zawiesi się ani nie wywali.
    func testOneRefreshAgainstTheRealMachine() async {
        let monitor = Monitor(
            sources: .live(),
            swapWatcher: SwapWatcher(store: InMemorySwapBaselineStore())
        )
        let state = await monitor.refresh()
        print("stan tej maszyny → \(state)")
        XCTAssertNotNil(monitor.lastRefresh)
    }
}

/// Akcja pisząca — jedyne miejsce, w którym ta aplikacja zmienia cudzy stan.
@MainActor
final class MonitorActionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func model() -> LoadedModel {
        LoadedModel(name: "qwen2.5-coder:14b", sizeBytes: 9_000_000_000, sizeVRAMBytes: 9_000_000_000)
    }

    /// Źródła, w których `/api/ps` opróżnia się po udanym zwolnieniu —
    /// czyli tak, jak zachowuje się prawdziwy serwer.
    private func sources(
        loaded: Box<[LoadedModel]>,
        unloaded: Box<[String]>,
        outcome: OllamaClient.ActionOutcome = .done
    ) -> MonitorSources {
        let moment = now
        return MonitorSources(
            ollama: { .running(models: loaded.value) },
            gpu: { .reading(percent: 0, serviceClass: "AGXAccelerator", key: "Device Utilization %") },
            swap: { SwapUsage(usedGB: 10, freeGB: 1.4) },
            log: { [] },
            now: { moment },
            unload: { name in
                unloaded.value.append(name)
                if case .done = outcome { loaded.value.removeAll { $0.name == name } }
                return outcome
            },
            load: { _ in .done }
        )
    }

    private func monitor(_ sources: MonitorSources) -> Monitor {
        Monitor(sources: sources, swapWatcher: SwapWatcher(store: InMemorySwapBaselineStore()))
    }

    /// Najważniejszy test w tym pliku: odświeżanie **nigdy** nie zwalnia
    /// modelu. Gdyby kiedyś zwolniło, aplikacja do patrzenia zaczęłaby
    /// wyrzucać ludziom modele z pamięci bez pytania.
    func testRefreshingNeverWritesAnything() async {
        let loaded = Box([model()])
        let unloaded = Box<[String]>([])
        let monitor = monitor(sources(loaded: loaded, unloaded: unloaded))
        for _ in 0..<5 { await monitor.refresh() }
        XCTAssertEqual(unloaded.value, [], "pętla odświeżania sięgnęła po akcję piszącą")
    }

    func testReleaseNowUnloadsAndShowsTheResultAtOnce() async {
        let loaded = Box([model()])
        let unloaded = Box<[String]>([])
        let monitor = monitor(sources(loaded: loaded, unloaded: unloaded))
        await monitor.refresh()

        let outcome = await monitor.releaseNow(model: "qwen2.5-coder:14b")
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(unloaded.value, ["qwen2.5-coder:14b"])
        // Bez odświeżenia w środku akcji przycisk wyglądałby na niedziałający
        // jeszcze przez sekundę.
        XCTAssertEqual(monitor.state, .asleep)
        XCTAssertEqual(monitor.lastUnloaded, "qwen2.5-coder:14b")
        XCTAssertNil(monitor.lastActionProblem)
    }

    /// Nieudana akcja nie może przejść w milczeniu ani udawać, że model
    /// zniknął — inaczej „Załaduj ponownie" proponowałoby cofnięcie czegoś,
    /// co się nie stało.
    func testFailedReleaseSaysWhyAndOffersNoUndo() async {
        let loaded = Box([model()])
        let unloaded = Box<[String]>([])
        let monitor = monitor(sources(
            loaded: loaded, unloaded: unloaded, outcome: .failed(reason: "serwer odpowiedział kodem 500")
        ))
        await monitor.refresh()

        let outcome = await monitor.releaseNow(model: "qwen2.5-coder:14b")
        XCTAssertEqual(outcome, .failed(reason: "serwer odpowiedział kodem 500"))
        XCTAssertEqual(monitor.lastActionProblem, "serwer odpowiedział kodem 500")
        XCTAssertNil(monitor.lastUnloaded, "nie ma czego cofać, skoro nic się nie stało")
        XCTAssertEqual(monitor.models.count, 1, "model nadal siedzi w pamięci")
    }

    /// §7: „Załaduj ponownie" istnieje wyłącznie jako cofnięcie. Bez
    /// poprzedniego zwolnienia nie ma czego ładować — i nie wolno tu wstawić
    /// listy modeli do wyboru, bo wtedy przestajemy być wskaźnikiem.
    func testLoadAgainIsOnlyAnUndo() async {
        let loaded = Box([model()])
        let unloaded = Box<[String]>([])
        let monitor = monitor(sources(loaded: loaded, unloaded: unloaded))
        await monitor.refresh()

        let withoutUndo = await monitor.loadAgain()
        XCTAssertEqual(withoutUndo, .failed(reason: "nie ma czego ładować ponownie"))

        await monitor.releaseNow(model: "qwen2.5-coder:14b")
        let undo = await monitor.loadAgain()
        XCTAssertEqual(undo, .done)
        XCTAssertNil(monitor.lastUnloaded, "cofnięcie zużywa się po jednym użyciu")
    }

    /// Bramka aktywności ma zgasnąć razem z pamięcią. Inaczej tuż po
    /// kliknięciu „Zwolnij teraz" ikona jeszcze przez pięć sekund pokazywała
    /// by pracę — dokładnie wtedy, gdy użytkownik patrzy, czy zadziałało.
    func testReleasingStopsTheWorkImmediately() async {
        let loaded = Box([model()])
        let unloaded = Box<[String]>([])
        let busy = Box(90)
        let moment = Box(now)
        let sources = MonitorSources(
            ollama: { .running(models: loaded.value) },
            gpu: { .reading(percent: busy.value, serviceClass: "AGXAccelerator", key: "Device Utilization %") },
            swap: { SwapUsage(usedGB: 10, freeGB: 1.4) },
            log: { [] },
            now: { moment.value },
            unload: { name in
                unloaded.value.append(name)
                loaded.value.removeAll { $0.name == name }
                busy.value = 0
                return .done
            }
        )
        let monitor = monitor(sources)
        await monitor.refresh()
        guard case .working = monitor.state else {
            return XCTFail("miało pracować, mamy \(monitor.state)")
        }

        await monitor.releaseNow(model: "qwen2.5-coder:14b")
        XCTAssertEqual(monitor.state, .asleep, "histereza przetrzymała pracę po zwolnieniu pamięci")
    }

    /// Historia do ikony rośnie z każdym odczytem, także wtedy, gdy odczyt
    /// się nie udał — dziura w wykresie jest informacją.
    func testHistoryGrowsWithEveryRefreshIncludingFailedOnes() async {
        let loaded = Box([model()])
        let unloaded = Box<[String]>([])
        let monitor = monitor(sources(loaded: loaded, unloaded: unloaded))
        await monitor.refresh()
        await monitor.refresh()
        XCTAssertEqual(monitor.history.samples.count, 2)
    }
}
