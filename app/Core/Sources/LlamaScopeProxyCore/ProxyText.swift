import Foundation
import LlamaScopeText

/// Wszystko, co pośrednik mówi człowiekowi. Osobno od liczenia, bo zdania
/// są tu treścią produktu, nie ozdobą — i mają swoje testy.
///
/// Zasada ta sama co w aplikacji (§7): **zdanie przed liczbą**, a każde
/// ostrzeżenie kończy się radą, którą da się wykonać.
///
/// Język jest argumentem, tak samo jak w `StateText` i z tego samego
/// powodu: zdanie, które zmienia się w zależności od tego, co ktoś ustawił
/// wcześniej, nie da się sprawdzić testem.
public enum ProxyText {
    /// Rada jest jedna i wykonalna, a jej treść zależy od tego, czym klient
    /// w ogóle może pokręcić. Przez `/v1` nie da się ustawić okna w żądaniu,
    /// więc rada „`options.num_ctx = …`" byłaby tam radą nie do wykonania.
    public static func advice(
        for report: RequestReport, modelMaximum: Int?, in language: Language
    ) -> String {
        let n = Numbers(language)
        let proposed = nextPowerOfTwo(atLeast: report.estimateHigh)

        if let modelMaximum, proposed > modelMaximum {
            return language == .polish
                ? "model potrafi najwyżej \(n.count(modelMaximum)) — "
                    + "skróć prompt albo podziel zadanie"
                : "the model can do at most \(n.count(modelMaximum)) — "
                    + "shorten the prompt or split the task"
        }
        if report.path.hasPrefix("/v1/") {
            return language == .polish
                ? "przez /v1 nie ustawisz okna w żądaniu — "
                    + "OLLAMA_CONTEXT_LENGTH=\(proposed) albo własny Modelfile"
                : "you cannot set the window per request through /v1 — "
                    + "OLLAMA_CONTEXT_LENGTH=\(proposed) or your own Modelfile"
        }
        if let modelMaximum {
            let ceiling = language == .polish
                ? "(model potrafi \(n.count(modelMaximum)))"
                : "(the model can do \(n.count(modelMaximum)))"
            return "options.num_ctx = \(proposed)  \(ceiling)"
        }
        return "options.num_ctx = \(proposed)"
    }

    /// Wiersze do wypisania. Pierwszy jest zawsze nagłówkiem żądania.
    public static func lines(
        for report: RequestReport, modelMaximum: Int? = nil, in language: Language
    ) -> [String] {
        let w = Words(language)
        let n = Numbers(language)
        let window = report.window.map { n.count($0.tokens) } ?? "?"
        let estimate = n.count(report.estimatedTokens)
        let header = "\(report.path)  \(report.model)"

        switch report.assessment {
        case .truncated:
            var lines = [header]
            lines.append("\(w.prompt) ~\(estimate) \(w.tok) (\(report.characters / 1024) kB)   "
                + "\(w.window) \(window)   ← \(w.exceeded) ~\(n.count(report.excessTokens ?? 0))")
            if let reported = report.reportedTokens {
                lines.append(w.ollamaCounted(n.count(reported)))
            }
            // Dwa różne czasowniki, bo to dwa różne zjawiska: przy rozmowie
            // nic nie zostało ucięte — część rozmowy po prostu nigdy nie
            // pojechała do modelu.
            let verb = report.visibleInOllamaLog ? w.cutOff : w.fellOutOfConversation
            // Czasownik należy się tylko stratom. Dopisek w nawiasie mówi coś
            // dokładnie odwrotnego („instrukcja systemowa przeżywa"), więc
            // z przedrostkiem byłby zdaniem przeczącym samemu sobie.
            lines.append(contentsOf: shortened(report.lost, in: language).map {
                $0.hasPrefix("(") || $0.hasPrefix("…") ? "  \($0)" : "\(verb): \($0)"
            })
            if !report.visibleInOllamaLog {
                lines.append(w.notAWordInTheLog)
            }
            lines.append(w.advicePrefix + advice(
                for: report, modelMaximum: modelMaximum, in: language
            ))
            return lines

        case .risk:
            return [
                header,
                "\(w.prompt) \(report.estimateLow)–\(report.estimateHigh) \(w.tok), "
                    + "\(w.window) \(window)   ← \(w.possiblyTruncated)",
                w.advicePrefix + advice(for: report, modelMaximum: modelMaximum, in: language),
            ]

        case .close:
            return [header + "  \(w.prompt) ~\(estimate) \(w.tok), "
                + "\(w.window) \(window) — \(w.nearTheEdge)"]

        case .cache:
            return [header + "  ~\(estimate) \(w.tok), "
                + w.fromCache(n.count(report.reportedTokens ?? 0))]

        case .fine:
            let calibration = report.calibrationSamples > 0
                ? w.calibratedFrom(report.calibrationSamples)
                : ""
            return [header + "  ~\(estimate) \(w.tok) / \(w.window) \(window)\(calibration)"]
        }
    }

    /// Ile strat wypisujemy, zanim zaczniemy je liczyć zamiast wymieniać.
    ///
    /// Długa rozmowa gubi kilkadziesiąt wiadomości naraz i wypisanie ich
    /// wszystkich zasypuje jedyne zdanie, po które ktoś tu przyszedł — radę.
    /// Pełna lista zostaje w pliku obserwacji; na ekranie ma być czytelnie.
    static let shownVictims = 4

    static func shortened(_ lost: [String], in language: Language) -> [String] {
        guard lost.count > shownVictims + 1 else { return lost }
        let more = lost.count - shownVictims - 1
        // Ostatnia pozycja bywa dopiskiem o instrukcji systemowej, a on niesie
        // treść, której nie wolno uciąć — dlatego zostaje na końcu.
        return lost.prefix(shownVictims)
            + [language == .polish ? "…i jeszcze \(more)" : "…and \(more) more"]
            + [lost[lost.count - 1]]
    }

    /// Najbliższa potęga dwójki nie mniejsza niż szacunek — okna kontekstu
    /// ustawia się potęgami dwójki i taka rada da się wkleić bez liczenia.
    static func nextPowerOfTwo(atLeast value: Int) -> Int {
        var result = 1024
        while result < value { result *= 2 }
        return result
    }

    /// Słowa, z których składają się wiersze wyżej. Wydzielone, żeby układ
    /// wiersza był napisany raz — gdyby każdy język miał własną wersję
    /// całego `switch`, dwa układy rozjechałyby się przy pierwszej zmianie,
    /// a to są wiersze, które ktoś potem porównuje kolumnami.
    struct Words {
        let language: Language

        init(_ language: Language) { self.language = language }

        private func pick(_ polish: String, _ english: String) -> String {
            language == .polish ? polish : english
        }

        var prompt: String { pick("prompt", "prompt") }
        var tok: String { pick("tok", "tok") }
        var window: String { pick("okno", "window") }
        var exceeded: String { pick("PRZEKROCZONE o co najmniej", "EXCEEDED by at least") }
        var cutOff: String { pick("ucięte", "cut off") }
        var fellOutOfConversation: String {
            pick("wypadło z rozmowy", "fell out of the conversation")
        }
        var advicePrefix: String { pick("rada: ", "advice: ") }
        var possiblyTruncated: String {
            pick("możliwe ucięcie (szacunek przecina granicę)",
                 "truncation possible (the estimate straddles the limit)")
        }
        var nearTheEdge: String { pick("blisko granicy", "close to the limit") }
        var notAWordInTheLog: String {
            pick("w logu Ollamy nie ma o tym ani słowa — widzi to tylko pośrednik",
                 "the Ollama log says not a word about this — only the proxy sees it")
        }

        func ollamaCounted(_ tokens: String) -> String {
            pick("Ollama przeliczyła \(tokens) tokenów promptu",
                 "Ollama counted \(tokens) prompt tokens")
        }

        func fromCache(_ counted: String) -> String {
            pick("przeliczono \(counted) — reszta z pamięci podręcznej",
                 "\(counted) counted — the rest came from the cache")
        }

        func calibratedFrom(_ samples: Int) -> String {
            pick(", kalibracja z \(samples) próbek",
                 ", calibrated from \(samples) samples")
        }
    }
}
