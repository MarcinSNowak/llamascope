import Foundation

/// Dowolna wartość JSON, bo żądania do Ollamy nie mają jednego kształtu.
///
/// Typ jawny (`struct ChatRequest: Decodable`) odpadł z powodu, który widać
/// dopiero na prawdziwym ruchu: pośrednik stoi w cudzym połączeniu i dostaje
/// to, co wysyła Continue, `ollama-python`, `curl` albo klient, którego
/// jeszcze nie ma. Pole, którego nie przewidzieliśmy, nie może wywrócić
/// rozbioru — a przy typie jawnym wywraca albo wypada po cichu.
///
/// `content` bywa napisem albo listą kawałków (kształt OpenAI), więc mieszany
/// kształt jest tu regułą, nie wyjątkiem.
public indirect enum JSONValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case let .object(fields) = self { return fields[key] }
        return nil
    }

    public var stringValue: String? {
        if case let .string(text) = self { return text }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case let .number(value): return Int(value)
        // `num_ctx` potrafi przyjechać jako napis — klienci składają
        // żądania z konfiguracji, a w konfiguracji wszystko jest napisem.
        case let .string(text): return Int(text)
        default: return nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(items) = self { return items }
        return nil
    }

    /// Treść wiadomości jako tekst. Napis zwraca sam siebie, lista kawałków
    /// — sklejone pola `text`. Obrazek albo dźwięk nie ma pola `text` i nie
    /// wnosi tu nic; to jest świadome uproszczenie, bo liczymy znaki tekstu,
    /// a nie tokeny obrazu.
    public var text: String {
        switch self {
        case let .string(value): return value
        case let .array(items): return items.map(\.text).joined()
        case let .object(fields): return fields["text"]?.stringValue ?? ""
        default: return ""
        }
    }

    /// Długość zwartego zapisu JSON — tym mierzymy definicje narzędzi
    /// i wywołania narzędzi, bo one nie są tekstem, a do modelu jadą jako
    /// tekst i zajmują okno tak samo.
    public var characterCount: Int { compactJSON.count }

    public var compactJSON: String {
        switch self {
        case let .string(value):
            let data = try? JSONEncoder().encode(value)
            return data.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        case let .number(value):
            return value == value.rounded() && abs(value) < 1e15
                ? String(Int(value))
                : String(value)
        case let .bool(value): return value ? "true" : "false"
        case .null: return "null"
        case let .array(items):
            return "[" + items.map(\.compactJSON).joined(separator: ",") + "]"
        case let .object(fields):
            // Klucze posortowane, żeby ta sama treść zawsze dawała tę samą
            // liczbę — inaczej testy zależałyby od kolejności w słowniku.
            let pairs = fields.keys.sorted().map { key in
                "\(JSONValue.string(key).compactJSON):\(fields[key]!.compactJSON)"
            }
            return "{" + pairs.joined(separator: ",") + "}"
        }
    }

    public static func parse(_ data: Data) -> JSONValue? {
        guard let object = try? JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed]
        ) else { return nil }
        return from(object)
    }

    static func from(_ object: Any) -> JSONValue {
        switch object {
        case let text as String: return .string(text)
        case let number as NSNumber:
            // W JSON-ie z `JSONSerialization` `true` jest NSNumber-em.
            // Bez tego rozróżnienia definicje narzędzi liczyłyby się jako
            // „1" zamiast „true" — drobiazg, ale to jest liczenie znaków.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return .number(number.doubleValue)
        case is NSNull: return .null
        case let items as [Any]: return .array(items.map(from))
        case let fields as [String: Any]:
            return .object(fields.mapValues(from))
        default: return .null
        }
    }
}
