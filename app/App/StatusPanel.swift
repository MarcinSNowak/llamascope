import LlamaScopeCore
import LlamaScopeText
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
    @ObservedObject var proxy: ProxyControl
    @ObservedObject var diagnostics: DiagnosticsStore

    /// Rozstrzygnięty raz, przy starcie aplikacji, i podany tutaj wprost.
    /// Widok, który sam pyta system o język, nie da się obejrzeć w drugim
    /// języku inaczej niż przez przestawienie całego systemu.
    let language: Language

    /// Potwierdzenie zwolnienia pamięci. §7: pytamy tylko wtedy, gdy GPU nie
    /// jest przy zerze, czyli gdy grozi przerwanie komuś generowania.
    @State private var confirmingRelease = false

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            details
            if let advice = StateText.howToFix(monitor.state, in: language) {
                Divider()
                Text(advice)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = monitor.lastActionProblem {
                Text(PanelText.actionFailed(problem, in: language))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
            Divider()
            // Wymóg z §5, nie ozdoba: bez tego zdania obietnica „powiem Ci,
            // gdy model przestanie czytać" jest nieprawdziwa dla każdego,
            // kto prowadzi z modelem rozmowę.
            Text(StateText.detectionLimit(in: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            proxySection
            bottomRow
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            MenuBarIcon(state: monitor.state, history: monitor.history)
            Text(StateText.headline(monitor.state, in: language))
                .font(.headline)
                // Ten sam kolor co ikona. Nagłówek jest pierwszą rzeczą,
                // na którą pada wzrok po otwarciu panelu.
                .foregroundStyle(StateColor.of(monitor.state))
        }
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(StateText.sentence(monitor.state, in: language))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(monitor.models, id: \.name) { model in
                row(model.name, value: StateText.gigabytesText(model.sizeBytes, in: language)
                    + PanelText.whereItRuns(
                        outsideGPU: model.bytesOutsideGPU > 0, in: language
                    ))
            }

            if let percent = monitor.history.samples.last ?? nil {
                row("GPU", value: "\(percent)%")
            }

            // Trzecia liczba z logu (§5) — jedyna, którą widać, **zanim**
            // cokolwiek się utnie. Dlatego stoi w panelu na stałe, a nie
            // tylko wtedy, gdy jest źle.
            if let prompt = monitor.lastPrompt {
                row(PanelText.contextWindow(in: language), value: StateText.windowFill(prompt, in: language))
            }

            // Podpisane „ostatnia", bo tempo trwającej odpowiedzi nie
            // istnieje — Ollama zapisuje je dopiero na końcu.
            if let generation = monitor.lastGeneration {
                row(PanelText.lastAnswer(in: language), value: StateText.lastAnswer(generation, in: language))
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
                    Text(PanelText.releaseWillInterrupt(in: language))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(PanelText.releaseAnyway(in: language)) { release(model.name) }
                        Button(PanelText.cancel(in: language)) { confirmingRelease = false }
                    }
                }
            } else {
                Button(PanelText.releaseNow(in: language)) {
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
            Button(PanelText.loadAgain(name, in: language)) {
                Task { await monitor.loadAgain() }
            }
        }
    }

    /// Pośrednik (§12). Domyślnie wyłączony i tak ma zostać — to jest
    /// dodatek dla kogoś, kto ma konkretne podejrzenie, a nie druga połowa
    /// narzędzia. Dlatego siedzi na dole panelu, jednym wierszem.
    @ViewBuilder
    private var proxySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(ProxyPresenceText.headline(proxy.presence, in: language))
                    .font(.callout)
                Spacer(minLength: 12)
                Button(PanelText.turnProxy(on: !proxy.presence.isRunning, in: language)) {
                    proxy.toggle()
                }
                .disabled(isProxyStarting)
            }

            Text(ProxyPresenceText.sentence(proxy.presence, in: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Zdanie o tym, co pośrednik widzi, pokazuje się wtedy, kiedy
            // ma znaczenie: gdy proces działa. Włączenie go zmienia to, co
            // §9 obiecuje o całym narzędziu, i człowiek ma o tym przeczytać
            // w chwili, w której to się dzieje — nie w dokumentacji.
            if proxy.presence.isRunning {
                Text(ProxyPresenceText.seesPrompts(in: language))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let advice = ProxyPresenceText.howToFix(proxy.presence, in: language) {
                Text(advice)
                    .font(.caption)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isProxyStarting: Bool {
        if case .starting = proxy.presence { return true }
        return false
    }

    /// „Zbierz diagnostykę" (§10) stoi w jednym rzędzie z „Zakończ", a nie
    /// przy stanach wyżej, i to jest celowe: to nie jest czynność, którą się
    /// robi, gdy jest źle — to jest czynność, którą się robi, gdy się pisze
    /// zgłoszenie. Wyżej przeszkadzałaby wszystkim pozostałym razom.
    private var bottomRow: some View {
        HStack {
            Button(PanelText.collectDiagnostics(in: language)) { collectDiagnostics() }
                .font(.caption)
                .buttonStyle(.link)
                .disabled(diagnostics.collecting)

            Spacer()

            if let refresh = monitor.lastRefresh {
                Text(PanelText.lastRefresh(
                    refresh.formatted(date: .omitted, time: .standard), in: language
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(PanelText.quit(in: language)) { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private var isBusy: Bool {
        if case .working = monitor.state { return true }
        return false
    }

    /// Okno otwieramy **od razu**, a treść dochodzi do niego chwilę później.
    /// Odwrotna kolejność — poczekać na zebranie, potem pokazać — daje
    /// kliknięcie bez żadnej odpowiedzi przez dwie sekundy odpytywania
    /// serwera, czyli przycisk, który wygląda na zepsuty.
    private func collectDiagnostics() {
        // Aplikacja nie ma ikony w Docku (LSUIElement), więc nowe okno samo
        // z siebie nie wychodzi na wierzch ani nie dostaje klawiatury.
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: DiagnosticsWindow.id)
        Task { await diagnostics.collect() }
    }

    private func release(_ name: String) {
        confirmingRelease = false
        Task { await monitor.releaseNow(model: name) }
    }
}
