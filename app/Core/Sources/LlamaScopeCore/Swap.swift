import Foundation

/// Odczyt `sysctl vm.swapusage`.
///
/// Liczy się swap **użyty**, nie wolny — i to jest pomiar, nie preferencja.
/// macOS sam powiększa plik wymiany, więc gdy model 14B wchodził do pamięci,
/// wolne miejsce spadło z 1,4 do 1,1 GB, a użyte urosło z 13,6 do 17,9 GB
/// (2026-09-06). Reguła oparta na wolnym miejscu nie zadziałałaby nigdy.
public struct SwapUsage: Sendable, Equatable {
    public let usedGB: Double
    public let freeGB: Double

    public init(usedGB: Double, freeGB: Double) {
        self.usedGB = usedGB
        self.freeGB = freeGB
    }
}

public enum SwapReader {
    /// Czytane przez `sysctlbyname`, nie przez uruchamianie `sysctl`.
    /// Wersja pythonowa wołała proces co sekundę; aplikacja działa bez
    /// przerwy i nie ma powodu, żeby robić to samo.
    public static func read() -> SwapUsage? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        let gigabyte = 1024.0 * 1024.0 * 1024.0
        return SwapUsage(
            usedGB: Double(usage.xsu_used) / gigabyte,
            freeGB: Double(usage.xsu_avail) / gigabyte
        )
    }
}

/// Punkt odniesienia: ile swapu było zajęte, gdy Ollama nic nie trzymała.
public struct SwapBaseline: Sendable, Equatable, Codable {
    public let usedGB: Double
    public let recordedAt: Date
}

public protocol SwapBaselineStore: AnyObject {
    func load() -> SwapBaseline?
    func save(_ baseline: SwapBaseline)
}

/// Punkt odniesienia w pamięci. Wystarcza w testach i na czas jednego
/// uruchomienia aplikacji.
public final class InMemorySwapBaselineStore: SwapBaselineStore {
    private var baseline: SwapBaseline?
    public init(_ baseline: SwapBaseline? = nil) { self.baseline = baseline }
    public func load() -> SwapBaseline? { baseline }
    public func save(_ baseline: SwapBaseline) { self.baseline = baseline }
}

/// Punkt odniesienia na dysku, w katalogu aplikacji.
///
/// Rozstrzygnięcie otwartego pytania z 2026-09-18. Wersja pythonowa trzymała
/// go w `/tmp`, bo w pasku menu każde odświeżenie to osobny proces i nie ma
/// czego pamiętać między nimi. Aplikacja tego problemu nie ma — ale ma inny:
/// **po jej restarcie przy już załadowanym modelu punktu nie byłoby wcale,
/// a wtedy z §5 wynika milczenie.** Aktualizacja aplikacji w środku pracy
/// wyciszałaby więc ostrzeżenie do czasu, aż Ollama zwolni pamięć.
///
/// Dysk to naprawia, a godzinna ważność punktu pilnuje, żeby nie opisywał
/// maszyny sprzed pół dnia. `/tmp` odpada, bo trzymanie stanu aplikacji
/// w katalogu sprzątanym przez system to przypadek, nie decyzja.
public final class FileSwapBaselineStore: SwapBaselineStore {
    public static let defaultURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LlamaScope", isDirectory: true)
        .appendingPathComponent("swap-baseline.json")

    private let url: URL
    private var cached: SwapBaseline?

    public init(url: URL = defaultURL) {
        self.url = url
        cached = (try? Data(contentsOf: url)).flatMap {
            try? JSONDecoder().decode(SwapBaseline.self, from: $0)
        }
    }

    public func load() -> SwapBaseline? { cached }

    public func save(_ baseline: SwapBaseline) {
        cached = baseline
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? JSONEncoder().encode(baseline).write(to: url, options: .atomic)
    }
}

/// Ocena swapu według reguły z §5.
///
/// Próg bezwzględny się nie sprawdził: maszyna, która od rana siedzi na
/// swapie, trzymała ostrzeżenie zapalone na okrągło i zamieniła wskaźnik
/// w tapetę. Interesuje nas **pogorszenie, które sami spowodowaliśmy**.
public final class SwapWatcher {
    public static let thresholdGB = 1.0
    public static let baselineValidFor: TimeInterval = 3600

    private let store: SwapBaselineStore
    private let thresholdGB: Double
    private let validFor: TimeInterval

    public init(
        store: SwapBaselineStore,
        thresholdGB: Double = SwapWatcher.thresholdGB,
        validFor: TimeInterval = SwapWatcher.baselineValidFor
    ) {
        self.store = store
        self.thresholdGB = thresholdGB
        self.validFor = validFor
    }

    /// - Parameter anythingLoaded: czy Ollama cokolwiek trzyma. Gdy nie
    ///   trzyma, jesteśmy w chwili spokoju i wolno nam zapisać odniesienie.
    public func assess(usage: SwapUsage?, anythingLoaded: Bool, now: Date = Date()) -> SwapAssessment {
        guard let used = usage?.usedGB else { return .noBaseline }

        var baseline = store.load()
        if let current = baseline, now.timeIntervalSince(current.recordedAt) > validFor {
            baseline = nil
        }

        guard anythingLoaded else {
            // Punktem odniesienia jest **najniższy** stan zapamiętany podczas
            // spokoju, a nie ostatni. Przy ładowaniu modelu `/api/ps` bywa
            // jeszcze przez chwilę puste, gdy swap już rośnie; taki odczyt
            // wygląda jak spokój i podniósłby odniesienie, wyciszając
            // ostrzeżenie na dobre. Raz się to zdarzyło naprawdę.
            if baseline == nil || used <= baseline!.usedGB {
                store.save(SwapBaseline(usedGB: used, recordedAt: now))
            }
            return .steady
        }

        // Bez punktu odniesienia nie ostrzegamy wcale — nie wiemy, co
        // zastaliśmy, a zastany stan maszyny to nie jest nasza sprawa.
        guard let reference = baseline else { return .noBaseline }

        let grown = used - reference.usedGB
        return grown >= thresholdGB ? .worsened(grownGB: grown) : .steady
    }
}
