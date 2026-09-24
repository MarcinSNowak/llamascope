import Foundation
import LlamaScopeText

/// Kawałek promptu w kolejności, w jakiej trafia do modelu.
///
/// `kind` nie jest opisem — decyduje o losie kawałka przy przycinaniu
/// rozmowy. `system` i `tools` przeżywają, `turn` idzie pod nóż od
/// najstarszej. To rozróżnienie jest zmierzone (2026-09-06), nie wymyślone.
public struct PromptPart: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case tools
        case system
        case turn
        case prompt
    }

    public let label: String
    public let characters: Int
    public let kind: Kind

    public init(label: String, characters: Int, kind: Kind) {
        self.label = label
        self.characters = characters
        self.kind = kind
    }
}

public enum PromptBreakdown {
    /// Etykiety kawałków. Osobno od rozkładania, bo to jedyne miejsce
    /// w tym pliku, w którym cokolwiek zależy od języka — reszta liczy
    /// znaki i nie ma o czym mówić.
    enum Words {
        static func tools(_ count: Int, in language: Language) -> String {
            language == .polish ? "definicje narzędzi (\(count))" : "tool definitions (\(count))"
        }

        static func systemInstruction(in language: Language) -> String {
            language == .polish ? "instrukcja systemowa" : "system instruction"
        }

        static func message(_ index: Int, role: String, in language: Language) -> String {
            language == .polish ? "wiadomość \(index) (\(role))" : "message \(index) (\(role))"
        }

        static func prompt(in language: Language) -> String {
            language == .polish ? "prompt" : "prompt"
        }

        static func whole(in language: Language) -> String {
            language == .polish ? "cała" : "all of it"
        }

        static func beginning(_ percent: Int, in language: Language) -> String {
            language == .polish
                ? "początek, ok. \(percent)%"
                : "the beginning, about \(percent)%"
        }

        static func latestDoesNotFit(in language: Language) -> String {
            language == .polish
                ? "najnowsza wiadomość sama nie mieści się w oknie "
                    + "— ucinany jest jej początek, po tokenach"
                : "the latest message alone does not fit the window "
                    + "— its beginning is being cut, by tokens"
        }

        static func systemSurvives(in language: Language) -> String {
            language == .polish
                ? "(instrukcja systemowa przeżywa — Ollama ją zachowuje)"
                : "(the system instruction survives — Ollama keeps it)"
        }
    }

    /// Rozkłada żądanie na kawałki. Kolejność odpowiada kolejności wysyłki.
    public static func parts(of body: JSONValue, in language: Language) -> [PromptPart] {
        var parts: [PromptPart] = []

        if let tools = body["tools"]?.arrayValue, !tools.isEmpty {
            parts.append(PromptPart(
                label: Words.tools(tools.count, in: language),
                characters: JSONValue.array(tools).characterCount,
                kind: .tools
            ))
        }

        if let system = body["system"]?.stringValue, !system.isEmpty {
            parts.append(PromptPart(
                label: Words.systemInstruction(in: language),
                characters: system.count, kind: .system
            ))
        }

        for (index, message) in (body["messages"]?.arrayValue ?? []).enumerated() {
            let role = message["role"]?.stringValue ?? "?"
            var characters = (message["content"]?.text ?? "").count
            // Wywołania narzędzi jadą do modelu razem z wiadomością i zajmują
            // okno, choć nie są jej treścią.
            for call in message["tool_calls"]?.arrayValue ?? [] {
                characters += call.characterCount
            }
            let isSystem = role == "system"
            parts.append(PromptPart(
                label: isSystem
                    ? Words.systemInstruction(in: language)
                    : Words.message(index + 1, role: role, in: language),
                characters: characters,
                kind: isSystem ? .system : .turn
            ))
        }

        if let prompt = body["prompt"], !prompt.text.isEmpty {
            parts.append(PromptPart(
                label: Words.prompt(in: language), characters: prompt.text.count, kind: .prompt
            ))
        }

        return parts
    }

    /// Które kawałki wypadną, gdy ucinane są **tokeny** od początku
    /// (`/api/generate` i `/v1/completions`).
    public static func victims(
        in parts: [PromptPart], charactersCut: Int, in language: Language
    ) -> [String] {
        var lost: [String] = []
        var remaining = charactersCut
        for part in parts {
            guard remaining > 0 else { break }
            if part.characters <= remaining {
                lost.append("\(part.label) — \(Words.whole(in: language))")
                remaining -= part.characters
            } else {
                let percent = part.characters > 0
                    ? Int((100.0 * Double(remaining) / Double(part.characters)).rounded())
                    : 0
                lost.append("\(part.label) — \(Words.beginning(percent, in: language))")
                remaining = 0
            }
        }
        return lost
    }

    /// Co wypadnie z **rozmowy** (`/api/chat`, `/v1/chat/completions`).
    ///
    /// Serwer idzie od końca i bierze tyle wiadomości, ile mieści się w oknie,
    /// a instrukcję systemową dokłada niezależnie od tego, jak stara jest.
    /// Ginie więc **środek rozmowy**, nie jej początek — i to jest powód,
    /// dla którego log milczy: żaden token nie został ucięty, po prostu część
    /// rozmowy nigdy do modelu nie pojechała.
    ///
    /// `overflowed` znaczy, że nawet sama najnowsza wiadomość nie mieści się
    /// w oknie. Wtedy przycinanie po wiadomościach nie wystarcza, wchodzi
    /// ucinanie po tokenach — i **to** już w logu widać. Rozróżnienie jest
    /// zmierzone: ta sama treść jako jedna wielka wiadomość daje WARN,
    /// rozbita na osiemnaście tur nie daje nic.
    ///
    /// `lostTurns` to **liczba samych tur**, policzona osobno od etykiet.
    /// Etykiet bywa o jedną więcej (dopisek o instrukcji systemowej), więc
    /// `lost.count` byłby liczbą o jeden za dużą — a §15 stawia hipotezę
    /// o płaskowyżu właśnie na tej liczbie i ma ją zmierzyć, nie oszacować.
    public static func conversationVictims(
        in parts: [PromptPart], characterBudget: Int, in language: Language
    ) -> (lost: [String], overflowed: Bool, lostTurns: Int) {
        var budget = characterBudget
        for part in parts where part.kind == .system || part.kind == .tools {
            budget -= part.characters      // te wchodzą zawsze, kosztem tur
        }

        var survivors = Set<Int>()
        for index in stride(from: parts.count - 1, through: 0, by: -1) {
            let part = parts[index]
            guard part.kind == .turn else { continue }
            // Dalej w przeszłość jest już tylko gorzej.
            guard part.characters <= budget else { break }
            budget -= part.characters
            survivors.insert(index)
        }

        let turns = parts.enumerated().filter { $0.element.kind == .turn }
        let overflowed = survivors.isEmpty && !turns.isEmpty
        if overflowed {
            return ([Words.latestDoesNotFit(in: language)], true, turns.count)
        }

        let casualties = turns.filter { !survivors.contains($0.offset) }
        var lost = casualties.map { "\($0.element.label) — \(Words.whole(in: language))" }
        if !lost.isEmpty, parts.contains(where: { $0.kind == .system }) {
            lost.append(Words.systemSurvives(in: language))
        }
        return (lost, false, casualties.count)
    }
}
