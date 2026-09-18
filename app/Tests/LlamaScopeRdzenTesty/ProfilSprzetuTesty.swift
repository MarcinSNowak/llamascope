import XCTest
@testable import LlamaScopeRdzen

/// Testy rozbierania nazwy układu chodzą na łańcuchach, a nie na maszynie,
/// bo maszynę mamy jedną. Łańcuchy dla M1, M3, M4 i wariantów Max oraz Ultra
/// są przepisane z tego, co `machdep.cpu.brand_string` zwraca u Apple.
final class RodzinaUkladuTesty: XCTestCase {
    func testRozpoznajeNaszaMaszyne() {
        XCTAssertEqual(RodzinaUkladu.zTekstu("Apple M2 Pro"), .apple(generacja: 2, wariant: .pro))
    }

    func testRozpoznajeUkladPodstawowy() {
        XCTAssertEqual(RodzinaUkladu.zTekstu("Apple M1"), .apple(generacja: 1, wariant: .podstawowy))
        XCTAssertEqual(RodzinaUkladu.zTekstu("Apple M4"), .apple(generacja: 4, wariant: .podstawowy))
    }

    func testRozpoznajeWariantyWyzsze() {
        XCTAssertEqual(RodzinaUkladu.zTekstu("Apple M3 Max"), .apple(generacja: 3, wariant: .max))
        XCTAssertEqual(RodzinaUkladu.zTekstu("Apple M1 Ultra"), .apple(generacja: 1, wariant: .ultra))
    }

    func testZnosiBialeZnaki() {
        XCTAssertEqual(RodzinaUkladu.zTekstu("  Apple M2 Pro\n"), .apple(generacja: 2, wariant: .pro))
    }

    func testIntelToNieAppleSilicon() {
        let rodzina = RodzinaUkladu.zTekstu("Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz")
        guard case .nieAppleSilicon = rodzina else {
            return XCTFail("Intel ma być rozpoznany jako nie-Apple Silicon, dostaliśmy \(rodzina)")
        }
        XCTAssertFalse(rodzina.toAppleSilicon)
    }

    /// Najważniejszy test w tym pliku. Nieznany wariant NIE może udawać
    /// podstawowego — inaczej pierwsze zgłoszenie z układu, którego jeszcze
    /// nie ma, powie nam, że wszystko jest w porządku.
    func testNieznanyWariantNieUdajePodstawowego() {
        let rodzina = RodzinaUkladu.zTekstu("Apple M5 Hiper")
        guard case let .nierozpoznany(nazwa) = rodzina else {
            return XCTFail("Nieznany wariant ma być nierozpoznany, dostaliśmy \(rodzina)")
        }
        XCTAssertEqual(nazwa, "Apple M5 Hiper")
    }

    func testNowaGeneracjaJestRozpoznawana() {
        XCTAssertEqual(RodzinaUkladu.zTekstu("Apple M9 Max"), .apple(generacja: 9, wariant: .max))
    }
}

final class ProfilSprzetuTesty: XCTestCase {
    private let wzorzec = ProfilSprzetu(
        nazwaUkladu: "Apple M2 Pro",
        rodzina: .apple(generacja: 2, wariant: .pro),
        rdzeniCPU: 12,
        rdzeniGPU: 19,
        pamiecBajty: 34_359_738_368,
        wersjaMacOS: "Version 27.0",
        wersjaAplikacji: "0.5"
    )

    func testPrzeliczaPamiecNaGigabajty() {
        XCTAssertEqual(wzorzec.pamiecGB, 32, accuracy: 0.001)
    }

    func testLinijkaLoguNiesieWszystkieUstalonePola() {
        let linijka = wzorzec.linijkaLogu
        for pole in ["Apple M2 Pro", "CPU 12", "GPU 19", "32 GB", "27.0", "0.5"] {
            XCTAssertTrue(linijka.contains(pole), "brakuje „\(pole)” w: \(linijka)")
        }
    }

    /// Nieznana liczba rdzeni GPU ma być nazwana, a nie pokazana jako zero —
    /// z tego samego powodu co przy odczycie obciążenia.
    func testNieznaneRdzenieGPUSaNazwane() {
        let bezRdzeni = ProfilSprzetu(
            nazwaUkladu: wzorzec.nazwaUkladu,
            rodzina: wzorzec.rodzina,
            rdzeniCPU: wzorzec.rdzeniCPU,
            rdzeniGPU: nil,
            pamiecBajty: wzorzec.pamiecBajty,
            wersjaMacOS: wzorzec.wersjaMacOS,
            wersjaAplikacji: wzorzec.wersjaAplikacji
        )
        XCTAssertTrue(bezRdzeni.linijkaLogu.contains("GPU nieznane"))
        XCTAssertFalse(bezRdzeni.linijkaLogu.contains("GPU 0"))
    }

    /// Test na żywej maszynie: cokolwiek tu wyjdzie, ma być zapisywalne.
    /// Na naszej (M2 Pro) sprawdza dodatkowo, że rozbiór nazwy działa
    /// na prawdziwym `sysctl`, a nie tylko na przepisanych łańcuchach.
    func testOdczytZTejMaszyny() {
        let profil = CzytnikProfilu.odczytaj(wersjaAplikacji: "0.5-test")
        XCTAssertGreaterThan(profil.rdzeniCPU, 0)
        XCTAssertGreaterThan(profil.pamiecBajty, 0)
        XCTAssertFalse(profil.linijkaLogu.isEmpty)
        print("profil tej maszyny → \(profil.linijkaLogu)")
    }
}
