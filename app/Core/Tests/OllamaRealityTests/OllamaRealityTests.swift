import XCTest
import LlamaScopeCore

/// Dwa testy, które **nie sprawdzają naszego kodu**.
///
/// Reszta zestawu bada, czy dobrze liczymy. Te dwa badają dwa twierdzenia
/// o cudzym programie, na których stoi całe narzędzie:
///
/// 1. **Log Ollamy nie zawiera treści promptów.** Na tym opiera się
///    obietnica z §9 — że tryb domyślny nie widzi, co piszesz. Ta obietnica
///    nie jest naszą decyzją, tylko własnością cudzego formatu logu, i może
///    zniknąć w dowolnym wydaniu Ollamy bez słowa uprzedzenia.
/// 2. **Przycięta rozmowa nie zostawia w logu żadnego śladu.** Na tym stoi
///    granica wykrywania z §5, którą piszemy wprost w panelu i w README.
///
/// Dlatego są osobnym celem. Gdyby siedziały wśród testów jednostkowych,
/// czerwony wynik czytałoby się jako „zepsuliśmy kod" — a tutaj czerwony
/// znaczy **„świat się zmienił, popraw dokumentację"**. To inny gatunek
/// wiadomości i ma wyglądać inaczej.
///
/// Uruchomienie: `swift test --filter OllamaRealityTests`. Bez chodzącej
/// Ollamy testy się **pomijają, a nie przechodzą**. Test, który na pustej
/// maszynie świeci na zielono, mówiłby „sprawdzone" o czymś, czego nie
/// sprawdził — to dokładnie ta rodzina kłamstwa co `truncated = 0`.
final class OllamaRealityTests: XCTestCase {

    // MARK: - Twierdzenie 1: w logu nie ma treści promptów

    /// Wysyłamy przez Ollamę hasło, które nie ma prawa wystąpić nigdzie
    /// indziej, i sprawdzamy, czy pojawiło się w logu.
    ///
    /// Sprawdzenie „czy w logu jest ten ciąg" ma jedną pułapkę i jest nią
    /// odpowiedź „nie ma" z niewłaściwego powodu: jeśli log w ogóle nie
    /// urósł, to hasła nie ma, bo nie ma **niczego**, a nie dlatego, że
    /// Ollama go nie zapisuje. Dlatego przyrost logu jest sprawdzany
    /// osobno i jego brak jest błędem testu, nie jego zaliczeniem.
    func testTheOllamaLogNeverContainsPromptText() async throws {
        let ollama = try await LiveOllama.requireRunning()
        let secret = "kanarek-llamascope-\(UUID().uuidString.prefix(8))"

        _ = try await ollama.generate(
            prompt: "Powtórz dokładnie to słowo i nic więcej: \(secret)"
        )
        let fresh = try ollama.logTextAppendedSinceStart()

        // Strażnik: czy w dopisanych liniach jest ślad **naszego** żądania.
        //
        // Pierwsza wersja sprawdzała tylko, czy log urósł — i to było za
        // mało, co widać było dopiero na żywej maszynie. Gdy działa
        // aplikacja, log rośnie co sekundę o linie `[GIN] GET /api/ps`,
        // więc warunek „urósł" spełniał się sam, niezależnie od tego, czy
        // prompt w ogóle dotarł do modelu. Zielone światło znaczyłoby
        // wtedy „nie znalazłem hasła w cudzym hałasie".
        let reachedTheModel = fresh.split(separator: "\n").contains {
            if case .promptAccepted = OllamaLogParser.parse(line: String($0)) { return true }
            return false
        }
        XCTAssertTrue(
            reachedTheModel,
            """
            W dopisanych liniach nie ma ani jednej `new prompt`, więc prompt \
            nie dotarł do modelu i ten test niczego nie sprawdził. Brak hasła \
            w logu, który nie widział żądania, nie jest dowodem na nic. \
            Ollama \(ollama.version), log: \(ollama.logPath)
            """
        )
        XCTAssertFalse(
            fresh.contains(secret),
            """
            W logu Ollamy \(ollama.version) znalazła się treść promptu. \
            To unieważnia obietnicę z §9 — tryb domyślny przestał być ślepy \
            na treść. Zanim cokolwiek poprawisz w kodzie, popraw README \
            i panel, bo od tej chwili obiecują nieprawdę. Log: \(ollama.logPath)
            """
        )
    }

    // MARK: - Twierdzenie 2: przycięta rozmowa jest w logu niewidoczna

    /// Wpychamy w ciasne okno rozmowę wielokrotnie od niego dłuższą i
    /// sprawdzamy, że log **nie mówi o tym nic**.
    ///
    /// Ten test jest napisany tak, żeby czerwień była dobrą wiadomością.
    /// Jeśli kiedyś padnie na linii o `truncating input prompt`, znaczy to,
    /// że Ollama zaczęła zgłaszać także ten przypadek — a wtedy granica
    /// wykrywania z §5 jest za ostrożna i trzeba ją poluzować, nie łatać
    /// testu. Kto to zobaczy, niech zajrzy tutaj, a nie do `git blame`.
    func testATrimmedConversationLeavesNoTraceInTheLog() async throws {
        let ollama = try await LiveOllama.requireRunning()

        // Okno 512 tokenów i rozmowa na kilkadziesiąt tysięcy znaków.
        // Zapas jest celowo absurdalny: nawet przy najbardziej ostrożnym
        // przeliczniku znaków na tokeny ta historia nie ma prawa się
        // zmieścić, więc „zmieściła się" może znaczyć tylko „przycięto ją".
        let window = 512
        let history = (1...120).map { turn in
            [
                "role": turn.isMultiple(of: 2) ? "assistant" : "user",
                "content": "Tura \(turn). " + String(repeating: "Opowiedz o kompilatorach. ", count: 12),
            ]
        }
        let sentCharacters = history.reduce(0) { $0 + ($1["content"]?.count ?? 0) }

        _ = try await ollama.chat(messages: history, window: window)
        let fresh = try ollama.logTextAppendedSinceStart()
        let events = fresh.split(separator: "\n").compactMap {
            OllamaLogParser.parse(line: String($0))
        }

        // Dowód, że przycinanie faktycznie zaszło: prompt przyjęty do
        // liczenia zmieścił się w oknie, choć wysłaliśmy wielokrotnie
        // więcej. Bez tego reszta testu opisywałaby przebieg, w którym
        // nic się nie stało.
        // Po oknie, a nie po kolejności: gdyby ktoś w tej chwili używał
        // Ollamy z drugiego okna, `ostatnia linia` mogłaby opisywać jego
        // żądanie i test badałby cudzy ruch, nie swój.
        let accepted: [PromptAccepted] = events.compactMap {
            if case .promptAccepted(let prompt) = $0, prompt.windowTokens == window {
                return prompt
            }
            return nil
        }
        let trimmed = try XCTUnwrap(
            accepted.last,
            """
            W logu nie ma linii `new prompt` z oknem \(window), więc nie \
            wiadomo, czy rozmowa w ogóle doszła do modelu. \
            Ollama \(ollama.version), log: \(ollama.logPath)
            """
        )
        XCTAssertLessThanOrEqual(
            trimmed.promptTokens, trimmed.windowTokens,
            "prompt miał się zmieścić w oknie \(trimmed.windowTokens), a ma \(trimmed.promptTokens)"
        )
        XCTAssertGreaterThan(
            sentCharacters / 4, trimmed.windowTokens * 2,
            """
            Wysłana rozmowa (\(sentCharacters) znaków) nie jest dość większa \
            od okna \(trimmed.windowTokens), żeby przycięcie było pewne. \
            Popraw ten test, bo przestał sprawdzać to, co miał.
            """
        )

        // I sedno: mimo że przepadły całe tury, log o tym milczy.
        let truncations: [InputTruncation] = events.compactMap {
            if case .inputTruncated(let cut) = $0 { return cut }
            return nil
        }
        XCTAssertTrue(
            truncations.isEmpty,
            """
            DOBRA WIADOMOŚĆ, NIE AWARIA: Ollama \(ollama.version) zaczęła \
            zgłaszać ucięcie także dla przyciętej rozmowy. Granica wykrywania \
            z §5 jest od tej chwili za ostrożna — popraw ją w panelu \
            (`StateText.detectionLimit`) i w README, zamiast łatać ten test.
            """
        )

        // Druga połowa twierdzenia z §13: log nie tylko milczy, ale zaprzecza.
        //
        // Flagę trzeba wziąć **z naszego żądania**, po numerze zadania z linii
        // `new prompt`, a nie ze wszystkich świeżych linii. W logu tej maszyny
        // `truncated = 1` stoi przy 28 żądaniach na 959 — ta flaga opisuje
        // przesunięcie kontekstu w trakcie generowania, nie ucięcie wejścia,
        // i parser ignoruje ją świadomie. Ocenianie ich hurtem zapalałoby
        // „dobrą wiadomość" od cudzego ruchu, który z tym testem nie ma
        // nic wspólnego.
        if let flag = releaseFlag(forTask: trimmed.task, in: fresh) {
            XCTAssertEqual(
                flag, 0,
                """
                DOBRA WIADOMOŚĆ, NIE AWARIA: przy przyciętej rozmowie \
                `truncated` przestało być zerem (Ollama \(ollama.version), \
                zadanie \(trimmed.task), wartość \(flag)). To była nasza \
                najmocniejsza teza o fałszywym spokoju logu — §13 wymaga \
                przepisania.
                """
            )
        } else {
            // Nie `XCTFail`: linia `slot release` zależy od gadatliwości
            // serwera, a jej brak nie podważa twierdzenia. Ale i nie cisza —
            // przebieg, który sprawdził połowę, ma to powiedzieć.
            print("""
                  uwaga: brak linii `slot release` dla zadania \(trimmed.task), \
                  więc drugiej połowy twierdzenia z §13 ten przebieg nie sprawdził \
                  (Ollama \(ollama.version))
                  """)
        }
    }

    /// Flaga `truncated` z linii zwolnienia gniazda, dla **jednego** zadania.
    private func releaseFlag(forTask task: Int, in text: String) -> Int? {
        let pattern = #/task\s+(\d+)\s*\|\s*stop processing:.*?truncated\s*=\s*(\d+)/#
        return text.matches(of: pattern)
            .first { Int($0.1) == task }
            .flatMap { Int($0.2) }
    }
}

/// Dojście do żywej Ollamy. Wszystko, czego brakuje, kończy się pominięciem
/// testu z powodem wypisanym wprost — nie zaliczeniem i nie wywrotką.
private struct LiveOllama {
    let version: String
    let logPath: String
    let model: String
    let logSizeAtStart: UInt64

    private static let host = ProcessInfo.processInfo.environment["OLLAMA_HOST"]
        ?? "http://127.0.0.1:11434"

    static func requireRunning() async throws -> LiveOllama {
        guard let logPath = OllamaLogLocation.find() else {
            throw XCTSkip("""
                Nie znalazłem logu Ollamy w żadnej ze znanych ścieżek: \
                \(OllamaLogLocation.knownPaths.joined(separator: ", "))
                """)
        }

        let version: String
        do {
            let payload = try await get("/api/version")
            version = (payload["version"] as? String) ?? "nieznana"
        } catch {
            throw XCTSkip("Ollama nie odpowiada pod \(host) — \(error.localizedDescription)")
        }

        let tags = try await get("/api/tags")
        let models = (tags["models"] as? [[String: Any]]) ?? []
        guard let model = models.compactMap({ $0["name"] as? String }).first else {
            throw XCTSkip("Ollama działa, ale nie ma ani jednego modelu (`ollama pull …`)")
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: logPath)[.size] as? UInt64)
        return LiveOllama(
            version: version, logPath: logPath, model: model,
            logSizeAtStart: size ?? 0
        )
    }

    /// Wyłącznie to, co dopisało się od początku testu. Czytanie całego
    /// pliku mieszałoby nasz przebieg z cudzym ruchem sprzed godzin.
    func logTextAppendedSinceStart() throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: logPath))
        defer { try? handle.close() }
        try handle.seek(toOffset: logSizeAtStart)
        let data = try handle.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    func generate(prompt: String) async throws -> [String: Any] {
        try await Self.post("/api/generate", body: [
            "model": model, "prompt": prompt, "stream": false,
            "options": ["num_predict": 20],
        ])
    }

    func chat(messages: [[String: String]], window: Int) async throws -> [String: Any] {
        try await Self.post("/api/chat", body: [
            "model": model, "messages": messages, "stream": false,
            "options": ["num_ctx": window, "num_predict": 20],
        ])
    }

    private static func get(_ path: String) async throws -> [String: Any] {
        let (data, _) = try await session.data(from: URL(string: host + path)!)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: host + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Model ładowany do pamięci potrafi zająć kilkadziesiąt sekund, a to
    /// nie jest awaria, tylko pierwsze żądanie po starcie maszyny.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        return URLSession(configuration: configuration)
    }()
}
