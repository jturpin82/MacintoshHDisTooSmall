// Generates AppIcon.iconset. Run with: swift Tools/make-icon.swift <output.iconset>
import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels,
                                     pixelsHigh: pixels,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let side = CGFloat(pixels)
    let inset = side * 0.055
    let plate = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let corner = side * 0.225
    let path = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.60, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.36, green: 0.24, blue: 0.86, alpha: 1)
    ])
    gradient?.draw(in: path, angle: -90)

    if let symbol = NSImage(systemSymbolName: "externaldrive.connected.to.line.below.fill",
                            accessibilityDescription: nil) {
        let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.42, weight: .medium)
        let glyph = symbol.withSymbolConfiguration(configuration) ?? symbol
        let glyphSize = glyph.size
        let target = NSRect(x: (side - glyphSize.width) / 2,
                            y: (side - glyphSize.height) / 2,
                            width: glyphSize.width,
                            height: glyphSize.height)
        NSColor.white.set()
        target.fill(using: .sourceOver)
        glyph.draw(in: target, from: .zero, operation: .destinationIn, fraction: 1)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    guard let data = render(pixels: variant.pixels) else {
        FileHandle.standardError.write(Data("failed to render \(variant.name)\n".utf8))
        exit(1)
    }
    try data.write(to: outputURL.appendingPathComponent(variant.name))
}
