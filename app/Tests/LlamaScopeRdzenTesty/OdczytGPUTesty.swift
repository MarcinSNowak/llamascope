import XCTest
@testable import LlamaScopeRdzen

final class OdczytGPUTesty: XCTestCase {
    /// Sedno decyzji z §10: żadna z awarii odczytu nie może dać się pomylić
    /// z zerowym obciążeniem. Test pilnuje tego na poziomie typu — gdyby ktoś
    /// kiedyś uprościł `WynikGPU` do `Int?`, ten plik przestanie się budować.
    func testAwariaNieDajeProcentu() {
        XCTAssertNil(WynikGPU.brakKlasy(szukane: ["AGXAccelerator"]).procent)
        XCTAssertNil(WynikGPU.brakStatystyk(klasa: "AGXAccelerator").procent)
        XCTAssertNil(WynikGPU.brakKlucza(klasa: "AGXAccelerator", dostepne: []).procent)
        XCTAssertEqual(WynikGPU.odczyt(procent: 0, klasa: "A", klucz: "B").procent, 0)
    }

    func testZeroObciazeniaToNieAwaria() {
        let bezczynny = WynikGPU.odczyt(procent: 0, klasa: "AGXAccelerator", klucz: "Device Utilization %")
        XCTAssertEqual(bezczynny.procent, 0)
        XCTAssertFalse(bezczynny.linijkaLogu.contains("BRAK ODCZYTU"))
    }

    func testKazdaAwariaJestOznaczonaWLogu() {
        let awarie: [WynikGPU] = [
            .brakKlasy(szukane: OdczytGPU.znaneKlasy),
            .brakStatystyk(klasa: "IOAccelerator"),
            .brakKlucza(klasa: "IOGPU", dostepne: ["Inny Klucz"]),
        ]
        for awaria in awarie {
            XCTAssertTrue(awaria.linijkaLogu.contains("BRAK ODCZYTU"), "nieoznaczona: \(awaria)")
        }
    }

    /// Zgłoszenie z maszyny, której nie mamy, jest coś warte tylko wtedy, gdy
    /// niesie nazwy, których szukaliśmy, albo nazwy, które zastaliśmy.
    func testLogAwariiNiesieNazwyDoZgloszenia() {
        let brakKlasy = WynikGPU.brakKlasy(szukane: ["AGXAccelerator", "IOGPU"])
        XCTAssertTrue(brakKlasy.linijkaLogu.contains("AGXAccelerator"))
        XCTAssertTrue(brakKlasy.linijkaLogu.contains("IOGPU"))

        let brakKlucza = WynikGPU.brakKlucza(klasa: "IOGPU", dostepne: ["Nowa Nazwa %"])
        XCTAssertTrue(brakKlucza.linijkaLogu.contains("Nowa Nazwa %"))
    }

    func testUdanyOdczytZapisujeKlaseIKlucz() {
        let wynik = WynikGPU.odczyt(procent: 84, klasa: "AGXAccelerator", klucz: "Device Utilization %")
        XCTAssertTrue(wynik.linijkaLogu.contains("AGXAccelerator"))
        XCTAssertTrue(wynik.linijkaLogu.contains("Device Utilization %"))
        XCTAssertTrue(wynik.linijkaLogu.contains("84%"))
    }

    /// Na żywej maszynie. Nie sprawdzamy wartości — sprawdzamy, że odczyt
    /// kończy się rozstrzygnięciem i że wynik da się wpisać do logu.
    func testOdczytZTejMaszyny() {
        let wynik = OdczytGPU.obciazenie()
        print("GPU tej maszyny → \(wynik.linijkaLogu)")
        if let procent = wynik.procent {
            XCTAssertTrue((0...100).contains(procent), "procent poza zakresem: \(procent)")
        }
        XCTAssertFalse(wynik.linijkaLogu.isEmpty)
    }
}
