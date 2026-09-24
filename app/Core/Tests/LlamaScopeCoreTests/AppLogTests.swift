import XCTest
@testable import LlamaScopeCore

/// Log z §10 — rotacja, limit i to, że zapis nie ma prawa wywrócić aplikacji.
final class AppLogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("llamascope-log-test-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func log(maxBytes: Int = 1_000_000, keep: Int = 5) -> AppLog {
        AppLog(directory: directory, maxBytes: maxBytes, keep: keep,
               clock: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    private func contents(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func testWritingCreatesTheDirectoryItself() {
        log().write("pierwszy wiersz")
        XCTAssertTrue(contents(log().currentFile).contains("pierwszy wiersz"))
    }

    func testEveryLineCarriesTheTime() {
        log().write("cokolwiek")
        XCTAssertTrue(contents(log().currentFile).hasPrefix("2027-01-15"),
                      "wiersz bez czasu jest w zgłoszeniu bezużyteczny")
    }

    func testLinesAppendInOrder() {
        let writer = log()
        writer.write("pierwszy")
        writer.write("drugi")
        let lines = contents(writer.currentFile).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("pierwszy"))
        XCTAssertTrue(lines[1].contains("drugi"))
    }

    /// Twardy limit z §10. Narzędzie do pilnowania cudzej pamięci, które samo
    /// zapycha dysk, byłoby żartem z własnego przesłania.
    func testTheLogRotatesInsteadOfGrowing() {
        let writer = log(maxBytes: 200, keep: 3)
        for index in 1...40 {
            writer.write("wiersz numer \(index) z zapasem znaków na dobicie limitu")
        }

        let sizes = (0..<3).map { index -> Int in
            let attributes = try? FileManager.default.attributesOfItem(atPath: writer.file(index).path)
            return ((attributes?[.size] as? NSNumber)?.intValue) ?? 0
        }
        for (index, size) in sizes.enumerated() {
            XCTAssertLessThanOrEqual(size, 200 + 100, "plik \(index) przerósł limit")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.file(3).path),
                       "poza `keep` nie ma prawa zostać żaden plik")
        XCTAssertTrue(contents(writer.currentFile).contains("wiersz numer 40"),
                      "po rotacji w bieżącym pliku ma być to, co najnowsze")
    }

    /// Najstarsze wypada, najnowsze zostaje — a nie odwrotnie.
    func testRotationKeepsTheNewestAndDropsTheOldest() {
        let writer = log(maxBytes: 100, keep: 2)
        writer.write("najstarszy wiersz, który ma wypaść z logu po dwóch rotacjach")
        writer.write("środkowy wiersz")
        writer.write("najnowszy wiersz")

        XCTAssertTrue(contents(writer.file(0)).contains("najnowszy"))
        XCTAssertFalse(contents(writer.file(0)).contains("najstarszy"))
        XCTAssertFalse(contents(writer.file(2)).contains("najstarszy"),
                       "trzeci plik przy keep = 2 nie ma prawa istnieć")
    }

    /// Log jest narzędziem do zgłoszeń, a nie celem. Kiedy nie da się go
    /// zapisać, aplikacja ma dalej pokazywać stan Ollamy.
    func testFailedWriteDoesNotThrow() {
        let blocked = AppLog(directory: URL(fileURLWithPath: "/nie-ma-takiego-miejsca/llamascope"))
        blocked.write("to się nie uda i nie ma prawa nikogo przewrócić")
    }
}

/// Wiersze startowe — tabela z §10 co do pola.
final class StartupReportTests: XCTestCase {
    private func profile() -> HardwareProfile {
        HardwareProfile(
            chipName: "Apple M2 Pro", family: .apple(generation: 2, variant: .pro),
            cpuCores: 12, gpuCores: 19, memoryBytes: 34_359_738_368,
            macOSVersion: "Version 27.0", appVersion: "0.5"
        )
    }

    private var host: URL { URL(string: "http://127.0.0.1:11434")! }

    func testTheProfileLineCarriesEverythingAReportNeeds() {
        let text = StartupReport.lines(
            profile: profile(),
            gpu: .reading(percent: 0, serviceClass: "AGXAccelerator", key: "Device Utilization %"),
            logPath: "/opt/homebrew/var/log/ollama.log",
            ollamaHost: host
        ).joined(separator: "\n")

        XCTAssertTrue(text.contains("Apple M2 Pro"))
        XCTAssertTrue(text.contains("CPU 12"))
        XCTAssertTrue(text.contains("GPU 19"))
        XCTAssertTrue(text.contains("32 GB"))
        XCTAssertTrue(text.contains("Version 27.0"))
        XCTAssertTrue(text.contains("LlamaScope 0.5"))
        // Klasa GPU i klucz, z którego czytamy — bez nich pytanie otwarte
        // z §15 o M1, M3 i M4 nie zamknie się nigdy.
        XCTAssertTrue(text.contains("AGXAccelerator"))
        XCTAssertTrue(text.contains("Device Utilization %"))
        XCTAssertTrue(text.contains("/opt/homebrew/var/log/ollama.log"))
        XCTAssertTrue(text.contains("11434"))
    }

    /// Zerowy odczyt i brak odczytu nie mogą w zgłoszeniu wyglądać tak samo
    /// — to najstarsza zasada tego projektu, więc obowiązuje też w logu.
    func testAFailedGPUReadingIsNamedAsFailureNotAsZero() {
        let text = StartupReport.lines(
            profile: profile(),
            gpu: .classNotFound(searched: GPUReader.knownClasses),
            logPath: nil,
            ollamaHost: host
        ).joined(separator: "\n")

        XCTAssertTrue(text.contains("BRAK ODCZYTU"))
        XCTAssertTrue(text.contains("To nie jest zero obciążenia."))
    }

    /// „Nie znalazłem logu" i „nie widzę ucięć" to dwie różne diagnozy (§10).
    /// Pierwsza musi nieść listę przeszukanych miejsc, bo odpowiedź na nią
    /// brzmi „log jest gdzie indziej", a nie „aplikacja nie działa".
    func testAMissingOllamaLogSaysWhereWeLooked() {
        let text = StartupReport.lines(
            profile: profile(),
            gpu: .reading(percent: 3, serviceClass: "AGXAccelerator", key: "Device Utilization %"),
            logPath: nil,
            searchedPaths: ["/opt/homebrew/var/log/ollama.log", "/usr/local/var/log/ollama.log"],
            ollamaHost: host
        ).joined(separator: "\n")

        XCTAssertTrue(text.contains("NIE ZNALEZIONY"))
        XCTAssertTrue(text.contains("/usr/local/var/log/ollama.log"))
    }
}

/// Czyszczenie tekstu przed tym, jak użytkownik zdecyduje o wysyłce (§9).
final class DiagnosticsTextTests: XCTestCase {
    func testHomeDirectoryNamesAreRemoved() {
        let text = DiagnosticsText.anonymized(
            "log Ollamy: /Users/marcinnowak/.ollama/logs/server.log"
        )
        XCTAssertEqual(text, "log Ollamy: /Users/<użytkownik>/.ollama/logs/server.log")
        XCTAssertFalse(text.contains("marcinnowak"))
    }

    func testEveryOccurrenceIsReplacedNotJustTheFirst() {
        let text = DiagnosticsText.anonymized("/Users/ala/a.log oraz /Users/ala/b.log")
        XCTAssertFalse(text.contains("ala"))
    }

    func testLongLinesAreShortenedSoOneLineCannotFloodTheLog() {
        let line = String(repeating: "x", count: 900)
        let short = DiagnosticsText.shortened(line)
        XCTAssertTrue(short.hasSuffix("[przycięte]"))
        XCTAssertLessThan(short.count, 330)
    }

    func testShortLinesGoThroughUntouched() {
        XCTAssertEqual(DiagnosticsText.shortened("  krótka linia  "), "krótka linia")
    }
}
