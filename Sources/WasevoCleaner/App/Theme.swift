import SwiftUI
import AppKit

// Wasevo brand (wasevo.com): orange #FD5E15. Every neutral colour has a light and a dark value and
// follows the appearance chosen in Settings (System / Light / Dark).

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
    /// A colour that switches with light/dark mode.
    static func dyn(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            let isDark = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let v = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

enum W {
    static let orange = Color(hex: 0xFD5E15)
    static let orange600 = Color(hex: 0xE54E0A)
    static let orange300 = Color.dyn(0xE0560F, 0xFFA274)      // orange text: darker on light backgrounds
    static let bg = Color.dyn(0xF4F1EE, 0x0E0D12)
    static let panel = Color.dyn(0xFFFFFF, 0x17161D)
    static let panel2 = Color.dyn(0xECE8E4, 0x201F28)
    static let line = Color.dyn(0x000000, 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.07)
    static let text = Color.dyn(0x1B1A21, 0xF4F3F7)
    static let muted = Color.dyn(0x47444F, 0xC9C8D3)
    static let faint = Color.dyn(0x7D7987, 0x8A8996)
    static let green = Color.dyn(0x16A34A, 0x22C55E)
    static let amber = Color.dyn(0xB7791F, 0xF5B83D)
    static let red = Color.dyn(0xDC2626, 0xFF5A4E)
    /// Frosted card fill: lets the coloured backdrop shine through a little.
    static let glass = Color.dyn(0xFFFFFF, 0x1C1B23, lightAlpha: 0.62, darkAlpha: 0.55)

    static func risk(_ r: Risk) -> Color { [green, amber, red][r.rawValue] }

    /// Crisp SF Pro (not the rounded face), one step lighter than asked: bold reads as semibold,
    /// semibold as medium. Keeps headings sharp instead of chunky.
    static func lighter(_ w: Font.Weight) -> Font.Weight {
        switch w {
        case .heavy, .black: return .bold
        case .bold: return .semibold
        case .semibold: return .medium
        default: return w
        }
    }
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: lighter(weight), design: .default)
    }
    static func body(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: lighter(weight), design: .default)
    }
    static let mono = Font.system(size: 11, design: .monospaced)

    /// Brand gradient used on primary actions and the selected sidebar item.
    static let accent = LinearGradient(colors: [Color(hex: 0xFF7A3D), orange, orange600],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)

    static var logo: NSImage? { NSImage(named: "wasevo-logo") }
}

/// SF Symbol in a softly tinted rounded square.
struct IconBadge: View {
    let icon: String
    var color: Color = W.orange
    var size: CGFloat = 34
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3)
            .fill(color.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3).stroke(color.opacity(0.22), lineWidth: 1))
            .overlay(Image(systemName: icon).font(.system(size: size * 0.46, weight: .semibold)).foregroundColor(color))
            .frame(width: size, height: size)
    }
}

/// Centered placeholder for empty pages.
struct EmptyState: View {
    let icon: String, title: String, text: String
    var body: some View {
        VStack(spacing: 12) {
            IconBadge(icon: icon, size: 56)
            Text(title).font(W.display(17, .semibold)).foregroundColor(W.text)
            Text(text).font(W.body(12)).foregroundColor(W.faint).multilineTextAlignment(.center).frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small colored pill ("In use", "Idle 30 days").
struct Pill: View {
    let text: String, color: Color
    var icon: String?
    init(_ text: String, _ color: Color, icon: String? = nil) { self.text = text; self.color = color; self.icon = icon }
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 8.5, weight: .bold)) }
            Text(text).font(.system(size: 10.5, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.75))
        .fixedSize()
    }
}

/// Every button presses in a little and springs back.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

func daysAgo(_ d: Int) -> String { d == 0 ? "today" : d == 1 ? "yesterday" : "\(d) days ago" }

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
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24).frame(height: 44)
            .background(
                Capsule().fill(disabled ? AnyShapeStyle(W.faint.opacity(0.35)) : AnyShapeStyle(W.accent))
                    // glossy top light
                    .overlay(Capsule().fill(LinearGradient(colors: [Color.white.opacity(disabled ? 0 : 0.28), .clear],
                                                           startPoint: .top, endPoint: .center)).padding(1.5))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(disabled ? 0 : 0.25), lineWidth: 1))
                    .brightness(hover && !disabled ? 0.05 : 0)
            )
            .shadow(color: W.orange.opacity(disabled ? 0 : (hover ? 0.45 : 0.30)), radius: hover ? 16 : 11, y: 5)
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
        .onHover { hover = $0 }
    }
}

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).foregroundColor(hover ? W.orange : W.muted) }
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(W.text)
            .padding(.horizontal, 14).frame(height: 32)
            .liquidCapsule(hover: hover)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
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
            Circle().fill(W.panel.opacity(0.8)).padding(8)
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
        .background(
            Circle().fill(RadialGradient(colors: [W.orange.opacity(0.16), .clear], center: .center,
                                         startRadius: size * 0.2, endRadius: size * 0.95))
                .frame(width: size * 1.9, height: size * 1.9)
                .allowsHitTesting(false)
        )
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassCard(radius: 16)
    }
}

func revealInFinder(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}


// MARK: - Appearance & glass

enum AppAppearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"
    var icon: String { self == .system ? "circle.lefthalf.filled" : self == .light ? "sun.max.fill" : "moon.fill" }
    /// Light by default; Dark or System when chosen in the toolbar or Settings.
    static var current: AppAppearance { AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .light }
    /// Applies to every window and the menu bar menu.
    func apply() {
        NSApp.appearance = self == .system ? nil : NSAppearance(named: self == .light ? .aqua : .darkAqua)
    }
}

/// Native macOS blur (the same material Finder's sidebar uses).
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blending; v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material; v.blendingMode = blending }
}

// MARK: - Module colour

private struct PageTintKey: EnvironmentKey { static let defaultValue: Color = W.orange }
private struct PageIconKey: EnvironmentKey { static let defaultValue: String = "sparkles" }
extension EnvironmentValues {
    var pageTint: Color { get { self[PageTintKey.self] } set { self[PageTintKey.self] = newValue } }
    var pageIcon: String { get { self[PageIconKey.self] } set { self[PageIconKey.self] = newValue } }
}

/// Soft light in the current module's colour behind the content, so glass has something to frost.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.pageTint) private var tint
    var body: some View {
        ZStack {
            W.bg
            GeometryReader { g in
                Circle().fill(tint.opacity(scheme == .dark ? 0.22 : 0.20))
                    .frame(width: g.size.width * 0.75).blur(radius: 130)
                    .position(x: g.size.width * 0.95, y: g.size.height * 0.0)
                Circle().fill(tint.opacity(scheme == .dark ? 0.12 : 0.10))
                    .frame(width: g.size.width * 0.55).blur(radius: 140)
                    .position(x: g.size.width * 0.10, y: g.size.height * 1.02)
                Circle().fill(Color(hex: 0x7C5CFF).opacity(scheme == .dark ? 0.08 : 0.06))
                    .frame(width: g.size.width * 0.45).blur(radius: 140)
                    .position(x: g.size.width * 0.55, y: g.size.height * 0.75)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: tint)
        .ignoresSafeArea()
    }
}

/// Glossy, 3D-looking app-style icon: colour gradient, light from the top, soft coloured shadow.
struct GlossyIcon: View {
    let icon: String
    var tint: Color = W.orange
    var size: CGFloat = 44
    var glow = true
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [tint.opacity(0.78), tint], startPoint: .top, endPoint: .bottom))
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.0)], startPoint: .top, endPoint: .center))
                .padding(size * 0.04)
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                               lineWidth: max(1, size * 0.025))
            Image(systemName: icon).font(.system(size: size * 0.46, weight: .semibold)).foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.18), radius: size * 0.03, y: size * 0.02)
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(glow ? 0.40 : 0), radius: size * 0.22, y: size * 0.10)
    }
}

extension View {
    /// Frosted-glass card: blur + tinted fill + hairline border with a light top edge.
    @ViewBuilder func glassCard(radius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            // Liquid Glass on macOS 26 Tahoe
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            classicGlass(radius: radius)
        }
    }

    /// Frosted glass for macOS 13–15.
    func classicGlass(radius: CGFloat) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: radius).fill(W.glass))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(
                LinearGradient(colors: [Color.white.opacity(0.22), W.line], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
    }
}

extension View {
    /// Secondary buttons: Liquid Glass capsule on macOS 26, frosted capsule before that.
    @ViewBuilder func liquidCapsule(hover: Bool) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(Capsule().fill(.ultraThinMaterial))
                .background(Capsule().fill(hover ? W.panel2 : W.glass))
                .overlay(Capsule().stroke(hover ? W.orange.opacity(0.45) : W.line.opacity(3), lineWidth: 1))
        }
    }
}
