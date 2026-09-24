import XCTest
@testable import LlamaScopeCore

final class ProxyPresenceTests: XCTestCase {
    /// Najważniejszy test w tym pliku. Gdy na porcie coś słucha, a to nie
    /// nasz proces, nie wolno napisać „wyłączony" — to byłoby spokojne zero
    /// tej samej rodziny co `truncated = 0`.
    func testABusyPortIsNeverCalledOff() {
        let foreign = ProxyPresence.foreign(port: 11435)
        XCTAssertFalse(ProxyPresenceText.headline(foreign).lowercased().contains("wyłączon"))
        XCTAssertFalse(ProxyPresenceText.sentence(foreign).contains("Tego procesu nie ma"))
        XCTAssertFalse(foreign.isRunning, "cudzego procesu nie liczymy jako swojego")
    }

    /// „Wyłączony" znaczy coś, co da się sprawdzić bez wiary w nas — i to
    /// zdanie ma mówić, czym to sprawdzić (§12).
    func testBeingOffPointsAtHowToCheckIt() {
        let sentence = ProxyPresenceText.sentence(.off)
        XCTAssertTrue(sentence.contains("Monitorze aktywności"))
        XCTAssertTrue(sentence.contains("lsof"))
    }

    func testABusyPortComesWithACommandToRun() {
        let advice = ProxyPresenceText.howToFix(.foreign(port: 11435))
        XCTAssertEqual(advice?.contains("lsof -nP -iTCP:11435 -sTCP:LISTEN"), true)
        XCTAssertNil(ProxyPresenceText.howToFix(.off), "dobry stan nie potrzebuje rady")
        XCTAssertNil(ProxyPresenceText.howToFix(.listening(port: 11435)))
    }

    func testAListeningProxyTellsYouWhatToSetInTheClient() {
        let sentence = ProxyPresenceText.sentence(.listening(port: 11435))
        XCTAssertTrue(sentence.contains("OLLAMA_HOST=http://127.0.0.1:11435"))
        XCTAssertTrue(sentence.contains("/v1"))
        XCTAssertTrue(ProxyPresence.listening(port: 11435).isRunning)
    }

    /// Włączenie pośrednika zmienia to, co §9 obiecuje o całym narzędziu.
    /// Zdanie o tym musi mówić obie rzeczy naraz: że widzi, i co z tego
    /// zapisuje — samo „widzi" straszy, samo „zapisuje liczby" uspokaja.
    func testThePrivacyWarningSaysBothWhatItSeesAndWhatItKeeps() {
        XCTAssertTrue(ProxyPresenceText.seesPrompts.contains("widzi treści promptów"))
        XCTAssertTrue(ProxyPresenceText.seesPrompts.contains("nigdy treść"))
        XCTAssertTrue(ProxyPresenceText.seesPrompts.contains("na tym dysku"))
    }

    func testAFailureRepeatsTheReasonInsteadOfSwallowingIt() {
        let presence = ProxyPresence.failed(reason: "proces zakończył się z kodem 1")
        XCTAssertEqual(ProxyPresenceText.sentence(presence), "proces zakończył się z kodem 1")
        XCTAssertNotNil(ProxyPresenceText.howToFix(presence))
        XCTAssertFalse(presence.isRunning)
    }
}
