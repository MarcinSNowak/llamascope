import Foundation
import LlamaScopeCore

// Sonda bez interfejsu: to samo rozpoznawanie stanów, które trafi do paska
// menu, tylko wypisane do terminala. Zostaje w repozytorium na stałe, bo
// przy zgłoszeniu z cudzej maszyny to jest pierwsza rzecz, o którą warto
// poprosić — działa bez podpisanej aplikacji i bez zgody na cokolwiek.
//
//     swift run LlamaScope            jedno przejście
//     swift run LlamaScope --sledz    co sekundę, do Ctrl-C

// Wyjście linia po linii także wtedy, gdy ktoś przekieruje je do pliku.
// Bez tego `swift run LlamaScope --sledz > sonda.txt` zbiera wszystko
// w buforze i plik jest pusty dokładnie wtedy, gdy się do niego zagląda.
setvbuf(stdout, nil, _IOLBF, 0)

let appVersion = "0.5-rozwojowa"
let profile = HardwareProfileReader.read(appVersion: appVersion)

guard case .apple = profile.family else {
    // §12: bez ścieżki zapasowej dla Intela. Czytelny komunikat zamiast
    // trybu, w którym połowa stanów nic nie znaczy.
    FileHandle.standardError.write(Data("""
        LlamaScope wymaga Maca z procesorem Apple (M1 albo nowszym).
        Wykryto: \(profile.chipName)

        Powód nie jest formalny: program mierzy pamięć zunifikowaną
        i obciążenie GPU Apple. Na Intelu połowa jego odczytów nie znaczy nic.

        """.utf8))
    exit(1)
}

print(profile.logLine)
print(GPUReader.utilization().logLine)

switch OllamaLogLocation.find() {
case let .some(path): print("log Ollamy: \(path)")
case .none:
    // Nie to samo co „nie widzę ucięć" i musi się różnić w zgłoszeniu (§10).
    print("log Ollamy: NIE ZNALEZIONY — szukano w \(OllamaLogLocation.knownPaths.joined(separator: ", "))")
}

/// Jedno zdanie o stanie. Docelowo mieszka w interfejsie; tutaj jest po to,
/// żeby dało się przeczytać to samo rozpoznawanie bez uruchamiania aplikacji.
func describe(_ state: AppState) -> String {
    switch state {
    case let .promptTruncated(truncation):
        let percent = Int((truncation.lostShare * 100).rounded())
        return "PROMPT UCIĘTY — wysłane \(truncation.promptTokens) tokenów, "
            + "przeczytane \(truncation.readTokens). Przepadło \(percent)%."
    case let .modelOutsideGPU(model, bytes):
        let gb = Double(bytes) / 1e9
        return String(format: "POZA GPU — %@: %.1f GB liczy się na procesorze, będzie wolno.",
                      model.name, gb)
    case let .memoryRunningOut(grown):
        return String(format: "PAMIĘĆ — swapu przybyło %.1f GB, odkąd Ollama nic nie trzymała.", grown)
    case let .holdingMemoryIdle(model, releasesIn):
        let when = releasesIn.map { " Zwolni za \(Int($0 / 60)) min \(Int($0.truncatingRemainder(dividingBy: 60))) s." } ?? ""
        return String(format: "BEZCZYNNY — %@ trzyma %.1f GB i nic nie liczy.%@",
                      model.name, Double(model.sizeBytes) / 1e9, when)
    case let .working(model, generation):
        let speed = generation.map { String(format: " %.1f tok/s", $0.tokensPerSecond) } ?? ""
        return "PRACUJE — \(model.name)\(speed)"
    case .asleep:
        return "UŚPIONA — nic nie jest załadowane."
    case let .loadedActivityUnknown(model, reason):
        return "NIE WIEM — \(model.name) jest w pamięci, ale odczyt GPU się nie udał. \(reason.logLine)"
    case let .ollamaNotResponding(reason):
        return "OLLAMA NIE ODPOWIADA — \(reason)"
    }
}

let monitor = Monitor()
let follow = CommandLine.arguments.contains("--sledz")

print("")
if follow {
    var previous: String?
    while true {
        let line = describe(await monitor.refresh())
        // Wypisujemy przy zmianie, nie co sekundę — inaczej po minucie nie
        // da się odczytać, kiedy właściwie coś się wydarzyło.
        if line != previous {
            print("\(Date().formatted(date: .omitted, time: .standard))  \(line)")
            previous = line
        }
        try? await Task.sleep(for: Monitor.defaultInterval)
    }
} else {
    print(describe(await monitor.refresh()))
}
