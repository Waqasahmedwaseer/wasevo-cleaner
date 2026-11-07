import SwiftUI
import AppKit

// Wasevo Cleaner — the safe disk cleaner for developers. Open source (MIT).

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ n: Notification) { SystemMonitor.shared.start() }
}

@main
struct WasevoCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = Store()

    init() {
        if CommandLine.arguments.contains("--selftest") { SelfTest.run(); exit(SelfTest.failures == 0 ? 0 : 1) }
    }

    var body: some Scene {
        WindowGroup("Wasevo Cleaner", id: "main") {
            RootView().environmentObject(store)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1120, height: 780)

        MenuBarExtra {
            MenuBarContent().environmentObject(store)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: Self.menuIcon)
                Text(gb(store.free))
            }
        }
    }

    /// The Wasevo logo, sized for the menu bar.
    static let menuIcon: NSImage = {
        let size = NSSize(width: 16, height: 16)
        guard let logo = W.logo else { return NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)! }
        let img = NSImage(size: size, flipped: false) { r in logo.draw(in: r); return true }
        img.isTemplate = false
        return img
    }()

    func gb(_ b: Int64) -> String {
        let v = Double(b) / 1e9
        return v >= 100 ? String(format: "%.0fGB", v) : String(format: "%.1fGB", v)
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var mon = SystemMonitor.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("\(human(store.free)) free of \(human(store.total))")
        if store.isLow { Label("Disk space is low", systemImage: "exclamationmark.triangle") }
        Text("CPU \(Int(mon.cpu * 100))% · Memory \(human(mon.memory.used)) of \(human(mon.memory.total))")
        if let b = mon.battery { Text("Battery \(b.percent)%\(b.charging ? " (charging)" : "")") }
        Divider()
        Button("Open Wasevo Cleaner") { show() }.keyboardShortcut("o")
        Button("Smart Scan") { show(); store.scan() }.keyboardShortcut("s")
        Divider()
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    func show() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
