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
        case let .working(model, generation):
            let speed = generation.map { " — \(decimal($0.tokensPerSecond)) tok/s" } ?? ""
            return "\(model.name) pracuje\(speed)."
        case .asleep:
            return "Nic nie jest załadowane. Spokój."
        case let .loadedActivityUnknown(model, reason):
            return "\(model.name) jest w pamięci, ale nie umiem odczytać GPU, "
                + "więc nie wiem, czy liczy. \(reason.logLine)"
        case let .ollamaNotResponding(reason):
            return "Ollama nie odpowiada (\(reason)). Uruchom: ollama serve"
        }
    }

    /// Kilka znaków do paska menu. Docelowo obok ikony.
    public static func shortLabel(_ state: AppState) -> String {
        switch state {
        case .promptTruncated: return "ucięty"
        case .modelOutsideGPU: return "poza GPU"
        case .memoryRunningOut: return "pamięć"
        case .holdingMemoryIdle: return "bezczynny"
        case let .working(_, generation):
            return generation.map { "\(Int($0.tokensPerSecond.rounded())) tok/s" } ?? "pracuje"
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

    private static func tokens(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{00A0}"
        let number = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(number) \(tokenWord(count))"
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
