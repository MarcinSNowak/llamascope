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
        guard case let .working(_, generation) = await monitor.refresh() else {
            return XCTFail("spodziewana praca, dostaliśmy \(monitor.state)")
        }
        XCTAssertEqual(generation?.tokensPerSecond ?? 0, 54.31, accuracy: 0.01)
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
