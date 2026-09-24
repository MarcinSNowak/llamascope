import XCTest
@testable import LlamaScopeText

/// Wybór języka i odmiana liczb.
///
/// Wygląda na drobiazg, więc warto powiedzieć wprost, czemu ma własny cel
/// testów: to jedyne miejsce w aplikacji, w którym **wszystkie** zdania
/// naraz mogą zacząć kłamać w sposób, którego nikt nie zauważy okiem.
/// „1 tokens" albo „4.3 GB" w polskim zdaniu to nie literówka, tylko
/// widoczny dowód, że tekst jest tłumaczeniem, a nie tekstem.
final class LanguageTests: XCTestCase {
    // MARK: - Wybór języka

    func testPolishOnlyWhenSomeoneAsksForIt() {
        XCTAssertEqual(Language.preferred(from: ["pl-PL", "en-US"]), .polish)
        XCTAssertEqual(Language.preferred(from: ["pl"]), .polish)
    }

    /// Język, którego nie mamy, nie przesłania tego, który mamy — nawet
    /// stojąc wyżej na liście. Lista preferencji systemu bywa długa i ktoś
    /// z niemieckim na pierwszym miejscu, a polskim na trzecim, prosi
    /// o polski tak samo wyraźnie.
    func testAnUnknownLanguageDoesNotHideAKnownOneBelowIt() {
        XCTAssertEqual(Language.preferred(from: ["de-DE", "fr-FR", "pl-PL"]), .polish)
        XCTAssertEqual(Language.preferred(from: ["de-DE", "en-GB", "pl-PL"]), .english)
    }

    /// Angielski, a nie polski, jest tu wyjściem awaryjnym. Z tych dwóch
    /// języków tylko on daje szansę, że ktoś w Lizbonie w ogóle przeczyta,
    /// co się stało z jego promptem.
    func testEnglishIsTheFallbackForEveryoneElse() {
        XCTAssertEqual(Language.preferred(from: ["de-DE", "fr-FR"]), .english)
        XCTAssertEqual(Language.preferred(from: []), .english)
    }

    // MARK: - Odmiana

    func testPolishPluralOfToken() {
        let word = { Numbers.tokenWord($0, in: .polish) }
        XCTAssertEqual(word(1), "token")
        XCTAssertEqual(word(2), "tokeny")
        XCTAssertEqual(word(4), "tokeny")
        XCTAssertEqual(word(5), "tokenów")
        XCTAssertEqual(word(0), "tokenów")
        // Nastolatki są wyjątkiem: 12 tokenów, nie 12 tokeny.
        XCTAssertEqual(word(12), "tokenów")
        XCTAssertEqual(word(14), "tokenów")
        // Ale końcówki 22-24 już nie.
        XCTAssertEqual(word(22), "tokeny")
        XCTAssertEqual(word(258), "tokenów")
        XCTAssertEqual(word(7260), "tokenów")
    }

    func testEnglishPluralOfToken() {
        XCTAssertEqual(Numbers.tokenWord(1, in: .english), "token")
        XCTAssertEqual(Numbers.tokenWord(0, in: .english), "tokens")
        XCTAssertEqual(Numbers.tokenWord(2, in: .english), "tokens")
        XCTAssertEqual(Numbers.tokenWord(22, in: .english), "tokens")
        XCTAssertEqual(Numbers.tokenWord(7260, in: .english), "tokens")
    }

    // MARK: - Znaki

    func testDecimalSeparatorFollowsTheLanguage() {
        XCTAssertEqual(Numbers(.polish).decimal(4.3), "4,3")
        XCTAssertEqual(Numbers(.english).decimal(4.3), "4.3")
        XCTAssertEqual(Numbers(.polish).gigabytes(9_000_000_000), "9,0 GB")
        XCTAssertEqual(Numbers(.english).gigabytes(9_000_000_000), "9.0 GB")
    }

    /// Separator tysięcy nie zależy od ustawień maszyny, na której to
    /// biegnie. `NumberFormatter` domyślnie bierze je z systemu, a wtedy ten
    /// test byłby zielony tu i czerwony u kogoś w Berlinie — czyli mówiłby
    /// o maszynie, a nie o programie.
    func testThousandsSeparatorDoesNotDependOnTheMachine() {
        XCTAssertEqual(Numbers(.polish).count(7260), "7\u{00A0}260")
        XCTAssertEqual(Numbers(.english).count(7260), "7,260")
        XCTAssertEqual(Numbers(.polish).count(258), "258")
        XCTAssertEqual(Numbers(.english).count(258), "258")
    }

    /// Spacja **nierozdzielająca**, nie zwykła. Liczba złamana na końcu
    /// wiersza czyta się jak dwie liczby.
    func testTheSpaceInPolishNumbersDoesNotBreak() {
        XCTAssertFalse(Numbers(.polish).count(7260).contains(" "))
    }

    func testDurationReadsTheSameInBothLanguages() {
        for language in Language.allCases {
            XCTAssertEqual(Numbers(language).duration(195), "3 min 15 s")
            XCTAssertEqual(Numbers(language).duration(42), "42 s")
        }
    }
}
