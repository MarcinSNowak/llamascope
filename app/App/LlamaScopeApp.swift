import LlamaScopeCore
import SwiftUI

/// Aplikacja w pasku menu — na razie szkielet.
///
/// Interfejs właściwy (ikony dla ośmiu stanów, szczegóły, „Zwolnij teraz")
/// jest osobnym krokiem. Tutaj jest dokładnie tyle, ile trzeba, żeby
/// sprawdzić, że pakiet .app powstaje, startuje **bez ikony w Docku**
/// i pokazuje ten sam stan, który wypisuje sonda wiersza poleceń. Gdyby
/// tego kroku nie było, projekt Xcode byłby pustą obietnicą zamiast czegoś,
/// co się uruchamia.
///
/// Zdania o stanach biorą się z `StateText` w rdzeniu, nie stąd — żeby
/// ikona i sonda nie mogły powiedzieć dwóch różnych rzeczy o tej samej
/// chwili.
@main
struct LlamaScopeApp: App {
    @StateObject private var monitor: Monitor

    init() {
        let monitor = Monitor()
        monitor.start()
        _monitor = StateObject(wrappedValue: monitor)
    }

    var body: some Scene {
        MenuBarExtra {
            Text(StateText.sentence(monitor.state))

            Divider()

            // Wymóg z §5, nie ozdoba: bez tego zdania obietnica narzędzia
            // jest nieprawdziwa dla każdego, kto prowadzi z modelem rozmowę.
            Text(StateText.detectionLimit)

            Divider()

            Button("Zakończ") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Text(StateText.shortLabel(monitor.state))
        }
        .menuBarExtraStyle(.menu)
    }
}
