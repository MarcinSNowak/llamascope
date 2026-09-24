import XCTest
@testable import LlamaScopeProxyCore

/// Kształty żądań przepisane z prawdziwego ruchu, nie ułożone pod kod.
enum RequestSamples {
    static func body(_ json: String) -> JSONValue {
        JSONValue.parse(Data(json.utf8))!
    }

    /// Kształt własny Ollamy.
    static func chat(messages: [(String, String)], system: String? = nil, numCtx: Int? = nil) -> JSONValue {
        var fields: [String: JSONValue] = [
            "model": .string("llama3.2:latest"),
            "messages": .array(messages.map { role, content in
                .object(["role": .string(role), "content": .string(content)])
            }),
        ]
        if let system { fields["system"] = .string(system) }
        if let numCtx { fields["options"] = .object(["num_ctx": .number(Double(numCtx))]) }
        return .object(fields)
    }

    static func generate(prompt: String, numCtx: Int? = nil) -> JSONValue {
        var fields: [String: JSONValue] = [
            "model": .string("llama3.2:latest"),
            "prompt": .string(prompt),
        ]
        if let numCtx { fields["options"] = .object(["num_ctx": .number(Double(numCtx))]) }
        return .object(fields)
    }

    static func text(_ count: Int) -> String { String(repeating: "a", count: count) }
}

final class PromptBreakdownTests: XCTestCase {
    func testMessagesToolsAndSystemAllCountTowardsTheWindow() {
        let body = RequestSamples.body("""
        {"model":"llama3.2","system":"jesteś pomocny",
         "tools":[{"type":"function","function":{"name":"pogoda"}}],
         "messages":[{"role":"user","content":"cześć"},
                     {"role":"assistant","content":"witaj"}]}
        """)
        let parts = PromptBreakdown.parts(of: body)

        XCTAssertEqual(parts.map(\.kind), [.tools, .system, .turn, .turn])
        XCTAssertEqual(parts[1].characters, "jesteś pomocny".count)
        XCTAssertGreaterThan(parts[0].characters, 20, "definicje narzędzi zajmują okno jak tekst")
    }

    /// Rola `system` wewnątrz `messages` to ta sama instrukcja systemowa co
    /// pole `system` — i przeżywa przycinanie tak samo. Gdyby liczyła się
    /// jako tura, pokazalibyśmy jako straconą rzecz, którą Ollama zachowuje.
    func testASystemRoleInsideMessagesIsNotATurn() {
        let parts = PromptBreakdown.parts(of: RequestSamples.chat(
            messages: [("system", "reguły"), ("user", "pytanie")]
        ))
        XCTAssertEqual(parts.map(\.kind), [.system, .turn])
        XCTAssertEqual(parts[0].label, "instrukcja systemowa")
    }

    /// Kształt OpenAI: treść jako lista kawałków. Klient Continue wysyła
    /// właśnie tak i przy liczeniu „content jako napis" wychodziło zero.
    func testContentAsAListOfChunksIsMeasuredNotSkipped() {
        let body = RequestSamples.body("""
        {"model":"gpt","messages":[{"role":"user","content":[
            {"type":"text","text":"pierwszy"},{"type":"text","text":"drugi"}]}]}
        """)
        XCTAssertEqual(PromptBreakdown.parts(of: body).first?.characters, "pierwszydrugi".count)
    }

    func testToolCallsInsideAMessageAreCounted() {
        let body = RequestSamples.body("""
        {"model":"m","messages":[{"role":"assistant","content":"",
          "tool_calls":[{"function":{"name":"pogoda","arguments":"{}"}}]}]}
        """)
        XCTAssertGreaterThan(PromptBreakdown.parts(of: body).first?.characters ?? 0, 20)
    }

    func testEmptyRequestHasNothingToBreakDown() {
        XCTAssertTrue(PromptBreakdown.parts(of: RequestSamples.body(#"{"model":"m"}"#)).isEmpty)
    }
}

final class ConversationVictimsTests: XCTestCase {
    private func parts(turns: [Int], system: Int? = nil) -> [PromptPart] {
        var parts: [PromptPart] = []
        if let system {
            parts.append(PromptPart(label: "instrukcja systemowa", characters: system, kind: .system))
        }
        for (index, size) in turns.enumerated() {
            parts.append(PromptPart(label: "wiadomość \(index + 1) (user)", characters: size, kind: .turn))
        }
        return parts
    }

    /// Ginie środek rozmowy, nie jej początek — i to jest cały powód,
    /// dla którego log Ollamy o tym milczy.
    func testTheOldestTurnsFallOutAndTheNewestSurvive() {
        let outcome = PromptBreakdown.conversationVictims(
            in: parts(turns: [100, 100, 100, 100]), characterBudget: 250
        )
        XCTAssertEqual(outcome.lost, ["wiadomość 1 (user) — cała", "wiadomość 2 (user) — cała"])
        XCTAssertFalse(outcome.overflowed)
    }

    /// Instrukcja systemowa wchodzi zawsze — kosztem tur, nie zamiast nich.
    /// Budżet 350 znaków przy instrukcji na 200 zostawia turom 150: najnowsza
    /// (100) wchodzi, starsza już nie.
    func testTheSystemPromptSurvivesAndEatsTheBudget() {
        let outcome = PromptBreakdown.conversationVictims(
            in: parts(turns: [100, 100], system: 200), characterBudget: 350
        )
        XCTAssertTrue(outcome.lost.contains("wiadomość 1 (user) — cała"))
        XCTAssertTrue(outcome.lost.contains("(instrukcja systemowa przeżywa — Ollama ją zachowuje)"))
    }

    /// Dopisek o instrukcji systemowej jest zdaniem dla człowieka, nie turą.
    /// Liczenie go do strat dałoby liczbę o jeden za dużą w pliku obserwacji
    /// — a to jest ten sam gatunek kłamstwa co `truncated = 0`: liczba
    /// wygląda na zmierzoną, a jest doliczona.
    func testTheNoteAboutTheSystemPromptIsNotCountedAsALostTurn() {
        let outcome = PromptBreakdown.conversationVictims(
            in: parts(turns: [100, 100], system: 200), characterBudget: 350
        )
        XCTAssertEqual(outcome.lostTurns, 1)
        XCTAssertEqual(outcome.lost.count, 2, "jedna tura i jeden dopisek")
    }

    /// Rozróżnienie, na którym stoi cała wartość pośrednika: gdy nie mieści
    /// się sama najnowsza wiadomość, wchodzi ucinanie po tokenach — i wtedy
    /// log Ollamy **widzi**. W każdym innym wypadku widzi tylko pośrednik.
    func testOverflowIsTheOnlyCaseTheOllamaLogCanSee() {
        let overflow = PromptBreakdown.conversationVictims(
            in: parts(turns: [5000]), characterBudget: 400
        )
        XCTAssertTrue(overflow.overflowed)
        XCTAssertEqual(overflow.lost.count, 1)
        XCTAssertTrue(overflow.lost[0].contains("po tokenach"))

        let quiet = PromptBreakdown.conversationVictims(
            in: parts(turns: [300, 300, 300]), characterBudget: 400
        )
        XCTAssertFalse(quiet.overflowed, "wypadnięcie starych tur jest dla logu niewidoczne")
    }

    func testNothingIsLostWhenEverythingFits() {
        let outcome = PromptBreakdown.conversationVictims(
            in: parts(turns: [10, 10]), characterBudget: 1000
        )
        XCTAssertTrue(outcome.lost.isEmpty)
        XCTAssertFalse(outcome.overflowed)
    }
}

final class RequestAnalystTests: XCTestCase {
    private var calibrator = Calibrator()

    private func analyse(
        path: String, body: JSONValue, window: Int?, reported: Int? = nil
    ) -> RequestReport? {
        RequestAnalyst.analyse(
            path: path, body: body,
            window: window.map { ContextWindow(tokens: $0, source: .explicitOption) },
            reportedTokens: reported, calibrator: &calibrator
        )
    }

    /// Fizyka, nie heurystyka: przy najostrożniejszym szacunku (4 znaki na
    /// token) 40 000 znaków to ponad 10 000 tokenów, a okno ma 512.
    func testAPromptThatCannotFitIsCalledTruncatedNotRisky() {
        let report = analyse(
            path: "/api/generate",
            body: RequestSamples.generate(prompt: RequestSamples.text(40_000), numCtx: 512),
            window: 512
        )
        XCTAssertEqual(report?.assessment, .truncated)
        XCTAssertGreaterThan(report?.excessTokens ?? 0, 9000)
        XCTAssertTrue(report?.lost.first?.contains("prompt") ?? false)
    }

    /// Przedział przecina granicę okna. Milczenie byłoby tu gorsze niż
    /// fałszywy alarm — model odpowie pewnie i błędnie.
    func testAnEstimateCrossingTheWindowIsReportedAsRisk() {
        let report = analyse(
            path: "/api/generate",
            body: RequestSamples.generate(prompt: RequestSamples.text(3000)),
            window: 1000
        )
        XCTAssertEqual(report?.assessment, .risk)
        XCTAssertLessThanOrEqual(report?.estimateLow ?? 0, 1000)
        XCTAssertGreaterThan(report?.estimateHigh ?? 0, 1000)
    }

    func testAPromptWellInsideTheWindowIsQuiet() {
        let report = analyse(
            path: "/api/generate",
            body: RequestSamples.generate(prompt: RequestSamples.text(400)),
            window: 4096
        )
        XCTAssertEqual(report?.assessment, .fine)
        XCTAssertTrue(report?.lost.isEmpty ?? false)
    }

    /// Bez tego rozróżnienia narzędzie krzyczałoby przy każdej kolejnej
    /// turze rozmowy: Ollama przelicza tylko nową część i zgłasza mniej
    /// tokenów, co wygląda dokładnie jak ucięcie.
    func testACacheHitIsNotMistakenForTruncation() {
        let report = analyse(
            path: "/api/chat",
            body: RequestSamples.chat(messages: [("user", RequestSamples.text(4000))]),
            window: 32_768, reported: 60
        )
        XCTAssertEqual(report?.assessment, .cache)
    }

    /// Przy rozmowie strata jest dla logu Ollamy niewidoczna — to jedyny
    /// powód, dla którego pośrednik w ogóle istnieje (§5).
    ///
    /// Wiadomości dobrane tak, żeby każda z osobna mieściła się w oknie,
    /// a razem nie — bo tylko wtedy Ollama przycina rozmowę po całych
    /// wiadomościach i milczy. Gdy nie mieści się sama najnowsza, wchodzi
    /// ucinanie po tokenach i log przestaje być ślepy.
    func testAConversationLossIsMarkedAsInvisibleInTheOllamaLog() {
        let turn = RequestSamples.text(700)
        let report = analyse(
            path: "/api/chat",
            body: RequestSamples.chat(
                messages: [("user", turn), ("assistant", turn), ("user", turn),
                           ("assistant", turn), ("user", turn)],
                numCtx: 512
            ),
            window: 512
        )
        XCTAssertEqual(report?.assessment, .truncated)
        XCTAssertEqual(report?.visibleInOllamaLog, false)
        XCTAssertTrue(report?.lost.contains { $0.contains("wiadomość 1") } ?? false)
    }

    /// A ucięcie pojedynczej wielkiej wiadomości log widzi — i tu pośrednik
    /// ma mówić to samo co aplikacja, a nie coś innego.
    func testASingleOversizedMessageIsMarkedAsVisibleInTheLog() {
        let report = analyse(
            path: "/api/chat",
            body: RequestSamples.chat(messages: [("user", RequestSamples.text(40_000))], numCtx: 512),
            window: 512
        )
        XCTAssertEqual(report?.assessment, .truncated)
        XCTAssertEqual(report?.visibleInOllamaLog, true)
    }

    func testARequestWithoutAnyPromptIsNotReportedAtAll() {
        XCTAssertNil(analyse(path: "/api/chat", body: RequestSamples.body(#"{"model":"m"}"#), window: 4096))
    }

    /// Bez okna nie zgadujemy. Nie znamy granicy — nie ma ostrzeżenia.
    func testWithoutAKnownWindowThereIsNoWarning() {
        let report = analyse(
            path: "/api/generate",
            body: RequestSamples.generate(prompt: RequestSamples.text(40_000)),
            window: nil
        )
        XCTAssertEqual(report?.assessment, .fine)
        XCTAssertNil(report?.window)
    }

    /// Ucięte żądanie nie może uczyć kalibratora — stosunek znaków do
    /// tokenów jest wtedy absurdalny, bo policzono tylko resztkę promptu.
    func testATruncatedRequestDoesNotPoisonTheCalibration() {
        _ = analyse(
            path: "/api/generate",
            body: RequestSamples.generate(prompt: RequestSamples.text(40_000), numCtx: 512),
            window: 512, reported: 258
        )
        XCTAssertEqual(calibrator.band(for: "llama3.2:latest").samples, 0)
    }

    /// Za to żądanie ostrzeżone, ale nieucięte, jest pełnowartościową
    /// próbką — inaczej narzędzie, które raz zaczęło ostrzegać, nigdy by
    /// się nie douczyło i ostrzegało w kółko.
    func testAWarnedButIntactRequestStillTeachesTheCalibrator() {
        _ = analyse(
            path: "/api/generate",
            body: RequestSamples.generate(prompt: RequestSamples.text(3000)),
            window: 1000, reported: 1000
        )
        XCTAssertEqual(calibrator.band(for: "llama3.2:latest").samples, 1)
    }
}

final class ContextWindowTests: XCTestCase {
    /// Jawne `num_ctx` wygrywa ze stanem załadowanego modelu, bo to ono
    /// zadecyduje o przeładowaniu.
    func testAnExplicitOptionIsRecognised() {
        let window = ContextWindow.declared(in: RequestSamples.generate(prompt: "x", numCtx: 8192))
        XCTAssertEqual(window?.tokens, 8192)
        XCTAssertEqual(window?.source, .explicitOption)
    }

    func testWithoutAnExplicitOptionThereIsNothingToDeclare() {
        XCTAssertNil(ContextWindow.declared(in: RequestSamples.generate(prompt: "x")))
    }

    /// Klienci składają żądania z konfiguracji, a w konfiguracji wszystko
    /// bywa napisem.
    func testANumericStringIsStillANumber() {
        let body = RequestSamples.body(#"{"model":"m","options":{"num_ctx":"2048"}}"#)
        XCTAssertEqual(ContextWindow.declared(in: body)?.tokens, 2048)
    }
}

final class CalibratorTests: XCTestCase {
    func testWithoutSamplesItAdmitsToGuessing() {
        let band = Calibrator().band(for: "llama3.2")
        XCTAssertEqual(band.low, Calibrator.startingBand.low)
        XCTAssertEqual(band.samples, 0)
    }

    func testShortRequestsAreTooNoisyToLearnFrom() {
        var calibrator = Calibrator()
        calibrator.add(model: "m", characters: 300, tokens: 100)
        XCTAssertEqual(calibrator.band(for: "m").samples, 0)
    }

    /// Absurdalny stosunek znaczy, że coś się stało z żądaniem — trafienie
    /// w pamięć podręczną albo ucięcie. Jedno i drugie zatrułoby kalibrację.
    func testImpossibleRatiosAreRejected() {
        var calibrator = Calibrator()
        calibrator.add(model: "m", characters: 40_000, tokens: 258)   // ucięcie
        calibrator.add(model: "m", characters: 1000, tokens: 800)     // 1,25 znaku na token
        XCTAssertEqual(calibrator.band(for: "m").samples, 0)
    }

    func testTheBandNarrowsWithSamplesButNeverBelowTenPercent() {
        var calibrator = Calibrator()
        for _ in 0..<50 { calibrator.add(model: "m", characters: 3000, tokens: 1000) }
        let band = calibrator.band(for: "m")
        XCTAssertEqual(band.samples, Calibrator.sampleLimit, "pamiętamy tylko ostatnie próbki")
        XCTAssertEqual(band.low, 3.0 * 0.9, accuracy: 0.01)
        XCTAssertEqual(band.high, 3.0 * 1.1, accuracy: 0.01)
    }

    func testModelsAreLearnedSeparately() {
        var calibrator = Calibrator()
        for _ in 0..<5 { calibrator.add(model: "polski", characters: 2400, tokens: 1000) }
        XCTAssertEqual(calibrator.band(for: "polski").samples, 5)
        XCTAssertEqual(calibrator.band(for: "kod").samples, 0)
    }
}

final class ProxyTextTests: XCTestCase {
    private func report(
        assessment: Assessment, path: String = "/api/chat",
        visible: Bool = true, lost: [String] = [], high: Int = 3000
    ) -> RequestReport {
        RequestReport(
            path: path, model: "llama3.2:latest", characters: 9000,
            estimatedTokens: 2500, estimateLow: 2000, estimateHigh: high,
            reportedTokens: 258,
            window: ContextWindow(tokens: 2048, source: .explicitOption),
            calibrationSamples: 4, assessment: assessment,
            excessTokens: 452, lost: lost, lostTurns: lost.count,
            visibleInOllamaLog: visible
        )
    }

    /// Najważniejsze zdanie całego pośrednika. Gdy strata jest dla logu
    /// niewidoczna, trzeba to powiedzieć wprost — inaczej człowiek sprawdzi
    /// log Ollamy, zobaczy spokój i uzna, że nic się nie stało.
    func testAnInvisibleLossSaysSoOutLoud() {
        let lines = ProxyText.lines(for: report(
            assessment: .truncated, visible: false, lost: ["wiadomość 1 (user) — cała"]
        ))
        XCTAssertTrue(lines.contains { $0.contains("widzi to tylko pośrednik") })
        XCTAssertTrue(lines.contains { $0.contains("wypadło z rozmowy") })
    }

    /// Długa rozmowa gubi kilkadziesiąt wiadomości naraz. Wypisanie ich
    /// wszystkich spycha radę poza ekran, a rada jest jedyną rzeczą, po którą
    /// ktoś tu przyszedł. Pełna lista zostaje w pliku obserwacji.
    func testALongListOfLossesIsCountedInsteadOfRecited() {
        var lost = (1...23).map { "wiadomość \($0) (user) — cała" }
        lost.append("(instrukcja systemowa przeżywa — Ollama ją zachowuje)")
        let lines = ProxyText.lines(for: report(
            assessment: .truncated, visible: false, lost: lost
        ))
        XCTAssertLessThanOrEqual(lines.count, 11)
        XCTAssertTrue(lines.contains { $0.contains("…i jeszcze 19") })
        XCTAssertTrue(lines.contains { $0.contains("instrukcja systemowa przeżywa") },
                      "dopisek niesie treść, więc nie wolno go uciąć razem z listą")
        XCTAssertFalse(
            lines.contains { $0.hasPrefix("wypadło z rozmowy: (instrukcja") },
            "„wypadło: przeżywa” to zdanie przeczące samemu sobie"
        )
        XCTAssertTrue(lines.last?.hasPrefix("rada:") ?? false)
    }

    func testAShortListIsShownInFull() {
        let lost = (1...4).map { "wiadomość \($0) (user) — cała" }
        let lines = ProxyText.lines(for: report(assessment: .truncated, lost: lost))
        XCTAssertFalse(lines.contains { $0.contains("…i jeszcze") })
        XCTAssertTrue(lines.contains { $0.contains("wiadomość 4") })
    }

    func testAVisibleTruncationUsesTheOtherVerb() {
        let lines = ProxyText.lines(for: report(assessment: .truncated, lost: ["prompt — początek, ok. 90%"]))
        XCTAssertTrue(lines.contains { $0.contains("ucięte: prompt") })
        XCTAssertFalse(lines.contains { $0.contains("tylko pośrednik") })
    }

    /// Rada ma być wykonalna. Przez `/v1` nie da się ustawić okna
    /// w żądaniu, więc rada „options.num_ctx" byłaby tam radą donikąd.
    func testAdviceForOpenAIPathsDoesNotTellYouToSetSomethingYouCannotSet() {
        let advice = ProxyText.advice(
            for: report(assessment: .truncated, path: "/v1/chat/completions"), modelMaximum: nil
        )
        XCTAssertTrue(advice.contains("OLLAMA_CONTEXT_LENGTH"))
        XCTAssertFalse(advice.contains("options.num_ctx"))
    }

    /// Gdy proponowane okno przekracza możliwości modelu, rada zmienia się
    /// na jedyną prawdziwą: skróć prompt.
    func testAdviceStopsProposingWindowsTheModelCannotDo() {
        let advice = ProxyText.advice(
            for: report(assessment: .truncated, high: 40_000), modelMaximum: 8192
        )
        XCTAssertTrue(advice.contains("najwyżej"))
        XCTAssertTrue(advice.contains("skróć prompt"))
    }

    func testAdviceProposesAPowerOfTwo() {
        XCTAssertEqual(ProxyText.nextPowerOfTwo(atLeast: 3000), 4096)
        XCTAssertEqual(ProxyText.nextPowerOfTwo(atLeast: 4096), 4096)
        XCTAssertEqual(ProxyText.nextPowerOfTwo(atLeast: 10), 1024)
    }

    func testAQuietRequestIsOneLineAndSaysHowSureWeAre() {
        let lines = ProxyText.lines(for: report(assessment: .fine))
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("kalibracja z 4 próbek"))
    }
}
