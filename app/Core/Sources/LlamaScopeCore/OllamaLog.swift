import Foundation

/// Ucięcie wejścia — jedyny sygnał w logu, który naprawdę znaczy „model nie
/// przeczytał tego, co wysłałeś".
///
/// `promptTokens` jest tu najcenniejszą liczbą w całym pliku: to dokładna
/// długość promptu w tokenach, której API Ollamy nie zwraca nigdzie
/// (`prompt_eval_count` w odpowiedzi podaje tylko to, co zostało *po*
/// ucięciu). Wersja pythonowa musiała ją szacować z liczby znaków.
public struct InputTruncation: Sendable, Equatable {
    /// Czas z logu, nie z zegara. Inaczej ucięcie sprzed godzin udaje
    /// świeży alarm po każdym restarcie aplikacji.
    public let time: Date
    public let limitTokens: Int
    public let promptTokens: Int
    public let keptTokens: Int
    public let readTokens: Int

    public init(time: Date, limitTokens: Int, promptTokens: Int, keptTokens: Int, readTokens: Int) {
        self.time = time
        self.limitTokens = limitTokens
        self.promptTokens = promptTokens
        self.keptTokens = keptTokens
        self.readTokens = readTokens
    }

    public var lostTokens: Int { max(0, promptTokens - readTokens) }

    /// Udział straty, 0…1. Przy `prompt=7260 new=258` wychodzi 0,96.
    public var lostShare: Double {
        promptTokens > 0 ? Double(lostTokens) / Double(promptTokens) : 0
    }
}

/// Rozmiar promptu przyjętego do liczenia, z linii `new prompt`.
///
/// Wersja pythonowa tej linii nie czytała. Warto, bo jest przy **każdym**
/// żądaniu — także wtedy, gdy nic nie zostało ucięte — i podaje okno
/// (`n_ctx_slot`) razem z zajętością. To jedyne źródło odpowiedzi na pytanie
/// „jak blisko granicy jestem”, zanim granica zostanie przekroczona.
///
/// Uwaga na granicę poznania: przy przyciętej **rozmowie** `promptTokens`
/// to długość promptu już po wyrzuceniu najstarszych wiadomości. Ta liczba
/// nie powie, że coś przepadło — powie tylko, że okno jest pełne.
public struct PromptAccepted: Sendable, Equatable {
    public let task: Int
    public let windowTokens: Int
    public let keepTokens: Int
    public let promptTokens: Int

    public init(task: Int, windowTokens: Int, keepTokens: Int, promptTokens: Int) {
        self.task = task
        self.windowTokens = windowTokens
        self.keepTokens = keepTokens
        self.promptTokens = promptTokens
    }

    /// Zajętość okna, 0…1.
    public var fill: Double {
        windowTokens > 0 ? Double(promptTokens) / Double(windowTokens) : 0
    }
}

/// Prędkość z linii `print_timing`. Osobno czytanie promptu, osobno pisanie
/// odpowiedzi — to dwie różne liczby i mylenie ich zawyża wynik.
public struct EvalSpeed: Sendable, Equatable {
    public let tokens: Int
    public let tokensPerSecond: Double

    public init(tokens: Int, tokensPerSecond: Double) {
        self.tokens = tokens
        self.tokensPerSecond = tokensPerSecond
    }
}

public enum LogEvent: Sendable, Equatable {
    case inputTruncated(InputTruncation)
    case promptAccepted(PromptAccepted)
    case promptEval(EvalSpeed)
    case generationEval(EvalSpeed)
}

/// Rozbiór pojedynczych linii logu. Osobno od czytnika, bo linie mamy
/// nagrane i chcemy je testować bez dotykania dysku.
public enum OllamaLogParser {
    private static let truncation =
        #/time=(\S+).*?msg="truncating input prompt" limit=(\d+) prompt=(\d+) keep=(\d+) new=(\d+)/#
    private static let newPrompt =
        #/task (\d+) \| new prompt, n_ctx_slot = (\d+), n_keep = (\d+), task\.n_tokens = (\d+)/#
    private static let promptEval =
        #/prompt eval time =\s*[\d.]+ ms /\s*(\d+) tokens \(.*?([\d.]+) tokens per second/#
    private static let generationEval =
        #/\|\s+eval time =\s*[\d.]+ ms /\s*(\d+) tokens \(.*?([\d.]+) tokens per second/#

    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static func parse(line: String) -> LogEvent? {
        // Kolejność prób jest istotna tylko w jednym miejscu: wzorzec
        // generowania pasowałby też do linii promptu, gdyby nie wiodący „|”.
        // Dlatego prompt sprawdzamy pierwszy i wychodzimy.
        if let match = line.firstMatch(of: truncation) {
            guard let time = date(from: String(match.1)),
                  let limit = Int(match.2), let prompt = Int(match.3),
                  let keep = Int(match.4), let new = Int(match.5)
            else { return nil }
            return .inputTruncated(InputTruncation(
                time: time, limitTokens: limit, promptTokens: prompt,
                keptTokens: keep, readTokens: new
            ))
        }

        if let match = line.firstMatch(of: newPrompt) {
            guard let task = Int(match.1), let window = Int(match.2),
                  let keep = Int(match.3), let tokens = Int(match.4)
            else { return nil }
            return .promptAccepted(PromptAccepted(
                task: task, windowTokens: window, keepTokens: keep, promptTokens: tokens
            ))
        }

        if let match = line.firstMatch(of: promptEval) {
            guard let tokens = Int(match.1), let speed = Double(match.2) else { return nil }
            return .promptEval(EvalSpeed(tokens: tokens, tokensPerSecond: speed))
        }

        if let match = line.firstMatch(of: generationEval) {
            guard let tokens = Int(match.1), let speed = Double(match.2) else { return nil }
            return .generationEval(EvalSpeed(tokens: tokens, tokensPerSecond: speed))
        }

        // Wszystko inne, a w szczególności `slot release ... truncated = N`,
        // jest tu świadomie pominięte. Ta flaga dotyczy przesunięcia kontekstu
        // w trakcie generowania, nie ucięcia wejścia — w logu tej maszyny stoi
        // przy 752 żądaniach na 754, w tym przy takich, z których Ollama
        // wyrzuciła 83% rozmowy. Czytana jako sygnał ucięcia mówiłaby
        // „wszystko w porządku” dokładnie wtedy, gdy nie jest.
        return nil
    }

    private static func date(from text: String) -> Date? {
        timestamp.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Gdzie szukać logu. Kolejność jak w wersji pythonowej: pierwsza istniejąca
/// ścieżka wygrywa. Która to była, trafia do logu aplikacji — bo przy
/// zgłoszeniu z cudzej maszyny „nie widzę ucięć” i „nie znalazłem logu”
/// to dwie zupełnie różne diagnozy (§10).
public enum OllamaLogLocation {
    public static let knownPaths = [
        "/opt/homebrew/var/log/ollama.log",
        "/usr/local/var/log/ollama.log",
        NSString(string: "~/.ollama/logs/server.log").expandingTildeInPath,
        NSString(string: "~/Library/Logs/Ollama/server.log").expandingTildeInPath,
    ]

    public static func find(
        in paths: [String] = knownPaths,
        using fileManager: FileManager = .default
    ) -> String? {
        paths.first { fileManager.fileExists(atPath: $0) }
    }
}

/// Przyrostowe czytanie ogona logu.
///
/// Trzy rzeczy, których nie widać, dopóki się nie napisze:
///
/// - **Log się obraca.** Gdy plik zmalał, nasza pozycja wskazuje w środek
///   nowej treści. Wtedy wracamy na początek, zamiast czytać śmieci.
/// - **Odczyt wypada w połowie linii.** Ollama dopisuje w trakcie naszego
///   czytania, więc ostatnia porcja bywa urwana. Gdybyśmy rozbierali ją od
///   razu, zgubilibyśmy właśnie ten WARN, dla którego to wszystko powstało.
///   Dlatego pozycję przesuwamy tylko do ostatniego pełnego przełamania
///   linii, a resztę doczytamy następnym razem.
/// - **Start ma być na końcu.** Aplikacja mówi o tym, co dzieje się teraz;
///   ucięcia sprzed tygodnia nie są stanem bieżącym. `.beginning` jest
///   wyłącznie dla testów i dla ewentualnego „przejrzyj historię”.
public final class OllamaLogReader {
    public enum Start: Sendable { case end, beginning }

    public let path: String
    public private(set) var offset: UInt64
    /// Ile razy zauważyliśmy rotację. Do logu aplikacji — jeśli u kogoś
    /// rośnie, to znaczy, że tracimy zdarzenia między odświeżeniami.
    public private(set) var rotations = 0

    public init(path: String, start: Start = .end, using fileManager: FileManager = .default) {
        self.path = path
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        self.offset = start == .end ? size : 0
    }

    public func readNew() -> [LogEvent] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }

        do {
            let size = try handle.seekToEnd()
            if size < offset {
                rotations += 1
                offset = 0
            }
            guard size > offset else { return [] }

            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd(), !data.isEmpty else { return [] }

            // Urwany ogon zostaje na następny raz.
            guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
            let complete = data[data.startIndex...lastNewline]
            offset += UInt64(complete.count)

            let text = String(decoding: complete, as: UTF8.self)
            return text.split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { OllamaLogParser.parse(line: String($0)) }
        } catch {
            return []
        }
    }
}

/// To, co z logu zostaje po przeczytaniu porcji: ostatnie ucięcie, ostatnia
/// zajętość okna, ostatnie prędkości. Stan, a nie strumień — bo interfejs
/// odświeża się co kilka sekund i pyta „co jest teraz”.
public struct OllamaLogState: Sendable, Equatable {
    public var lastTruncation: InputTruncation?
    public var lastPrompt: PromptAccepted?
    public var lastPromptEval: EvalSpeed?
    public var lastGeneration: EvalSpeed?

    public init() {}

    public mutating func apply(_ events: [LogEvent]) {
        for event in events {
            switch event {
            case let .inputTruncated(truncation): lastTruncation = truncation
            case let .promptAccepted(prompt): lastPrompt = prompt
            case let .promptEval(speed): lastPromptEval = speed
            case let .generationEval(speed): lastGeneration = speed
            }
        }
    }
}
