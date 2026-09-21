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
public enum GPUReading: Sendable, Equatable {
    case reading(percent: Int, serviceClass: String, key: String)
    /// Żadna ze znanych nam klas IOKit nie istnieje na tej maszynie.
    case classNotFound(searched: [String])
    /// Klasa jest, ale nie ma w niej słownika statystyk.
    case statisticsNotFound(serviceClass: String)
    /// Statystyki są, ale pod innymi nazwami niż te, które znamy.
    /// `available` jest tu po to, żeby zgłoszenie od razu niosło odpowiedź.
    case keyNotFound(serviceClass: String, available: [String])

    public var percent: Int? {
        if case let .reading(percent, _, _) = self { return percent }
        return nil
    }

    public var logLine: String {
        switch self {
        case let .reading(percent, serviceClass, key):
            return "GPU: \(percent)% | klasa \(serviceClass) | klucz „\(key)”"
        case let .classNotFound(searched):
            return "GPU: BRAK ODCZYTU — żadnej z klas \(searched.joined(separator: ", ")) "
                + "nie ma w IORegistry. To nie jest zero obciążenia."
        case let .statisticsNotFound(serviceClass):
            return "GPU: BRAK ODCZYTU — klasa \(serviceClass) istnieje, ale nie ma "
                + "słownika PerformanceStatistics. To nie jest zero obciążenia."
        case let .keyNotFound(serviceClass, available):
            return "GPU: BRAK ODCZYTU — klasa \(serviceClass) ma statystyki, ale żadnego "
                + "ze znanych kluczy. Dostępne: \(available.joined(separator: ", "))"
        }
    }
}

public enum GPUReader {
    /// Kolejność ma znaczenie — pierwsza pasująca wygrywa.
    /// `AGXAccelerator` jest jedyną sprawdzoną przez nas (M2 Pro, 2026-09);
    /// pozostałe są zgadywane i dlatego log zapisuje, która zadziałała.
    public static let knownClasses = ["AGXAccelerator", "IOAccelerator", "IOGPU"]

    /// Też zgadywane poza pierwszym. „Device Utilization %" jest tym, co czyta
    /// wersja pythonowa i co było mierzone.
    public static let knownKeys = [
        "Device Utilization %",
        "Renderer Utilization %",
        "GPU Activity(%)",
    ]

    public static func utilization() -> GPUReading {
        for serviceClass in knownClasses {
            guard let service = matchingService(class: serviceClass) else { continue }
            defer { IOObjectRelease(service) }

            guard let statistics = property(service, "PerformanceStatistics") as? [String: Any] else {
                return .statisticsNotFound(serviceClass: serviceClass)
            }

            for key in knownKeys {
                if let value = statistics[key] as? NSNumber {
                    return .reading(percent: value.intValue, serviceClass: serviceClass, key: key)
                }
            }

            return .keyNotFound(serviceClass: serviceClass, available: statistics.keys.sorted())
        }

        return .classNotFound(searched: knownClasses)
    }

    /// Liczba rdzeni GPU. Wariantów układu jest więcej niż nazw generacji
    /// i właśnie tym się różnią, więc bez tego zgłoszenie mówi mniej, niż może.
    public static func coreCount() -> Int? {
        for serviceClass in knownClasses {
            guard let service = matchingService(class: serviceClass) else { continue }
            defer { IOObjectRelease(service) }

            if let count = property(service, "gpu-core-count") as? NSNumber {
                return count.intValue
            }
        }
        return nil
    }

    private static func matchingService(class name: String) -> io_service_t? {
        guard let matching = IOServiceMatching(name) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        return service == IO_OBJECT_NULL ? nil : service
    }

    private static func property(_ service: io_service_t, _ name: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
