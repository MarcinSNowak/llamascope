import Foundation

/// Ile znaków przypada na token — uczone osobno dla każdego modelu.
///
/// Ollama nie ma endpointu tokenizacji, więc liczbę tokenów da się tylko
/// oszacować, a pomiar pokazał pomyłkę rzędu 40% w obie strony: polszczyzna
/// schodzi do ~2,2 znaku na token, powtarzalny kod idzie powyżej 3. Dlatego
/// zamiast jednej liczby trzymamy **przedział**, a o ostrzeżeniu decyduje
/// jego dolny kraniec, bo mniej znaków na token to więcej tokenów.
public struct Calibrator: Sendable, Equatable {
    /// Punkt wyjścia, zanim przyjdzie pierwsza wiarygodna próbka.
    public static let startingBand = (low: 2.2, high: 4.0)

    /// Ile ostatnich próbek trzymamy na model. Rozmowa potrafi zmienić
    /// charakter (polski tekst, potem kod), więc pamięć bez końca
    /// uśredniałaby dwa różne zjawiska.
    public static let sampleLimit = 30

    private var ratios: [String: [Double]] = [:]

    public init() {}

    public func band(for model: String) -> (low: Double, high: Double, samples: Int) {
        guard let samples = ratios[model], !samples.isEmpty else {
            return (Self.startingBand.low, Self.startingBand.high, 0)
        }
        let average = samples.reduce(0, +) / Double(samples.count)
        // Margines maleje z liczbą próbek, ale nigdy nie schodzi poniżej 10%.
        // Ten sam model tokenizuje polski tekst i kod zupełnie inaczej, więc
        // zbieżność do jednej wartości byłaby złudzeniem dokładności.
        let margin = max(0.10, 0.35 / Double(samples.count).squareRoot())
        return (average * (1 - margin), average * (1 + margin), samples.count)
    }

    /// Dokłada próbkę, o ile jest wiarygodna.
    ///
    /// Dwa odrzucenia, obydwa konieczne: żądania krótkie (szum dzielenia
    /// przez małą liczbę) oraz stosunki spoza rozsądnego pasma. To drugie
    /// odsiewa trafienie w pamięć podręczną promptu — Ollama zgłasza wtedy
    /// znacznie mniej tokenów, bo przelicza tylko nową część rozmowy —
    /// i samo ucięcie, czyli dokładnie to, co chcemy wykrywać.
    public mutating func add(model: String, characters: Int, tokens: Int?) {
        guard let tokens, tokens >= 200 else { return }
        let ratio = Double(characters) / Double(tokens)
        guard ratio > 2.0, ratio < 6.0 else { return }
        var samples = ratios[model] ?? []
        samples.append(ratio)
        if samples.count > Self.sampleLimit {
            samples.removeFirst(samples.count - Self.sampleLimit)
        }
        ratios[model] = samples
    }
}
