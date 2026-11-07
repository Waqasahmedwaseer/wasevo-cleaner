import SwiftUI
import AppKit

// Shared building blocks: staggered list entrance, scan states, the Trash bar, thumbnails.

/// Fades and slides a row in, a little later for each row (capped so long lists stay fast).
struct StaggerIn: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(Double(min(index, 14)) * 0.035)) { shown = true }
            }
    }
}
extension View {
    func staggerIn(_ i: Int) -> some View { modifier(StaggerIn(index: i)) }
    /// Numbers that roll when they change (macOS 14+), plain on macOS 13.
    @ViewBuilder func rollingNumber() -> some View {
        if #available(macOS 14.0, *) { self.contentTransition(.numericText()) } else { self }
    }
}

/// Header row used by the tool pages: title + subtitle on the left, an action on the right.
struct ToolHeader<Trailing: View>: View {
    let title: String, subtitle: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .bottom) {
            PageHeader(title: title, subtitle: subtitle)
            trailing.padding(.trailing, 28).padding(.bottom, 14)
        }
    }
}

/// "Nothing scanned yet" state with a big button.
struct StartPanel: View {
    let icon: String, title: String, text: String, button: String
    let action: () -> Void
    @State private var pulse = false
    @Environment(\.pageTint) private var tint
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 150, height: 150).scaleEffect(pulse ? 1.12 : 0.92)
                Circle().fill(tint.opacity(0.07)).frame(width: 200, height: 200).scaleEffect(pulse ? 1.0 : 0.85)
                GlossyIcon(icon: icon, tint: tint, size: 96)
                    .offset(y: pulse ? -3 : 3)
            }
            .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: pulse)
            Text(title).font(W.display(22)).foregroundColor(W.text)
            Text(text).font(W.body(13)).foregroundColor(W.faint).multilineTextAlignment(.center).frame(maxWidth: 460)
            PrimaryButton(title: button, icon: "sparkles", action: action).padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true }
    }
}

/// Spinner with the Wasevo logo, used while a tool is scanning.
struct BusyPanel: View {
    let text: String
    @State private var spin = false
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().stroke(W.panel2, lineWidth: 8).frame(width: 110, height: 110)
                Circle().trim(from: 0, to: 0.3).stroke(W.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 110, height: 110).rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                Logo(size: 40)
            }
            Text(text).font(W.body(13)).foregroundColor(W.faint).animation(nil, value: text)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { spin = true }
    }
}

/// Bottom bar: what is selected, and the (always restorable) Move to Trash button.
struct TrashBar: View {
    let size: Int64, count: Int
    var note = "Everything goes to the Trash, so you can put it back."
    var title = "Move to Trash"
    let action: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(human(size)) selected").font(W.display(20)).foregroundColor(W.text).rollingNumber()
                    .animation(.spring(response: 0.35), value: size)
                Text("\(count) item\(count == 1 ? "" : "s") · \(note)").font(W.body(11)).foregroundColor(W.faint)
            }
            Spacer()
            PrimaryButton(title: title, icon: "trash", disabled: count == 0, action: action)
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(.regularMaterial)
        .overlay(Rectangle().fill(W.line).frame(height: 1), alignment: .top)
    }
}

/// Green confirmation strip that slides in from the bottom.
struct Toast: View {
    let text: String
    var color: Color = W.green
    let close: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: color == W.green ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundColor(color)
            Text(text).font(W.body(12, .semibold)).foregroundColor(W.text)
            Spacer()
            Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundColor(W.faint)
        }
        .padding(14).background(W.panel2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// File icon, or a real thumbnail for images (loaded in the background).
struct FileThumb: View {
    let path: String
    var size: CGFloat = 34
    @State private var img: NSImage?
    var body: some View {
        Group {
            if let img { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) }
            else { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable() }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        .onAppear {
            guard img == nil, PHOTO_EXTS.contains((path as NSString).pathExtension.lowercased()) else { return }
            DispatchQueue.global(qos: .utility).async {
                let t = thumbnail(path, maxPixels: Int(size * 2.5)).map { NSImage(cgImage: $0, size: .zero) }
                DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.25)) { img = t } }
            }
        }
    }
}

/// Little chip: value + label.
struct StatChip: View {
    let value: String, label: String
    var color: Color = W.text
    var body: some View {
        HStack(spacing: 5) {
            Text(value).font(W.body(12, .bold)).foregroundColor(color).rollingNumber()
            Text(label).font(W.body(11)).foregroundColor(W.faint)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(W.panel))
        .overlay(Capsule().stroke(W.line, lineWidth: 1))
    }
}

func relativeDate(_ d: Date) -> String {
    RelativeDateTimeFormatter().localizedString(for: d, relativeTo: Date())
}
