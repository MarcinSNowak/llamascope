// swift-tools-version: 5.9
import PackageDescription

// Rdzeń szczebla 0.5 i sonda wiersza poleceń — wszystko, co da się sprawdzić
// przez `swift test`, bez Xcode i bez interfejsu. Tego wymaga §12
// („rdzeń w jednym miejscu"): logika rozpoznawania stanów ma być sprawdzalna
// bez uruchamiania paska menu.
//
// Sama aplikacja w pasku menu jest celem projektu Xcode piętro wyżej, bo
// pakietu SwiftPM nie da się zbudować do pakietu .app z Info.plist, a bez
// Info.plist z LSUIElement aplikacja ma ikonę w Docku i własny pasek u góry
// ekranu — czyli robi dokładnie to, czego to narzędzie ma nie robić.
//
// Zależność idzie w jedną stronę: projekt Xcode zna ten pakiet, pakiet nie
// wie o istnieniu projektu. Dlatego testy rdzenia chodzą tak samo w Xcode
// i w wierszu poleceń.
let package = Package(
    name: "LlamaScope",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LlamaScopeCore", targets: ["LlamaScopeCore"]),
        // Osobny produkt, żeby cel pośrednika w projekcie Xcode miał się
        // do czego podpiąć. Aplikacja go nie wymienia i wymieniać nie ma.
        .library(name: "LlamaScopeProxyCore", targets: ["LlamaScopeProxyCore"]),
        .executable(name: "LlamaScopeProbe", targets: ["LlamaScopeProbe"]),
        .executable(name: "LlamaScopeProxy", targets: ["LlamaScopeProxy"]),
    ],
    targets: [
        .target(name: "LlamaScopeCore"),
        // Sonda wiersza poleceń. Nazywa się inaczej niż aplikacja, bo
        // aplikacja jest celem projektu Xcode i to ona ma być „LlamaScope".
        .executableTarget(name: "LlamaScopeProbe", dependencies: ["LlamaScopeCore"]),

        // Pośrednik z §12 — osobny proces, więc i osobne cele. Rozbity na
        // dwa, bo to nie jest podział dla porządku:
        //
        // `LlamaScopeProxyCore` liczy i **nie umie gadać przez sieć**,
        // `LlamaScopeProxy` gada przez sieć i sam nic nie rozstrzyga.
        //
        // Aplikacji w pasku menu nie wolno linkować żadnego z nich. §9
        // obiecuje, że tryb domyślny nie ma technicznej możliwości
        // zobaczenia treści promptu — obietnica oparta na tym, że kodu do
        // czytania promptów nie ma w tym binarium, jest sprawdzalna
        // z zewnątrz; obietnica oparta na tym, że go nie wywołujemy,
        // wymaga wiary w nasz kod.
        .target(name: "LlamaScopeProxyCore"),
        // Strzałka do `LlamaScopeCore` idzie tylko w tę stronę — po rotujący
        // log z §10, żeby pośrednik nie miał drugiej implementacji tego
        // samego. Aplikacja nadal nie linkuje niczego stąd.
        .executableTarget(
            name: "LlamaScopeProxy", dependencies: ["LlamaScopeProxyCore", "LlamaScopeCore"]
        ),

        .testTarget(name: "LlamaScopeCoreTests", dependencies: ["LlamaScopeCore"]),
        .testTarget(name: "LlamaScopeProxyCoreTests", dependencies: ["LlamaScopeProxyCore"]),
    ]
)
