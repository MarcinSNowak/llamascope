import LlamaScopeText
import XCTest
@testable import LlamaScopeCore

final class AppStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func model(
        name: String = "qwen2.5-coder:14b",
        size: UInt64 = 9_000_000_000,
        vram: UInt64 = 9_000_000_000,
        expiresIn: TimeInterval? = nil
    ) -> LoadedModel {
        LoadedModel(
            name: name, sizeBytes: size, sizeVRAMBytes: vram,
            contextTokens: 2048, expiresAt: expiresIn.map { now.addingTimeInterval($0) }
        )
    }

    private func busyGPU(_ percent: Int) -> GPUReading {
        .reading(percent: percent, serviceClass: "AGXAccelerator", key: "Device Utilization %")
    }

    private func logWithTruncation(secondsAgo: TimeInterval) -> OllamaLogState {
        var state = OllamaLogState()
        state.apply([.inputTruncated(InputTruncation(
            time: now.addingTimeInterval(-secondsAgo),
            limitTokens: 258, promptTokens: 7260, keptTokens: 4, readTokens: 258
        ))])
        return state
    }

    func testFreshTruncationWinsOverEverythingElse() {
        let state = StateRecognizer.recognize(StateInput(
            now: now,
            models: [model(vram: 4_000_000_000)],   // także poza GPU
            gpu: busyGPU(90),                        // także pracuje
            swap: .worsened(grownGB: 3),             // także pamięć
            log: logWithTruncation(secondsAgo: 10)
        ))
        guard case let .promptTruncated(truncation) = state else {
            return XCTFail("ucięcie ma być pierwsze, dostaliśmy \(state)")
        }
        XCTAssertEqual(truncation.lostTokens, 7002)
    }

    /// Ucięcie sprzed godziny to historia, nie stan. Inaczej powtórzyłby się
    /// błąd stanu 3 z §5: ostrzeżenie wiszące na okrągło przestaje
    /// cokolwiek znaczyć.
    func testOldTruncationStopsBeingTheCurrentState() {
        let state = StateRecognizer.recognize(StateInput(
            now: now, models: [], gpu: busyGPU(0), swap: .steady,
            log: logWithTruncation(secondsAgo: 3600)
        ))
        XCTAssertEqual(state, .asleep)
    }

    /// Log ze zdarzeniem z przyszłości oznacza przestawiony zegar albo
    /// pomyloną strefę. Wtedy milczymy, zamiast alarmować bez końca.
    func testTruncationFromTheFutureIsIgnored() {
        let state = StateRecognizer.recognize(StateInput(
            now: now, models: [], gpu: busyGPU(0), swap: .steady,
            log: logWithTruncation(secondsAgo: -600)
        ))
        XCTAssertEqual(state, .asleep)
    }

    func testModelOutsideGPUIsReportedWithTheAmount() {
        let state = StateRecognizer.recognize(StateInput(
            now: now,
            models: [model(size: 9_000_000_000, vram: 6_900_000_000)],
            gpu: busyGPU(80), swap: .steady
        ))
        guard case let .modelOutsideGPU(_, bytes) = state else {
            return XCTFail("spodziewany model poza GPU, dostaliśmy \(state)")
        }
        XCTAssertEqual(bytes, 2_100_000_000)
    }

    /// Przy pełnym załadowaniu `size_vram` bywa o ułamek procenta mniejsze
    /// niż `size`. To nie jest liczenie na procesorze i nie może zapalać
    /// ostrzeżenia przy każdym modelu.
    func testAlmostFullVRAMCountsAsFullyOnGPU() {
        let state = StateRecognizer.recognize(StateInput(
            now: now,
            models: [model(size: 9_000_000_000, vram: 8_991_000_000)],
            gpu: busyGPU(80), swap: .steady
        ))
        guard case .working = state else {
            return XCTFail("99% w VRAM to nie jest liczenie poza GPU, dostaliśmy \(state)")
        }
    }

    func testTheHeavierSpilledModelIsTheOneReported() {
        let state = StateRecognizer.recognize(StateInput(
            now: now,
            models: [
                model(name: "mały", size: 2_000_000_000, vram: 1_500_000_000),
                model(name: "duży", size: 9_000_000_000, vram: 5_000_000_000),
            ],
            gpu: busyGPU(50), swap: .steady
        ))
        guard case let .modelOutsideGPU(spilled, _) = state else {
            return XCTFail("spodziewany model poza GPU, dostaliśmy \(state)")
        }
        XCTAssertEqual(spilled.name, "duży")
    }

    /// Reguła z §5: bez punktu odniesienia nie ostrzegamy wcale. Maszyna
    /// testowa ma stale mało wolnego swapu — ostrzeganie o zastanym stanie
    /// zamieniło wskaźnik w tapetę.
    func testWithoutASwapBaselineWeDoNotWarn() {
        let state = StateRecognizer.recognize(StateInput(
            now: now, models: [model(expiresIn: 180)],
            gpu: busyGPU(0), swap: .noBaseline
        ))
        guard case .holdingMemoryIdle = state else {
            return XCTFail("brak punktu odniesienia ma milczeć, dostaliśmy \(state)")
        }
    }

    func testSwapGrowthSinceStartIsReported() {
        let state = StateRecognizer.recognize(StateInput(
            now: now, models: [model()], gpu: busyGPU(0), swap: .worsened(grownGB: 4.3)
        ))
        XCTAssertEqual(state, .memoryRunningOut(grownGB: 4.3))
    }

    func testIdleModelReportsTimeToRelease() {
        let state = StateRecognizer.recognize(StateInput(
            now: now, models: [model(expiresIn: 180)], gpu: busyGPU(1), swap: .steady
        ))
        guard case let .holdingMemoryIdle(_, releasesIn) = state else {
            return XCTFail("spodziewane bezczynne trzymanie pamięci, dostaliśmy \(state)")
        }
        XCTAssertEqual(releasesIn ?? 0, 180, accuracy: 1)
    }

    func testExpiredKeepAliveGivesNoCountdown() {
        let state = StateRecognizer.recognize(StateInput(
            now: now, models: [model(expiresIn: -30)], gpu: busyGPU(0), swap: .steady
        ))
        guard case let .holdingMemoryIdle(_, releasesIn) = state else {
            return XCTFail("spodziewane bezczynne trzymanie pamięci, dostaliśmy \(state)")
        }
        XCTAssertNil(releasesIn, "przeterminowany odliczacz ma milczeć, a nie liczyć wstecz")
    }

    /// Stan pracy **nie** niesie tempa i to jest cała poprawka: Ollama
    /// zapisuje szybkość dopiero po skończonej odpowiedzi, więc liczba
    /// dostępna w trakcie pracy opisuje poprzednią odpowiedź. Widzieliśmy to
    /// na żywo — aplikacja pokazywała „57,4 tok/s" o generowaniu, które
    /// skończyło się kilkanaście sekund wcześniej.
    func testWorkingDoesNotCarryTheSpeedOfSomeEarlierAnswer() {
        var log = OllamaLogState()
        log.apply([.generationEval(EvalSpeed(tokens: 209, tokensPerSecond: 54.31))])
        let state = StateRecognizer.recognize(StateInput(
            now: now, models: [model()], gpu: busyGPU(96), swap: .steady, log: log
        ))
        guard case .working = state else {
            return XCTFail("spodziewana praca, dostaliśmy \(state)")
        }
        // W obu językach: liczba wzięta z poprzedniej odpowiedzi,
        // pokazana przy trwającej, opisuje co innego, niż się wydaje.
        for language in Language.allCases {
            XCTAssertFalse(StateText.sentence(state, in: language).contains("54"),
                           "tempo poprzedniej odpowiedzi wróciło do zdania o pracy")
            XCTAssertFalse(StateText.shortLabel(state, in: language).contains("tok/s"),
                           "tempo poprzedniej odpowiedzi wróciło na etykietę w pasku")
        }
    }

    func testFivePercentIsStillIdle() {
        let idle = StateRecognizer.recognize(StateInput(
            now: now, models: [model()], gpu: busyGPU(5), swap: .steady
        ))
        guard case .holdingMemoryIdle = idle else {
            return XCTFail("5% to jeszcze nie praca, dostaliśmy \(idle)")
        }
        let working = StateRecognizer.recognize(StateInput(
            now: now, models: [model()], gpu: busyGPU(6), swap: .steady
        ))
        guard case .working = working else {
            return XCTFail("6% to już praca, dostaliśmy \(working)")
        }
    }

    func testNothingLoadedIsCalmNotBroken() {
        XCTAssertEqual(
            StateRecognizer.recognize(StateInput(
                now: now, models: [], gpu: busyGPU(0), swap: .steady
            )),
            .asleep
        )
    }

    /// Sedno §10 przeniesione na stany: nieudany odczyt GPU nie może
    /// zostać wyświetlony jako bezczynność. Model liczący pełną parą przy
    /// zepsutym odczycie wyglądałby wtedy jak „trzyma pamięć i nic nie robi”.
    func testFailedGPUReadingIsNotShownAsIdle() {
        let state = StateRecognizer.recognize(StateInput(
            now: now, models: [model(expiresIn: 180)],
            gpu: .classNotFound(searched: GPUReader.knownClasses), swap: .steady
        ))
        guard case let .loadedActivityUnknown(_, reason) = state else {
            return XCTFail("brak odczytu ma być nazwany, dostaliśmy \(state)")
        }
        XCTAssertTrue(reason.logLine.contains("BRAK ODCZYTU"))
    }

    /// Ale gdy nic nie jest załadowane, zepsuty odczyt GPU niczego nie
    /// zmienia — stan i tak jest spokojny.
    func testFailedGPUReadingWithNothingLoadedIsStillAsleep() {
        XCTAssertEqual(
            StateRecognizer.recognize(StateInput(
                now: now, models: [],
                gpu: .statisticsNotFound(serviceClass: "AGXAccelerator"), swap: .steady
            )),
            .asleep
        )
    }
}

/// Powaga stanu, czyli to, z czego bierze się kolor ikony.
final class StateSeverityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func model() -> LoadedModel {
        LoadedModel(name: "qwen2.5-coder:14b", sizeBytes: 9_000_000_000, sizeVRAMBytes: 9_000_000_000)
    }

    /// Najważniejszy test w tym pliku. Niewiedza nie może dostać koloru
    /// spokoju — inaczej kolorem powiedzielibyśmy dokładnie to kłamstwo,
    /// przed którym broni ósmy i siódmy stan.
    func testNotKnowingIsNeverCalm() {
        XCTAssertEqual(
            AppState.loadedActivityUnknown(model: model(), reason: .classNotFound(searched: [])).severity,
            .unknown
        )
        XCTAssertEqual(AppState.ollamaNotResponding(reason: "brak").severity, .unknown)
        XCTAssertNotEqual(AppState.ollamaNotResponding(reason: "brak").severity, .calm)
    }

    func testTheThreeBadStatesAreAlarms() {
        let truncation = InputTruncation(time: now, limitTokens: 258, promptTokens: 7260, keptTokens: 4, readTokens: 258)
        XCTAssertEqual(AppState.promptTruncated(truncation).severity, .alarm)
        XCTAssertEqual(AppState.modelOutsideGPU(model: model(), bytesOutside: 2_100_000_000).severity, .alarm)
        XCTAssertEqual(AppState.memoryRunningOut(grownGB: 4.3).severity, .alarm)
    }

    func testCalmIsOnlyWhereNothingIsWrong() {
        XCTAssertEqual(AppState.asleep.severity, .calm)
        XCTAssertEqual(AppState.holdingMemoryIdle(model: model(), releasesIn: 180).severity, .calm)
        XCTAssertEqual(AppState.working(model: model()).severity, .busy)
    }
}
