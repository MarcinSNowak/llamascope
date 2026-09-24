import LlamaScopeCore
import LlamaScopeText
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
    @StateObject private var proxy: ProxyControl

    /// Język rozstrzygnięty **raz**, tutaj, i dalej podawany wprost.
    /// Polski dostaje ten, kto ma polski wśród języków systemu; każdy inny
    /// dostaje angielski. Przełącznika w panelu nie ma świadomie — narzędzie,
    /// które mieszka w pasku menu, ma mieć jedno ustawienie mniej.
    private let language: Language

    init() {
        // Profil maszyny idzie do logu **przed** pierwszym odczytem. Mamy
        // jedną maszynę, a pytania z §15 o M1, M3, M4 i warianty Pro/Max
        // zamkną wyłącznie zgłoszenia — a zgłoszenie bez tej linii kosztuje
        // dwie tury korespondencji, z których druga zwykle nie nadchodzi.
        let logPath = OllamaLogLocation.find()
        for line in StartupReport.lines(
            profile: HardwareProfileReader.read(appVersion: Self.version),
            gpu: GPUReader.utilization(),
            logPath: logPath,
            ollamaHost: OllamaClient.hostFromEnvironment()
        ) {
            AppLog.shared.write(line)
        }

        // Zmienna lokalna, nie `self.language`: `StateObject(wrappedValue:)`
        // bierze wyrażenie odroczone, a takie wyrażenie nie ma prawa sięgnąć
        // do pola struktury, która dopiero się składa.
        let language = Language.preferred()
        self.language = language

        let monitor = Monitor(sources: .live(logPath: logPath))
        monitor.start()
        _monitor = StateObject(wrappedValue: monitor)
        _proxy = StateObject(wrappedValue: ProxyControl(language: language))
    }

    /// Znak zapytania zamiast pustego miejsca: wersja, której nie umiemy
    /// odczytać, ma być widoczna w zgłoszeniu jako brak, a nie jako nic.
    static var version: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(monitor: monitor, proxy: proxy, language: language)
        } label: {
            MenuBarIcon(state: monitor.state, history: monitor.history)
        }
        // Okno, nie menu: panel z §7 ma słupki, wiersze liczb i przyciski,
        // a pozycja menu potrafi być tylko wierszem tekstu.
        .menuBarExtraStyle(.window)
    }
}
