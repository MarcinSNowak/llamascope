import Foundation

/// Wariant układu w obrębie jednej generacji. Wariantów jest więcej niż nazw
/// generacji i różnią się liczbą rdzeni GPU, więc sama „M3" nie wystarcza,
/// żeby zrozumieć zgłoszenie od użytkownika.
public enum ChipVariant: String, Sendable, Equatable {
    case base
    case pro
    case max
    case ultra

    /// Nazwa z `machdep.cpu.brand_string`; układ podstawowy nie ma tam słowa.
    static func from(word: String) -> ChipVariant? {
        switch word.lowercased() {
        case "pro": return .pro
        case "max": return .max
        case "ultra": return .ultra
        default: return nil
        }
    }
}

/// Rodzina procesora Apple albo stwierdzenie, że to nie jest Apple Silicon.
///
/// Rozdzielenie `notAppleSilicon` od `unrecognized` jest celowe: pierwsze
/// znaczy, że aplikacja ma się nie uruchomić (§12 — bez ścieżki zapasowej dla
/// Intela), drugie znaczy, że wyszedł układ nowszy od nas i chcemy o tym
/// wiedzieć ze zgłoszenia, zamiast zgadywać.
public enum ChipFamily: Sendable, Equatable {
    case apple(generation: Int, variant: ChipVariant)
    case notAppleSilicon(name: String)
    case unrecognized(name: String)

    /// Rozbiera łańcuch z `machdep.cpu.brand_string`, na przykład „Apple M2 Pro".
    public static func from(brandString: String) -> ChipFamily {
        let name = brandString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.hasPrefix("Apple M") else {
            // Wszystko, co nie zaczyna się od „Apple M", jest dla nas Intelem:
            // „Intel(R) Core(TM) i7", cokolwiek zwróci Rosetta.
            return .notAppleSilicon(name: name)
        }

        let parts = name.split(separator: " ")
        guard parts.count >= 2, let generation = Int(parts[1].dropFirst()) else {
            return .unrecognized(name: name)
        }

        guard parts.count >= 3 else {
            return .apple(generation: generation, variant: .base)
        }

        guard let variant = ChipVariant.from(word: String(parts[2])) else {
            // Nowy wariant, o którym nie wiemy. Nie udajemy, że to podstawowy —
            // zgłoszenie ma nam powiedzieć, jak się nazywa.
            return .unrecognized(name: name)
        }

        return .apple(generation: generation, variant: variant)
    }

    public var isAppleSilicon: Bool {
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
public struct HardwareProfile: Sendable, Equatable {
    public let chipName: String
    public let family: ChipFamily
    public let cpuCores: Int
    public let gpuCores: Int?
    public let memoryBytes: UInt64
    public let macOSVersion: String
    public let appVersion: String

    public init(
        chipName: String,
        family: ChipFamily,
        cpuCores: Int,
        gpuCores: Int?,
        memoryBytes: UInt64,
        macOSVersion: String,
        appVersion: String
    ) {
        self.chipName = chipName
        self.family = family
        self.cpuCores = cpuCores
        self.gpuCores = gpuCores
        self.memoryBytes = memoryBytes
        self.macOSVersion = macOSVersion
        self.appVersion = appVersion
    }

    public var memoryGB: Double {
        Double(memoryBytes) / 1_073_741_824
    }

    /// Jedna linia do logu. Ma się czytać w zgłoszeniu na GitHubie bez
    /// tłumaczenia, co znaczy które pole. Treść zostaje po polsku, bo log
    /// czyta użytkownik — po angielsku są nazwy w kodzie, nie komunikaty.
    public var logLine: String {
        let cores = gpuCores.map(String.init) ?? "nieznane"
        return "sprzęt: \(chipName) | CPU \(cpuCores) rdz. | GPU \(cores) rdz. "
            + "| pamięć \(String(format: "%.0f", memoryGB)) GB | macOS \(macOSVersion) "
            + "| LlamaScope \(appVersion)"
    }
}

/// Odczyt profilu z żyjącego systemu. Wydzielone z `HardwareProfile`, żeby samą
/// strukturę dało się składać w testach bez dotykania `sysctl`.
public enum HardwareProfileReader {
    public static func read(appVersion: String) -> HardwareProfile {
        let name = sysctlString("machdep.cpu.brand_string") ?? "nieznany"
        return HardwareProfile(
            chipName: name,
            family: .from(brandString: name),
            cpuCores: Int(sysctlNumber("hw.ncpu") ?? 0),
            gpuCores: GPUReader.coreCount(),
            memoryBytes: sysctlNumber("hw.memsize") ?? 0,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: appVersion
        )
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func sysctlNumber(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
