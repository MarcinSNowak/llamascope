import XCTest
@testable import LlamaScopeCore

final class SwapWatcherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func usage(_ used: Double) -> SwapUsage {
        SwapUsage(usedGB: used, freeGB: 1.4)
    }

    /// Cała reguła w jednym przebiegu: spokój zapisuje odniesienie, potem
    /// model wchodzi do pamięci i swap rośnie ponad próg.
    func testWarnsOnlyAboutGrowthSinceTheQuietMoment() {
        let watcher = SwapWatcher(store: InMemorySwapBaselineStore())

        XCTAssertEqual(watcher.assess(usage: usage(13.6), anythingLoaded: false, now: now), .steady)

        let loaded = watcher.assess(usage: usage(17.9), anythingLoaded: true, now: now.addingTimeInterval(30))
        guard case let .worsened(grown) = loaded else {
            return XCTFail("spodziewane pogorszenie, dostaliśmy \(loaded)")
        }
        XCTAssertEqual(grown, 4.3, accuracy: 0.001)
    }

    /// Powód istnienia całej reguły: maszyna, która od rana siedzi na
    /// swapie, nie ma być powodem ostrzeżenia. 13,6 GB zajęte i nic z tego
    /// nie jest nasze.
    func testAMachineAlreadyOnSwapIsNotAWarning() {
        let watcher = SwapWatcher(store: InMemorySwapBaselineStore())
        XCTAssertEqual(watcher.assess(usage: usage(13.6), anythingLoaded: false, now: now), .steady)
        XCTAssertEqual(
            watcher.assess(usage: usage(13.8), anythingLoaded: true, now: now.addingTimeInterval(10)),
            .steady
        )
    }

    /// Bez punktu odniesienia milczymy — model był załadowany, zanim nas
    /// uruchomiono, więc nie wiadomo, co zastaliśmy.
    func testNoBaselineMeansNoWarningEvenAtHighUsage() {
        let watcher = SwapWatcher(store: InMemorySwapBaselineStore())
        XCTAssertEqual(watcher.assess(usage: usage(31.0), anythingLoaded: true, now: now), .noBaseline)
    }

    /// Wyścig, który zdarzył się naprawdę: przy ładowaniu modelu `/api/ps`
    /// bywa jeszcze przez chwilę puste, a swap już rośnie. Taki odczyt
    /// wygląda jak spokój i **nie może** podnieść odniesienia, bo wyciszyłby
    /// ostrzeżenie na dobre.
    func testAQuietReadingDuringLoadingDoesNotRaiseTheBaseline() {
        let watcher = SwapWatcher(store: InMemorySwapBaselineStore())
        _ = watcher.assess(usage: usage(13.6), anythingLoaded: false, now: now)
        // Pozorny spokój w trakcie ładowania, swap już urósł:
        _ = watcher.assess(usage: usage(17.5), anythingLoaded: false, now: now.addingTimeInterval(1))

        let loaded = watcher.assess(usage: usage(17.9), anythingLoaded: true, now: now.addingTimeInterval(2))
        guard case let .worsened(grown) = loaded else {
            return XCTFail("odniesienie zostało zawyżone przez pozorny spokój, dostaliśmy \(loaded)")
        }
        XCTAssertEqual(grown, 4.3, accuracy: 0.001)
    }

    /// Odwrotnie: gdy maszyna naprawdę odetchnęła, odniesienie ma zejść
    /// niżej, żeby nadążało za maszyną.
    func testTheBaselineFollowsTheMachineDown() {
        let watcher = SwapWatcher(store: InMemorySwapBaselineStore())
        _ = watcher.assess(usage: usage(13.6), anythingLoaded: false, now: now)
        _ = watcher.assess(usage: usage(8.0), anythingLoaded: false, now: now.addingTimeInterval(60))

        guard case let .worsened(grown) = watcher.assess(
            usage: usage(9.5), anythingLoaded: true, now: now.addingTimeInterval(90)
        ) else { return XCTFail("odniesienie nie zeszło za maszyną") }
        XCTAssertEqual(grown, 1.5, accuracy: 0.001)
    }

    func testAnHourOldBaselineExpires() {
        let store = InMemorySwapBaselineStore(
            SwapBaseline(usedGB: 2.0, recordedAt: now.addingTimeInterval(-3601))
        )
        let watcher = SwapWatcher(store: store)
        XCTAssertEqual(watcher.assess(usage: usage(20.0), anythingLoaded: true, now: now), .noBaseline)
    }

    func testGrowthBelowThresholdIsNotAWarning() {
        let store = InMemorySwapBaselineStore(SwapBaseline(usedGB: 10.0, recordedAt: now))
        let watcher = SwapWatcher(store: store)
        XCTAssertEqual(
            watcher.assess(usage: usage(10.9), anythingLoaded: true, now: now.addingTimeInterval(10)),
            .steady
        )
    }

    func testUnreadableSwapIsNotAWarning() {
        let watcher = SwapWatcher(store: InMemorySwapBaselineStore())
        XCTAssertEqual(watcher.assess(usage: nil, anythingLoaded: true, now: now), .noBaseline)
    }
}

final class FileSwapBaselineStoreTests: XCTestCase {
    /// Punkt odniesienia ma przetrwać restart aplikacji — inaczej
    /// aktualizacja w środku pracy wycisza ostrzeżenie do czasu, aż Ollama
    /// zwolni pamięć.
    func testTheBaselineSurvivesARestart() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("llamascope-swap-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let baseline = SwapBaseline(usedGB: 13.6, recordedAt: Date(timeIntervalSince1970: 1_800_000_000))
        FileSwapBaselineStore(url: url).save(baseline)

        XCTAssertEqual(FileSwapBaselineStore(url: url).load(), baseline)
    }

    func testAMissingFileIsNotAnError() {
        let url = URL(fileURLWithPath: "/nie/ma/takiego/katalogu/swap.json")
        XCTAssertNil(FileSwapBaselineStore(url: url).load())
    }

    func testStoresUnderTheAppsOwnDirectory() {
        let path = FileSwapBaselineStore.defaultURL.path
        XCTAssertTrue(path.contains("Application Support/LlamaScope"), "dostaliśmy: \(path)")
        XCTAssertFalse(path.hasPrefix("/tmp"), "stan aplikacji nie należy do katalogu sprzątanego przez system")
    }
}

final class SwapReaderTests: XCTestCase {
    /// Na żywej maszynie. Wartości nie sprawdzamy — sprawdzamy, że
    /// `sysctlbyname` zwraca coś sensownego, bo to jedyne miejsce, gdzie
    /// odczyt może się rozejść z rzeczywistością po cichu.
    func testReadsThisMachine() throws {
        let usage = try XCTUnwrap(SwapReader.read(), "nie udało się odczytać vm.swapusage")
        print("swap tej maszyny → użyte \(usage.usedGB) GB, wolne \(usage.freeGB) GB")
        XCTAssertGreaterThanOrEqual(usage.usedGB, 0)
        XCTAssertGreaterThanOrEqual(usage.freeGB, 0)
    }
}
