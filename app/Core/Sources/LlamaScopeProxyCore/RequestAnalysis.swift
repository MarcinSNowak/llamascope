import Foundation
import LlamaScopeText

/// Ścieżki, które w ogóle niosą prompt.
public enum ProxyPaths {
    public static let analysed = [
        "/api/chat", "/api/generate", "/v1/chat/completions", "/v1/completions",
    ]

    /// Ścieżki „rozmowne". Podział zmierzony 2026-09-06 na Ollamie 0.32.14:
    /// ścieżki promptowe ucinają **tokeny** od początku i zostawiają w logu
    /// WARN, ścieżki rozmowne wyrzucają całe **najstarsze wiadomości**
    /// i nie logują niczego.
    public static let conversation = ["/api/chat", "/v1/chat/completions"]

    public static func isConversation(_ path: String) -> Bool {
        conversation.contains(path)
    }
}

/// Skąd wiemy, jakie okno obowiązuje to żądanie.
///
/// Kolejność ma znaczenie i jest częścią odpowiedzi: jawne `options.num_ctx`
/// wygrywa ze stanem załadowanego modelu, bo to ono zadecyduje
/// o przeładowaniu. Stała nie wygrywa nigdy — okno w Ollamie **nie jest
/// stałą**, dobiera się przy każdym ładowaniu do wolnej pamięci (§14).
public struct ContextWindow: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case explicitOption
        case loadedModel

        /// Nazwa do pliku obserwacji, **niezależna od języka**. Plik
        /// obserwacji to dane, nie zdanie: wartość pola, która zmienia się
        /// razem z ustawieniami systemu, psuje każde porównanie dwóch
        /// przebiegów i każdy skrypt, który po nich przejdzie.
        public var key: String {
            switch self {
            case .explicitOption: return "options.num_ctx"
            case .loadedModel: return "loaded_model"
            }
        }

        public func described(in language: Language) -> String {
            switch (self, language) {
            // Nazwa pola w API, nie słowo — nie tłumaczy się.
            case (.explicitOption, _): return "options.num_ctx"
            case (.loadedModel, .polish): return "załadowany model"
            case (.loadedModel, .english): return "the loaded model"
            }
        }
    }

    public let tokens: Int
    public let source: Source

    public init(tokens: Int, source: Source) {
        self.tokens = tokens
        self.source = source
    }

    /// Jawne `num_ctx` z żądania. Druga możliwość — okno załadowanego modelu
    /// — wymaga zapytania Ollamy, więc nie należy do czystej analizy i jest
    /// dostarczana z zewnątrz.
    public static func declared(in body: JSONValue) -> ContextWindow? {
        guard let tokens = body["options"]?["num_ctx"]?.intValue, tokens > 0 else { return nil }
        return ContextWindow(tokens: tokens, source: .explicitOption)
    }
}

/// Ocena jednego żądania.
public enum Assessment: Sendable, Equatable {
    /// Nawet przy najostrożniejszym szacunku prompt nie mieści się w oknie.
    /// To jest fizyka, nie heurystyka — musiał zostać ucięty.
    case truncated
    /// Przedział niepewności przecina granicę okna. Ucięcie jest możliwe,
    /// ale nieprzesądzone; milczenie byłoby tu gorsze niż fałszywy alarm.
    case risk
    case close
    /// Prompt mieści się w oknie, a Ollama przeliczyła znacznie mniej —
    /// to trafienie w pamięć podręczną, nie ucięcie. Bez tego rozróżnienia
    /// narzędzie krzyczałoby przy każdej kolejnej turze rozmowy.
    case cache
    case fine
}

public struct RequestReport: Sendable, Equatable {
    public let path: String
    public let model: String
    public let characters: Int
    public let estimatedTokens: Int
    public let estimateLow: Int
    public let estimateHigh: Int
    public let reportedTokens: Int?
    public let window: ContextWindow?
    public let calibrationSamples: Int
    public let assessment: Assessment
    public let excessTokens: Int?
    public let lost: [String]
    /// Ile **tur rozmowy** przepadło. Liczba, nie długość listy `lost` —
    /// tamta bywa dłuższa o dopiski dla człowieka. Przy ścieżkach promptowych
    /// (`/api/generate`, `/v1/completions`) tury nie występują i jest tu zero.
    public let lostTurns: Int
    /// Czy sam log Ollamy miałby szansę to zauważyć. Przy rozmowie zwykle
    /// nie ma: serwer wyrzuca wiadomości bez słowa, więc narzędzie czytające
    /// log jest ślepe i **tylko pośrednik widzi stratę**.
    public let visibleInOllamaLog: Bool

    public var isAlarming: Bool { assessment == .truncated || assessment == .risk }
}

public enum RequestAnalyst {
    /// Czysta funkcja: nic nie czyta, nic nie zapisuje, niczego nie pyta.
    /// Okno i liczba tokenów zgłoszona przez Ollamę przychodzą z zewnątrz,
    /// bo obie wymagają sieci — a analiza ma się dawać sprawdzić bez niej.
    public static func analyse(
        path: String,
        body: JSONValue,
        window: ContextWindow?,
        reportedTokens: Int?,
        calibrator: inout Calibrator,
        in language: Language
    ) -> RequestReport? {
        let model = body["model"]?.stringValue ?? "?"
        let parts = PromptBreakdown.parts(of: body, in: language)
        let characters = parts.reduce(0) { $0 + $1.characters }
        guard characters > 0 else { return nil }

        let band = calibrator.band(for: model)
        // Mniej znaków na token to więcej tokenów — stąd odwrócenie krańców.
        let high = Int(Double(characters) / band.low)
        let low = Int(Double(characters) / band.high)
        let estimate = (low + high) / 2

        var assessment = Assessment.fine
        var excess: Int?
        var lost: [String] = []
        var lostTurns = 0
        var visibleInLog = true

        if let window {
            if low > window.tokens {
                assessment = .truncated
                excess = low - window.tokens
                if ProxyPaths.isConversation(path) {
                    let budget = Int(Double(window.tokens) * band.high)
                    let outcome = PromptBreakdown.conversationVictims(
                        in: parts, characterBudget: budget, in: language
                    )
                    lost = outcome.lost
                    lostTurns = outcome.lostTurns
                    visibleInLog = outcome.overflowed
                } else {
                    lost = PromptBreakdown.victims(
                        in: parts,
                        charactersCut: Int(Double(low - window.tokens) * band.high),
                        in: language
                    )
                }
            } else if high > window.tokens {
                assessment = .risk
            } else if Double(high) > Double(window.tokens) * 0.9 {
                assessment = .close
            }
        }

        if assessment == .fine, let reportedTokens, estimate > 200,
           Double(reportedTokens) < Double(estimate) * 0.5 {
            assessment = .cache
        }

        // Kalibracja poza łańcuchem ocen, bo inaczej narzędzie, które raz
        // zaczęło ostrzegać, nigdy by się nie douczyło i ostrzegałoby
        // w kółko. Żądanie ostrzeżone, ale nieucięte, jest pełnowartościową
        // próbką — a te faktycznie ucięte odsiewa `add`, bo dają absurdalnie
        // wysoki stosunek znaków na token.
        if assessment != .truncated {
            calibrator.add(model: model, characters: characters, tokens: reportedTokens)
        }

        return RequestReport(
            path: path, model: model, characters: characters,
            estimatedTokens: estimate, estimateLow: low, estimateHigh: high,
            reportedTokens: reportedTokens, window: window,
            calibrationSamples: band.samples, assessment: assessment,
            excessTokens: excess, lost: lost, lostTurns: lostTurns,
            visibleInOllamaLog: visibleInLog
        )
    }
}
