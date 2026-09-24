import XCTest
@testable import LlamaScopeCore

final class ActivityGateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// Powód istnienia tej bramki, przepisany z obserwacji na żywej sondzie:
    /// trzy kolejne odczyty 12 → 3 → 40 to jedno generowanie, a nie trzy
    /// zmiany stanu. Bez histerezy ikona mrugnęła tu dwa razy.
    func testDipBetweenTokensDoesNotStopTheWork() {
        var gate = ActivityGate()
        XCTAssertTrue(gate.update(percent: 12, now: at(0)))
        XCTAssertTrue(gate.update(percent: 3, now: at(1)), "zapaść między tokenami zgasiła ikonę")
        XCTAssertTrue(gate.update(percent: 40, now: at(2)))
    }

    func testQuietLongEnoughEndsTheWork() {
        var gate = ActivityGate()
        gate.update(percent: 60, now: at(0))
        XCTAssertTrue(gate.update(percent: 0, now: at(2)), "dwie sekundy ciszy to za mało")
        XCTAssertTrue(gate.update(percent: 0, now: at(4)))
        XCTAssertFalse(gate.update(percent: 0, now: at(6)), "po pięciu sekundach ciszy ma zgasnąć")
    }

    /// Cisza liczy się od ostatniej chwili pracy, nie od pierwszego zera.
    /// Inaczej długie generowanie z regularnymi zapaściami zgasłoby w środku.
    func testQuietClockRestartsWithEveryBusyReading() {
        var gate = ActivityGate()
        gate.update(percent: 60, now: at(0))
        gate.update(percent: 0, now: at(4))
        gate.update(percent: 30, now: at(5))
        XCTAssertTrue(gate.update(percent: 0, now: at(9)), "zegar ciszy nie ruszył od nowa")
    }

    /// Próg zapłonu jest wyższy niż próg podtrzymania i tak ma być: 3% to za
    /// mało, żeby zacząć, i dość, żeby nie przerywać.
    func testThreePercentStartsNothing() {
        var gate = ActivityGate()
        XCTAssertFalse(gate.update(percent: 3, now: at(0)))
        XCTAssertFalse(gate.update(percent: 5, now: at(1)), "próg jest „powyżej 5%”, nie „od 5%”")
    }

    /// Nieudany odczyt nie jest zerem. Nie wolno mu ani zgasić ikony, ani
    /// jej zapalić — o niewiedzy mówi osobny stan.
    func testFailedReadingChangesNothing() {
        var gate = ActivityGate()
        gate.update(percent: 60, now: at(0))
        XCTAssertTrue(gate.update(percent: nil, now: at(100)), "brak odczytu udał ciszę")

        var cold = ActivityGate()
        XCTAssertFalse(cold.update(percent: nil, now: at(0)))
    }

    func testResetStopsTheWorkAtOnce() {
        var gate = ActivityGate()
        gate.update(percent: 90, now: at(0))
        gate.reset()
        XCTAssertFalse(gate.isWorking)
        XCTAssertFalse(gate.update(percent: 0, now: at(1)), "po zwolnieniu pamięci nic już nie liczy")
    }
}

final class GPUHistoryTests: XCTestCase {
    private func gpu(_ percent: Int) -> GPUReading {
        .reading(percent: percent, serviceClass: "AGXAccelerator", key: "Device Utilization %")
    }

    /// Najważniejszy test w tym pliku. Nieudany odczyt zostaje dziurą; gdyby
    /// wpadł do wykresu jako zero, ikona rysowałaby spokój tam, gdzie mamy
    /// niewiedzę.
    func testFailedReadingStaysAHoleNotAZero() {
        var history = GPUHistory()
        history.append(gpu(40))
        history.append(.classNotFound(searched: GPUReader.knownClasses))
        history.append(gpu(50))
        XCTAssertEqual(history.samples.count, 3)
        XCTAssertNil(history.samples[1])
        XCTAssertNotEqual(history.samples[1], 0)
    }

    func testHistoryKeepsTwoMinutesAndDropsTheOldest() {
        var history = GPUHistory()
        for value in 0..<(GPUHistory.capacity + 30) {
            history.append(gpu(value % 100))
        }
        XCTAssertEqual(history.samples.count, GPUHistory.capacity)
        XCTAssertEqual(history.samples.last, (GPUHistory.capacity + 29) % 100)
        XCTAssertEqual(history.samples.first, 30 % 100)
    }

    func testRecentAsksForLessThanThereIs() {
        var history = GPUHistory()
        XCTAssertTrue(history.recent(16).isEmpty, "pusta historia nie ma czego oddać")
        for value in 1...5 { history.append(gpu(value)) }
        XCTAssertEqual(history.recent(3), [3, 4, 5])
        XCTAssertEqual(history.recent(50).count, 5, "nie wolno dorabiać próbek, których nie było")
    }
}
