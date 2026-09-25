import XCTest
@testable import LlamaScopeCore

/// Czytanie własnego logu z powrotem (§10).
///
/// Najważniejszy test w tym pliku nie dotyczy rozbioru linii, tylko tego, że
/// zapis i odczyt mówią o tej samej rzeczy: `Monitor` zapisuje linię
/// nierozpoznaną, a paczka diagnostyczna ma ją znaleźć. Rozjazd tych dwóch
/// napisów niczego by nie wywalił — dałby pustą sekcję w zgłoszeniu.
final class AppLogArchiveTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("llamascope-archive-test-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ name: String, _ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private var archive: AppLogArchive {
        AppLogArchive(log: AppLog(directory: directory, keep: 3))
    }

    func testReadsBackWhatTheLogWrote() {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let log = AppLog(directory: directory, keep: 3, clock: { moment })
        log.write("stan: Ollama nic nie trzyma")

        let entries = archive.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.message, "stan: Ollama nic nie trzyma")
        // Sekundowa dokładność stempla — porównujemy do sekundy.
        XCTAssertEqual(
            entries.first.map { AppLog.stamp.string(from: $0.time) },
            AppLog.stamp.string(from: moment)
        )
    }

    func testFilesComeBackOldestFirst() throws {
        try write("llamascope.2.log", "2026-09-25 08:00:00 najstarszy\n")
        try write("llamascope.1.log", "2026-09-25 09:00:00 średni\n")
        try write("llamascope.log", "2026-09-25 10:00:00 bieżący\n")

        XCTAssertEqual(archive.entries().map(\.message), ["najstarszy", "średni", "bieżący"])
    }

    /// Zacytowana linia cudzego logu może zawierać przełamanie wiersza.
    /// Wyrzucony dalszy ciąg zmieniłby treść linii, której nie zrozumieliśmy
    /// — a po to ona w logu jest.
    func testLineWithoutStampIsGluedToThePreviousOne() throws {
        try write("llamascope.log", "2026-09-25 08:00:00 pierwsza\ndalszy ciąg\n")

        let entries = archive.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.message, "pierwsza\ndalszy ciąg")
    }

    func testOnlyEntriesFromTheWindowSurvive() throws {
        try write("llamascope.log", """
        2026-09-25 08:00:00 dawno
        2026-09-25 10:30:00 przed chwilą

        """)
        let now = AppLog.stamp.date(from: "2026-09-25 10:45:00")!

        let recent = archive.entries().since(now.addingTimeInterval(-DiagnosticsReport.recentWindow))
        XCTAssertEqual(recent.map(\.message), ["przed chwilą"])
    }

    /// Ten test pilnuje umowy między `Monitor` a paczką. Gdyby przedrostek
    /// rozjechał się między zapisem a odczytem, sekcja „linie nierozpoznane”
    /// byłaby pusta — i wyglądałaby jak dobra wiadomość.
    @MainActor
    func testUnrecognizedLineWrittenByMonitorIsFoundByTheArchive() async {
        let log = AppLog(directory: directory, keep: 3)
        let monitor = Monitor(sources: MonitorSources(
            ollama: { .running(models: []) },
            gpu: { .reading(percent: 0, serviceClass: "AGXAccelerator", key: "Device Utilization %") },
            swap: { SwapUsage(usedGB: 0, freeGB: 8) },
            log: { [] },
            unparsedLog: { ["time=2026-09-25T08:00:00.000+02:00 level=INFO msg=\"coś nowego\""] },
            record: { log.write($0) }
        ))
        _ = await monitor.refresh()

        let found = archive.entries().unrecognized
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found.first?.message.contains("coś nowego") == true)
    }

    func testMissingFilesAreNotAnError() {
        XCTAssertTrue(archive.entries().isEmpty)
    }
}
