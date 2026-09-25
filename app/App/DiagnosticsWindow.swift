import LlamaScopeCore
import LlamaScopeText
import SwiftUI

/// Okno paczki diagnostycznej (§10).
///
/// Układ ma jedną zasadę, z której wynika cała reszta: **tekst jest większy
/// od przycisków**. Okno, w którym plik jest paskiem na trzy linijki, a pod
/// nim stoi duży przycisk „wyślij", w praktyce nie jest oknem do czytania,
/// tylko do klikania — a §10 wymaga, żeby użytkownik przeczytał, co wysyła.
/// Dlatego przyciski wysyłki są niżej niż treść i nie są wyróżnione.
struct DiagnosticsWindow: View {
    /// Identyfikator sceny. W jednym miejscu, bo scena i przycisk, który ją
    /// otwiera, są w dwóch różnych plikach — a literówka w takim napisie
    /// kończy się przyciskiem, który po prostu nic nie robi.
    static let id = "diagnostics"

    @ObservedObject var store: DiagnosticsStore
    let language: Language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(PanelText.diagnosticsIntro(in: language))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            if let note = PanelText.diagnosticsIsPolish(in: language) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let report = store.report {
                // Do zaznaczenia i skopiowania w kawałkach. Kto chce wkleić
                // fragment, ma go wziąć stąd, a nie zgadywać z ekranu.
                ScrollView {
                    Text(report.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 280)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            } else if store.collecting {
                ProgressView(PanelText.collectingDiagnostics(in: language))
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                // To okno da się otworzyć **bez** zbierania: z menu „Okno”
                // i przy odtworzeniu układu okien po restarcie systemu.
                // Kręcące się wtedy „Składam…” byłoby napisem o pracy,
                // której nikt nie wykonuje — czyli dokładnie tą klasą
                // spokojnego kłamstwa, którą to narzędzie tropi u innych.
                // Sprawdzone: okno otwarte z menu naprawdę tak wyglądało.
                VStack(spacing: 12) {
                    Text(PanelText.nothingCollectedYet(in: language))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(PanelText.collectDiagnostics(in: language)) {
                        Task { await store.collect() }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            }

            Divider()
            delivery
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 520)
    }

    /// Trzy drogi z tabeli w §10 i ani jednej więcej. Własnego punktu
    /// odbiorczego tu nie ma i nie będzie — zbierając cudze logi u siebie
    /// stalibyśmy się administratorem danych osobowych i stracili jedyny
    /// mocny argument zaufania, jaki ta aplikacja ma.
    @ViewBuilder
    private var delivery: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(PanelText.saveToDesktop(in: language)) { store.saveToDesktop() }
                    .disabled(store.report == nil)
                Button(PanelText.copyText(in: language)) { store.copyToPasteboard() }
                    .disabled(store.report == nil)
                Spacer()
                Button(PanelText.close(in: language)) {
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
            }

            if let saved = store.savedTo {
                HStack(alignment: .firstTextBaseline) {
                    Text(PanelText.savedTo(saved.path, in: language))
                        .font(.caption)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(PanelText.revealInFinder(in: language)) { store.revealInFinder() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            if let problem = store.problem {
                Text(PanelText.actionFailed(problem, in: language))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(PanelText.issueCarriesMetadataOnly(in: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(PanelText.reportOnGitHub(in: language)) { store.openIssue() }
                    .disabled(store.report == nil)
                Button(PanelText.sendByMail(in: language)) { store.openMail() }
                    .disabled(store.report == nil)
            }

            Text(PanelText.noGitHubAccount(DiagnosticsReport.email, in: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
