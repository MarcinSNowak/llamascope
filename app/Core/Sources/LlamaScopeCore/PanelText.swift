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

    // MARK: - Paczka diagnostyczna (§10)

    /// Napisy okna diagnostyki. Dwujęzyczne, mimo że **treść** paczki jest
    /// po polsku: to są zdania o tym, co się zaraz stanie z plikiem, i muszą
    /// być zrozumiałe, zanim ktokolwiek naciśnie „wyślij". Sama treść zostaje
    /// po polsku, bo składa się z linii logu, które powstały wcześniej.
    public static func collectDiagnostics(in language: Language) -> String {
        language == .polish ? "Zbierz diagnostykę" : "Collect diagnostics"
    }

    public static func collectingDiagnostics(in language: Language) -> String {
        language == .polish ? "Składam…" : "Collecting…"
    }

    /// Okno otwarte bez zbierania — z menu „Okno" albo po odtworzeniu układu
    /// okien przez system. Puste okno musi powiedzieć, że jest puste, a nie
    /// udawać, że coś się w nim liczy.
    public static func nothingCollectedYet(in language: Language) -> String {
        language == .polish
            ? "Nic jeszcze nie zebrano."
            : "Nothing has been collected yet."
    }

    public static func diagnosticsTitle(in language: Language) -> String {
        language == .polish ? "Diagnostyka" : "Diagnostics"
    }

    /// Pierwsze zdanie okna, i ono jest tu najważniejsze. Mówi, że nic
    /// jeszcze nigdzie nie poszło — bo dopóki tego nie wiadomo, czytanie
    /// dalszego ciągu jest czytaniem po fakcie.
    public static func diagnosticsIntro(in language: Language) -> String {
        language == .polish
            ? "To jest cały plik. Nic jeszcze nigdzie nie poszło — przeczytaj go "
                + "i sam zdecyduj, co z nim zrobić."
            : "This is the whole file. Nothing has been sent anywhere yet — read it "
                + "and decide for yourself what to do with it."
    }

    /// Dopisek o języku treści. Bez niego angielski użytkownik dostaje ścianę
    /// polszczyzny bez wyjaśnienia, skąd się wzięła.
    public static func diagnosticsIsPolish(in language: Language) -> String? {
        language == .polish
            ? nil
            : "The report itself is in Polish: it is made of lines the application "
                + "wrote to its log, and those are written in Polish."
    }

    public static func saveToDesktop(in language: Language) -> String {
        language == .polish ? "Zapisz na pulpicie" : "Save to the Desktop"
    }

    public static func savedTo(_ path: String, in language: Language) -> String {
        language == .polish ? "Zapisano: \(path)" : "Saved to: \(path)"
    }

    public static func revealInFinder(in language: Language) -> String {
        language == .polish ? "Pokaż w Finderze" : "Show in Finder"
    }

    public static func copyText(in language: Language) -> String {
        language == .polish ? "Kopiuj" : "Copy"
    }

    public static func reportOnGitHub(in language: Language) -> String {
        language == .polish ? "Zgłoś na GitHubie" : "Report on GitHub"
    }

    /// Co dokładnie idzie w odnośniku, powiedziane **przy przycisku**.
    /// Zgłoszenie na GitHubie jest publiczne i ta granica ma być widoczna
    /// w chwili klikania, a nie w dokumentacji (§10).
    public static func issueCarriesMetadataOnly(in language: Language) -> String {
        language == .polish
            ? "W zgłoszeniu idą same wersje i stan. Plik dołączasz sam albo wcale — "
                + "treść zgłoszenia na GitHubie jest publiczna."
            : "The issue carries versions and state only. You attach the file yourself "
                + "or not at all — GitHub issues are public."
    }

    public static func noGitHubAccount(_ address: String, in language: Language) -> String {
        language == .polish
            ? "Bez konta na GitHubie: wyślij plik pocztą na \(address)."
            : "No GitHub account? Send the file by e-mail to \(address)."
    }

    public static func sendByMail(in language: Language) -> String {
        language == .polish ? "Napisz wiadomość" : "Write an e-mail"
    }

    public static func close(in language: Language) -> String {
        language == .polish ? "Zamknij" : "Close"
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
