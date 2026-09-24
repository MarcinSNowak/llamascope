import LlamaScopeText
import XCTest
@testable import LlamaScopeCore

final class StateTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func model(size: UInt64 = 9_000_000_000, vram: UInt64 = 9_000_000_000) -> LoadedModel {
        LoadedModel(name: "qwen2.5-coder:14b", sizeBytes: size, sizeVRAMBytes: vram)
    }

    private var truncation: InputTruncation {
        InputTruncation(
            time: now, limitTokens: 258, promptTokens: 7260, keptTokens: 4, readTokens: 258
        )
    }

    private var everyState: [AppState] {
        [
            .promptTruncated(truncation),
            .modelOutsideGPU(model: model(vram: 6_900_000_000), bytesOutside: 2_100_000_000),
            .memoryRunningOut(grownGB: 4.3),
            .holdingMemoryIdle(model: model(), releasesIn: 180),
            .working(model: model()),
            .asleep,
            .loadedActivityUnknown(
                model: model(), reason: .statisticsNotFound(serviceClass: "AGXAccelerator")
            ),
            .ollamaNotResponding(reason: "brak połączenia"),
        ]
    }

    // MARK: - Reguły, które obowiązują w obu językach

    /// Zdanie z §5, co do sensu: ile wysłane, ile przeczytane, ile przepadło.
    /// Liczby są tą samą treścią w każdym języku, więc i test jest wspólny.
    func testTruncationSentenceCarriesBothNumbers() {
        for language in Language.allCases {
            let sentence = StateText.sentence(.promptTruncated(truncation), in: language)
            XCTAssertTrue(sentence.contains("260"), "brakuje liczby wysłanych: \(sentence)")
            XCTAssertTrue(sentence.contains("258"), "brakuje liczby przeczytanych: \(sentence)")
            XCTAssertTrue(sentence.contains("96%"), "brakuje udziału straty: \(sentence)")
        }
    }

    /// Najważniejszy test w tym pliku. Żaden stan niepewności nie może
    /// zabrzmieć jak spokój — ani w menu, ani na etykiecie w pasku, ani
    /// w drugim języku, którego autor na co dzień nie czyta.
    func testUncertainStatesNeverSoundCalm() {
        let unknown = AppState.loadedActivityUnknown(
            model: model(), reason: .classNotFound(searched: GPUReader.knownClasses)
        )
        let down = AppState.ollamaNotResponding(reason: "brak połączenia")

        XCTAssertTrue(StateText.sentence(unknown, in: .polish).contains("nie wiem"))
        XCTAssertTrue(StateText.sentence(unknown, in: .english).contains("do not know"))
        XCTAssertTrue(StateText.sentence(down, in: .polish).contains("nie odpowiada"))
        XCTAssertTrue(StateText.sentence(down, in: .english).contains("not responding"))

        for language in Language.allCases {
            XCTAssertNotEqual(StateText.shortLabel(unknown, in: language),
                              StateText.shortLabel(.asleep, in: language))
            XCTAssertNotEqual(StateText.shortLabel(down, in: language),
                              StateText.shortLabel(.asleep, in: language))
        }
    }

    /// Każdy stan musi mieć zdanie i etykietę **w obu językach**. Gdyby
    /// doszedł nowy, a ktoś dopisał tekst tylko po polsku, angielski pasek
    /// menu pokazałby pustkę — a pustka wygląda jak awaria.
    func testEveryStateHasWordsInBothLanguages() {
        for language in Language.allCases {
            for state in everyState {
                XCTAssertFalse(StateText.sentence(state, in: language).isEmpty,
                               "bez zdania: \(state) / \(language.rawValue)")
                XCTAssertFalse(StateText.shortLabel(state, in: language).isEmpty,
                               "bez etykiety: \(state) / \(language.rawValue)")
                XCTAssertFalse(StateText.headline(state, in: language).isEmpty,
                               "bez nagłówka: \(state) / \(language.rawValue)")
            }
        }
    }

    /// Pierwsza reguła z §7: nagłówek to zdanie, liczby są niżej. Gdyby
    /// w nagłówku siedziała liczba, panel zaczynałby się od uzasadnienia,
    /// a nie od tego, co się stało.
    func testHeadlineIsASentenceWithoutNumbers() {
        for language in Language.allCases {
            for state in everyState {
                let headline = StateText.headline(state, in: language)
                XCTAssertNil(headline.rangeOfCharacter(from: .decimalDigits),
                             "liczba w nagłówku: \(headline)")
            }
        }
    }

    /// Rada ma być przy każdym złym stanie i **nie może** być przy dobrym.
    /// Zdanie doklejone do spokoju zamienia panel w tapetę — ten sam błąd,
    /// który raz już popełniliśmy przy ostrzeżeniu o swapie (§5).
    func testAdviceOnlyWhereThereIsSomethingToFix() {
        for language in Language.allCases {
            XCTAssertNil(StateText.howToFix(.asleep, in: language))
            XCTAssertNil(StateText.howToFix(.working(model: model()), in: language))
            XCTAssertNil(
                StateText.howToFix(.holdingMemoryIdle(model: model(), releasesIn: 180), in: language),
                "ten stan ma przycisk, więc rada byłaby powtórzeniem"
            )

            // Rada bez nazwy pokrętła jest życzeniem, nie radą — i nazwa
            // pokrętła jest ta sama w każdym języku, bo to nazwa pola w API.
            let advice = StateText.howToFix(.promptTruncated(truncation), in: language)
            XCTAssertNotNil(advice)
            XCTAssertTrue(advice?.contains("num_ctx") ?? false, "dostaliśmy: \(advice ?? "")")
            XCTAssertTrue(advice?.contains("258") ?? false, "rada nie mówi, jakie jest okno")

            XCTAssertTrue(
                StateText.howToFix(.ollamaNotResponding(reason: "x"), in: language)?
                    .contains("ollama serve") ?? false
            )
        }
    }

    /// Granica wykrywania jest wymogiem z §5, nie ozdobą, więc musi
    /// nazywać rozmowę po imieniu, a nie mówić ogólnie o ograniczeniach.
    func testTheDetectionLimitNamesTheCaseItMisses() {
        let polish = StateText.detectionLimit(in: .polish)
        XCTAssertTrue(polish.contains("rozmowa"))
        XCTAssertTrue(polish.contains("nie zobaczę"))

        let english = StateText.detectionLimit(in: .english)
        XCTAssertTrue(english.contains("conversation"))
        XCTAssertTrue(english.contains("will not see"))
    }

    /// Odliczanie pokazujemy tylko wtedy, gdy je mamy. Udawane odliczanie
    /// byłoby liczbą wziętą znikąd — w obu językach tak samo.
    func testIdleSentenceCountsDownWhenItCan() {
        for language in Language.allCases {
            let withCountdown = StateText.sentence(
                .holdingMemoryIdle(model: model(), releasesIn: 195), in: language
            )
            XCTAssertTrue(withCountdown.contains("3 min 15 s"), "dostaliśmy: \(withCountdown)")
        }

        XCTAssertFalse(
            StateText.sentence(.holdingMemoryIdle(model: model(), releasesIn: nil), in: .polish)
                .contains("zwolni"),
            "bez odliczacza nie wolno go udawać"
        )
        XCTAssertFalse(
            StateText.sentence(.holdingMemoryIdle(model: model(), releasesIn: nil), in: .english)
                .contains("releasing in"),
            "bez odliczacza nie wolno go udawać"
        )
    }

    /// Zajętość okna to jedyna liczba, którą widać, **zanim** coś się utnie.
    func testWindowFillShowsBothNumbersAndTheShare() {
        let prompt = PromptAccepted(task: 164, windowTokens: 2048, keepTokens: 4, promptTokens: 1978)
        for language in Language.allCases {
            let text = StateText.windowFill(prompt, in: language)
            XCTAssertTrue(text.contains("978"), "dostaliśmy: \(text)")
            XCTAssertTrue(text.contains("048"), "dostaliśmy: \(text)")
            XCTAssertTrue(text.contains("97%"), "dostaliśmy: \(text)")
        }
    }

    // MARK: - Rzeczy, które różnią się między językami

    /// Tekst po polsku ma mieć przecinek dziesiętny, angielski kropkę.
    /// Drobiazg, ale widać go w każdym stanie z liczbą gigabajtów — i to
    /// po nim najszybciej widać, że jeden z tych tekstów jest przekładem
    /// drugiego, a nie własnym zdaniem.
    func testDecimalSeparatorFollowsTheLanguageOfTheSentence() {
        let polish = StateText.sentence(.memoryRunningOut(grownGB: 4.3), in: .polish)
        XCTAssertTrue(polish.contains("4,3"), "dostaliśmy: \(polish)")
        XCTAssertFalse(polish.contains("4.3"))

        let english = StateText.sentence(.memoryRunningOut(grownGB: 4.3), in: .english)
        XCTAssertTrue(english.contains("4.3"), "dostaliśmy: \(english)")
        XCTAssertFalse(english.contains("4,3"))
    }

    /// Dwa języki mają brzmieć inaczej, a nie tak samo. Gdyby któryś stan
    /// został dopisany tylko raz i wklejony do obu gałęzi, ten test to
    /// pokaże — a panel pokazałby wtedy polskie zdanie komuś, kto go nie
    /// przeczyta.
    func testTheTwoLanguagesActuallyDiffer() {
        for state in everyState {
            XCTAssertNotEqual(StateText.headline(state, in: .polish),
                              StateText.headline(state, in: .english),
                              "ten sam nagłówek w obu językach: \(state)")
        }
    }
}
