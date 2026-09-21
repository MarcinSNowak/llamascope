import XCTest
@testable import LlamaScopeCore

final class GPUReaderTests: XCTestCase {
    /// Sedno decyzji z §10: żadna z awarii odczytu nie może dać się pomylić
    /// z zerowym obciążeniem. Test pilnuje tego na poziomie typu — gdyby ktoś
    /// kiedyś uprościł `GPUReading` do `Int?`, ten plik przestanie się budować.
    func testFailureYieldsNoPercent() {
        XCTAssertNil(GPUReading.classNotFound(searched: ["AGXAccelerator"]).percent)
        XCTAssertNil(GPUReading.statisticsNotFound(serviceClass: "AGXAccelerator").percent)
        XCTAssertNil(GPUReading.keyNotFound(serviceClass: "AGXAccelerator", available: []).percent)
        XCTAssertEqual(GPUReading.reading(percent: 0, serviceClass: "A", key: "B").percent, 0)
    }

    func testZeroUtilizationIsNotAFailure() {
        let idle = GPUReading.reading(percent: 0, serviceClass: "AGXAccelerator", key: "Device Utilization %")
        XCTAssertEqual(idle.percent, 0)
        XCTAssertFalse(idle.logLine.contains("BRAK ODCZYTU"))
    }

    func testEveryFailureIsMarkedInTheLog() {
        let failures: [GPUReading] = [
            .classNotFound(searched: GPUReader.knownClasses),
            .statisticsNotFound(serviceClass: "IOAccelerator"),
            .keyNotFound(serviceClass: "IOGPU", available: ["Inny Klucz"]),
        ]
        for failure in failures {
            XCTAssertTrue(failure.logLine.contains("BRAK ODCZYTU"), "nieoznaczona: \(failure)")
        }
    }

    /// Zgłoszenie z maszyny, której nie mamy, jest coś warte tylko wtedy, gdy
    /// niesie nazwy, których szukaliśmy, albo nazwy, które zastaliśmy.
    func testFailureLogCarriesNamesWorthReporting() {
        let classNotFound = GPUReading.classNotFound(searched: ["AGXAccelerator", "IOGPU"])
        XCTAssertTrue(classNotFound.logLine.contains("AGXAccelerator"))
        XCTAssertTrue(classNotFound.logLine.contains("IOGPU"))

        let keyNotFound = GPUReading.keyNotFound(serviceClass: "IOGPU", available: ["Nowa Nazwa %"])
        XCTAssertTrue(keyNotFound.logLine.contains("Nowa Nazwa %"))
    }

    func testSuccessfulReadingRecordsClassAndKey() {
        let reading = GPUReading.reading(percent: 84, serviceClass: "AGXAccelerator", key: "Device Utilization %")
        XCTAssertTrue(reading.logLine.contains("AGXAccelerator"))
        XCTAssertTrue(reading.logLine.contains("Device Utilization %"))
        XCTAssertTrue(reading.logLine.contains("84%"))
    }

    /// Na żywej maszynie. Nie sprawdzamy wartości — sprawdzamy, że odczyt
    /// kończy się rozstrzygnięciem i że wynik da się wpisać do logu.
    func testReadFromThisMachine() {
        let reading = GPUReader.utilization()
        print("GPU tej maszyny → \(reading.logLine)")
        if let percent = reading.percent {
            XCTAssertTrue((0...100).contains(percent), "procent poza zakresem: \(percent)")
        }
        XCTAssertFalse(reading.logLine.isEmpty)
    }
}
