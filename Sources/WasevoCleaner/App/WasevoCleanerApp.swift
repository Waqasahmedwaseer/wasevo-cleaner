import SwiftUI
import AppKit

// Wasevo Cleaner — the safe disk cleaner for developers. Open source (MIT).

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct WasevoCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("Wasevo Cleaner", id: "main") {
            RootView().environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra {
            MenuBarContent().environmentObject(store)
        } label: {
            Text(store.isLow ? "⚠︎ \(gb(store.free))" : "✳︎ \(gb(store.free))")
        }
    }

    func gb(_ b: Int64) -> String {
        let v = Double(b) / 1e9
        return v >= 100 ? String(format: "%.0fGB", v) : String(format: "%.1fGB", v)
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("\(human(store.free)) free of \(human(store.total))")
        if store.isLow { Text("⚠︎ Disk space is low") }
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
