import AppKit

// Renders the app icon from the same emoji the menu bar uses, so the two stay in
// step. Run via scripts/make-icon.sh; output is Resources/Toothpaste.icns.
let glyph = "\u{1F4DD}"
let background = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    let dimension = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icons are rounded squares with a little breathing room at the edges.
    let inset = dimension * 0.06
    let body = NSRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
    let radius = body.width * 0.22
    background.setFill()
    NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).fill()

    let font = NSFont.systemFont(ofSize: dimension * 0.56)
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let text = glyph as NSString
    let textSize = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: (dimension - textSize.width) / 2, y: (dimension - textSize.height) / 2),
        withAttributes: attributes
    )

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent("\(size).png")
    try? png.write(to: url)
}
print("rendered \(sizes.count) sizes")
