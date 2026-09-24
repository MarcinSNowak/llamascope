import Foundation
import LlamaScopeText

/// Zdania o stanach — jedno miejsce dla sondy wiersza poleceń i dla paska
/// menu. Gdyby były dwa, rozeszłyby się w dwa tygodnie, a wtedy zgłoszenie
/// od użytkownika („sonda mówi co innego niż ikona") byłoby nie do
/// odczytania. Ten sam powód, dla którego rdzeń jest w jednym miejscu (§12).
///
/// Język jest **argumentem każdej z tych funkcji**, a nie ustawieniem
/// gdzieś z boku. Statyczna zmienna z bieżącym językiem czytałaby się
/// wygodniej o jeden argument, ale wynik zależałby wtedy od tego, co ktoś
/// ustawił wcześniej — a te zdania są treścią produktu i mają mieć testy,
/// które nie zależą od kolejności ich uruchomienia ani od ustawień maszyny.
///
/// Nazwy po angielsku, zdania w dwóch językach — granica jak w całej
/// aplikacji. Napisy w logu zostają po polsku świadomie: log jest
/// materiałem do zgłoszenia, czyta go ten, kto pisze tę aplikację.
public enum StateText {
    /// Pełne zdanie z odpowiedzią „więc co". Do menu i do sondy.
    public static func sentence(_ state: AppState, in language: Language) -> String {
        switch language {
        case .polish: return Polish.sentence(state)
        case .english: return English.sentence(state)
        }
    }

    /// Nagłówek panelu — **zdanie przed liczbą**, pierwsza z trzech reguł
    /// projektowych z §7. Mówi, co się dzieje, i nie zawiera ani jednej
    /// liczby; liczby są niżej, jako uzasadnienie.
    public static func headline(_ state: AppState, in language: Language) -> String {
        switch language {
        case .polish: return Polish.headline(state)
        case .english: return English.headline(state)
        }
    }

    /// Co z tym zrobić. Druga reguła z §7 mówi, że każdy zły stan ma mieć
    /// przycisk — ale przycisk mamy tylko do jednego stanu, bo tylko jedną
    /// rzecz umiemy naprawić sami. Do pozostałych zostaje uczciwa rada.
    ///
    /// `nil` znaczy „nie ma czego naprawiać" i tak ma zostać: dopisanie tu
    /// zdania do stanu spokojnego zamieniłoby panel w tapetę.
    public static func howToFix(_ state: AppState, in language: Language) -> String? {
        switch language {
        case .polish: return Polish.howToFix(state)
        case .english: return English.howToFix(state)
        }
    }

    /// Kilka znaków do paska menu, obok ikony.
    public static func shortLabel(_ state: AppState, in language: Language) -> String {
        switch language {
        case .polish: return Polish.shortLabel(state)
        case .english: return English.shortLabel(state)
        }
    }

    /// Zdanie o tym, czego aplikacja **nie** widzi. Wymóg z §5: obietnica
    /// „powiem Ci, gdy model przestanie czytać" bez tego zdania jest
    /// nieprawdziwa dla każdego, kto prowadzi z modelem rozmowę.
    public static func detectionLimit(in language: Language) -> String {
        switch language {
        case .polish:
            return "Widzę ucięcie tylko wtedy, gdy sama najnowsza wiadomość nie mieści się "
                + "w oknie. Gdy to rozmowa jest za długa, Ollama wyrzuca najstarsze "
                + "wiadomości i nie zapisuje tego w logu — tego nie zobaczę."
        case .english:
            return "I can see truncation only when the latest message alone does not fit "
                + "the window. When it is the conversation that got too long, Ollama drops "
                + "the oldest messages and writes nothing about it to the log — that one "
                + "I will not see."
        }
    }

    /// Zajętość okna kontekstu do panelu szczegółów — trzecia liczba z logu
    /// (§5), jedyna, którą widać **zanim** coś się utnie.
    public static func windowFill(_ prompt: PromptAccepted, in language: Language) -> String {
        let numbers = Numbers(language)
        return "\(numbers.count(prompt.promptTokens)) "
            + (language == .polish ? "z" : "of")
            + " \(numbers.count(prompt.windowTokens)) (\(numbers.percent(prompt.fill)))"
    }

    /// Tempo **skończonej** odpowiedzi, do panelu. Podpisane wprost jako
    /// ostatnia, bo w trakcie generowania Ollama nie zapisała jeszcze
    /// szybkości tej trwającej i każda liczba pokazana bez tego podpisu
    /// opisywałaby co innego, niż się wydaje.
    public static func lastAnswer(_ generation: EvalSpeed, in language: Language) -> String {
        let numbers = Numbers(language)
        return "\(numbers.tokens(generation.tokens)), "
            + "\(numbers.decimal(generation.tokensPerSecond)) tok/s"
    }

    public static func gigabytesText(_ bytes: UInt64, in language: Language) -> String {
        Numbers(language).gigabytes(bytes)
    }

    public static func durationText(_ seconds: TimeInterval, in language: Language) -> String {
        Numbers(language).duration(seconds)
    }
}
