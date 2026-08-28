// Рисует иконку приложения и раскладывает её в AppIcon.iconset.
// Иконка задана кодом, а не бинарной картинкой: её можно перечитать,
// изменить цвет или пропорции и пересобрать, ничего не рисуя руками.
//
// Запуск (обычно через make.sh):
//   swiftc -O Tools/GenerateIcon.swift -o /tmp/genicon && /tmp/genicon <каталог>

import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

/// Тёплый тёмный фон панели и коралловый акцент Claude — та же палитра,
/// что и в самом приложении.
let background = NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.11, alpha: 1)
let accent = NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)

/// Рисует иконку размером side×side.
func drawIcon(side: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Поля по сетке иконок macOS: содержимое занимает ~82% полотна.
    let margin = side * 0.09
    let rect = NSRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2)
    let squircle = NSBezierPath(roundedRect: rect,
                                xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    background.setFill()
    squircle.fill()

    // Тонкая тёплая обводка, чтобы иконка не сливалась с тёмными обоями.
    accent.withAlphaComponent(0.25).setStroke()
    squircle.lineWidth = max(1, side * 0.006)
    squircle.stroke()

    // Звёздочка Claude — шесть лучей из центра.
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let rayLength = rect.width * 0.29
    let rayWidth = rect.width * 0.085
    accent.setStroke()
    for index in 0..<6 {
        let angle = CGFloat(index) * .pi / 3 + .pi / 6
        let ray = NSBezierPath()
        ray.lineWidth = rayWidth
        ray.lineCapStyle = .round
        ray.move(to: center)
        ray.line(to: NSPoint(x: center.x + cos(angle) * rayLength,
                             y: center.y + sin(angle) * rayLength))
        ray.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Размеры, которых требует iconutil.
let variants: [(name: String, side: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try? FileManager.default.createDirectory(atPath: outputDir,
                                         withIntermediateDirectories: true)

for variant in variants {
    let rep = drawIcon(side: variant.side)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("не удалось закодировать \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let path = "\(outputDir)/\(variant.name).png"
    try! data.write(to: URL(fileURLWithPath: path))
}

print("иконки записаны в \(outputDir) (\(variants.count) размеров)")
