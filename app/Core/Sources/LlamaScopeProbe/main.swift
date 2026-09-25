import Foundation
import LlamaScopeCore
import LlamaScopeText

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

// Z jednego miejsca, sprawdzanego przy wydaniu. Wpisany tu wprost numer
// przeżył trzy szczeble i kłamał w każdym wydruku sondy.
let appVersion = "\(LlamaScopeVersion.current) (sonda)"
// Ten sam wybór co w aplikacji i z tego samego miejsca: polski dla tego,
// kto ma polski w systemie, angielski dla wszystkich pozostałych.
let language = Language.preferred()
let profile = HardwareProfileReader.read(appVersion: appVersion)

guard case .apple = profile.family else {
    // §12: bez ścieżki zapasowej dla Intela. Czytelny komunikat zamiast
    // trybu, w którym połowa stanów nic nie znaczy.
    let complaint = language == .polish ? """
        LlamaScope wymaga Maca z procesorem Apple (M1 albo nowszym).
        Wykryto: \(profile.chipName)

        Powód nie jest formalny: program mierzy pamięć zunifikowaną
        i obciążenie GPU Apple. Na Intelu połowa jego odczytów nie znaczy nic.

        """ : """
        LlamaScope needs a Mac with an Apple processor (M1 or newer).
        Found: \(profile.chipName)

        The reason is not a formality: this program measures unified memory
        and Apple GPU load. On Intel half of its readings mean nothing.

        """
    FileHandle.standardError.write(Data(complaint.utf8))
    exit(1)
}

// Dokładnie te same wiersze, od których zaczyna się własny log aplikacji
// (§10) — jedno źródło, żeby zgłoszenie z sondy i zgłoszenie z aplikacji
// dawały się porównać bez tłumaczenia jednego na drugie.
let logPath = OllamaLogLocation.find()
for line in StartupReport.lines(
    profile: profile,
    gpu: GPUReader.utilization(),
    logPath: logPath,
    ollamaHost: OllamaClient.hostFromEnvironment()
) {
    print(line)
}

// Sonda **nie pisze** do pliku logu aplikacji. Narzędzie uruchamiane ręką
// do obejrzenia stanu nie ma prawa po cichu dopisywać się do materiału
// dowodowego zbieranego przez aplikację. To, co aplikacja by zapisała,
// sonda pokazuje na wyjściu błędów — osobnym strumieniem, żeby przekierowanie
// zwykłego wyjścia do pliku niczego nie zlepiło.
let monitor = Monitor(sources: .live(logPath: logPath, record: { line in
    FileHandle.standardError.write(Data("log: \(line)\n".utf8))
}))
let follow = CommandLine.arguments.contains("--sledz")

// Paczka diagnostyczna (§10) wypisana na wyjście, bez zapisywania pliku
// i bez otwierania czegokolwiek. Ten sam tekst, który składa aplikacja —
// więc dający się sprawdzić na żywej maszynie, zanim ktokolwiek kliknie
// przycisk w pasku menu. I ten sam powód, dla którego sonda w ogóle jest:
// przy zgłoszeniu z cudzego Maca da się o to poprosić jednym poleceniem.
if CommandLine.arguments.contains("--diagnostyka") {
    let collector = DiagnosticsCollector(
        sources: .live(appVersion: appVersion, logPath: logPath)
    )
    print(DiagnosticsReport.text(await collector.collect(state: await monitor.refresh())))
    exit(0)
}

print("")
print(StateText.detectionLimit(in: language))
print("")
if follow {
    var previous: String?
    while true {
        let state = await monitor.refresh()
        // Porównujemy **rodzaj** stanu, nie całe zdanie. Zdanie o modelu
        // bezczynnym zawiera odliczanie do zwolnienia pamięci, więc zmienia
        // się co sekundę — porównywane w całości zalewało wydruk i chowało
        // w nim te chwile, w których naprawdę coś się wydarzyło.
        let kind = StateText.shortLabel(state, in: language)
        if kind != previous {
            print("\(Date().formatted(date: .omitted, time: .standard))  \(StateText.sentence(state, in: language))")
            previous = kind
        }
        try? await Task.sleep(for: Monitor.defaultInterval)
    }
} else {
    print(StateText.sentence(await monitor.refresh(), in: language))
}
