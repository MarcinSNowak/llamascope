import Foundation
import LlamaScopeText

/// Polska wersja zdań o stanach.
///
/// Osobny plik obok angielskiego, a nie dwa warianty wewnątrz każdego
/// `case`. Powód jest redakcyjny, nie techniczny: te zdania czyta się jak
/// tekst i poprawia jak tekst, a wymieszane po dwa na przemian przestają
/// być tekstem, którym mają być. Kompilator i tak pilnuje, żeby żadna
/// z dwóch wersji nie zgubiła stanu — oba `switch` są wyczerpujące.
extension StateText {
    enum Polish {
        private static let n = Numbers(.polish)

        static func sentence(_ state: AppState) -> String {
            switch state {
            case let .promptTruncated(truncation):
                return "Wysłałeś \(n.tokens(truncation.promptTokens)), model przeczytał "
                    + "\(n.tokens(truncation.readTokens)). Przepadło \(n.percent(truncation.lostShare))."
            case let .modelOutsideGPU(model, bytesOutside):
                return "\(n.gigabytes(bytesOutside)) z \(n.gigabytes(model.sizeBytes)) liczy się "
                    + "na procesorze — będzie kilka razy wolniej (\(model.name))."
            case let .memoryRunningOut(grownGB):
                return "Swapu przybyło \(n.decimal(grownGB)) GB, odkąd Ollama nic nie trzymała. "
                    + "Model nie mieści się obok tego, co masz otwarte."
            case let .holdingMemoryIdle(model, releasesIn):
                let when = releasesIn.map { ", zwolni za \(n.duration($0))" } ?? ""
                return "\(n.gigabytes(model.sizeBytes)) zajęte, nic nie liczy\(when) (\(model.name))."
            case let .working(model):
                return "\(model.name) pracuje."
            case .asleep:
                return "Nic nie jest załadowane. Spokój."
            case let .loadedActivityUnknown(model, reason):
                return "\(model.name) jest w pamięci, ale nie umiem odczytać GPU, "
                    + "więc nie wiem, czy liczy. \(reason.reason(in: .polish))"
            case let .ollamaNotResponding(reason):
                return "Ollama nie odpowiada (\(reason)). Uruchom: ollama serve"
            }
        }

        static func headline(_ state: AppState) -> String {
            switch state {
            case .promptTruncated: return "Prompt został ucięty"
            case .modelOutsideGPU: return "Model nie mieści się w GPU"
            case .memoryRunningOut: return "Pamięć się kończy"
            case .holdingMemoryIdle: return "Model trzyma pamięć"
            case .working: return "Wszystko gra"
            case .asleep: return "Nic nie jest załadowane"
            case .loadedActivityUnknown: return "Nie wiem, czy liczy"
            case .ollamaNotResponding: return "Ollama nie odpowiada"
            }
        }

        static func howToFix(_ state: AppState) -> String? {
            switch state {
            case let .promptTruncated(truncation):
                return "Okno tego modelu to \(n.tokens(truncation.limitTokens)). Albo powiększ "
                    + "je przy uruchamianiu modelu (num_ctx), albo podziel to, co wysyłasz, "
                    + "na kawałki. Sama odpowiedź, którą właśnie dostałeś, nie widziała "
                    + "większości Twojego tekstu."
            case let .modelOutsideGPU(model, _):
                return "Zwolnij pamięć — zamknij część programów albo wyłącz inne modele "
                    + "— i załaduj \(model.name) jeszcze raz. Dopóki część liczy się na "
                    + "procesorze, będzie kilka razy wolniej."
            case .memoryRunningOut:
                return "Zamknij, czego nie używasz, albo zwolnij model. Swap to dysk "
                    + "udający pamięć i przy modelu widać to natychmiast."
            case .loadedActivityUnknown:
                return "To jest luka w tej aplikacji, nie awaria Twojej maszyny. "
                    + "Zgłoś to razem z logiem — w środku jest napisane, czego szukałem."
            case .ollamaNotResponding:
                return "Uruchom serwer poleceniem: ollama serve"
            case .holdingMemoryIdle, .working, .asleep:
                return nil
            }
        }

        static func shortLabel(_ state: AppState) -> String {
            switch state {
            case .promptTruncated: return "ucięty"
            case .modelOutsideGPU: return "poza GPU"
            case .memoryRunningOut: return "pamięć"
            case .holdingMemoryIdle: return "bezczynny"
            case .working: return "pracuje"
            case .asleep: return "—"
            case .loadedActivityUnknown: return "?"
            case .ollamaNotResponding: return "brak"
            }
        }
    }
}
