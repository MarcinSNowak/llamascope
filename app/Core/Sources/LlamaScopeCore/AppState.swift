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
///
/// Sześć pierwszych to stany **Ollamy**. Dwa ostatnie to stany **naszej
/// wiedzy o niej** i nie są ozdobnikiem: oba powstały dlatego, że bez nich
/// awaria odczytu wyglądałaby jak spokój. To ta sama klasa kłamstwa, którą
/// tym narzędziem tropimy u innych, więc nie wolno jej popełnić u siebie.
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
    ///
    /// Bez tempa generowania i to jest świadome. Ollama zapisuje szybkość
    /// dopiero po **skończonej** odpowiedzi, więc każda liczba, którą mamy
    /// w trakcie pracy, opisuje poprzednią odpowiedź, a nie tę trwającą.
    /// Wstawiona tutaj wyglądałaby na bieżącą — czyli byłaby tym samym
    /// rodzajem kłamstwa co „truncated = 0" w cudzym logu. Tempo pokazuje
    /// panel, wprost podpisane jako ostatnia odpowiedź.
    case working(model: LoadedModel)
    /// 6. Uśpiona. Spokój, nie awaria odczytu.
    case asleep

    /// Stan nieprzewidziany w §5, wymuszony przez zasadę z §10: model jest
    /// załadowany, ale odczyt GPU się nie udał, więc nie wiemy, czy pracuje,
    /// czy stoi. Bez tego przypadku brak odczytu wyglądałby jak 0% i
    /// aplikacja twierdziłaby „trzyma pamięć bezczynnie” o modelu liczącym
    /// pełną parą. To dokładnie ta klasa kłamstwa, którą tym narzędziem
    /// tropimy u innych.
    case loadedActivityUnknown(model: LoadedModel, reason: GPUReading)

    /// Serwer nie odpowiada. Stan 6 („uśpiona") ma wyglądać na spokój, więc
    /// martwy albo niewystartowany serwer nie może go udawać — inaczej
    /// aplikacja uspokajałaby dokładnie wtedy, gdy nie ma czego uspokajać.
    case ollamaNotResponding(reason: String)
}

public struct StateInput: Sendable {
    public var now: Date
    public var ollama: OllamaStatus
    public var gpu: GPUReading
    public var swap: SwapAssessment
    public var log: OllamaLogState

    /// Rozstrzygnięcie „liczy czy stoi", podjęte **poza** tą funkcją, bo
    /// wymaga pamięci o poprzednich odczytach (`ActivityGate`). Domyślnie
    /// bierzemy sam próg z §5 — to znaczy tyle, że jednorazowy odczyt bez
    /// historii odpowiada tak jak przedtem.
    public var working: Bool

    public init(
        now: Date = Date(),
        ollama: OllamaStatus,
        gpu: GPUReading,
        swap: SwapAssessment = .noBaseline,
        log: OllamaLogState = OllamaLogState(),
        working: Bool? = nil
    ) {
        self.now = now
        self.ollama = ollama
        self.gpu = gpu
        self.swap = swap
        self.log = log
        self.working = working ?? gpu.percent.map(ActivityGate.busyOnItsOwn) ?? false
    }

    /// Wygoda dla testów i dla miejsc, w których serwer na pewno odpowiada.
    public init(
        now: Date = Date(),
        models: [LoadedModel],
        gpu: GPUReading,
        swap: SwapAssessment = .noBaseline,
        log: OllamaLogState = OllamaLogState(),
        working: Bool? = nil
    ) {
        self.init(
            now: now, ollama: .running(models: models), gpu: gpu,
            swap: swap, log: log, working: working
        )
    }

    var models: [LoadedModel] {
        if case let .running(models) = ollama { return models }
        return []
    }
}

public enum StateRecognizer {
    /// Jak długo ucięcie jest stanem bieżącym, a nie historią. Po tym czasie
    /// przestaje podnosić ikonę — zostaje w logu i w szczegółach. Bez tego
    /// jedno ucięcie z rana wisiałoby w pasku menu do wieczora i powtórzyłby
    /// się błąd, który przy stanie 3 zamienił wskaźnik w tapetę (§5).
    public static let truncationIsCurrentFor: TimeInterval = 5 * 60

    /// Powyżej tej wartości uznajemy, że GPU liczy. 5% zgodnie z §5.
    /// Próg mieszka w `ActivityGate`, bo tam jest też reguła gaszenia.
    public static let workingAbovePercent = ActivityGate.startsWorkingAbove

    public static func recognize(_ input: StateInput) -> AppState {
        // Przed wszystkim innym, bo gdy nie ma z kim rozmawiać, reszta
        // odczytów opisuje maszynę, a nie Ollamę. Tak samo ustawia to
        // wersja pythonowa.
        if case let .notResponding(reason) = input.ollama {
            return .ollamaNotResponding(reason: reason)
        }

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

        guard input.gpu.percent != nil else {
            return .loadedActivityUnknown(model: model, reason: input.gpu)
        }

        if input.working {
            return .working(model: model)
        }

        let releasesIn = model.expiresAt.map { $0.timeIntervalSince(input.now) }
        return .holdingMemoryIdle(model: model, releasesIn: releasesIn.flatMap { $0 > 0 ? $0 : nil })
    }
}

/// Powaga stanu — cztery szczeble, z których bierze się kolor ikony.
///
/// Mieszka w rdzeniu, a nie przy rysowaniu, z dwóch powodów. Po pierwsze
/// da się to sprawdzić testem: **żaden stan niepewności nie może wpaść do
/// tego samego worka co spokój**, a to jest reguła, nie kwestia gustu.
/// Po drugie sonda wiersza poleceń i pasek menu mają mieć to samo zdanie
/// o tym, co jest alarmem.
///
/// Kolor jest **drugim** kanałem, nie pierwszym. §7 zostaje w mocy: znaczenie
/// niesie kształt, bo pasek menu bywa monochromatyczny, tryb ciemny zmienia
/// kontrast, a część ludzi nie odróżnia czerwieni od zieleni. Barwa tylko
/// przyspiesza rozpoznanie temu, kto ją widzi.
public enum StateSeverity: Sendable, Equatable {
    /// Coś jest nie tak i wiemy co. Stany 1–3.
    case alarm
    /// Nie wiemy, co się dzieje. Dwa stany naszej niewiedzy.
    case unknown
    /// Model liczy.
    case busy
    /// Spokój: model czeka albo nic nie jest załadowane.
    case calm
}

public extension AppState {
    var severity: StateSeverity {
        switch self {
        case .promptTruncated, .modelOutsideGPU, .memoryRunningOut: return .alarm
        case .loadedActivityUnknown, .ollamaNotResponding: return .unknown
        case .working: return .busy
        case .holdingMemoryIdle, .asleep: return .calm
        }
    }
}
