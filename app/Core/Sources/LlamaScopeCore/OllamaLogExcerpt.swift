import Foundation

/// Fragment logu Ollamy do paczki diagnostycznej (§10), z jedną obietnicą
/// w tabeli: **bez treści promptów**.
///
/// Obietnica jest tu spełniona odwrotnie, niż podpowiada odruch. Odruch mówi:
/// weź ostatnie sto linii i wytnij z nich to, co wygląda na prompt. To jest
/// lista rzeczy zakazanych, a lista rzeczy zakazanych chroni dokładnie do
/// pierwszego kształtu, którego na nią nie wpisaliśmy — i wtedy milczy.
/// Milczy tak samo spokojnie jak `truncated = 0`.
///
/// Dlatego jest odwrotnie: **cytujemy wyłącznie linie, które umiemy nazwać.**
/// Wszystko inne jest liczone i zgłaszane jako liczba, nie jako treść. Paczka
/// mówi wprost „pominąłem 812 linii, których nie umiem uznać za bezpieczne" —
/// a to jest zdanie, które da się sprawdzić okiem, w przeciwieństwie do braku
/// zdania.
///
/// Powód, dla którego to nie jest przesada: `OLLAMA_DEBUG=1` włącza w Ollamie
/// logowanie treści żądań. Użytkownik, który ma włączony debug, to
/// **dokładnie ten sam** użytkownik, który przysyła zgłoszenie.
public struct OllamaLogExcerpt: Sendable, Equatable {
    /// Linie zacytowane — zanonimizowane i przycięte.
    public let lines: [String]
    /// Ile linii odrzuciliśmy jako nieznane. Zero tutaj znaczy „przejrzałem
    /// i wszystkie rozpoznałem", a nie „nie patrzyłem" — od tego jest
    /// `problem`, które w tym drugim przypadku nie jest puste.
    public let skipped: Int
    /// Dlaczego fragmentu nie ma albo jest niepełny. `nil` znaczy, że plik
    /// przeczytaliśmy w całości, o którą prosiliśmy.
    public let problem: String?

    public init(lines: [String], skipped: Int, problem: String? = nil) {
        self.lines = lines
        self.skipped = skipped
        self.problem = problem
    }

    /// Linie, które wolno zacytować. Celowo krótka lista i celowo krótkie
    /// fragmenty: to są te linie, o których ta aplikacja w ogóle cokolwiek
    /// twierdzi (§5, §6), plus te, które mówią, w jakim środowisku pracuje
    /// serwer. Linii `level=ERROR` tu nie ma i to nie jest przeoczenie —
    /// komunikat błędu bywa powtórzeniem tego, co przyszło w żądaniu.
    public static let safeMarkers = [
        // To, co czytamy (§5). Zgodne z `OllamaLogParser.ourMarkers`.
        "truncating input prompt",
        "new prompt, n_ctx_slot",
        "tokens per second",
        // Środowisko: skąd wiadomo, na czym to w ogóle działa.
        "starting ollama server",
        "system memory",
        "inference compute",
        "looking for compatible gpus",
        "offloading",
        "llama_model_loader: loaded meta data",
        "load_tensors:",
        "llama_context:",
        "srv  load_model",
        "listening on",
    ]

    /// Druga siatka, pod pierwszą. Wszystkie linie z listy wyżej są krótkie;
    /// linia z markerem, ale długa na tysiąc znaków, znaczy, że do znanego
    /// kształtu doklejono coś, czego nie znamy. Przycięcie jej zostawiłoby
    /// trzysta znaków cudzej treści, więc nie przycinamy — odrzucamy.
    public static let maxSafeLength = 400

    /// Ile ostatnich linii pliku w ogóle oglądamy i ile z nich najwyżej
    /// zacytujemy. Paczka ma być do przeczytania przez człowieka przed
    /// wysłaniem — plik na tysiąc linii nie zostanie przeczytany.
    public static let linesConsidered = 500
    public static let linesQuoted = 60

    public static func take(fromText text: String) -> OllamaLogExcerpt {
        let all = text.split(separator: "\n", omittingEmptySubsequences: true)
        let considered = all.suffix(linesConsidered)

        var kept: [String] = []
        var skipped = 0
        for line in considered {
            let line = String(line)
            let lowered = line.lowercased()
            guard line.count <= maxSafeLength, safeMarkers.contains(where: lowered.contains) else {
                skipped += 1
                continue
            }
            kept.append(DiagnosticsText.shortened(DiagnosticsText.anonymized(line)))
        }

        // Ostatnie, nie pierwsze: zgłoszenie dotyczy tego, co działo się przed
        // kliknięciem „Zbierz diagnostykę”.
        let quoted = kept.count <= linesQuoted ? kept : Array(kept.suffix(linesQuoted))
        return OllamaLogExcerpt(
            lines: quoted,
            skipped: skipped,
            problem: all.count > linesConsidered
                ? "oglądano \(linesConsidered) ostatnich linii pliku"
                : nil
        )
    }

    /// Ile bajtów ogona czytamy z pliku. Log Ollamy potrafi mieć setki
    /// megabajtów; wczytanie go w całości po to, żeby wziąć pięćset linii,
    /// zamroziłoby aplikację w chwili, w której użytkownik zgłasza, że coś
    /// z nią jest nie tak.
    static let tailBytes = 512 * 1024

    public static func take(
        fromFileAt path: String?,
        using fileManager: FileManager = .default
    ) -> OllamaLogExcerpt {
        guard let path else {
            // Nie to samo co pusty fragment. „Nie znalazłem logu” jest
            // diagnozą samą w sobie (§10) i nie może wyglądać jak „log był,
            // ale nic w nim nie było”.
            return OllamaLogExcerpt(
                lines: [], skipped: 0,
                problem: "nie znaleziono logu Ollamy — szukano w "
                    + OllamaLogLocation.knownPaths.joined(separator: ", ")
            )
        }
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return OllamaLogExcerpt(
                lines: [], skipped: 0,
                problem: "logu \(path) nie dało się otworzyć do odczytu"
            )
        }
        defer { try? handle.close() }

        do {
            let size = try handle.seekToEnd()
            let from = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
            try handle.seek(toOffset: from)
            let data = try handle.readToEnd() ?? Data()
            var text = String(decoding: data, as: UTF8.self)
            // Pierwsza linia ogona jest prawie na pewno urwana w połowie.
            if from > 0, let newline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newline)...])
            }
            return take(fromText: text)
        } catch {
            return OllamaLogExcerpt(
                lines: [], skipped: 0,
                problem: "odczyt logu \(path) nie powiódł się: "
                    + (error as NSError).localizedDescription
            )
        }
    }
}
