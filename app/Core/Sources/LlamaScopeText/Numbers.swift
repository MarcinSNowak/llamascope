import Foundation

/// Liczby w zdaniu i to, co przy nich stoi.
///
/// Między polskim a angielskim różni się tu więcej niż słownik: inny
/// separator tysięcy, inny znak dziesiętny i zupełnie inna odmiana przez
/// liczbę. Gdyby to zostało rozsypane po zdaniach, angielska wersja
/// pierwszego dnia pokazałaby „4,3 GB" albo „1 tokens" — drobiazgi, po
/// których widać, że tekst jest tłumaczeniem, a nie tekstem.
public struct Numbers: Sendable {
    public let language: Language

    public init(_ language: Language) { self.language = language }

    /// Separator tysięcy: po polsku spacja, po angielsku przecinek.
    /// Spacja **nierozdzielająca**, żeby liczba nie pękła na końcu wiersza.
    public func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = language == .polish ? "\u{00A0}" : ","
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    public func tokens(_ value: Int) -> String {
        "\(count(value)) \(Numbers.tokenWord(value, in: language))"
    }

    /// Odmiana słowa „token". Polska reguła ma trzy formy i dwa wyjątki,
    /// angielska ma dwie formy — dlatego to jest funkcja, a nie pole w
    /// słowniku tłumaczeń.
    public static func tokenWord(_ count: Int, in language: Language) -> String {
        switch language {
        case .polish:
            let last = count % 10
            let lastTwo = count % 100
            if count == 1 { return "token" }
            if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "tokeny" }
            return "tokenów"
        case .english:
            return count == 1 ? "token" : "tokens"
        }
    }

    public func gigabytes(_ bytes: UInt64) -> String {
        "\(decimal(Double(bytes) / 1e9)) GB"
    }

    /// Przecinek albo kropka. Drobiazg, ale widoczny w każdym zdaniu,
    /// w którym pada liczba gigabajtów albo tokenów na sekundę.
    public func decimal(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return language == .polish ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    /// Minuty i sekundy zapisuje się tak samo w obu językach — skróty
    /// jednostek są międzynarodowe. Zostaje tu mimo to, żeby wszystkie
    /// liczby z panelu szły przez jedno miejsce.
    public func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let rest = total % 60
        return minutes > 0 ? "\(minutes) min \(rest) s" : "\(rest) s"
    }

    public func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}
