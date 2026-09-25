import Foundation
import LlamaScopeText

/// Paczka diagnostyczna z §10: **jeden plik tekstowy**, pokazany w oknie,
/// zanim cokolwiek się z nim stanie.
///
/// To jest treść, a nie zapisywanie i nie wysyłanie — dokładnie z tego samego
/// powodu, z którego `StartupReport` stoi osobno od `AppLog`. Plik, który
/// użytkownik ma przeczytać przed wysłaniem, musi dać się sprawdzić testem
/// co do zawartości, bez uruchamiania paska menu i bez dotykania dysku.
///
/// Językowo: nagłówki dwujęzycznie, treść po polsku. Nie z lenistwa — treścią
/// są linie logu aplikacji, a te są po polsku z decyzji z §12 i przetłumaczyć
/// się ich nie da, bo nie powstają w chwili składania paczki. Nagłówek po
/// angielsku pozwala przynajmniej zobaczyć, co jest w której sekcji.
public enum DiagnosticsReport {
    /// Wszystko, czego paczka potrzebuje, zebrane **przed** składaniem.
    /// Composer sam niczego nie odczytuje: gdyby odczytywał, nie dałoby się
    /// go sprawdzić bez Ollamy, IOKitu i cudzego logu na dysku.
    public struct Input: Sendable {
        public var generatedAt: Date
        public var profile: HardwareProfile
        public var gpu: GPUReading
        public var state: AppState
        public var ollamaHost: URL
        public var ollamaVersion: OllamaVersion
        public var ollama: OllamaStatus
        public var appLogPath: String
        public var ollamaLogPath: String?
        /// Wpisy z ostatniej godziny — już odfiltrowane, chronologicznie.
        public var recentEntries: [AppLogArchive.Entry]
        /// Linie nierozpoznane z całego archiwum.
        public var unrecognized: [AppLogArchive.Entry]
        public var ollamaExcerpt: OllamaLogExcerpt

        public init(
            generatedAt: Date,
            profile: HardwareProfile,
            gpu: GPUReading,
            state: AppState,
            ollamaHost: URL,
            ollamaVersion: OllamaVersion,
            ollama: OllamaStatus,
            appLogPath: String,
            ollamaLogPath: String?,
            recentEntries: [AppLogArchive.Entry],
            unrecognized: [AppLogArchive.Entry],
            ollamaExcerpt: OllamaLogExcerpt
        ) {
            self.generatedAt = generatedAt
            self.profile = profile
            self.gpu = gpu
            self.state = state
            self.ollamaHost = ollamaHost
            self.ollamaVersion = ollamaVersion
            self.ollama = ollama
            self.appLogPath = appLogPath
            self.ollamaLogPath = ollamaLogPath
            self.recentEntries = recentEntries
            self.unrecognized = unrecognized
            self.ollamaExcerpt = ollamaExcerpt
        }
    }

    /// Okno, z którego bierzemy „ostatnie stany" — godzina z tabeli w §10.
    public static let recentWindow: TimeInterval = 60 * 60
    /// Ile linii nierozpoznanych cytujemy. Powyżej tego liczy się już tylko
    /// liczba: „50 linii i jeszcze 3000" to ta sama diagnoza co „50 linii”,
    /// a trzy tysiące linii nikt nie przeczyta przed wysłaniem.
    public static let unrecognizedQuoted = 50
    /// Ile wpisów z ostatniej godziny. Przy odświeżaniu co sekundę godzina
    /// potrafi dać sporo linii, ale zapisujemy tylko **zmiany** stanu.
    public static let recentQuoted = 200

    // MARK: - Plik

    public static func text(_ input: Input) -> String {
        var lines: [String] = []

        lines.append("LlamaScope — paczka diagnostyczna")
        lines.append("utworzona: \(AppLog.stamp.string(from: input.generatedAt))")
        lines.append("")
        lines.append("Treść jest po polsku, bo po polsku pisany jest log aplikacji.")
        lines.append("This report is in Polish — the application log is written in Polish.")

        lines.append(contentsOf: section("Maszyna i wersje / Machine and versions", [
            input.profile.logLine,
            input.gpu.logLine,
            input.ollamaVersion.logLine,
            "serwer Ollamy: \(input.ollamaHost.absoluteString)",
            "stan w chwili zbierania: \(StateText.sentence(input.state, in: .polish))",
            "log aplikacji: \(input.appLogPath)",
            input.ollamaLogPath.map { "log Ollamy: \($0)" }
                ?? "log Ollamy: NIE ZNALEZIONY",
        ]))

        lines.append(contentsOf: section("Co trzyma Ollama / Loaded models", modelLines(input.ollama)))

        lines.append(contentsOf: section(
            "Ostatnia godzina / Last hour",
            entryLines(input.recentEntries.last(recentQuoted), total: input.recentEntries.count),
            ifEmpty: "nic nie zapisano w ostatniej godzinie"
        ))

        // Najważniejsza sekcja w całym pliku (§10) — i jedyna, która ma
        // wytłumaczenie **przy sobie**, bo człowiek, który to czyta przed
        // wysłaniem, ma prawo wiedzieć, czemu wkleja cudze linie.
        lines.append(contentsOf: section(
            "Linie nierozpoznane / Unrecognized lines",
            ["(linie logu Ollamy, które wyglądały na nasze, a których nie umieliśmy rozebrać —"
                + " zwykle znaczy to, że Ollama zmieniła format)"]
                + entryLines(input.unrecognized.last(unrecognizedQuoted), total: input.unrecognized.count),
            ifEmpty: nil
        ))

        lines.append(contentsOf: section(
            "Fragment logu Ollamy / Ollama log excerpt",
            excerptLines(input.ollamaExcerpt),
            ifEmpty: nil
        ))

        // Anonimizacja na samym końcu i na całości. Wcześniej, sekcja po
        // sekcji, byłaby listą miejsc do zapamiętania przy dopisywaniu
        // kolejnej sekcji — a zapomniana sekcja nie wygląda na błąd.
        return DiagnosticsText.anonymized(lines.joined(separator: "\n") + "\n")
    }

    private static func section(
        _ title: String,
        _ body: [String?],
        ifEmpty: String? = nil
    ) -> [String] {
        let body = body.compactMap { $0 }
        return ["", "== \(title) ==", ""] + (body.isEmpty ? [ifEmpty ?? "(brak)"] : body)
    }

    private static func modelLines(_ status: OllamaStatus) -> [String] {
        switch status {
        case let .notResponding(reason):
            return ["serwer nie odpowiedział: \(reason)"]
        case let .running(models) where models.isEmpty:
            return ["serwer odpowiedział, nic nie jest załadowane"]
        case let .running(models):
            return models.map { model in
                var line = "\(model.name): \(StateText.gigabytesText(model.sizeBytes, in: .polish))"
                if model.bytesOutsideGPU > 0 {
                    line += ", poza GPU \(StateText.gigabytesText(model.bytesOutsideGPU, in: .polish))"
                }
                if let context = model.contextTokens { line += ", okno \(context)" }
                return line
            }
        }
    }

    private static func entryLines(_ entries: [AppLogArchive.Entry], total: Int) -> [String] {
        var lines = entries.map(\.line)
        // Liczba pominiętych stoi **nad** linijkami, nie pod nimi: kto czyta
        // po wierzchu, ten czyta górę sekcji.
        if total > entries.count {
            lines.insert("(pokazano ostatnie \(entries.count) z \(total))", at: 0)
        }
        return lines
    }

    private static func excerptLines(_ excerpt: OllamaLogExcerpt) -> [String] {
        var lines: [String] = []
        if let problem = excerpt.problem { lines.append("(\(problem))") }
        // To zdanie jest obietnicą z tabeli w §10, postawioną tam, gdzie da
        // się ją sprawdzić okiem — a nie w dokumentacji, której nikt nie ma
        // pod ręką w chwili wysyłania zgłoszenia.
        lines.append(
            "(cytujemy wyłącznie linie o znanym kształcie; pominięto \(excerpt.skipped) "
            + "innych linii — to jest sposób, w jaki ten plik nie zawiera treści promptów)"
        )
        lines.append(contentsOf: excerpt.lines)
        return lines
    }

    /// Nazwa pliku na pulpicie. Z datą i godziną, bo drugie zgłoszenie tego
    /// samego dnia nie ma prawa nadpisać pierwszego.
    public static func fileName(at moment: Date) -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmm"
        return "LlamaScope-diagnostyka-\(stamp.string(from: moment)).txt"
    }

    // MARK: - Dokąd to idzie (§10)

    public static let repository = "https://github.com/MarcinSNowak/llamascope"
    /// Dla kogoś bez konta na GitHubie. Adres firmowy, bo to on odpowiada za
    /// aplikację — i bo wtedy to użytkownik wysyła plik, świadomie, ze swojej
    /// skrzynki (§10).
    public static let email = "info@qshmobile.com"

    /// Wypełnione zgłoszenie na GitHubie. **Same metadane**, bez logu:
    /// treść zgłoszenia jest publiczna, a plik z pulpitu użytkownik dołącza
    /// sam albo wcale. Ta granica jest w §10 postawiona wprost.
    public static func issueURL(_ input: Input) -> URL? {
        let body = """
        <!-- Opisz, co się stało. Describe what happened. -->


        ---

        \(input.profile.logLine)
        \(input.gpu.logLine)
        \(input.ollamaVersion.logLine)
        stan / state: \(StateText.sentence(input.state, in: .polish))
        linie nierozpoznane / unrecognized lines: \(input.unrecognized.count)

        <!--
        Plik z pełną diagnostyką jest na pulpicie. Dołącz go, jeśli chcesz —
        przeczytaj go najpierw.
        The full report is on your Desktop. Attach it if you want to — read it first.
        -->
        """

        var components = URLComponents(string: "\(repository)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: "LlamaScope \(input.profile.appVersion): "),
            URLQueryItem(name: "body", value: DiagnosticsText.anonymized(body)),
        ]
        return components?.url
    }

    public static func mailtoURL(_ input: Input) -> URL? {
        var components = URLComponents(string: "mailto:\(email)")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: "LlamaScope \(input.profile.appVersion)"),
            URLQueryItem(name: "body", value: """
            Plik z diagnostyką jest na pulpicie — dołącz go do tej wiadomości.
            The diagnostics file is on your Desktop — attach it to this message.
            """),
        ]
        return components?.url
    }
}
