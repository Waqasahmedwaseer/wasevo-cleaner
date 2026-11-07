import SwiftUI
import AppKit

// First-launch welcome: what the app does, the safety promise, and the one permission that stops pop-ups.

struct Onboarding: View {
    @Binding var isPresented: Bool
    @State private var step = 0
    @State private var forward = true

    private struct Step { let icon: String; let tint: Color; let title: String; let text: String }
    private let steps = [
        Step(icon: "sparkles", tint: W.orange, title: "Welcome to Wasevo Cleaner",
             text: "Free up space, find duplicates and old downloads, keep apps up to date and see what your Mac is doing. One scan checks everything."),
        Step(icon: "lock.shield", tint: Color(hex: 0xEF4444), title: "Built to be safe",
             text: "Your code, git history, databases, Docker data and logins are never touched. Everything you remove goes to the Trash first, and you can put it back with one click."),
        Step(icon: "lock.open", tint: Color(hex: 0x3B82F6), title: "One permission, no more pop-ups",
             text: "Give Wasevo Cleaner Full Disk Access once so it can measure your folders without macOS asking every time. You can change this any time in System Settings."),
    ]

    var body: some View {
        let s = steps[step]
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            ZStack {
                Circle().fill(s.tint.opacity(0.12)).frame(width: 170, height: 170)
                if step == 0 { Logo(size: 84) } else { GlossyIcon(icon: s.icon, tint: s.tint, size: 92) }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            VStack(spacing: 10) {
                Text(s.title).font(W.display(24)).foregroundColor(W.text)
                Text(s.text).font(W.body(13.5)).foregroundColor(W.muted).multilineTextAlignment(.center)
                    .lineSpacing(3).frame(maxWidth: 420)
            }
            .id("t\(step)").transition(.opacity)
            if step == 2 {
                SecondaryButton(title: "Open Full Disk Access", icon: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
            }
            Spacer(minLength: 10)
            HStack {
                HStack(spacing: 7) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Capsule().fill(i == step ? W.orange : W.line).frame(width: i == step ? 20 : 7, height: 7)
                    }
                }
                .animation(.spring(response: 0.35), value: step)
                Spacer()
                if step > 0 { SecondaryButton(title: "Back") { move(-1) } }
                PrimaryButton(title: step == steps.count - 1 ? "Get started" : "Next",
                              icon: step == steps.count - 1 ? "checkmark" : "arrow.right") {
                    if step == steps.count - 1 { isPresented = false } else { move(1) }
                }
            }
        }
        .padding(32)
        .frame(width: 600, height: 520)
        .background(Backdrop())
    }

    func move(_ d: Int) {
        forward = d > 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += d }
    }
}
