import LlamaScopeCore
import SwiftUI

/// Ikona w pasku menu. §7: **ikona jest wykresem** — sparkline obciążenia
/// GPU z ostatnich dwóch minut, kilkanaście punktów w szesnastu pikselach.
/// Przy stanach alarmowych sparkline ustępuje znakowi ostrzegawczemu.
///
/// Znaczenie niesie **kształt, nie kolor**. Pasek menu bywa monochromatyczny,
/// tryb ciemny i jasny zmieniają kontrast, a część ludzi nie odróżnia
/// czerwieni od zieleni. Dlatego tu nie ma ani jednego `.foregroundColor`
/// z konkretną barwą — wszystko rysuje się kolorem paska.
struct MenuBarIcon: View {
    let state: AppState
    let history: GPUHistory

    /// Tyle słupków mieści się sensownie w pasku. Dwie minuty z §7 mamy
    /// w historii; tutaj pokazujemy jej ogon.
    static let barCount = 16

    var body: some View {
        switch state {
        case .promptTruncated, .modelOutsideGPU, .memoryRunningOut:
            // Trzy stany alarmowe — trójkąt, bo trójkąt znaczy „uwaga"
            // nawet na monochromatycznym pasku.
            Image(systemName: "exclamationmark.triangle.fill")
        case .loadedActivityUnknown:
            // Nie alarm i nie spokój: nie wiemy. Osobny kształt, bo gdyby
            // to był sparkline, narysowalibyśmy płaską linię, czyli spokój.
            Image(systemName: "questionmark.circle")
        case .ollamaNotResponding:
            // Nie ma z kim rozmawiać. Kształt przerwanego połączenia,
            // wyraźnie inny niż spokojny księżyc stanu uśpionego.
            Image(systemName: "bolt.horizontal.circle")
        case .asleep:
            Image(systemName: "moon")
        case .working, .holdingMemoryIdle:
            Sparkline(samples: history.recent(Self.barCount))
                .frame(width: 30, height: 14)
        }
    }
}

/// Słupki obciążenia. Najstarsze po lewej.
///
/// Brak odczytu (`nil`) **nie jest zerem** i nie wolno go narysować jako
/// zera. Odczyt zerowy zostawia widoczną kreskę przy podstawie; brak
/// odczytu nie zostawia nic. Pusta przerwa w wykresie jest informacją,
/// płaska kreska byłaby kłamstwem.
struct Sparkline: View {
    let samples: [Int?]

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }
            let slot = size.width / CGFloat(MenuBarIcon.barCount)
            let barWidth = max(1, slot * 0.6)
            // Wykres wyrównany do prawej: świeże próbki zawsze w tym samym
            // miejscu, także zanim uzbiera się pełne dwie minuty.
            let offset = size.width - CGFloat(samples.count) * slot

            for (index, sample) in samples.enumerated() {
                guard let sample else { continue }
                let x = offset + CGFloat(index) * slot
                // Zero też ma być widoczne — inaczej spokojna maszyna
                // wyglądałaby tak samo jak maszyna bez odczytu.
                let height = max(1, size.height * CGFloat(min(100, max(0, sample))) / 100)
                let bar = CGRect(x: x, y: size.height - height, width: barWidth, height: height)
                context.fill(Path(bar), with: .foreground)
            }
        }
    }
}
