import XCTest
@testable import LlamaScopeCore

/// Testy rozbierania nazwy układu chodzą na łańcuchach, a nie na maszynie,
/// bo maszynę mamy jedną. Łańcuchy dla M1, M3, M4 i wariantów Max oraz Ultra
/// są przepisane z tego, co `machdep.cpu.brand_string` zwraca u Apple.
final class ChipFamilyTests: XCTestCase {
    func testRecognizesOurMachine() {
        XCTAssertEqual(ChipFamily.from(brandString: "Apple M2 Pro"), .apple(generation: 2, variant: .pro))
    }

    func testRecognizesBaseChip() {
        XCTAssertEqual(ChipFamily.from(brandString: "Apple M1"), .apple(generation: 1, variant: .base))
        XCTAssertEqual(ChipFamily.from(brandString: "Apple M4"), .apple(generation: 4, variant: .base))
    }

    func testRecognizesHigherVariants() {
        XCTAssertEqual(ChipFamily.from(brandString: "Apple M3 Max"), .apple(generation: 3, variant: .max))
        XCTAssertEqual(ChipFamily.from(brandString: "Apple M1 Ultra"), .apple(generation: 1, variant: .ultra))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(ChipFamily.from(brandString: "  Apple M2 Pro\n"), .apple(generation: 2, variant: .pro))
    }

    func testIntelIsNotAppleSilicon() {
        let family = ChipFamily.from(brandString: "Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz")
        guard case .notAppleSilicon = family else {
            return XCTFail("Intel ma być rozpoznany jako nie-Apple Silicon, dostaliśmy \(family)")
        }
        XCTAssertFalse(family.isAppleSilicon)
    }

    /// Najważniejszy test w tym pliku. Nieznany wariant NIE może udawać
    /// podstawowego — inaczej pierwsze zgłoszenie z układu, którego jeszcze
    /// nie ma, powie nam, że wszystko jest w porządku.
    func testUnknownVariantDoesNotPassAsBase() {
        let family = ChipFamily.from(brandString: "Apple M5 Hiper")
        guard case let .unrecognized(name) = family else {
            return XCTFail("Nieznany wariant ma być nierozpoznany, dostaliśmy \(family)")
        }
        XCTAssertEqual(name, "Apple M5 Hiper")
    }

    func testNewGenerationIsRecognized() {
        XCTAssertEqual(ChipFamily.from(brandString: "Apple M9 Max"), .apple(generation: 9, variant: .max))
    }
}

final class HardwareProfileTests: XCTestCase {
    private let sample = HardwareProfile(
        chipName: "Apple M2 Pro",
        family: .apple(generation: 2, variant: .pro),
        cpuCores: 12,
        gpuCores: 19,
        memoryBytes: 34_359_738_368,
        macOSVersion: "Version 27.0",
        appVersion: "0.5"
    )

    func testConvertsMemoryToGigabytes() {
        XCTAssertEqual(sample.memoryGB, 32, accuracy: 0.001)
    }

    func testLogLineCarriesEveryAgreedField() {
        let line = sample.logLine
        for field in ["Apple M2 Pro", "CPU 12", "GPU 19", "32 GB", "27.0", "0.5"] {
            XCTAssertTrue(line.contains(field), "brakuje „\(field)” w: \(line)")
        }
    }

    /// Nieznana liczba rdzeni GPU ma być nazwana, a nie pokazana jako zero —
    /// z tego samego powodu co przy odczycie obciążenia.
    func testUnknownGPUCoresAreNamed() {
        let withoutCores = HardwareProfile(
            chipName: sample.chipName,
            family: sample.family,
            cpuCores: sample.cpuCores,
            gpuCores: nil,
            memoryBytes: sample.memoryBytes,
            macOSVersion: sample.macOSVersion,
            appVersion: sample.appVersion
        )
        XCTAssertTrue(withoutCores.logLine.contains("GPU nieznane"))
        XCTAssertFalse(withoutCores.logLine.contains("GPU 0"))
    }

    /// Test na żywej maszynie: cokolwiek tu wyjdzie, ma być zapisywalne.
    /// Na naszej (M2 Pro) sprawdza dodatkowo, że rozbiór nazwy działa
    /// na prawdziwym `sysctl`, a nie tylko na przepisanych łańcuchach.
    func testReadFromThisMachine() {
        let profile = HardwareProfileReader.read(appVersion: "0.5-test")
        XCTAssertGreaterThan(profile.cpuCores, 0)
        XCTAssertGreaterThan(profile.memoryBytes, 0)
        XCTAssertFalse(profile.logLine.isEmpty)
        print("profil tej maszyny → \(profile.logLine)")
    }
}
