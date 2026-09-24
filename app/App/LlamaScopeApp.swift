import LlamaScopeCore
import SwiftUI

/// Aplikacja w pasku menu.
///
/// Wszystko, co mówi i liczy, siedzi w rdzeniu (`LlamaScopeCore`) i jest
/// sprawdzone testami. Tutaj zostaje samo rysowanie: ikona (`MenuBarIcon`)
/// i panel pod nią (`StatusPanel`). Ten podział jest celowy — §12 wymaga,
/// żeby rdzeń dało się sprawdzić bez uruchamiania interfejsu, a interfejs,
/// który sam z siebie coś wylicza, ten wymóg po cichu łamie.
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
            StatusPanel(monitor: monitor)
        } label: {
            MenuBarIcon(state: monitor.state, history: monitor.history)
        }
        // Okno, nie menu: panel z §7 ma słupki, wiersze liczb i przyciski,
        // a pozycja menu potrafi być tylko wierszem tekstu.
        .menuBarExtraStyle(.window)
    }
}
