import Foundation
import LlamaScopeText

/// Angielska wersja zdań o stanach.
///
/// Nie jest tłumaczeniem polskiej linijka w linijkę i nie ma być. Trzymają
/// się tej samej reguły z §7 — zdanie przed liczbą, a każdy zły stan kończy
/// się radą, którą da się wykonać — ale zdania, które po polsku brzmią
/// naturalnie z „Wysłałeś", po angielsku są krótsze i bezosobowe. Wspólne
/// ma być znaczenie i uczciwość, nie szyk wyrazów.
extension StateText {
    enum English {
        private static let n = Numbers(.english)

        static func sentence(_ state: AppState) -> String {
            switch state {
            case let .promptTruncated(truncation):
                return "You sent \(n.tokens(truncation.promptTokens)), the model read "
                    + "\(n.tokens(truncation.readTokens)). \(n.percent(truncation.lostShare)) was lost."
            case let .modelOutsideGPU(model, bytesOutside):
                return "\(n.gigabytes(bytesOutside)) of \(n.gigabytes(model.sizeBytes)) is running "
                    + "on the CPU — expect it to be several times slower (\(model.name))."
            case let .memoryRunningOut(grownGB):
                return "Swap has grown by \(n.decimal(grownGB)) GB since Ollama last held nothing. "
                    + "The model does not fit next to what you have open."
            case let .holdingMemoryIdle(model, releasesIn):
                let when = releasesIn.map { ", releasing in \(n.duration($0))" } ?? ""
                return "\(n.gigabytes(model.sizeBytes)) held, computing nothing\(when) (\(model.name))."
            case let .working(model):
                return "\(model.name) is working."
            case .asleep:
                return "Nothing is loaded. All quiet."
            case let .loadedActivityUnknown(model, reason):
                return "\(model.name) is in memory, but I cannot read the GPU, "
                    + "so I do not know whether it is computing. \(reason.reason(in: .english))"
            case let .ollamaNotResponding(reason):
                return "Ollama is not responding (\(reason)). Start it with: ollama serve"
            }
        }

        static func headline(_ state: AppState) -> String {
            switch state {
            case .promptTruncated: return "The prompt was cut off"
            case .modelOutsideGPU: return "The model does not fit in the GPU"
            case .memoryRunningOut: return "Memory is running out"
            case .holdingMemoryIdle: return "The model is holding memory"
            case .working: return "All good"
            case .asleep: return "Nothing is loaded"
            case .loadedActivityUnknown: return "I do not know whether it is computing"
            case .ollamaNotResponding: return "Ollama is not responding"
            }
        }

        static func howToFix(_ state: AppState) -> String? {
            switch state {
            case let .promptTruncated(truncation):
                return "This model has a window of \(n.tokens(truncation.limitTokens)). Either "
                    + "enlarge it when starting the model (num_ctx), or split what you send "
                    + "into pieces. The answer you just received had not seen most of your text."
            case let .modelOutsideGPU(model, _):
                return "Free some memory — close a few programs or unload other models — and "
                    + "load \(model.name) again. As long as part of it runs on the CPU, it "
                    + "will be several times slower."
            case .memoryRunningOut:
                return "Close what you are not using, or release the model. Swap is a disk "
                    + "pretending to be memory, and with a model loaded you notice it at once."
            case .loadedActivityUnknown:
                return "This is a gap in this application, not a fault in your machine. "
                    + "Report it together with the log — it says inside what I looked for."
            case .ollamaNotResponding:
                return "Start the server with: ollama serve"
            case .holdingMemoryIdle, .working, .asleep:
                return nil
            }
        }

        static func shortLabel(_ state: AppState) -> String {
            switch state {
            case .promptTruncated: return "cut off"
            case .modelOutsideGPU: return "off GPU"
            case .memoryRunningOut: return "memory"
            case .holdingMemoryIdle: return "idle"
            case .working: return "working"
            case .asleep: return "—"
            case .loadedActivityUnknown: return "?"
            case .ollamaNotResponding: return "none"
            }
        }
    }
}
