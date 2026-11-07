// Generates Resources/AppIcon.icns from Resources/wasevo-logo.png
// Usage: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let logo = NSImage(contentsOf: root.appendingPathComponent("Resources/wasevo-logo.png"))!
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let ctx = NSGraphicsContext.current!.cgContext
    // macOS icon grid: the squircle sits inside a 10% margin and casts a soft shadow
    let inset = s * 0.085
    let rect = NSRect(x: inset, y: inset * 1.15, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035,
                  color: NSColor(white: 0, alpha: 0.28).cgColor)
    NSColor.white.setFill(); path.fill()
    ctx.restoreGState()

    // white → warm cream body
    NSGradient(colors: [NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                        NSColor(srgbRed: 1.0, green: 0.945, blue: 0.91, alpha: 1)])!.draw(in: path, angle: -90)
    // soft brand glow behind the mark
    ctx.saveGState()
    path.addClip()
    let glow = NSGradient(colors: [NSColor(srgbRed: 0.99, green: 0.37, blue: 0.08, alpha: 0.22),
                                   NSColor(srgbRed: 0.99, green: 0.37, blue: 0.08, alpha: 0)])!
    glow.draw(fromCenter: NSPoint(x: rect.midX, y: rect.midY - rect.height * 0.04), radius: 0,
              toCenter: NSPoint(x: rect.midX, y: rect.midY - rect.height * 0.04), radius: rect.width * 0.48, options: [])
    // glassy top highlight
    let hi = NSBezierPath(ovalIn: NSRect(x: rect.minX - rect.width * 0.2, y: rect.midY + rect.height * 0.18,
                                         width: rect.width * 1.4, height: rect.height * 0.9))
    NSColor(white: 1, alpha: 0.55).setFill(); hi.fill()
    ctx.restoreGState()
    // hairline edge
    NSColor(srgbRed: 0.99, green: 0.37, blue: 0.08, alpha: 0.18).setStroke()
    path.lineWidth = max(1, s * 0.003); path.stroke()

    let l = rect.width * 0.64
    logo.draw(in: NSRect(x: rect.midX - l / 2, y: rect.midY - l / 2, width: l, height: l))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("iconset written")
