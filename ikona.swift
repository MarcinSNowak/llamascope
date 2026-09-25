#!/usr/bin/env swift

// Ikona pakietu. Rysowana kodem, a nie w programie graficznym, z tego
// samego powodu, dla którego reszta tego projektu jest rysowana kodem:
// żeby dało się ją odtworzyć, obejrzeć różnicę i poprawić bez pliku
// źródłowego, którego nikt poza autorem nie umie otworzyć.
//
// Co rysujemy i dlaczego akurat to. §7 mówi: **ikona jest wykresem**.
// W pasku menu znaczy to sparkline obciążenia GPU. W Finderze nie da się
// pokazać bieżącego odczytu — pakiet leży na dysku także wtedy, gdy nic
// nie działa — więc ikona pakietu pokazuje ten sam kształt zamrożony:
// słupki obciążenia na linii podstawy.
//
// Jedna próbka jest **pusta** i to nie jest ozdoba. Cały ten program
// powstał wokół zdania „brak odczytu nie jest zerem”; ikona, w której
// wykres byłby gładki i pełny, obiecywałaby coś przeciwnego. Przerwa jest
// widoczna, bo linia podstawy biegnie pod całym wykresem — zero zostawia
// nad nią krótki słupek, brak odczytu nie zostawia nic.
//
// Uruchomienie:
//     swift ikona.swift
// Zapisuje build/LlamaScope.iconset oraz app/App/Resources/LlamaScope.icns.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Barwy marki

/// Granat i limonka QSHMOBILE, te same wartości co w `global.css` strony.
/// Wpisane liczbami, bo skrypt nie ma skąd wziąć tokenów CSS-a, a ikona
/// w innym odcieniu zieleni niż strona wyglądałaby na cudzą.
private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

private let inkTop = color(0x22304f)     // --color-ink-800
private let inkBottom = color(0x0b1428)  // --color-ink-950
private let lime = color(0x78b843)       // --color-accent-500
private let limeBright = color(0x9bd06a) // --color-accent-400

// MARK: - Próbki

/// Zamrożony odczyt. Wartości w procentach, `nil` znaczy brak odczytu.
///
/// Najnowsza próbka jest po prawej — tak samo jak w pasku menu, żeby
/// człowiek, który zobaczy oba wykresy, czytał je w tę samą stronę.
private let samples: [Int?] = [34, 52, 41, 66, nil, 79, 70, 88, 61, 93, 74, 58]

/// Przy 16 i 32 pikselach dwanaście słupków zlewa się w plamę. Mniejsze
/// rozmiary dostają mniej słupków, a nie te same słupki pomniejszone —
/// ikona nieczytelna to ikona, która nic nie mówi, choć zajmuje miejsce.
/// Przerwa zostaje w każdym wariancie; to ona jest treścią.
private func samples(forPixelSize size: Int) -> [Int?] {
    switch size {
    case ..<24: return [66, nil, 79, 93, 58]
    case ..<96: return [41, 66, nil, 79, 88, 93, 58]
    default: return samples
    }
}

// MARK: - Kształt

/// Zaokrąglony kwadrat w proporcjach macOS. Nie `roundedRect` z promieniem,
/// tylko superelipsa — róg systemowej ikony nie jest wycinkiem okręgu
/// i różnicę widać obok innych ikon w Finderze.
///
/// Próbkujemy krzywą gęsto zamiast składać ją z łuków: przy 1024 pikselach
/// tysiąc odcinków jest poniżej progu widzialności, a kod zostaje krótki
/// i bez magicznych współczynników kontrolnych.
private func squircle(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 1024

    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t), sinT = sin(t)
        // Superelipsa w postaci parametrycznej. `sign * |cos|^(2/n)`
        // zachowuje ćwiartkę, w której leży punkt.
        let x = cx + a * copysign(pow(abs(cosT), 2 / exponent), cosT)
        let y = cy + b * copysign(pow(abs(sinT), 2 / exponent), sinT)
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

// MARK: - Rysowanie

/// Rysuje ikonę o boku `size` pikseli i zwraca bitmapę.
///
/// Każdy rozmiar rysujemy osobno, a nie skalujemy z jednego dużego:
/// pomniejszenie 1024 do 16 daje szarą papkę, bo słupek szerokości
/// ułamka piksela znika w uśrednianiu. Tutaj przy każdym rozmiarze
/// słupek ma co najmniej jeden pełny piksel.
private func drawIcon(size: Int) -> CGImage {
    let side = CGFloat(size)
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setShouldAntialias(true)

    // Pole ikony: klasyczna siatka macOS — 824 z 1024, czyli margines
    // 9,8% z każdej strony. Bez tego marginesu pakiet wygląda na większy
    // od sąsiadów w tym samym rzędzie Findera.
    let inset = side * 0.098
    let body = CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let shape = squircle(in: body)

    // Tło: pion od granatu jaśniejszego do ciemniejszego, jak ciemne pasy
    // strony. Gradient, a nie płaska barwa, bo płaska plama przy 512
    // pikselach wygląda na niedokończoną.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [inkTop, inkBottom] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.minY),
        options: []
    )
    context.restoreGState()

    // Wykres. Pole rysunku węższe niż pakiet, żeby słupki nie dotykały
    // krawędzi — róg superelipsy odcinałby skrajny słupek.
    let padding = body.width * 0.17
    let plot = body.insetBy(dx: padding, dy: padding)
    let values = samples(forPixelSize: size)
    let slot = plot.width / CGFloat(values.count)
    let barWidth = max(1, (slot * 0.62).rounded())
    let baselineHeight = max(1, (side * 0.012).rounded())
    let baselineY = plot.minY

    // Linia podstawy pod całą szerokością. To ona robi z przerwy przerwę:
    // bez niej brak odczytu byłby nieodróżnialny od marginesu.
    context.setFillColor(color(0x78b843, alpha: 0.35))
    context.fill(CGRect(x: plot.minX, y: baselineY, width: plot.width, height: baselineHeight))

    let plotHeight = plot.height - baselineHeight
    for (index, sample) in values.enumerated() {
        guard let sample else { continue }
        // Najnowsza próbka jaśniejsza — drugi kanał tej samej informacji
        // co pozycja. Kto ogląda ikonę w skali szarości, ma pozycję.
        context.setFillColor(index == values.count - 1 ? limeBright : lime)
        let x = (plot.minX + CGFloat(index) * slot + (slot - barWidth) / 2).rounded()
        // Zero też zostawia widoczny ślad — inaczej spokojna maszyna
        // wyglądałaby jak maszyna bez odczytu. Ta sama reguła co w pasku.
        let height = max(baselineHeight * 2, (plotHeight * CGFloat(sample) / 100).rounded())
        context.fill(CGRect(x: x, y: baselineY, width: barWidth, height: height))
    }

    return context.makeImage()!
}

// MARK: - Zapis

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let iconset = root.appendingPathComponent("build/LlamaScope.iconset")
private let icns = root.appendingPathComponent("app/App/Resources/LlamaScope.icns")

/// Komplet wymagany przez `iconutil`. Braki w tej liście nie są błędem
/// budowy — są ikoną, która w jednym widoku Findera wygląda dobrze,
/// a w innym rozmazanie.
private let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(
    at: icns.deletingLastPathComponent(), withIntermediateDirectories: true)

for variant in variants {
    let image = drawIcon(size: variant.pixels)
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: variant.pixels, height: variant.pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("nie udało się zakodować \(variant.name)\n".utf8))
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent(variant.name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil odmówił złożenia .icns\n".utf8))
    exit(1)
}

print("\(icns.path) — \(variants.count) rozmiarów")
