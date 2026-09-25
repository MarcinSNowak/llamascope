import AppKit
import LlamaScopeCore
import LlamaScopeText
import SwiftUI

/// Stan okna diagnostyki (§10).
///
/// Kolejność kroków jest tu treścią, a nie szczegółem wykonania: **najpierw
/// tekst na ekranie, potem cokolwiek innego**. Nic w tej klasie nie zapisuje
/// pliku ani nie otwiera przeglądarki, dopóki człowiek nie naciśnie drugiego
/// przycisku — „zbierz diagnostykę", które po cichu coś zapisuje, byłoby
/// prośbą o zaufanie w ciemno, a §9 opiera się na czymś odwrotnym.
@MainActor
final class DiagnosticsStore: ObservableObject {
    /// Złożona paczka: tekst do pokazania i materiał, z którego powstał.
    /// Materiał zostaje, bo z niego składa się odnośnik do zgłoszenia —
    /// a ten niesie **same metadane** i nie wolno mu powstać z tekstu.
    struct Report {
        let input: DiagnosticsReport.Input
        let text: String
    }

    @Published private(set) var report: Report?
    @Published private(set) var collecting = false
    /// Gdzie plik wylądował. Ścieżka, a nie `Bool` — „zapisane" bez miejsca
    /// zmusza użytkownika do szukania.
    @Published private(set) var savedTo: URL?
    /// Czego nie udało się zrobić. Puste znaczy „nie próbowano albo poszło",
    /// i dlatego zerowane jest przy każdej próbie z osobna.
    @Published private(set) var problem: String?

    private let language: Language
    private let collector: DiagnosticsCollector
    /// Stan bieżący, podany jako źródło, a nie liczony tu od nowa. Paczka ma
    /// mówić o tej chwili, którą użytkownik ma na ekranie.
    private let currentState: @MainActor () -> AppState

    init(
        language: Language,
        collector: DiagnosticsCollector,
        currentState: @escaping @MainActor () -> AppState
    ) {
        self.language = language
        self.collector = collector
        self.currentState = currentState
    }

    func collect() async {
        await collect(state: currentState())
    }

    func collect(state: AppState) async {
        collecting = true
        savedTo = nil
        problem = nil
        defer { collecting = false }

        let input = await collector.collect(state: state)
        report = Report(input: input, text: DiagnosticsReport.text(input))
        AppLog.shared.write("złożono paczkę diagnostyczną")
    }

    /// Plik na pulpicie — droga z §10 o zerowym koszcie i bez pośredników.
    func saveToDesktop() {
        guard let report else { return }
        problem = nil

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let file = desktop.appendingPathComponent(
            DiagnosticsReport.fileName(at: report.input.generatedAt)
        )

        do {
            try report.text.write(to: file, atomically: true, encoding: .utf8)
            savedTo = file
            AppLog.shared.write("zapisano paczkę diagnostyczną na pulpicie")
        } catch {
            // Odmowa dostępu do pulpitu (TCC) wygląda stąd jak zwykły błąd
            // zapisu i **musi** być widoczna. Cicha porażka zostawiłaby
            // użytkownika z przekonaniem, że plik jest.
            problem = (error as NSError).localizedDescription
            AppLog.shared.write("nie udało się zapisać paczki: \(problem ?? "")")
        }
    }

    /// Otwiera pokazanie pliku w Finderze. Osobno od zapisu, bo Finder
    /// wyskakujący sam w trakcie czytania paczki zabrałby okno sprzed oczu.
    func revealInFinder() {
        guard let savedTo else { return }
        NSWorkspace.shared.activateFileViewerSelecting([savedTo])
    }

    func openIssue() {
        guard let report, let url = DiagnosticsReport.issueURL(report.input) else { return }
        NSWorkspace.shared.open(url)
    }

    func openMail() {
        guard let report, let url = DiagnosticsReport.mailtoURL(report.input) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyToPasteboard() {
        guard let report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.text, forType: .string)
    }
}
