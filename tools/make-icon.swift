// Generates the AppIcon PNGs: dark rounded tile with faded text lines and an
// orange reading-guide marker on the active line.
// Usage: swift tools/make-icon.swift <output dir>            (macOS: rounded tile, transparent corners)
//        swift tools/make-icon.swift <output dir> --ios      (iOS: opaque 1024px square, iOS rounds it)
import AppKit

let args = CommandLine.arguments.dropFirst()
let iOS = args.contains("--ios")
let outDir = args.first(where: { !$0.hasPrefix("--") }) ?? "."
let sizes = iOS ? [1024] : [16, 32, 64, 128, 256, 512, 1024]

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(px)
    let inset = iOS ? 0 : s * 0.075
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = iOS ? 0 : s * 0.19
    let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    NSGradient(starting: NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.20, alpha: 1),
               ending: NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.05, alpha: 1))!
        .draw(in: path, angle: -90)

    // (y from top, width, alpha) — middle line is the one being read
    let lines: [(CGFloat, CGFloat, CGFloat)] = [
        (0.24, 0.58, 0.22), (0.33, 0.46, 0.38), (0.42, 0.64, 0.6),
        (0.51, 0.66, 1.0),
        (0.60, 0.52, 0.6), (0.69, 0.60, 0.38), (0.78, 0.40, 0.22),
    ]
    let lineH = tile.height * 0.05
    let left = tile.minX + tile.width * 0.19
    for (i, (yFrac, wFrac, alpha)) in lines.enumerated() {
        let y = tile.maxY - yFrac * tile.height - lineH / 2
        let r = NSRect(x: left, y: y, width: tile.width * wFrac, height: lineH)
        NSColor(white: 1, alpha: alpha).setFill()
        NSBezierPath(roundedRect: r, xRadius: lineH / 2, yRadius: lineH / 2).fill()
        if i == 3 {
            let marker = NSRect(x: tile.minX + tile.width * 0.10, y: y - lineH * 0.35,
                                width: lineH * 0.9, height: lineH * 1.7)
            NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.0, alpha: 1).setFill()
            NSBezierPath(roundedRect: marker, xRadius: lineH * 0.3, yRadius: lineH * 0.3).fill()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in sizes {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("icon_\(px).png")
    try! render(px).write(to: url)
}
print("wrote \(sizes.count) icons to \(outDir)")
