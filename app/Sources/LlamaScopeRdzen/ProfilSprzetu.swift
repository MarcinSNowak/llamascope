import Foundation

/// Wariant układu w obrębie jednej generacji. Wariantów jest więcej niż nazw
/// generacji i różnią się liczbą rdzeni GPU, więc sama „M3" nie wystarcza,
/// żeby zrozumieć zgłoszenie od użytkownika.
public enum WariantUkladu: String, Sendable, Equatable {
    case podstawowy
    case pro
    case max
    case ultra
}

/// Rodzina procesora Apple albo stwierdzenie, że to nie jest Apple Silicon.
///
/// Rozdzielenie `nieAppleSilicon` od „nie rozpoznano" jest celowe: pierwsze
/// znaczy, że aplikacja ma się nie uruchomić (§12 — bez ścieżki zapasowej dla
/// Intela), drugie znaczy, że wyszedł układ nowszy od nas i chcemy o tym
/// wiedzieć ze zgłoszenia, zamiast zgadywać.
public enum RodzinaUkladu: Sendable, Equatable {
    case apple(generacja: Int, wariant: WariantUkladu)
    case nieAppleSilicon(nazwa: String)
    case nierozpoznany(nazwa: String)

    /// Rozbiera łańcuch z `machdep.cpu.brand_string`, na przykład „Apple M2 Pro".
    public static func zTekstu(_ tekst: String) -> RodzinaUkladu {
        let nazwa = tekst.trimmingCharacters(in: .whitespacesAndNewlines)
        guard nazwa.hasPrefix("Apple M") else {
            // Wszystko, co nie zaczyna się od „Apple M", jest dla nas Intelem:
            // „Intel(R) Core(TM) i7", „Apple processor" z Rosetty, cokolwiek.
            return .nieAppleSilicon(nazwa: nazwa)
        }

        let czesci = nazwa.split(separator: " ")
        guard czesci.count >= 2,
              let generacja = Int(czesci[1].dropFirst()) else {
            return .nierozpoznany(nazwa: nazwa)
        }

        guard czesci.count >= 3 else {
            return .apple(generacja: generacja, wariant: .podstawowy)
        }

        guard let wariant = WariantUkladu(rawValue: czesci[2].lowercased()) else {
            // Nowy wariant, o którym nie wiemy. Nie udajemy, że to podstawowy —
            // zgłoszenie ma nam powiedzieć, jak się nazywa.
            return .nierozpoznany(nazwa: nazwa)
        }

        return .apple(generacja: generacja, wariant: wariant)
    }

    public var toAppleSilicon: Bool {
        if case .apple = self { return true }
        return false
    }
}

/// Profil maszyny zapisywany do logu przy każdym starcie.
///
/// Powód istnienia tej struktury jest opisany w §10 specyfikacji i nie jest
/// techniczny: mamy jedną maszynę (M2 Pro, 32 GB), a pytania o M1, M3, M4 oraz
/// warianty Pro, Max i Ultra zamkną wyłącznie zgłoszenia od użytkowników.
/// Pola dopisane po zebraniu pierwszych zgłoszeń unieważniają te zgłoszenia,
/// więc komplet musi być tu od pierwszego wydania.
///
/// Nic z tego nie opuszcza maszyny samo — §9. Zapis jest lokalny, wysyłka
/// wychodzi z ręki użytkownika.
public struct ProfilSprzetu: Sendable, Equatable {
    public let nazwaUkladu: String
    public let rodzina: RodzinaUkladu
    public let rdzeniCPU: Int
    public let rdzeniGPU: Int?
    public let pamiecBajty: UInt64
    public let wersjaMacOS: String
    public let wersjaAplikacji: String

    public init(
        nazwaUkladu: String,
        rodzina: RodzinaUkladu,
        rdzeniCPU: Int,
        rdzeniGPU: Int?,
        pamiecBajty: UInt64,
        wersjaMacOS: String,
        wersjaAplikacji: String
    ) {
        self.nazwaUkladu = nazwaUkladu
        self.rodzina = rodzina
        self.rdzeniCPU = rdzeniCPU
        self.rdzeniGPU = rdzeniGPU
        self.pamiecBajty = pamiecBajty
        self.wersjaMacOS = wersjaMacOS
        self.wersjaAplikacji = wersjaAplikacji
    }

    public var pamiecGB: Double {
        Double(pamiecBajty) / 1_073_741_824
    }

    /// Jedna linia do logu. Ma się czytać w zgłoszeniu na GitHubie bez
    /// tłumaczenia, co znaczy które pole.
    public var linijkaLogu: String {
        let rdzenieGPU = rdzeniGPU.map(String.init) ?? "nieznane"
        return "sprzęt: \(nazwaUkladu) | CPU \(rdzeniCPU) rdz. | GPU \(rdzenieGPU) rdz. "
            + "| pamięć \(String(format: "%.0f", pamiecGB)) GB | macOS \(wersjaMacOS) "
            + "| LlamaScope \(wersjaAplikacji)"
    }
}

/// Odczyt profilu z żyjącego systemu. Wydzielone z `ProfilSprzetu`, żeby samą
/// strukturę dało się składać w testach bez dotykania `sysctl`.
public enum CzytnikProfilu {
    public static func odczytaj(wersjaAplikacji: String) -> ProfilSprzetu {
        let nazwa = sysctlTekst("machdep.cpu.brand_string") ?? "nieznany"
        return ProfilSprzetu(
            nazwaUkladu: nazwa,
            rodzina: .zTekstu(nazwa),
            rdzeniCPU: Int(sysctlLiczba("hw.ncpu") ?? 0),
            rdzeniGPU: OdczytGPU.liczbaRdzeni(),
            pamiecBajty: sysctlLiczba("hw.memsize") ?? 0,
            wersjaMacOS: ProcessInfo.processInfo.operatingSystemVersionString,
            wersjaAplikacji: wersjaAplikacji
        )
    }

    static func sysctlTekst(_ nazwa: String) -> String? {
        var rozmiar = 0
        guard sysctlbyname(nazwa, nil, &rozmiar, nil, 0) == 0, rozmiar > 0 else { return nil }
        var bufor = [CChar](repeating: 0, count: rozmiar)
        guard sysctlbyname(nazwa, &bufor, &rozmiar, nil, 0) == 0 else { return nil }
        return String(cString: bufor)
    }

    static func sysctlLiczba(_ nazwa: String) -> UInt64? {
        var wartosc: UInt64 = 0
        var rozmiar = MemoryLayout<UInt64>.size
        guard sysctlbyname(nazwa, &wartosc, &rozmiar, nil, 0) == 0 else { return nil }
        return wartosc
    }
}
