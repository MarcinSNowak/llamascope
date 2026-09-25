import Foundation

/// Czytanie własnego logu **z powrotem** — na paczkę diagnostyczną (§10).
///
/// Osobno od `AppLog`, bo `AppLog` ma jedno zadanie: dopisać linię i nie
/// zapchać dysku. Czytanie ma zupełnie inne ryzyka (rotacja, linie bez
/// znacznika czasu, plik skasowany w międzyczasie) i własne testy.
///
/// Zgodność z §9 bez zmian: to czyta pliki, których właścicielem jest
/// użytkownik, i nie wysyła ich nigdzie.
public struct AppLogArchive: Sendable {
    /// Pojedyncza linia logu, rozebrana na czas i treść. Czas jest z pliku,
    /// nie z zegara — inaczej „ostatnia godzina" po restarcie aplikacji
    /// oznaczałaby „wszystko, co zdążyliśmy zapisać od uruchomienia".
    public struct Entry: Sendable, Equatable {
        public let time: Date
        public let message: String

        public init(time: Date, message: String) {
            self.time = time
            self.message = message
        }

        public var line: String { "\(AppLog.stamp.string(from: time)) \(message)" }
    }

    /// Przedrostek, po którym poznajemy linię nierozpoznaną. Stała, a nie
    /// napis wpisany w dwóch miejscach: `Monitor` go zapisuje, paczka
    /// diagnostyczna go szuka, a §10 nazywa te linie najważniejszą rzeczą
    /// w całym zgłoszeniu. Rozjazd tych dwóch napisów nie wywaliłby niczego —
    /// dałby paczkę z pustą sekcją, czyli spokojne zero.
    public static let unrecognizedPrefix = "NIEROZPOZNANA LINIA LOGU OLLAMY:"

    /// Pliki od **najstarszego** do bieżącego. Kolejność jest częścią umowy:
    /// wynik `entries()` ma być chronologiczny, a rotacja numeruje pliki
    /// odwrotnie (`llamascope.4.log` jest najstarszy).
    public let files: [URL]

    public init(files: [URL]) {
        self.files = files
    }

    public init(log: AppLog) {
        self.init(files: stride(from: log.keep - 1, through: 0, by: -1).map(log.file(_:)))
    }

    /// Wszystko, co da się przeczytać, chronologicznie.
    ///
    /// Linia bez znacznika czasu na początku nie jest błędem do wyrzucenia:
    /// zacytowana linia cudzego logu może zawierać przełamanie wiersza
    /// i wtedy jej dalszy ciąg trafia do pliku bez stempla. Doklejamy ją do
    /// poprzedniej — wyrzucona zmieniłaby treść linii, której nie zrozumieliśmy,
    /// a po to ona w logu jest.
    public func entries() -> [Entry] {
        var entries: [Entry] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(line)
                if let entry = Self.parse(line: line) {
                    entries.append(entry)
                } else if !line.isEmpty, let previous = entries.popLast() {
                    entries.append(Entry(
                        time: previous.time, message: previous.message + "\n" + line
                    ))
                }
            }
        }
        return entries
    }

    static func parse(line: String) -> Entry? {
        // Stempel ma stałą długość: „2026-09-25 08:41:03" to 19 znaków,
        // po nim spacja. Sprawdzamy przez próbę rozbioru, a nie przez
        // wyliczanie znaków — format żyje w jednym miejscu (`AppLog.stamp`).
        guard line.count > 20 else { return nil }
        let stamp = String(line.prefix(19))
        guard line[line.index(line.startIndex, offsetBy: 19)] == " ",
              let time = AppLog.stamp.date(from: stamp)
        else { return nil }
        return Entry(time: time, message: String(line.dropFirst(20)))
    }
}

public extension Array where Element == AppLogArchive.Entry {
    /// Ostatnia godzina (§10). Granica podana wprost, nie liczona ze
    /// `Date()` w środku — paczka ma jeden moment powstania i wszystkie
    /// jej sekcje mają się do niego odnosić.
    func since(_ moment: Date) -> [AppLogArchive.Entry] {
        filter { $0.time >= moment }
    }

    /// Linie, których nie zrozumieliśmy — z **całego** archiwum, nie tylko
    /// z ostatniej godziny. Zmiana formatu logu Ollamy zdarza się przy
    /// aktualizacji serwera, czyli zwykle dużo wcześniej, niż ktoś siada
    /// do zgłoszenia.
    var unrecognized: [AppLogArchive.Entry] {
        filter { $0.message.hasPrefix(AppLogArchive.unrecognizedPrefix) }
    }

    /// Ostatnie `count` wpisów, w kolejności chronologicznej.
    func last(_ count: Int) -> [AppLogArchive.Entry] {
        self.count <= count ? self : Array(suffix(count))
    }
}
