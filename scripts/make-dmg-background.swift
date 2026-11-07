// Renders the DMG window background (1x + 2x) with the brand look.
// Usage: swift scripts/make-dmg-background.swift <outdir>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/dmg"
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let logo = NSImage(contentsOf: root.appendingPathComponent("Resources/wasevo-logo.png"))!
let W: CGFloat = 660, H: CGFloat = 420
let orange = NSColor(srgbRed: 0.99, green: 0.37, blue: 0.08, alpha: 1)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let full = NSRect(x: 0, y: 0, width: W, height: H)
    // warm white base
    NSGradient(colors: [NSColor(srgbRed: 1, green: 0.985, blue: 0.97, alpha: 1),
                        NSColor(srgbRed: 0.985, green: 0.945, blue: 0.92, alpha: 1)])!.draw(in: full, angle: -90)
    // soft brand glows
    for (c, r, a) in [(NSPoint(x: W * 0.92, y: H * 1.0), W * 0.55, 0.22), (NSPoint(x: W * 0.05, y: 0), W * 0.45, 0.12)] {
        NSGradient(colors: [orange.withAlphaComponent(a), orange.withAlphaComponent(0)])!
            .draw(fromCenter: c, radius: 0, toCenter: c, radius: r, options: [])
    }
    // header: logo + name
    logo.draw(in: NSRect(x: 40, y: H - 72, width: 34, height: 34))
    let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                                               .foregroundColor: NSColor(white: 0.1, alpha: 1)]
    ("Wasevo Cleaner" as NSString).draw(at: NSPoint(x: 84, y: H - 66), withAttributes: title)
    let sub: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12.5),
                                             .foregroundColor: NSColor(white: 0.42, alpha: 1)]
    ("The safe Mac cleaner for people who build things." as NSString).draw(at: NSPoint(x: 85, y: H - 86), withAttributes: sub)
    // dashed arrow between the two icons (icons sit at x 170 and 490, y 210 from top)
    let y = H - 210
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 252, y: y)); path.line(to: NSPoint(x: 400, y: y))
    path.lineWidth = 3; path.lineCapStyle = .round
    path.setLineDash([2, 9], count: 2, phase: 0)
    orange.withAlphaComponent(0.75).setStroke(); path.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 396, y: y + 9)); head.line(to: NSPoint(x: 408, y: y)); head.line(to: NSPoint(x: 396, y: y - 9))
    head.lineWidth = 3; head.lineCapStyle = .round; head.lineJoinStyle = .round; head.stroke()
    let hint: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: orange]
    let h = "Drag to Applications to install" as NSString
    h.draw(at: NSPoint(x: (W - h.size(withAttributes: hint).width) / 2, y: y - 34), withAttributes: hint)
    // footer credit
    let foot: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 0.45, alpha: 1)]
    let f = "Designed and built by Waqas Ahmed Waseer, Founder & CEO of Wasevo  ·  wasevo.com" as NSString
    f.draw(at: NSPoint(x: (W - f.size(withAttributes: foot).width) / 2, y: 22), withAttributes: foot)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
try! render(scale: 1).write(to: URL(fileURLWithPath: "\(out)/background.png"))
try! render(scale: 2).write(to: URL(fileURLWithPath: "\(out)/background@2x.png"))
print("background written")
