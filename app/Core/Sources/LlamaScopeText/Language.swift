import Foundation

/// Język tekstów pokazywanych człowiekowi.
///
/// To jest **osobny cel**, a nie typ w rdzeniu, z jednego powodu: potrzebują
/// go i rdzeń, i pośrednik, a pośrednikowi nie wolno zależeć od rdzenia.
/// `LlamaScopeProxyCore` ma nie umieć gadać przez sieć i to jest sprawdzalne
/// z zewnątrz; wciągnięcie tu `LlamaScopeCore` razem z `OllamaClient`
/// skasowałoby tę własność w zamian za jeden typ wyliczeniowy.
///
/// Dwie wartości i **ani jednej trzeciej** w rodzaju `.system`. Pytanie
/// „czego chce ten człowiek" rozstrzyga się raz, przy starcie programu,
/// i dalej jedzie jako zwykły argument. Funkcja, która sama dopytuje system
/// o język, daje inny wynik na innej maszynie — a test, który jest zielony
/// dlatego, że maszyna jest ustawiona po polsku, to dokładnie to spokojne
/// zero, które tym narzędziem tropimy u innych.
public enum Language: String, Sendable, CaseIterable {
    case polish = "pl"
    case english = "en"

    /// Polski tylko wtedy, gdy człowiek o niego prosi.
    ///
    /// Przy każdym innym ustawieniu systemu wychodzi angielski, i to nie
    /// jest uprzejmość wobec Apple: z tych dwóch języków angielski jest
    /// jedynym, który ktoś w Lizbonie w ogóle przeczyta. Lista preferencji
    /// jest uporządkowana, więc bierzemy z niej pierwszy język, który
    /// umiemy — niemiecki w środku listy nie przesłania polskiego z końca
    /// tylko dlatego, że stoi wyżej.
    public static func preferred(from codes: [String] = Locale.preferredLanguages) -> Language {
        for code in codes {
            let base = code.split(separator: "-").first.map(String.init) ?? code
            if let language = Language(rawValue: base.lowercased()) { return language }
        }
        return .english
    }
}
