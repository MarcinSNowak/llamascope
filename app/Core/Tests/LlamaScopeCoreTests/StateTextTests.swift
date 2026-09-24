import XCTest
@testable import LlamaScopeCore

final class StateTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func model(size: UInt64 = 9_000_000_000, vram: UInt64 = 9_000_000_000) -> LoadedModel {
        LoadedModel(name: "qwen2.5-coder:14b", sizeBytes: size, sizeVRAMBytes: vram)
    }

    /// Zdanie z §5, słowo w słowo co do sensu: ile wysłane, ile przeczytane.
    func testTruncationSentenceCarriesBothNumbers() {
        let sentence = StateText.sentence(.promptTruncated(InputTruncation(
            time: now, limitTokens: 258, promptTokens: 7260, keptTokens: 4, readTokens: 258
        )))
        XCTAssertTrue(sentence.contains("7"), "brakuje liczby wysłanych tokenów: \(sentence)")
        XCTAssertTrue(sentence.contains("260"), "brakuje liczby wysłanych tokenów: \(sentence)")
        XCTAssertTrue(sentence.contains("258"), "brakuje liczby przeczytanych tokenów: \(sentence)")
        XCTAssertTrue(sentence.contains("96%"), "brakuje udziału straty: \(sentence)")
    }

    func testPolishPluralOfToken() {
        XCTAssertEqual(StateText.tokenWord(1), "token")
        XCTAssertEqual(StateText.tokenWord(2), "tokeny")
        XCTAssertEqual(StateText.tokenWord(4), "tokeny")
        XCTAssertEqual(StateText.tokenWord(5), "tokenów")
        XCTAssertEqual(StateText.tokenWord(0), "tokenów")
        // Nastolatki są wyjątkiem: 12 tokenów, nie 12 tokeny.
        XCTAssertEqual(StateText.tokenWord(12), "tokenów")
        XCTAssertEqual(StateText.tokenWord(14), "tokenów")
        // Ale końcówki 22-24 już nie.
        XCTAssertEqual(StateText.tokenWord(22), "tokeny")
        XCTAssertEqual(StateText.tokenWord(258), "tokenów")
        XCTAssertEqual(StateText.tokenWord(7260), "tokenów")
    }

    /// Tekst po polsku ma mieć przecinek dziesiętny. Drobiazg, ale widać go
    /// w każdym stanie z liczbą gigabajtów.
    func testDecimalCommaNotPoint() {
        let sentence = StateText.sentence(.memoryRunningOut(grownGB: 4.3))
        XCTAssertTrue(sentence.contains("4,3"), "dostaliśmy: \(sentence)")
        XCTAssertFalse(sentence.contains("4.3"))
    }

    func testIdleSentenceCountsDownWhenItCan() {
        let withCountdown = StateText.sentence(.holdingMemoryIdle(model: model(), releasesIn: 195))
        XCTAssertTrue(withCountdown.contains("3 min 15 s"), "dostaliśmy: \(withCountdown)")

        let without = StateText.sentence(.holdingMemoryIdle(model: model(), releasesIn: nil))
        XCTAssertFalse(without.contains("zwolni"), "bez odliczacza nie wolno go udawać: \(without)")
    }

    /// Najważniejszy test w tym pliku. Żaden stan niepewności nie może
    /// zabrzmieć jak spokój — ani w menu, ani na etykiecie w pasku.
    func testUncertainStatesNeverSoundCalm() {
        let unknown = AppState.loadedActivityUnknown(
            model: model(), reason: .classNotFound(searched: GPUReader.knownClasses)
        )
        XCTAssertTrue(StateText.sentence(unknown).contains("nie wiem"))
        XCTAssertNotEqual(StateText.shortLabel(unknown), StateText.shortLabel(.asleep))

        let down = AppState.ollamaNotResponding(reason: "brak połączenia")
        XCTAssertTrue(StateText.sentence(down).contains("nie odpowiada"))
        XCTAssertNotEqual(StateText.shortLabel(down), StateText.shortLabel(.asleep))
    }

    /// Każdy stan musi mieć zdanie i etykietę. Gdyby doszedł nowy, a ktoś
    /// zapomniał o tekście, pusty napis w pasku menu wygląda jak awaria.
    func testEveryStateHasWords() {
        let states: [AppState] = [
            .promptTruncated(InputTruncation(time: now, limitTokens: 258, promptTokens: 7260, keptTokens: 4, readTokens: 258)),
            .modelOutsideGPU(model: model(vram: 6_900_000_000), bytesOutside: 2_100_000_000),
            .memoryRunningOut(grownGB: 4.3),
            .holdingMemoryIdle(model: model(), releasesIn: 180),
            .working(model: model(), generation: EvalSpeed(tokens: 209, tokensPerSecond: 54.31)),
            .asleep,
            .loadedActivityUnknown(model: model(), reason: .statisticsNotFound(serviceClass: "AGXAccelerator")),
            .ollamaNotResponding(reason: "brak połączenia"),
        ]
        for state in states {
            XCTAssertFalse(StateText.sentence(state).isEmpty, "bez zdania: \(state)")
            XCTAssertFalse(StateText.shortLabel(state).isEmpty, "bez etykiety: \(state)")
        }
    }

    /// Granica wykrywania jest wymogiem z §5, nie ozdobą, więc musi
    /// nazywać rozmowę po imieniu, a nie mówić ogólnie o ograniczeniach.
    func testTheDetectionLimitNamesTheCaseItMisses() {
        XCTAssertTrue(StateText.detectionLimit.contains("rozmowa"))
        XCTAssertTrue(StateText.detectionLimit.contains("nie zobaczę"))
    }

    /// Pierwsza reguła z §7: nagłówek to zdanie, liczby są niżej. Gdyby
    /// w nagłówku siedziała liczba, panel zaczynałby się od uzasadnienia,
    /// a nie od tego, co się stało.
    func testHeadlineIsASentenceWithoutNumbers() {
        let states: [AppState] = [
            .promptTruncated(InputTruncation(time: now, limitTokens: 258, promptTokens: 7260, keptTokens: 4, readTokens: 258)),
            .modelOutsideGPU(model: model(vram: 6_900_000_000), bytesOutside: 2_100_000_000),
            .memoryRunningOut(grownGB: 4.3),
            .holdingMemoryIdle(model: model(), releasesIn: 180),
            .working(model: model(), generation: EvalSpeed(tokens: 209, tokensPerSecond: 54.31)),
            .asleep,
            .loadedActivityUnknown(model: model(), reason: .statisticsNotFound(serviceClass: "AGXAccelerator")),
            .ollamaNotResponding(reason: "brak połączenia"),
        ]
        for state in states {
            let headline = StateText.headline(state)
            XCTAssertFalse(headline.isEmpty, "bez nagłówka: \(state)")
            XCTAssertNil(headline.rangeOfCharacter(from: .decimalDigits),
                         "liczba w nagłówku: \(headline)")
        }
    }

    /// Rada ma być przy każdym złym stanie i **nie może** być przy dobrym.
    /// Zdanie doklejone do spokoju zamienia panel w tapetę — ten sam błąd,
    /// który raz już popełniliśmy przy ostrzeżeniu o swapie (§5).
    func testAdviceOnlyWhereThereIsSomethingToFix() {
        XCTAssertNil(StateText.howToFix(.asleep))
        XCTAssertNil(StateText.howToFix(.working(model: model(), generation: nil)))
        XCTAssertNil(StateText.howToFix(.holdingMemoryIdle(model: model(), releasesIn: 180)),
                     "ten stan ma przycisk, więc rada byłaby powtórzeniem")

        let truncated = AppState.promptTruncated(InputTruncation(
            time: now, limitTokens: 258, promptTokens: 7260, keptTokens: 4, readTokens: 258
        ))
        let advice = StateText.howToFix(truncated)
        XCTAssertNotNil(advice)
        // Rada bez nazwy pokrętła jest życzeniem, nie radą.
        XCTAssertTrue(advice?.contains("num_ctx") ?? false, "dostaliśmy: \(advice ?? "")")
        XCTAssertTrue(advice?.contains("258") ?? false, "rada nie mówi, jakie jest okno")

        XCTAssertTrue(StateText.howToFix(.ollamaNotResponding(reason: "x"))?.contains("ollama serve") ?? false)
    }

    /// Zajętość okna to jedyna liczba, którą widać, **zanim** coś się utnie.
    func testWindowFillShowsBothNumbersAndTheShare() {
        let text = StateText.windowFill(PromptAccepted(task: 164, windowTokens: 2048, keepTokens: 4, promptTokens: 1978))
        XCTAssertTrue(text.contains("978"), "dostaliśmy: \(text)")
        XCTAssertTrue(text.contains("048"), "dostaliśmy: \(text)")
        XCTAssertTrue(text.contains("97%"), "dostaliśmy: \(text)")
    }
}
