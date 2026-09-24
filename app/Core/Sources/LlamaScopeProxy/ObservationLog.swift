import Foundation
import LlamaScopeCore
import LlamaScopeProxyCore

/// Zapis obserwacji — jedna linia JSON na żądanie.
///
/// **Tu nie ma ani jednego znaku cudzego promptu i mieć nie będzie.**
/// Pośrednik z natury widzi treści (§9 mówi o tym wprost i dlatego jest
/// osobnym procesem, który trzeba włączyć ręcznie), ale to, co zapisuje,
/// to wyłącznie liczby i etykiety: „wiadomość 7 (user) — cała". Plik można
/// komuś wysłać, nie czytając go wcześniej zdanie po zdaniu.
actor ObservationLog {
    private let file: URL?
    private let text: AppLog
    private let toTerminal: Bool

    init(file: URL?, text: AppLog, toTerminal: Bool) {
        self.file = file
        self.text = text
        self.toTerminal = toTerminal
    }

    /// Zdania dla człowieka — na ekran i do własnego logu pośrednika.
    func say(_ lines: [String], alarming: Bool = false) {
        for line in lines { text.write(line) }
        guard toTerminal else { return }
        let prefix = alarming ? "⚠︎ " : "   "
        FileHandle.standardOutput.write(Data((prefix + lines.joined(
            separator: "\n   "
        ) + "\n").utf8))
    }

    func record(_ report: RequestReport, modelMaximum: Int?) {
        say(ProxyText.lines(for: report, modelMaximum: modelMaximum),
            alarming: report.isAlarming)
        guard let file else { return }

        let entry = JSONValue.object([
            "time": .string(ISO8601DateFormatter().string(from: Date())),
            "path": .string(report.path),
            "model": .string(report.model),
            "characters": .number(Double(report.characters)),
            "estimated_tokens": .number(Double(report.estimatedTokens)),
            "estimate_low": .number(Double(report.estimateLow)),
            "estimate_high": .number(Double(report.estimateHigh)),
            "reported_tokens": report.reportedTokens.map { .number(Double($0)) } ?? .null,
            "window": report.window.map { .number(Double($0.tokens)) } ?? .null,
            "window_source": .string(report.window?.source.describedInPolish ?? "nieznane"),
            "calibration_samples": .number(Double(report.calibrationSamples)),
            "assessment": .string("\(report.assessment)"),
            "excess_tokens": report.excessTokens.map { .number(Double($0)) } ?? .null,
            // Sama liczba straconych tur, osobno od etykiet — to jest pomiar,
            // którego §15 potrzebuje do hipotezy o płaskowyżu.
            "lost_turns": .number(Double(report.lostTurns)),
            "lost": .array(report.lost.map { .string($0) }),
            "visible_in_ollama_log": .bool(report.visibleInOllamaLog),
        ])

        let line = Data((entry.compactJSON + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? line.write(to: file)
        }
    }
}
