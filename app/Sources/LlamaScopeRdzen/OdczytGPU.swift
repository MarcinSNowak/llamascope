import Foundation
import IOKit

/// Wynik próby odczytania obciążenia GPU.
///
/// Zasada, od której zaczyna się ten plik: **nieudany odczyt nie może wyglądać
/// jak zero.** Na wykresie brak odczytu i bezczynny układ są nie do
/// odróżnienia, a to dokładnie ta klasa awarii, którą tym narzędziem tropimy
/// u innych. Dlatego zamiast `Int?` mamy wyliczenie, które mówi, na czym
/// dokładnie stanęło — i które w tej postaci trafia do logu, bo z niego
/// powstaje odpowiedź na pytanie otwarte o M1, M3 i M4 (§15).
public enum WynikGPU: Sendable, Equatable {
    case odczyt(procent: Int, klasa: String, klucz: String)
    /// Żadna ze znanych nam klas IOKit nie istnieje na tej maszynie.
    case brakKlasy(szukane: [String])
    /// Klasa jest, ale nie ma w niej słownika statystyk.
    case brakStatystyk(klasa: String)
    /// Statystyki są, ale pod innymi nazwami niż te, które znamy.
    /// `dostepne` jest tu po to, żeby zgłoszenie od razu niosło odpowiedź.
    case brakKlucza(klasa: String, dostepne: [String])

    public var procent: Int? {
        if case let .odczyt(procent, _, _) = self { return procent }
        return nil
    }

    public var linijkaLogu: String {
        switch self {
        case let .odczyt(procent, klasa, klucz):
            return "GPU: \(procent)% | klasa \(klasa) | klucz „\(klucz)”"
        case let .brakKlasy(szukane):
            return "GPU: BRAK ODCZYTU — żadnej z klas \(szukane.joined(separator: ", ")) "
                + "nie ma w IORegistry. To nie jest zero obciążenia."
        case let .brakStatystyk(klasa):
            return "GPU: BRAK ODCZYTU — klasa \(klasa) istnieje, ale nie ma "
                + "słownika PerformanceStatistics. To nie jest zero obciążenia."
        case let .brakKlucza(klasa, dostepne):
            return "GPU: BRAK ODCZYTU — klasa \(klasa) ma statystyki, ale żadnego "
                + "ze znanych kluczy. Dostępne: \(dostepne.joined(separator: ", "))"
        }
    }
}

public enum OdczytGPU {
    /// Kolejność ma znaczenie — pierwsza pasująca wygrywa.
    /// `AGXAccelerator` jest jedyną sprawdzoną przez nas (M2 Pro, 2026-09);
    /// pozostałe są zgadywane i dlatego log zapisuje, która zadziałała.
    public static let znaneKlasy = ["AGXAccelerator", "IOAccelerator", "IOGPU"]

    /// Też zgadywane poza pierwszym. „Device Utilization %" jest tym, co czyta
    /// wersja pythonowa i co było mierzone.
    public static let znaneKlucze = [
        "Device Utilization %",
        "Renderer Utilization %",
        "GPU Activity(%)",
    ]

    public static func obciazenie() -> WynikGPU {
        for klasa in znaneKlasy {
            guard let usluga = usluga(klasy: klasa) else { continue }
            defer { IOObjectRelease(usluga) }

            guard let statystyki = wlasciwosc(usluga, "PerformanceStatistics") as? [String: Any] else {
                return .brakStatystyk(klasa: klasa)
            }

            for klucz in znaneKlucze {
                if let wartosc = statystyki[klucz] as? NSNumber {
                    return .odczyt(procent: wartosc.intValue, klasa: klasa, klucz: klucz)
                }
            }

            return .brakKlucza(klasa: klasa, dostepne: statystyki.keys.sorted())
        }

        return .brakKlasy(szukane: znaneKlasy)
    }

    /// Liczba rdzeni GPU. Wariantów układu jest więcej niż nazw generacji
    /// i właśnie tym się różnią, więc bez tego zgłoszenie mówi mniej, niż może.
    public static func liczbaRdzeni() -> Int? {
        for klasa in znaneKlasy {
            guard let usluga = usluga(klasy: klasa) else { continue }
            defer { IOObjectRelease(usluga) }

            if let liczba = wlasciwosc(usluga, "gpu-core-count") as? NSNumber {
                return liczba.intValue
            }
        }
        return nil
    }

    private static func usluga(klasy nazwa: String) -> io_service_t? {
        guard let dopasowanie = IOServiceMatching(nazwa) else { return nil }
        let usluga = IOServiceGetMatchingService(kIOMainPortDefault, dopasowanie)
        return usluga == IO_OBJECT_NULL ? nil : usluga
    }

    private static func wlasciwosc(_ usluga: io_service_t, _ nazwa: String) -> Any? {
        IORegistryEntryCreateCFProperty(usluga, nazwa as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
