import Foundation
import LlamaScopeText

/// Napisy panelu: przyciski, etykiety wierszy i te zdania, które nie opisują
/// stanu Ollamy, tylko to, co robi sama aplikacja.
///
/// Mieszkają w rdzeniu, a nie przy rysowaniu, z tego samego powodu co
/// `StateText`: §12 wymaga, żeby wszystko, co aplikacja mówi, dało się
/// sprawdzić bez uruchamiania paska menu. Napis wpisany wprost w widok jest
/// sprawdzalny wyłącznie okiem, a okiem nikt nie sprawdzi drugiego języka,
/// którym na co dzień nie mówi.
public enum PanelText {
    // MARK: - Przyciski

    public static func releaseNow(in language: Language) -> String {
        language == .polish ? "Zwolnij teraz" : "Release now"
    }

    public static func releaseAnyway(in language: Language) -> String {
        language == .polish ? "Zwolnij mimo to" : "Release anyway"
    }

    public static func cancel(in language: Language) -> String {
        language == .polish ? "Anuluj" : "Cancel"
    }

    public static func quit(in language: Language) -> String {
        language == .polish ? "Zakończ" : "Quit"
    }

    public static func turnProxy(on: Bool, in language: Language) -> String {
        switch (language, on) {
        case (.polish, true): return "Włącz"
        case (.polish, false): return "Wyłącz"
        case (.english, true): return "Turn on"
        case (.english, false): return "Turn off"
        }
    }

    public static func loadAgain(_ model: String, in language: Language) -> String {
        language == .polish ? "Załaduj ponownie \(model)" : "Load \(model) again"
    }

    // MARK: - Zdania

    /// Pytanie przed przerwaniem generowania (§7). Mówi wprost, co się
    /// stanie, bo przerwana odpowiedź wygląda z zewnątrz jak awaria.
    public static func releaseWillInterrupt(in language: Language) -> String {
        language == .polish
            ? "Model teraz liczy. Zwolnienie przerwie to, co robi."
            : "The model is computing right now. Releasing it will interrupt that."
    }

    public static func actionFailed(_ problem: String, in language: Language) -> String {
        language == .polish ? "Nie udało się: \(problem)" : "That did not work: \(problem)"
    }

    public static func lastRefresh(_ time: String, in language: Language) -> String {
        language == .polish ? "odczyt \(time)" : "read at \(time)"
    }

    // MARK: - Etykiety wierszy

    public static func contextWindow(in language: Language) -> String {
        language == .polish ? "Okno kontekstu" : "Context window"
    }

    public static func lastAnswer(in language: Language) -> String {
        language == .polish ? "Ostatnia odpowiedź" : "Last answer"
    }

    /// Dopisek przy rozmiarze modelu. Osobno od samej liczby, bo to jest
    /// jedyne miejsce w panelu, w którym widać rozdział modelu między GPU
    /// a procesor, zanim stanie się z tego alarm.
    public static func whereItRuns(outsideGPU: Bool, in language: Language) -> String {
        switch (language, outsideGPU) {
        case (.polish, false): return ", w GPU"
        case (.polish, true): return ", częściowo poza GPU"
        case (.english, false): return ", in GPU"
        case (.english, true): return ", partly outside the GPU"
        }
    }

    // MARK: - Awarie pośrednika

    /// Powody, dla których pośrednik nie wystartował. Typ wyliczeniowy,
    /// a nie gotowe zdanie budowane na miejscu: inaczej język byłby
    /// rozstrzygany tam, gdzie akurat nastąpiła awaria, a `ProxyControl`
    /// nie ma powodu nic wiedzieć o językach.
    public enum ProxyFailure: Sendable, Equatable {
        case executableMissing
        case exited(code: Int32)
        case didNotTakePort(UInt16)
    }

    public static func proxyFailure(_ failure: ProxyFailure, in language: Language) -> String {
        switch (language, failure) {
        case (.polish, .executableMissing):
            return "nie znalazłem programu pośrednika w pakiecie aplikacji"
        case let (.polish, .exited(code)):
            return "pośrednik zakończył się z kodem \(code)"
        case let (.polish, .didNotTakePort(port)):
            return "proces działa, ale nie zajął portu \(port)"
        case (.english, .executableMissing):
            return "I could not find the proxy program inside the application bundle"
        case let (.english, .exited(code)):
            return "the proxy exited with code \(code)"
        case let (.english, .didNotTakePort(port)):
            return "the process is running but did not take port \(port)"
        }
    }
}
