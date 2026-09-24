import Foundation

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
    /// Rozkłada żądanie na kawałki. Kolejność odpowiada kolejności wysyłki.
    public static func parts(of body: JSONValue) -> [PromptPart] {
        var parts: [PromptPart] = []

        if let tools = body["tools"]?.arrayValue, !tools.isEmpty {
            parts.append(PromptPart(
                label: "definicje narzędzi (\(tools.count))",
                characters: JSONValue.array(tools).characterCount,
                kind: .tools
            ))
        }

        if let system = body["system"]?.stringValue, !system.isEmpty {
            parts.append(PromptPart(
                label: "instrukcja systemowa", characters: system.count, kind: .system
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
                label: isSystem ? "instrukcja systemowa" : "wiadomość \(index + 1) (\(role))",
                characters: characters,
                kind: isSystem ? .system : .turn
            ))
        }

        if let prompt = body["prompt"], !prompt.text.isEmpty {
            parts.append(PromptPart(label: "prompt", characters: prompt.text.count, kind: .prompt))
        }

        return parts
    }

    /// Które kawałki wypadną, gdy ucinane są **tokeny** od początku
    /// (`/api/generate` i `/v1/completions`).
    public static func victims(in parts: [PromptPart], charactersCut: Int) -> [String] {
        var lost: [String] = []
        var remaining = charactersCut
        for part in parts {
            guard remaining > 0 else { break }
            if part.characters <= remaining {
                lost.append("\(part.label) — cała")
                remaining -= part.characters
            } else {
                let percent = part.characters > 0
                    ? Int((100.0 * Double(remaining) / Double(part.characters)).rounded())
                    : 0
                lost.append("\(part.label) — początek, ok. \(percent)%")
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
        in parts: [PromptPart], characterBudget: Int
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
            return (["najnowsza wiadomość sama nie mieści się w oknie "
                     + "— ucinany jest jej początek, po tokenach"], true, turns.count)
        }

        let casualties = turns.filter { !survivors.contains($0.offset) }
        var lost = casualties.map { "\($0.element.label) — cała" }
        if !lost.isEmpty, parts.contains(where: { $0.kind == .system }) {
            lost.append("(instrukcja systemowa przeżywa — Ollama ją zachowuje)")
        }
        return (lost, false, casualties.count)
    }
}
