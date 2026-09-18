// swift-tools-version: 5.9
import PackageDescription

// Szczebel 0.5 specyfikacji: natywna aplikacja w pasku menu, niepodpisana.
// Podział na bibliotekę i program wynika z §12 („rdzeń w jednym miejscu"):
// logika rozpoznawania stanów ma być testowalna bez uruchamiania interfejsu.
let package = Package(
    name: "LlamaScope",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LlamaScopeRdzen"),
        .executableTarget(name: "LlamaScope", dependencies: ["LlamaScopeRdzen"]),
        .testTarget(name: "LlamaScopeRdzenTesty", dependencies: ["LlamaScopeRdzen"]),
    ]
)
