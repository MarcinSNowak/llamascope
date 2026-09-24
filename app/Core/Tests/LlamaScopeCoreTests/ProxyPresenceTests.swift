import LlamaScopeText
import XCTest
@testable import LlamaScopeCore

final class ProxyPresenceTests: XCTestCase {
    /// Najważniejszy test w tym pliku. Gdy na porcie coś słucha, a to nie
    /// nasz proces, nie wolno napisać „wyłączony" — to byłoby spokojne zero
    /// tej samej rodziny co `truncated = 0`.
    ///
    /// Reguła nie zależy od języka, więc i test nie zależy. Wersja
    /// angielska, w której „port zajęty" brzmi uspokajająco, byłaby tym
    /// samym błędem popełnionym raz jeszcze, tylko ciszej.
    func testABusyPortIsNeverCalledOff() {
        let foreign = ProxyPresence.foreign(port: 11435)
        XCTAssertFalse(foreign.isRunning, "cudzego procesu nie liczymy jako swojego")

        XCTAssertFalse(ProxyPresenceText.headline(foreign, in: .polish)
            .lowercased().contains("wyłączon"))
        XCTAssertFalse(ProxyPresenceText.sentence(foreign, in: .polish)
            .contains("Tego procesu nie ma"))

        XCTAssertFalse(ProxyPresenceText.headline(foreign, in: .english)
            .lowercased().contains(" off"))
        XCTAssertFalse(ProxyPresenceText.sentence(foreign, in: .english)
            .contains("does not exist"))
    }

    /// „Wyłączony" znaczy coś, co da się sprawdzić bez wiary w nas — i to
    /// zdanie ma mówić, czym to sprawdzić (§12). W obu językach, bo to jest
    /// treść obietnicy, a nie uprzejmość.
    func testBeingOffPointsAtHowToCheckIt() {
        let polish = ProxyPresenceText.sentence(.off, in: .polish)
        XCTAssertTrue(polish.contains("Monitorze aktywności"))
        XCTAssertTrue(polish.contains("lsof"))

        let english = ProxyPresenceText.sentence(.off, in: .english)
        XCTAssertTrue(english.contains("Activity Monitor"))
        XCTAssertTrue(english.contains("lsof"))
    }

    func testABusyPortComesWithACommandToRun() {
        for language in Language.allCases {
            let advice = ProxyPresenceText.howToFix(.foreign(port: 11435), in: language)
            XCTAssertEqual(advice?.contains("lsof -nP -iTCP:11435 -sTCP:LISTEN"), true,
                           "brak komendy w języku \(language.rawValue)")
            XCTAssertNil(ProxyPresenceText.howToFix(.off, in: language),
                         "dobry stan nie potrzebuje rady")
            XCTAssertNil(ProxyPresenceText.howToFix(.listening(port: 11435), in: language))
        }
    }

    func testAListeningProxyTellsYouWhatToSetInTheClient() {
        for language in Language.allCases {
            let sentence = ProxyPresenceText.sentence(.listening(port: 11435), in: language)
            XCTAssertTrue(sentence.contains("OLLAMA_HOST=http://127.0.0.1:11435"),
                          "dostaliśmy: \(sentence)")
            XCTAssertTrue(sentence.contains("/v1"), "dostaliśmy: \(sentence)")
        }
        XCTAssertTrue(ProxyPresence.listening(port: 11435).isRunning)
    }

    /// Włączenie pośrednika zmienia to, co §9 obiecuje o całym narzędziu.
    /// Zdanie o tym musi mówić obie rzeczy naraz: że widzi, i co z tego
    /// zapisuje — samo „widzi" straszy, samo „zapisuje liczby" uspokaja.
    func testThePrivacyWarningSaysBothWhatItSeesAndWhatItKeeps() {
        let polish = ProxyPresenceText.seesPrompts(in: .polish)
        XCTAssertTrue(polish.contains("widzi treści promptów"))
        XCTAssertTrue(polish.contains("nigdy treść"))
        XCTAssertTrue(polish.contains("na tym dysku"))

        let english = ProxyPresenceText.seesPrompts(in: .english)
        XCTAssertTrue(english.contains("sees the contents"))
        XCTAssertTrue(english.contains("never"))
        XCTAssertTrue(english.contains("only on this disk"))
    }

    /// Powód awarii przychodzi gotowy i ma zostać powtórzony słowo w słowo.
    /// Gdyby któraś wersja językowa podmieniła go na własne zdanie, kod
    /// wyjścia pośrednika znikałby dokładnie wtedy, gdy jest potrzebny.
    func testAFailureRepeatsTheReasonInsteadOfSwallowingIt() {
        let presence = ProxyPresence.failed(reason: "proces zakończył się z kodem 1")
        for language in Language.allCases {
            XCTAssertEqual(ProxyPresenceText.sentence(presence, in: language),
                           "proces zakończył się z kodem 1")
            XCTAssertNotNil(ProxyPresenceText.howToFix(presence, in: language))
        }
        XCTAssertFalse(presence.isRunning)
    }

    /// Każdy stan ma nagłówek i zdanie w **obu** językach. Bez tego
    /// dopisanie stanu i zapomnienie o jednym z języków daje pusty napis
    /// w panelu — a pusty napis w pasku menu wygląda jak awaria.
    func testEveryPresenceHasWordsInBothLanguages() {
        let states: [ProxyPresence] = [
            .off, .starting, .listening(port: 11435), .foreign(port: 11435),
            .failed(reason: "powód"),
        ]
        for language in Language.allCases {
            for state in states {
                XCTAssertFalse(ProxyPresenceText.headline(state, in: language).isEmpty,
                               "bez nagłówka: \(state) / \(language.rawValue)")
                XCTAssertFalse(ProxyPresenceText.sentence(state, in: language).isEmpty,
                               "bez zdania: \(state) / \(language.rawValue)")
            }
        }
    }
}
