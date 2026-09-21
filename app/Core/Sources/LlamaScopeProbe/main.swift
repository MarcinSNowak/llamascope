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

let monitor = Monitor()
let follow = CommandLine.arguments.contains("--sledz")

print("")
print(StateText.detectionLimit)
print("")
if follow {
    var previous: String?
    while true {
        let line = StateText.sentence(await monitor.refresh())
        // Wypisujemy przy zmianie, nie co sekundę — inaczej po minucie nie
        // da się odczytać, kiedy właściwie coś się wydarzyło.
        if line != previous {
            print("\(Date().formatted(date: .omitted, time: .standard))  \(line)")
            previous = line
        }
        try? await Task.sleep(for: Monitor.defaultInterval)
    }
} else {
    print(StateText.sentence(await monitor.refresh()))
}
