import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-app-icon.swift OUTPUT.iconset\n", stderr)
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let files: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in files {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "mx3-lite.icon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSGraphicsContext.current?.imageInterpolation = .high

    let scale = CGFloat(size)
    let bounds = NSRect(x: 0, y: 0, width: scale, height: scale)
    NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.15, alpha: 1).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: scale * 0.045, dy: scale * 0.045), xRadius: scale * 0.22, yRadius: scale * 0.22).fill()

    let mouseRect = NSRect(x: scale * 0.31, y: scale * 0.18, width: scale * 0.38, height: scale * 0.64)
    let mouse = NSBezierPath(roundedRect: mouseRect, xRadius: scale * 0.19, yRadius: scale * 0.19)
    mouse.lineWidth = max(1, scale * 0.045)
    NSColor(calibratedRed: 0.36, green: 0.90, blue: 0.78, alpha: 1).setStroke()
    mouse.stroke()

    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: scale * 0.50, y: scale * 0.79))
    divider.line(to: NSPoint(x: scale * 0.50, y: scale * 0.63))
    divider.lineWidth = max(1, scale * 0.025)
    divider.stroke()

    let wheel = NSBezierPath(roundedRect: NSRect(x: scale * 0.465, y: scale * 0.61, width: scale * 0.07, height: scale * 0.13), xRadius: scale * 0.035, yRadius: scale * 0.035)
    NSColor.white.withAlphaComponent(0.92).setFill()
    wheel.fill()

    func drawChevron(points: [NSPoint]) {
        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = max(1, scale * 0.035)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.white.withAlphaComponent(0.92).setStroke()
        path.stroke()
    }

    drawChevron(points: [
        NSPoint(x: scale * 0.23, y: scale * 0.55),
        NSPoint(x: scale * 0.16, y: scale * 0.50),
        NSPoint(x: scale * 0.23, y: scale * 0.45)
    ])
    drawChevron(points: [
        NSPoint(x: scale * 0.77, y: scale * 0.55),
        NSPoint(x: scale * 0.84, y: scale * 0.50),
        NSPoint(x: scale * 0.77, y: scale * 0.45)
    ])

    NSGraphicsContext.restoreGraphicsState()
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "mx3-lite.icon", code: 2)
    }
    try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
}
