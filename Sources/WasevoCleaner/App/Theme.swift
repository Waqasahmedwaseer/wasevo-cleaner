import SwiftUI
import AppKit

// Wasevo brand (wasevo.com): orange #FD5E15 on near-black ink.

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

enum W {
    static let orange = Color(hex: 0xFD5E15)
    static let orange600 = Color(hex: 0xE54E0A)
    static let orange300 = Color(hex: 0xFFA274)
    static let bg = Color(hex: 0x0E0D12)        // --dark
    static let panel = Color(hex: 0x17161D)     // --dark-2
    static let panel2 = Color(hex: 0x201F28)
    static let line = Color.white.opacity(0.07)
    static let text = Color(hex: 0xF4F3F7)
    static let muted = Color(hex: 0xC9C8D3)     // --dark-text
    static let faint = Color(hex: 0x8A8996)
    static let green = Color(hex: 0x22C55E)
    static let amber = Color(hex: 0xF5B83D)
    static let red = Color(hex: 0xFF5A4E)

    static func risk(_ r: Risk) -> Color { [green, amber, red][r.rawValue] }

    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func body(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static let mono = Font.system(size: 11, design: .monospaced)

    static var logo: NSImage? { NSImage(named: "wasevo-logo") }
}

struct Logo: View {
    var size: CGFloat = 28
    var body: some View {
        if let img = W.logo {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "asterisk").font(.system(size: size * 0.8, weight: .black)).foregroundColor(W.orange)
        }
    }
}

/// Big orange call-to-action button.
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var disabled = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).font(W.body(15, .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 26).padding(.vertical, 13)
            .background(Capsule().fill(disabled ? W.faint.opacity(0.4) : (hover ? W.orange600 : W.orange)))
            .shadow(color: W.orange.opacity(disabled ? 0 : 0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hover = $0 }
    }
}

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).font(W.body(13, .semibold))
            }
            .foregroundColor(W.text)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().stroke(W.line.opacity(3), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct RiskBadge: View {
    let risk: Risk
    var body: some View {
        Text(risk.label)
            .font(W.body(10, .semibold))
            .foregroundColor(W.risk(risk))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(W.risk(risk).opacity(0.14)))
    }
}

/// Orange checkbox matching the brand.
struct CheckBox: View {
    let on: Bool
    var mixed = false
    var enabled = true
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(on || mixed ? W.orange : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(on || mixed ? W.orange : W.faint, lineWidth: 1.5))
            .overlay(Image(systemName: mixed ? "minus" : "checkmark")
                .font(.system(size: 10, weight: .heavy)).foregroundColor(.white).opacity(on || mixed ? 1 : 0))
            .frame(width: 18, height: 18)
            .opacity(enabled ? 1 : 0.35)
    }
}

/// Disk usage ring.
struct DiskRing: View {
    let used: Double   // 0…1
    var size: CGFloat = 170
    var body: some View {
        ZStack {
            Circle().stroke(W.panel2, lineWidth: 16)
            Circle().trim(from: 0, to: used)
                .stroke(AngularGradient(colors: [W.orange300, W.orange, W.orange600], center: .center),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: used)
            VStack(spacing: 2) {
                Text("\(Int(used * 100))%").font(W.display(34)).foregroundColor(W.text)
                Text("used").font(W.body(12)).foregroundColor(W.faint)
            }
        }
        .frame(width: size, height: size)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(W.panel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(W.line, lineWidth: 1))
    }
}

func revealInFinder(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}
