import Foundation

/// Rozstrzygnięcie „liczy czy stoi", odporne na migotanie.
///
/// Powód jest z obserwacji na żywej sondzie (§15): przy odświeżaniu co
/// sekundę obciążenie GPU przechodzi przez próg 5% w obie strony i stan
/// skacze „bezczynny → pracuje → bezczynny" w trzech kolejnych odczytach.
/// W pasku menu to mrugająca ikona, czyli wskaźnik, którego się nie czyta.
///
/// Odpowiedzią **nie może być rzadsze odpytywanie** — sekunda jest po to,
/// żeby ucięcie było widać od razu. Odpowiedzią jest histereza: inny próg
/// na wejściu niż na wyjściu, plus chwila ciszy wymagana do zgaszenia.
///
/// Generowanie jest z natury poszarpane — między tokenami GPU potrafi na
/// moment spaść do zera — więc to nie jest wygładzanie dla ozdoby, tylko
/// naprawa fałszywego odczytu.
public struct ActivityGate: Sendable, Equatable {
    /// Próg zapłonu, zgodnie z §5.
    public static let startsWorkingAbove = 5
    /// Próg podtrzymania. Niższy, bo model w trakcie generowania schodzi
    /// między tokenami niżej niż przy starcie.
    public static let staysWorkingAbove = 1
    /// Ile ciszy trzeba, żeby uznać, że skończył. Pięć sekund: dłużej niż
    /// przerwa między tokenami, krócej niż ktokolwiek zdąży się zastanowić,
    /// czemu ikona jeszcze świeci.
    public static let quietBeforeIdle: TimeInterval = 5

    public private(set) var isWorking = false
    private var lastBusy: Date?

    public init() {}

    /// Czy sam ten odczyt, bez historii, znaczy „liczy". Jedno miejsce na
    /// próg zapłonu — żeby czysta funkcja rozpoznająca stan i ta bramka nie
    /// mogły mieć dwóch różnych zdań o tej samej liczbie.
    public static func busyOnItsOwn(_ percent: Int) -> Bool {
        percent > startsWorkingAbove
    }

    /// Jeden odczyt. `nil` znaczy „nie udało się odczytać" i **niczego nie
    /// zmienia** — nieudany odczyt nie gasi ikony i jej nie zapala, bo
    /// o braku wiedzy mówi osobny stan (§10).
    @discardableResult
    public mutating func update(percent: Int?, now: Date) -> Bool {
        guard let percent else { return isWorking }

        if Self.busyOnItsOwn(percent) {
            isWorking = true
            lastBusy = now
            return true
        }

        guard isWorking else { return false }

        if percent > Self.staysWorkingAbove {
            lastBusy = now
            return true
        }

        if let lastBusy, now.timeIntervalSince(lastBusy) < Self.quietBeforeIdle {
            return true
        }

        isWorking = false
        self.lastBusy = nil
        return false
    }

    /// Model zniknął z pamięci albo serwer przestał odpowiadać — nie ma już
    /// czego podtrzymywać.
    public mutating func reset() {
        isWorking = false
        lastBusy = nil
    }
}

/// Ostatnie ~2 minuty obciążenia GPU. To z tego rysuje się ikona: §7 mówi
/// wprost, że ikoną jest sparkline, a nie kropka.
///
/// Próbka jest `Int?`, nie `Int`. Nieudany odczyt zostaje dziurą i ma się
/// rysować jako dziura — narysowany jako zero wyglądałby jak spokój, czyli
/// popełnilibyśmy w obrazku dokładnie to kłamstwo, które tym narzędziem
/// tropimy w cudzych logach.
public struct GPUHistory: Sendable, Equatable {
    /// 120 próbek przy sekundzie odświeżania, czyli dwie minuty z §7.
    public static let capacity = 120

    public private(set) var samples: [Int?] = []

    public init() {}

    public mutating func append(_ reading: GPUReading) {
        samples.append(reading.percent)
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    public var isEmpty: Bool { samples.isEmpty }

    /// Ostatnie `count` próbek, do ikony w 16 pikselach — tam mieści się
    /// kilkanaście punktów, nie sto dwadzieścia.
    public func recent(_ count: Int) -> [Int?] {
        Array(samples.suffix(count))
    }
}
