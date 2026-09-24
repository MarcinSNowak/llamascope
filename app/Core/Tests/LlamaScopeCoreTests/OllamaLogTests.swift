import XCTest
@testable import LlamaScopeCore

/// Wszystkie linie w tym pliku są **przepisane z żywego logu**
/// (`/opt/homebrew/var/log/ollama.log`, 9,2 MB, Ollama 0.32.14, M2 Pro),
/// a nie ułożone pod wzorzec. To jest cała wartość tych testów: wzorzec
/// dopasowany do wymyślonej linii przechodzi testy i nie działa u nikogo.
enum LogSamples {
    /// Ucięcie z pomiaru 2026-09-06 — prompt 11 907 tokenów, przeczytane 1026.
    static let truncation =
        #"time=2026-09-06T10:20:37.163+02:00 level=WARN source=llama_server.go:317 msg="truncating input prompt" limit=1026 prompt=11907 keep=4 new=1026"#

    /// Żądanie z K5 odcinka 7 — to, z którego przepadło 83% rozmowy.
    static let newPrompt =
        "slot   operator(): id  0 | task 164 | new prompt, n_ctx_slot = 2048, n_keep = 4, task.n_tokens = 1978"

    static let promptEval =
        "slot print_timing: id  0 | task 150 | prompt eval time =      20.97 ms /     1 tokens (   20.97 ms per token,    47.68 tokens per second)"

    static let generationEval =
        "slot print_timing: id  0 | task 150 |        eval time =     220.97 ms /    13 tokens (   18.41 ms per token,    54.31 tokens per second)"

    /// Linia z załadowania modelu. Ma w sobie `n_ctx_slot`, a mimo to nie
    /// jest nasza — trafiła tu z żywego logu 2026-09-24, bo pierwsza wersja
    /// detektora zgłaszała ją jako nierozpoznaną przy każdym starcie modelu.
    static let loadModel =
        "srv    load_model: initializing, n_slots = 1, n_ctx_slot = 512, kv_unified = 'false'"

    /// Linia, której NIE wolno czytać jako ucięcia.
    static let slotRelease =
        "slot      release: id  0 | task 164 | stop processing: n_tokens = 1990, truncated = 0"
}

final class OllamaLogParserTests: XCTestCase {
    func testReadsTruncationWithExactPromptLength() {
        guard case let .inputTruncated(truncation)? = OllamaLogParser.parse(line: LogSamples.truncation) else {
            return XCTFail("WARN o ucięciu nierozpoznany")
        }
        XCTAssertEqual(truncation.limitTokens, 1026)
        XCTAssertEqual(truncation.promptTokens, 11907)
        XCTAssertEqual(truncation.keptTokens, 4)
        XCTAssertEqual(truncation.readTokens, 1026)
        XCTAssertEqual(truncation.lostTokens, 10881)
        XCTAssertEqual(truncation.lostShare, 0.913, accuracy: 0.001)
    }

    func testTakesTimeFromTheLogNotTheClock() {
        guard case let .inputTruncated(truncation)? = OllamaLogParser.parse(line: LogSamples.truncation) else {
            return XCTFail("WARN o ucięciu nierozpoznany")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 3600)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: truncation.time)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 9)
        XCTAssertEqual(parts.day, 6)
        XCTAssertEqual(parts.hour, 10)
        XCTAssertEqual(parts.minute, 20)
    }

    /// Najważniejszy test w tym pliku. `truncated = 0` stoi w logu tej
    /// maszyny przy 752 żądaniach na 754 — w tym przy takich, z których
    /// Ollama wyrzuciła 83% rozmowy. Wzięta za sygnał ucięcia mówiłaby
    /// „wszystko w porządku” dokładnie wtedy, gdy nie jest.
    func testSlotReleaseIsNotReadAsTruncation() {
        XCTAssertNil(OllamaLogParser.parse(line: LogSamples.slotRelease))
    }

    func testReadsWindowOccupancy() {
        guard case let .promptAccepted(prompt)? = OllamaLogParser.parse(line: LogSamples.newPrompt) else {
            return XCTFail("linia „new prompt” nierozpoznana")
        }
        XCTAssertEqual(prompt.task, 164)
        XCTAssertEqual(prompt.windowTokens, 2048)
        XCTAssertEqual(prompt.keepTokens, 4)
        XCTAssertEqual(prompt.promptTokens, 1978)
        XCTAssertEqual(prompt.fill, 0.966, accuracy: 0.001)
    }

    /// Czytanie promptu i pisanie odpowiedzi to dwie różne prędkości.
    /// Obie linie zaczynają się tak samo i różnią jednym słowem — gdyby
    /// wzorce się myliły, w pasku menu stałaby prędkość nie ta.
    func testTellsPromptSpeedFromGenerationSpeed() {
        guard case let .promptEval(prompt)? = OllamaLogParser.parse(line: LogSamples.promptEval) else {
            return XCTFail("prędkość czytania promptu nierozpoznana")
        }
        XCTAssertEqual(prompt.tokensPerSecond, 47.68, accuracy: 0.01)

        guard case let .generationEval(generation)? = OllamaLogParser.parse(line: LogSamples.generationEval) else {
            return XCTFail("prędkość generowania nierozpoznana")
        }
        XCTAssertEqual(generation.tokens, 13)
        XCTAssertEqual(generation.tokensPerSecond, 54.31, accuracy: 0.01)
    }

    func testIgnoresUnrelatedLines() {
        XCTAssertNil(OllamaLogParser.parse(line: ""))
        XCTAssertNil(OllamaLogParser.parse(line: "time=2026-09-06T10:20:37.163+02:00 level=INFO msg=\"nic ciekawego\""))
    }
}

final class OllamaLogReaderTests: XCTestCase {
    private var path = ""

    override func setUpWithError() throws {
        path = NSTemporaryDirectory() + "llamascope-test-\(UUID().uuidString).log"
        FileManager.default.createFile(atPath: path, contents: Data())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func testStartsAtTheEndAndReadsOnlyWhatIsNew() throws {
        try append(LogSamples.truncation + "\n")
        let reader = OllamaLogReader(path: path)
        XCTAssertEqual(reader.readNew().count, 0, "stare wpisy nie są stanem bieżącym")

        try append(LogSamples.newPrompt + "\n")
        XCTAssertEqual(reader.readNew().count, 1)
        XCTAssertEqual(reader.readNew().count, 0, "drugi odczyt bez dopisu ma dać pustkę")
    }

    func testReadsFromTheBeginningWhenAsked() throws {
        try append(LogSamples.truncation + "\n" + LogSamples.slotRelease + "\n")
        let reader = OllamaLogReader(path: path, start: .beginning)
        XCTAssertEqual(reader.readNew().count, 1)
    }

    /// Ollama dopisuje w trakcie naszego czytania. Gdybyśmy rozbierali
    /// urwaną linię od razu, zgubilibyśmy dokładnie ten WARN, dla którego
    /// to wszystko powstało — bo urywa się zwykle na końcu, a `new=258`
    /// jest na końcu.
    func testHoldsAnIncompleteLineUntilItIsFinished() throws {
        let reader = OllamaLogReader(path: path, start: .beginning)
        let half = String(LogSamples.truncation.prefix(60))
        try append(half)
        XCTAssertEqual(reader.readNew().count, 0, "urwana linia nie może być rozbierana")

        try append(String(LogSamples.truncation.dropFirst(60)) + "\n")
        guard case .inputTruncated? = reader.readNew().first else {
            return XCTFail("dokończona linia ma zostać przeczytana w całości")
        }
    }

    func testStartsOverWhenTheLogRotates() throws {
        try append(LogSamples.truncation + "\n" + LogSamples.newPrompt + "\n")
        let reader = OllamaLogReader(path: path, start: .end)

        try Data((LogSamples.newPrompt + "\n").utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(reader.readNew().count, 1, "po rotacji czytamy od początku")
        XCTAssertEqual(reader.rotations, 1, "rotacja ma być policzona — do logu aplikacji")
    }

    func testMissingLogIsSilentNotFatal() {
        let reader = OllamaLogReader(path: "/nie/ma/takiego/ollama.log")
        XCTAssertEqual(reader.readNew().count, 0)
    }

    func testKnownPathsCoverBothInstallations() {
        XCTAssertTrue(OllamaLogLocation.knownPaths.contains("/opt/homebrew/var/log/ollama.log"))
        XCTAssertTrue(OllamaLogLocation.knownPaths.contains { $0.hasSuffix(".ollama/logs/server.log") })
    }

    /// Na żywej maszynie: czy w ogóle znajdujemy log i czy jego ogon daje się
    /// przeczytać. Nie sprawdzamy treści — sprawdzamy, że kod dotyka prawdy.
    func testReadsTheTailOfTheRealLogIfPresent() throws {
        guard let found = OllamaLogLocation.find() else {
            print("log Ollamy → nie znaleziony na tej maszynie")
            return
        }
        let reader = OllamaLogReader(path: found, start: .beginning)
        let events = reader.readNew()
        print("log Ollamy → \(found), zdarzeń: \(events.count)")
        let truncations = events.filter { if case .inputTruncated = $0 { return true } else { return false } }
        print("  w tym ucięć wejścia: \(truncations.count)")
    }
}

final class OllamaLogStateTests: XCTestCase {
    func testKeepsTheLatestOfEachKind() {
        var state = OllamaLogState()
        state.apply([
            OllamaLogParser.parse(line: LogSamples.truncation)!,
            OllamaLogParser.parse(line: LogSamples.newPrompt)!,
            OllamaLogParser.parse(line: LogSamples.promptEval)!,
            OllamaLogParser.parse(line: LogSamples.generationEval)!,
        ])
        XCTAssertEqual(state.lastTruncation?.promptTokens, 11907)
        XCTAssertEqual(state.lastPrompt?.windowTokens, 2048)
        XCTAssertEqual(state.lastPromptEval?.tokensPerSecond, 47.68)
        XCTAssertEqual(state.lastGeneration?.tokens, 13)
    }

    /// Nowe żądanie bez ucięcia nie kasuje poprzedniego ucięcia. O tym, czy
    /// ucięcie jest jeszcze stanem bieżącym, decyduje czas, nie kolejność.
    func testALaterCleanRequestDoesNotEraseTheTruncation() {
        var state = OllamaLogState()
        state.apply([OllamaLogParser.parse(line: LogSamples.truncation)!])
        state.apply([OllamaLogParser.parse(line: LogSamples.newPrompt)!])
        XCTAssertNotNil(state.lastTruncation)
    }
}

/// Rozróżnienie z §10: linia nie nasza kontra linia nasza, której nie
/// zrozumieliśmy. Bez tego rozróżnienia własny log albo milczy o zmianie
/// formatu w Ollamie, albo jest kopią cudzego logu — i jedno, i drugie
/// czyni go bezużytecznym przy zgłoszeniu.
final class UnrecognizedLineTests: XCTestCase {
    func testALineWeParsedIsNotReportedAsUnrecognized() {
        XCTAssertEqual(
            OllamaLogParser.read(line: LogSamples.newPrompt),
            .understood(OllamaLogParser.parse(line: LogSamples.newPrompt)!)
        )
    }

    /// Najważniejszy test w tej klasie. Gdy Ollama zmieni format linii
    /// o ucięciu, wzorzec przestanie pasować — i to jest dokładnie ta chwila,
    /// w której musimy się dowiedzieć, zamiast pokazywać spokój.
    func testAChangedTruncationLineIsKeptForTheReport() {
        let changed = #"time=2027-01-01T10:20:37Z level=WARN msg="truncating input prompt" ctx_limit=1026 tokens=11907"#
        guard case let .unrecognized(line) = OllamaLogParser.read(line: changed) else {
            return XCTFail("zmieniona linia o ucięciu musi trafić do zgłoszenia")
        }
        XCTAssertTrue(line.contains("truncating input prompt"))
    }

    /// A linia, o której z góry wiemy, że nas nie dotyczy, nie ma prawa
    /// trafić do naszego logu — łącznie z `truncated = 0`, którego świadomie
    /// nie czytamy. W żywym logu stoi ona przy 752 żądaniach na 754.
    func testLinesWeDeliberatelyIgnoreDoNotFloodOurLog() {
        XCTAssertEqual(OllamaLogParser.read(line: LogSamples.slotRelease), .notOurs)
        XCTAssertEqual(OllamaLogParser.read(line: LogSamples.loadModel), .notOurs,
                       "sam `n_ctx_slot` bez promptu to nie jest nasza linia")
        XCTAssertEqual(OllamaLogParser.read(line: "time=2026-09-06T10:20:37.163+02:00 level=INFO msg=\"nic ciekawego\""), .notOurs)
        XCTAssertEqual(OllamaLogParser.read(line: ""), .notOurs)
    }

    func testTheReaderCollectsThemAndHandsThemOverOnce() throws {
        let path = NSTemporaryDirectory() + "llamascope-unrecognized-\(UUID().uuidString).log"
        FileManager.default.createFile(atPath: path, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let reader = OllamaLogReader(path: path)
        let broken = #"msg="truncating input prompt" w nowym formacie"#
        try Data("\(LogSamples.slotRelease)\n\(broken)\n\(LogSamples.newPrompt)\n".utf8)
            .write(to: URL(fileURLWithPath: path))

        XCTAssertEqual(reader.readNew().count, 1, "rozumiane zdarzenia idą osobno")
        XCTAssertEqual(reader.takeUnrecognized(), [broken])
        XCTAssertEqual(reader.takeUnrecognized(), [], "drugie odebranie ma dać pustkę")
    }

    /// Zmiana formatu w Ollamie dotyczy **każdej** linii, więc bez limitu
    /// nasz log stałby się kopią cudzego. Licznik biegnie dalej, bo
    /// „10 linii i jeszcze cztery tysiące” to inna diagnoza niż „10 linii”.
    func testOnlyTheFirstFewLinesAreKeptButAllAreCounted() throws {
        let path = NSTemporaryDirectory() + "llamascope-flood-\(UUID().uuidString).log"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let broken = #"msg="truncating input prompt" w nowym formacie"#
        let flood = Array(repeating: broken, count: 50).joined(separator: "\n") + "\n"
        try Data(flood.utf8).write(to: URL(fileURLWithPath: path))

        let reader = OllamaLogReader(path: path, start: .beginning)
        _ = reader.readNew()
        XCTAssertEqual(reader.takeUnrecognized().count, OllamaLogReader.unrecognizedPerRead)
        XCTAssertEqual(reader.unrecognizedCount, 50)
    }
}
