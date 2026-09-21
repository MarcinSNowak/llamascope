import Foundation
import LlamaScopeCore

// Szczebel 0.5 dopiero powstaje. Na razie program wypisuje to, co aplikacja
// zapisze do logu przy starcie — czyli profil sprzętu i rozstrzygnięcie
// odczytu GPU. To jest pierwsza rzecz, którą warto móc obejrzeć na cudzej
// maszynie, więc jest pierwszą, która działa.

let appVersion = "0.5-rozwojowa"

guard case .apple = HardwareProfileReader.read(appVersion: appVersion).family else {
    // §12: bez ścieżki zapasowej dla Intela. Czytelny komunikat zamiast
    // trybu, w którym połowa stanów nic nie znaczy.
    let profile = HardwareProfileReader.read(appVersion: appVersion)
    FileHandle.standardError.write(Data("""
        LlamaScope wymaga Maca z procesorem Apple (M1 albo nowszym).
        Wykryto: \(profile.chipName)

        Powód nie jest formalny: program mierzy pamięć zunifikowaną
        i obciążenie GPU Apple. Na Intelu połowa jego odczytów nie znaczy nic.

        """.utf8))
    exit(1)
}

let profile = HardwareProfileReader.read(appVersion: appVersion)
print(profile.logLine)
print(GPUReader.utilization().logLine)
