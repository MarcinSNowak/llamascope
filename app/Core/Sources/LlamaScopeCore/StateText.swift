import Foundation

/// Zdania o stanach — jedno miejsce dla sondy wiersza poleceń i dla paska
/// menu. Gdyby były dwa, rozeszłyby się w dwa tygodnie, a wtedy zgłoszenie
/// od użytkownika („sonda mówi co innego niż ikona") byłoby nie do
/// odczytania. Ten sam powód, dla którego rdzeń jest w jednym miejscu (§12).
///
/// Teksty są po polsku, nazwy po angielsku — granica jak w całej aplikacji.
public enum StateText {
    /// Pełne zdanie z odpowiedzią „więc co". Do menu i do sondy.
    public static func sentence(_ state: AppState) -> String {
        switch state {
        case let .promptTruncated(truncation):
            let percent = Int((truncation.lostShare * 100).rounded())
            return "Wysłałeś \(tokens(truncation.promptTokens)), model przeczytał "
                + "\(tokens(truncation.readTokens)). Przepadło \(percent)%."
        case let .modelOutsideGPU(model, bytesOutside):
            return String(
                format: "%@ z %@ liczy się na procesorze — będzie kilka razy wolniej (%@).",
                gigabytes(bytesOutside), gigabytes(model.sizeBytes), model.name
            )
        case let .memoryRunningOut(grownGB):
            return String(
                format: "Swapu przybyło %@ GB, odkąd Ollama nic nie trzymała. "
                    + "Model nie mieści się obok tego, co masz otwarte.",
                decimal(grownGB)
            )
        case let .holdingMemoryIdle(model, releasesIn):
            let when = releasesIn.map { ", zwolni za \(duration($0))" } ?? ""
            return "\(gigabytes(model.sizeBytes)) zajęte, nic nie liczy\(when) (\(model.name))."
        case let .working(model):
            return "\(model.name) pracuje."
        case .asleep:
            return "Nic nie jest załadowane. Spokój."
        case let .loadedActivityUnknown(model, reason):
            return "\(model.name) jest w pamięci, ale nie umiem odczytać GPU, "
                + "więc nie wiem, czy liczy. \(reason.logLine)"
        case let .ollamaNotResponding(reason):
            return "Ollama nie odpowiada (\(reason)). Uruchom: ollama serve"
        }
    }

    /// Nagłówek panelu — **zdanie przed liczbą**, pierwsza z trzech reguł
    /// projektowych z §7. Mówi, co się dzieje, i nie zawiera ani jednej
    /// liczby; liczby są niżej, jako uzasadnienie.
    public static func headline(_ state: AppState) -> String {
        switch state {
        case .promptTruncated: return "Prompt został ucięty"
        case .modelOutsideGPU: return "Model nie mieści się w GPU"
        case .memoryRunningOut: return "Pamięć się kończy"
        case .holdingMemoryIdle: return "Model trzyma pamięć"
        case .working: return "Wszystko gra"
        case .asleep: return "Nic nie jest załadowane"
        case .loadedActivityUnknown: return "Nie wiem, czy liczy"
        case .ollamaNotResponding: return "Ollama nie odpowiada"
        }
    }

    /// Co z tym zrobić. Druga reguła z §7 mówi, że każdy zły stan ma mieć
    /// przycisk — ale przycisk mamy tylko do jednego stanu, bo tylko jedną
    /// rzecz umiemy naprawić sami. Do pozostałych zostaje uczciwa rada.
    ///
    /// `nil` znaczy „nie ma czego naprawiać" i tak ma zostać: dopisanie tu
    /// zdania do stanu spokojnego zamieniłoby panel w tapetę.
    public static func howToFix(_ state: AppState) -> String? {
        switch state {
        case let .promptTruncated(truncation):
            return "Okno tego modelu to \(tokens(truncation.limitTokens)). Albo powiększ "
                + "je przy uruchamianiu modelu (num_ctx), albo podziel to, co wysyłasz, "
                + "na kawałki. Sama odpowiedź, którą właśnie dostałeś, nie widziała "
                + "większości Twojego tekstu."
        case let .modelOutsideGPU(model, _):
            return "Zwolnij pamięć — zamknij część programów albo wyłącz inne modele "
                + "— i załaduj \(model.name) jeszcze raz. Dopóki część liczy się na "
                + "procesorze, będzie kilka razy wolniej."
        case .memoryRunningOut:
            return "Zamknij, czego nie używasz, albo zwolnij model. Swap to dysk "
                + "udający pamięć i przy modelu widać to natychmiast."
        case .loadedActivityUnknown:
            return "To jest luka w tej aplikacji, nie awaria Twojej maszyny. "
                + "Zgłoś to razem z logiem — w środku jest napisane, czego szukałem."
        case .ollamaNotResponding:
            return "Uruchom serwer poleceniem: ollama serve"
        case .holdingMemoryIdle, .working, .asleep:
            return nil
        }
    }

    /// Kilka znaków do paska menu. Docelowo obok ikony.
    public static func shortLabel(_ state: AppState) -> String {
        switch state {
        case .promptTruncated: return "ucięty"
        case .modelOutsideGPU: return "poza GPU"
        case .memoryRunningOut: return "pamięć"
        case .holdingMemoryIdle: return "bezczynny"
        case .working: return "pracuje"
        case .asleep: return "—"
        case .loadedActivityUnknown: return "?"
        case .ollamaNotResponding: return "brak"
        }
    }

    /// Zdanie o tym, czego aplikacja **nie** widzi. Wymóg z §5: obietnica
    /// „powiem Ci, gdy model przestanie czytać" bez tego zdania jest
    /// nieprawdziwa dla każdego, kto prowadzi z modelem rozmowę.
    public static let detectionLimit =
        "Widzę ucięcie tylko wtedy, gdy sama najnowsza wiadomość nie mieści się "
        + "w oknie. Gdy to rozmowa jest za długa, Ollama wyrzuca najstarsze "
        + "wiadomości i nie zapisuje tego w logu — tego nie zobaczę."

    /// Zajętość okna kontekstu do panelu szczegółów — trzecia liczba z logu
    /// (§5), jedyna, którą widać **zanim** coś się utnie.
    public static func windowFill(_ prompt: PromptAccepted) -> String {
        let percent = Int((prompt.fill * 100).rounded())
        return "\(number(prompt.promptTokens)) z \(number(prompt.windowTokens)) (\(percent)%)"
    }

    /// Tempo **skończonej** odpowiedzi, do panelu. Podpisane wprost jako
    /// ostatnia, bo w trakcie generowania Ollama nie zapisała jeszcze
    /// szybkości tej trwającej i każda liczba pokazana bez tego podpisu
    /// opisywałaby co innego, niż się wydaje.
    public static func lastAnswer(_ generation: EvalSpeed) -> String {
        "\(tokens(generation.tokens)), \(decimal(generation.tokensPerSecond)) tok/s"
    }

    public static func gigabytesText(_ bytes: UInt64) -> String { gigabytes(bytes) }

    public static func durationText(_ seconds: TimeInterval) -> String { duration(seconds) }

    private static func number(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{00A0}"
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private static func tokens(_ count: Int) -> String {
        "\(number(count)) \(tokenWord(count))"
    }

    /// Polska odmiana: 1 token, 2–4 tokeny, 5+ tokenów, z wyjątkiem
    /// nastolatków i z regułą na końcówki 22, 23, 24.
    static func tokenWord(_ count: Int) -> String {
        let last = count % 10
        let lastTwo = count % 100
        if count == 1 { return "token" }
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "tokeny" }
        return "tokenów"
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        "\(decimal(Double(bytes) / 1e9)) GB"
    }

    private static func decimal(_ value: Double) -> String {
        // Przecinek, nie kropka — to jest tekst po polsku.
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let rest = total % 60
        return minutes > 0 ? "\(minutes) min \(rest) s" : "\(rest) s"
    }
}
