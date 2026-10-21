import AppKit

// Package local SF Symbols as ordinary Finder/Dock icons. No asset downloads.
let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("Usage: macos-icon ICONSET SYMBOL") }
let directory = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let symbol = (NSImage(systemSymbolName: arguments[2], accessibilityDescription: nil)
    ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!)
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 500, weight: .medium))!
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let bounds = NSRect(x: 82, y: 82, width: 860, height: 860)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 190, yRadius: 190)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowBlurRadius = 25
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.systemBlue.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        // Constant-color scanlines avoid NSGradient's per-pixel dithering,
        // which otherwise dominates the PNG/ICNS size at Retina resolutions.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        context.setShouldAntialias(false)
        for row in 0..<pixels {
            let t = Double(row) / Double(pixels - 1)
            NSColor(srgbRed: 0.04 + 0.08 * t, green: 0.38 + 0.42 * t,
                blue: 0.95 - 0.19 * t, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: Double(row) * 1024 / Double(pixels),
                width: 1024, height: 1024 / Double(pixels)))
        }
        NSGraphicsContext.restoreGraphicsState()
        let glyph = NSRect(x: 252, y: 252, width: 520, height: 520)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        symbol.draw(in: glyph, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.setFill()
        glyph.fill(using: .sourceIn)
        context.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    }
}
