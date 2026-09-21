import Foundation

/// Model widziany przez `/api/ps`.
public struct LoadedModel: Sendable, Equatable {
    public let name: String
    public let sizeBytes: UInt64
    public let sizeVRAMBytes: UInt64
    public let contextTokens: Int?
    public let expiresAt: Date?

    public init(
        name: String, sizeBytes: UInt64, sizeVRAMBytes: UInt64,
        contextTokens: Int? = nil, expiresAt: Date? = nil
    ) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.sizeVRAMBytes = sizeVRAMBytes
        self.contextTokens = contextTokens
        self.expiresAt = expiresAt
    }

    /// Ile bajtów liczy się poza GPU. Zero z małym marginesem, bo
    /// `size_vram` bywa o ułamek procenta mniejsze przy pełnym załadowaniu.
    public var bytesOutsideGPU: UInt64 {
        sizeVRAMBytes >= UInt64(Double(sizeBytes) * 0.99) ? 0 : sizeBytes - min(sizeBytes, sizeVRAMBytes)
    }
}

/// Ocena swapu — gotowa, nie surowa liczba.
///
/// Trzy przypadki zamiast `Double`, bo §5 wymaga odróżnienia „nie urósł” od
/// „nie wiem, od czego urósł”. Gdy aplikacja wstała przy już załadowanym
/// modelu, punktu odniesienia nie ma i **nie ostrzegamy wcale** — zastany
/// stan maszyny to nie jest nasza sprawa.
public enum SwapAssessment: Sendable, Equatable {
    case noBaseline
    case steady
    case worsened(grownGB: Double)
}

/// Stany z §5 specyfikacji. Pierwszy pasujący decyduje o ikonie.
public enum AppState: Sendable, Equatable {
    /// 1. Prompt ucięty — jedyny stan czytany wprost z logu.
    case promptTruncated(InputTruncation)
    /// 2. Model liczy się częściowo poza GPU.
    case modelOutsideGPU(model: LoadedModel, bytesOutside: UInt64)
    /// 3. Pamięć się kończy — i to od naszego startu, nie od zawsze.
    case memoryRunningOut(grownGB: Double)
    /// 4. Trzyma pamięć bezczynnie.
    case holdingMemoryIdle(model: LoadedModel, releasesIn: TimeInterval?)
    /// 5. Pracuje.
    case working(model: LoadedModel, generation: EvalSpeed?)
    /// 6. Uśpiona. Spokój, nie awaria odczytu.
    case asleep

    /// Stan nieprzewidziany w §5, wymuszony przez zasadę z §10: model jest
    /// załadowany, ale odczyt GPU się nie udał, więc nie wiemy, czy pracuje,
    /// czy stoi. Bez tego przypadku brak odczytu wyglądałby jak 0% i
    /// aplikacja twierdziłaby „trzyma pamięć bezczynnie” o modelu liczącym
    /// pełną parą. To dokładnie ta klasa kłamstwa, którą tym narzędziem
    /// tropimy u innych.
    case loadedActivityUnknown(model: LoadedModel, reason: GPUReading)
}

public struct StateInput: Sendable {
    public var now: Date
    public var models: [LoadedModel]
    public var gpu: GPUReading
    public var swap: SwapAssessment
    public var log: OllamaLogState

    public init(
        now: Date = Date(),
        models: [LoadedModel],
        gpu: GPUReading,
        swap: SwapAssessment = .noBaseline,
        log: OllamaLogState = OllamaLogState()
    ) {
        self.now = now
        self.models = models
        self.gpu = gpu
        self.swap = swap
        self.log = log
    }
}

public enum StateRecognizer {
    /// Jak długo ucięcie jest stanem bieżącym, a nie historią. Po tym czasie
    /// przestaje podnosić ikonę — zostaje w logu i w szczegółach. Bez tego
    /// jedno ucięcie z rana wisiałoby w pasku menu do wieczora i powtórzyłby
    /// się błąd, który przy stanie 3 zamienił wskaźnik w tapetę (§5).
    public static let truncationIsCurrentFor: TimeInterval = 5 * 60

    /// Powyżej tej wartości uznajemy, że GPU liczy. 5% zgodnie z §5.
    public static let workingAbovePercent = 5

    public static func recognize(_ input: StateInput) -> AppState {
        if let truncation = input.log.lastTruncation,
           input.now.timeIntervalSince(truncation.time) <= truncationIsCurrentFor,
           input.now >= truncation.time {
            return .promptTruncated(truncation)
        }

        // Najcięższy model poza GPU jest ważniejszy niż jakikolwiek — gdy
        // stoją dwa, użytkownika spowalnia ten większy.
        if let spilled = input.models
            .filter({ $0.bytesOutsideGPU > 0 })
            .max(by: { $0.bytesOutsideGPU < $1.bytesOutsideGPU }) {
            return .modelOutsideGPU(model: spilled, bytesOutside: spilled.bytesOutsideGPU)
        }

        if case let .worsened(grown) = input.swap {
            return .memoryRunningOut(grownGB: grown)
        }

        guard let model = input.models.first else {
            return .asleep
        }

        guard let percent = input.gpu.percent else {
            return .loadedActivityUnknown(model: model, reason: input.gpu)
        }

        if percent > workingAbovePercent {
            return .working(model: model, generation: input.log.lastGeneration)
        }

        let releasesIn = model.expiresAt.map { $0.timeIntervalSince(input.now) }
        return .holdingMemoryIdle(model: model, releasesIn: releasesIn.flatMap { $0 > 0 ? $0 : nil })
    }
}
