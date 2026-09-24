import Foundation

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
    public static func headline(_ presence: ProxyPresence) -> String {
        switch presence {
        case .off: return "Pośrednik wyłączony"
        case .starting: return "Pośrednik startuje…"
        case let .listening(port): return "Pośrednik słucha na \(port)"
        case let .foreign(port): return "Port \(port) jest zajęty"
        case .failed: return "Pośrednik nie wystartował"
        }
    }

    public static func sentence(_ presence: ProxyPresence) -> String {
        switch presence {
        case .off:
            // To zdanie jest sprawdzalne i o to w §12 chodzi. Wyłączony
            // pośrednik to nie gałąź `if` w programie, który i tak chodzi.
            return "Tego procesu nie ma — zobaczysz to w Monitorze aktywności "
                + "albo przez `lsof -i`."
        case .starting:
            return "Czekam, aż zajmie port."
        case let .listening(port):
            return "Ustaw w kliencie OLLAMA_HOST=http://127.0.0.1:\(port) "
                + "albo base_url http://127.0.0.1:\(port)/v1."
        case .foreign:
            return "Słucha na nim proces, którego nie uruchomiłem. Nie napiszę "
                + "Ci, że pośrednik jest wyłączony, skoro nie wiem, co tam jest."
        case let .failed(reason):
            return reason
        }
    }

    /// Ostrzeżenie, które musi być widoczne zawsze, gdy pośrednik działa.
    ///
    /// Włączenie go zmienia to, co §9 obiecuje o całym narzędziu: tryb
    /// domyślny nie ma technicznej możliwości zobaczenia promptu, ten proces
    /// ma. Zmiana obietnicy nie może być schowana w dokumentacji.
    public static let seesPrompts =
        "Pośrednik widzi treści promptów — inaczej nie policzyłby, co przepadło. "
        + "Zapisuje z nich wyłącznie liczby i etykiety, nigdy treść, "
        + "i wyłącznie na tym dysku."

    public static func howToFix(_ presence: ProxyPresence) -> String? {
        switch presence {
        case let .foreign(port):
            return "Sprawdź, kto go trzyma:\nlsof -nP -iTCP:\(port) -sTCP:LISTEN"
        case .failed:
            return "Szczegóły są w ~/Library/Logs/LlamaScope/proxy.log"
        default:
            return nil
        }
    }
}
