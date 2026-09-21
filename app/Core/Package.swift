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
        .executable(name: "LlamaScopeProbe", targets: ["LlamaScopeProbe"]),
    ],
    targets: [
        .target(name: "LlamaScopeCore"),
        // Sonda wiersza poleceń. Nazywa się inaczej niż aplikacja, bo
        // aplikacja jest celem projektu Xcode i to ona ma być „LlamaScope".
        .executableTarget(name: "LlamaScopeProbe", dependencies: ["LlamaScopeCore"]),
        .testTarget(name: "LlamaScopeCoreTests", dependencies: ["LlamaScopeCore"]),
    ]
)
