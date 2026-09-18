import Foundation
import LlamaScopeRdzen

// Szczebel 0.5 dopiero powstaje. Na razie program wypisuje to, co aplikacja
// zapisze do logu przy starcie — czyli profil sprzętu i rozstrzygnięcie
// odczytu GPU. To jest pierwsza rzecz, którą warto móc obejrzeć na cudzej
// maszynie, więc jest pierwszą, która działa.

let wersja = "0.5-rozwojowa"

guard case .apple = CzytnikProfilu.odczytaj(wersjaAplikacji: wersja).rodzina else {
    // §12: bez ścieżki zapasowej dla Intela. Czytelny komunikat zamiast
    // trybu, w którym połowa stanów nic nie znaczy.
    let profil = CzytnikProfilu.odczytaj(wersjaAplikacji: wersja)
    FileHandle.standardError.write(Data("""
        LlamaScope wymaga Maca z procesorem Apple (M1 albo nowszym).
        Wykryto: \(profil.nazwaUkladu)

        Powód nie jest formalny: program mierzy pamięć zunifikowaną
        i obciążenie GPU Apple. Na Intelu połowa jego odczytów nie znaczy nic.

        """.utf8))
    exit(1)
}

let profil = CzytnikProfilu.odczytaj(wersjaAplikacji: wersja)
print(profil.linijkaLogu)
print(OdczytGPU.obciazenie().linijkaLogu)
