import LlamaScopeCore
import SwiftUI

/// Panel spod ikony. Układ z §7 i jego trzy reguły:
///
/// 1. **Zdanie przed liczbą** — nagłówek mówi, co się dzieje; liczby niżej
///    są uzasadnieniem, nie treścią.
/// 2. **Każdy zły stan ma przycisk albo radę.** Przycisk jest jeden, bo
///    jedną rzecz umiemy naprawić sami; do reszty zostaje uczciwa rada.
/// 3. **Nie zgaduj.** Czego nie wiemy, tego nie rysujemy.
///
/// Wszystkie zdania pochodzą z `StateText` w rdzeniu, żeby panel i sonda
/// wiersza poleceń nie mogły powiedzieć dwóch różnych rzeczy o tej samej
/// chwili.
struct StatusPanel: View {
    @ObservedObject var monitor: Monitor

    /// Potwierdzenie zwolnienia pamięci. §7: pytamy tylko wtedy, gdy GPU nie
    /// jest przy zerze, czyli gdy grozi przerwanie komuś generowania.
    @State private var confirmingRelease = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            details
            if let advice = StateText.howToFix(monitor.state) {
                Divider()
                Text(advice)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = monitor.lastActionProblem {
                Text("Nie udało się: \(problem)")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
            Divider()
            // Wymóg z §5, nie ozdoba: bez tego zdania obietnica „powiem Ci,
            // gdy model przestanie czytać" jest nieprawdziwa dla każdego,
            // kto prowadzi z modelem rozmowę.
            Text(StateText.detectionLimit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            bottomRow
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            MenuBarIcon(state: monitor.state, history: monitor.history)
            Text(StateText.headline(monitor.state))
                .font(.headline)
        }
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(StateText.sentence(monitor.state))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(monitor.models, id: \.name) { model in
                row(model.name, value: StateText.gigabytesText(model.sizeBytes)
                    + (model.bytesOutsideGPU == 0 ? ", w GPU" : ", częściowo poza GPU"))
            }

            if let percent = monitor.history.samples.last ?? nil {
                row("GPU", value: "\(percent)%")
            }

            // Trzecia liczba z logu (§5) — jedyna, którą widać, **zanim**
            // cokolwiek się utnie. Dlatego stoi w panelu na stałe, a nie
            // tylko wtedy, gdy jest źle.
            if let prompt = monitor.lastPrompt {
                row("Okno kontekstu", value: StateText.windowFill(prompt))
            }
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    @ViewBuilder
    private var actions: some View {
        if let model = monitor.models.first {
            if confirmingRelease {
                // Model teraz liczy. Pytamy raz i mówimy wprost, co się
                // stanie — bo przerwane generowanie wygląda jak awaria.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model teraz liczy. Zwolnienie przerwie to, co robi.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Zwolnij mimo to") { release(model.name) }
                        Button("Anuluj") { confirmingRelease = false }
                    }
                }
            } else {
                Button("Zwolnij teraz") {
                    if isBusy {
                        confirmingRelease = true
                    } else {
                        release(model.name)
                    }
                }
            }
        } else if let name = monitor.lastUnloaded {
            // Wyłącznie jako cofnięcie poprzedniego kliknięcia (§7). Listy
            // modeli do wyboru tu nie ma i nie będzie — w tej chwili
            // przestalibyśmy być wskaźnikiem, a zaczęli być menedżerem.
            Button("Załaduj ponownie \(name)") {
                Task { await monitor.loadAgain() }
            }
        }
    }

    private var bottomRow: some View {
        HStack {
            if let refresh = monitor.lastRefresh {
                Text("odczyt \(refresh.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private var isBusy: Bool {
        if case .working = monitor.state { return true }
        return false
    }

    private func release(_ name: String) {
        confirmingRelease = false
        Task { await monitor.releaseNow(model: name) }
    }
}
