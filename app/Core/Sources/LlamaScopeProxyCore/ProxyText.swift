import Foundation

/// Wszystko, co pośrednik mówi człowiekowi. Osobno od liczenia, bo zdania
/// są tu treścią produktu, nie ozdobą — i mają swoje testy.
///
/// Zasada ta sama co w aplikacji (§7): **zdanie przed liczbą**, a każde
/// ostrzeżenie kończy się radą, którą da się wykonać.
public enum ProxyText {
    /// Rada jest jedna i wykonalna, a jej treść zależy od tego, czym klient
    /// w ogóle może pokręcić. Przez `/v1` nie da się ustawić okna w żądaniu,
    /// więc rada „`options.num_ctx = …`" byłaby tam radą nie do wykonania.
    public static func advice(for report: RequestReport, modelMaximum: Int?) -> String {
        let proposed = nextPowerOfTwo(atLeast: report.estimateHigh)

        if let modelMaximum, proposed > modelMaximum {
            return "model potrafi najwyżej \(number(modelMaximum)) — "
                + "skróć prompt albo podziel zadanie"
        }
        if report.path.hasPrefix("/v1/") {
            return "przez /v1 nie ustawisz okna w żądaniu — "
                + "OLLAMA_CONTEXT_LENGTH=\(proposed) albo własny Modelfile"
        }
        if let modelMaximum {
            return "options.num_ctx = \(proposed)  (model potrafi \(number(modelMaximum)))"
        }
        return "options.num_ctx = \(proposed)"
    }

    /// Wiersze do wypisania. Pierwszy jest zawsze nagłówkiem żądania.
    public static func lines(for report: RequestReport, modelMaximum: Int? = nil) -> [String] {
        let window = report.window.map { number($0.tokens) } ?? "?"
        let estimate = number(report.estimatedTokens)
        let header = "\(report.path)  \(report.model)"

        switch report.assessment {
        case .truncated:
            var lines = [header]
            lines.append("prompt ~\(estimate) tok (\(report.characters / 1024) kB)   "
                + "okno \(window)   ← PRZEKROCZONE o co najmniej ~\(number(report.excessTokens ?? 0))")
            if let reported = report.reportedTokens {
                lines.append("Ollama przeliczyła \(number(reported)) tokenów promptu")
            }
            // Dwa różne czasowniki, bo to dwa różne zjawiska: przy rozmowie
            // nic nie zostało ucięte — część rozmowy po prostu nigdy nie
            // pojechała do modelu.
            let verb = report.visibleInOllamaLog ? "ucięte" : "wypadło z rozmowy"
            // Czasownik należy się tylko stratom. Dopisek w nawiasie mówi coś
            // dokładnie odwrotnego („instrukcja systemowa przeżywa"), więc
            // z przedrostkiem byłby zdaniem przeczącym samemu sobie.
            lines.append(contentsOf: shortened(report.lost).map {
                $0.hasPrefix("(") || $0.hasPrefix("…") ? "  \($0)" : "\(verb): \($0)"
            })
            if !report.visibleInOllamaLog {
                lines.append("w logu Ollamy nie ma o tym ani słowa — widzi to tylko pośrednik")
            }
            lines.append("rada: " + advice(for: report, modelMaximum: modelMaximum))
            return lines

        case .risk:
            return [
                header,
                "prompt \(report.estimateLow)–\(report.estimateHigh) tok, okno \(window)   "
                    + "← możliwe ucięcie (szacunek przecina granicę)",
                "rada: " + advice(for: report, modelMaximum: modelMaximum),
            ]

        case .close:
            return [header + "  prompt ~\(estimate) tok, okno \(window) — blisko granicy"]

        case .cache:
            return [header + "  ~\(estimate) tok, przeliczono "
                + "\(number(report.reportedTokens ?? 0)) — reszta z pamięci podręcznej"]

        case .fine:
            let calibration = report.calibrationSamples > 0
                ? ", kalibracja z \(report.calibrationSamples) próbek"
                : ""
            return [header + "  ~\(estimate) tok / okno \(window)\(calibration)"]
        }
    }

    /// Ile strat wypisujemy, zanim zaczniemy je liczyć zamiast wymieniać.
    ///
    /// Długa rozmowa gubi kilkadziesiąt wiadomości naraz i wypisanie ich
    /// wszystkich zasypuje jedyne zdanie, po które ktoś tu przyszedł — radę.
    /// Pełna lista zostaje w pliku obserwacji; na ekranie ma być czytelnie.
    static let shownVictims = 4

    static func shortened(_ lost: [String]) -> [String] {
        guard lost.count > shownVictims + 1 else { return lost }
        // Ostatnia pozycja bywa dopiskiem o instrukcji systemowej, a on niesie
        // treść, której nie wolno uciąć — dlatego zostaje na końcu.
        return lost.prefix(shownVictims)
            + ["…i jeszcze \(lost.count - shownVictims - 1)"]
            + [lost[lost.count - 1]]
    }

    /// Najbliższa potęga dwójki nie mniejsza niż szacunek — okna kontekstu
    /// ustawia się potęgami dwójki i taka rada da się wkleić bez liczenia.
    static func nextPowerOfTwo(atLeast value: Int) -> Int {
        var result = 1024
        while result < value { result *= 2 }
        return result
    }

    /// Spacja jako separator tysięcy, jak w całej aplikacji.
    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{00A0}"
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
