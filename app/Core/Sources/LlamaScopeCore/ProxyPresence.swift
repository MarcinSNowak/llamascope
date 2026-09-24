import Foundation
import LlamaScopeText

/// Czy pośrednik (§12) jest, i skąd to wiemy.
///
/// Pięć odczytów, nie dwa. „Włączony/wyłączony" wystarczyłoby, gdyby
/// aplikacja była jedyną rzeczą, która może zająć ten port — a nie jest.
/// Pośrednik przeżyje ubicie aplikacji, można go też uruchomić ręcznie
/// z wiersza poleceń; do tego port bywa zajęty przez coś zupełnie obcego.
///
/// Napis „wyłączony" w sytuacji, w której coś na tym porcie słucha, byłby
/// dokładnie tym rodzajem spokojnego zera, przed którym to narzędzie ma
/// ostrzegać. Dlatego „nie wiem, co to jest" ma własny stan.
public enum ProxyPresence: Sendable, Equatable {
    /// Procesu nie ma i port jest wolny.
    case off
    case starting
    /// Nasz proces żyje i słucha.
    case listening(port: UInt16)
    /// Port zajęty, ale nie przez proces, który uruchomiliśmy.
    case foreign(port: UInt16)
    case failed(reason: String)

    public var isRunning: Bool {
        if case .listening = self { return true }
        return false
    }
}

public enum ProxyPresenceText {
    public static func headline(_ presence: ProxyPresence, in language: Language) -> String {
        switch (language, presence) {
        case (.polish, .off): return "Pośrednik wyłączony"
        case (.polish, .starting): return "Pośrednik startuje…"
        case let (.polish, .listening(port)): return "Pośrednik słucha na \(port)"
        case let (.polish, .foreign(port)): return "Port \(port) jest zajęty"
        case (.polish, .failed): return "Pośrednik nie wystartował"

        case (.english, .off): return "Proxy is off"
        case (.english, .starting): return "Proxy is starting…"
        case let (.english, .listening(port)): return "Proxy is listening on \(port)"
        case let (.english, .foreign(port)): return "Port \(port) is taken"
        case (.english, .failed): return "The proxy did not start"
        }
    }

    public static func sentence(_ presence: ProxyPresence, in language: Language) -> String {
        switch (language, presence) {
        // To zdanie jest sprawdzalne i o to w §12 chodzi. Wyłączony
        // pośrednik to nie gałąź `if` w programie, który i tak chodzi.
        case (.polish, .off):
            return "Tego procesu nie ma — zobaczysz to w Monitorze aktywności "
                + "albo przez `lsof -i`."
        case (.polish, .starting):
            return "Czekam, aż zajmie port."
        case let (.polish, .listening(port)):
            return "Ustaw w kliencie OLLAMA_HOST=http://127.0.0.1:\(port) "
                + "albo base_url http://127.0.0.1:\(port)/v1."
        case (.polish, .foreign):
            return "Słucha na nim proces, którego nie uruchomiłem. Nie napiszę "
                + "Ci, że pośrednik jest wyłączony, skoro nie wiem, co tam jest."

        case (.english, .off):
            return "That process does not exist — check for yourself in Activity "
                + "Monitor or with `lsof -i`."
        case (.english, .starting):
            return "Waiting for it to take the port."
        case let (.english, .listening(port)):
            return "Point your client at OLLAMA_HOST=http://127.0.0.1:\(port) "
                + "or base_url http://127.0.0.1:\(port)/v1."
        case (.english, .foreign):
            return "A process I did not start is listening on it. I am not going to "
                + "tell you the proxy is off when I do not know what is there."

        // Powód awarii przychodzi gotowy z miejsca, w którym awaria
        // nastąpiła, i jest już w języku interfejsu — inaczej trzeba by go
        // tu tłumaczyć z powrotem ze zdania na typ wyliczeniowy.
        case let (_, .failed(reason)):
            return reason
        }
    }

    /// Ostrzeżenie, które musi być widoczne zawsze, gdy pośrednik działa.
    ///
    /// Włączenie go zmienia to, co §9 obiecuje o całym narzędziu: tryb
    /// domyślny nie ma technicznej możliwości zobaczenia promptu, ten proces
    /// ma. Zmiana obietnicy nie może być schowana w dokumentacji — ani
    /// w jednym z dwóch języków.
    public static func seesPrompts(in language: Language) -> String {
        switch language {
        case .polish:
            return "Pośrednik widzi treści promptów — inaczej nie policzyłby, co przepadło. "
                + "Zapisuje z nich wyłącznie liczby i etykiety, nigdy treść, "
                + "i wyłącznie na tym dysku."
        case .english:
            return "The proxy sees the contents of your prompts — it could not count what "
                + "was lost otherwise. From them it records only numbers and labels, never "
                + "the text, and only on this disk."
        }
    }

    public static func howToFix(_ presence: ProxyPresence, in language: Language) -> String? {
        switch (language, presence) {
        case let (.polish, .foreign(port)):
            return "Sprawdź, kto go trzyma:\nlsof -nP -iTCP:\(port) -sTCP:LISTEN"
        case (.polish, .failed):
            return "Szczegóły są w ~/Library/Logs/LlamaScope/proxy.log"
        case let (.english, .foreign(port)):
            return "Find out who holds it:\nlsof -nP -iTCP:\(port) -sTCP:LISTEN"
        case (.english, .failed):
            return "Details are in ~/Library/Logs/LlamaScope/proxy.log"
        default:
            return nil
        }
    }
}
