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

    // Drawn by hand rather than from an SF Symbol: symbol rasterisation is
    // unreliable in a headless build and silently produced a blank square.
    func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x * side, y: y * side, width: w * side, height: h * side),
                     xRadius: r * side, yRadius: r * side)
    }

    // Drive body, its slot, and the line it sits above.
    NSColor.white.setFill()
    rounded(0.24, 0.435, 0.52, 0.235, 0.05).fill()
    rounded(0.31, 0.295, 0.38, 0.05, 0.025).fill()

    NSColor(calibratedRed: 0.28, green: 0.45, blue: 0.94, alpha: 1).setFill()
    rounded(0.305, 0.495, 0.28, 0.038, 0.019).fill()

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
