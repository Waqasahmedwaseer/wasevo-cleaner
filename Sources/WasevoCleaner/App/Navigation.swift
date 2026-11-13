import Foundation
import AppKit
import UniformTypeIdentifiers

// Wasevo Cleaner — app-wide navigation requests, keyboard shortcuts, weekly report, settings export.

/// Lets any screen (dashboard cards, menu commands, shortcuts) open a page or ask the page to rescan.
final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var goTo: Page?
    @Published var refresh = 0
    @Published var showTour = false
    func open(_ p: Page) { goTo = p }
    func rescan() { refresh += 1 }
}

// MARK: - Weekly report

enum WeeklyReport {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "weeklyReport") as? Bool ?? true }
    private static let key = "lastWeeklyReport"

    /// Once a week: a notification with how much safe cache can be cleaned and how much space is free.
    /// Read-only: it measures, it never cleans.
    static func checkDue() {
        guard enabled else { return }
        let d = UserDefaults.standard
        let last = d.double(forKey: key)
        if last == 0 { d.set(Date().timeIntervalSince1970, forKey: key); return }   // first run: start the clock
        guard Date().timeIntervalSince1970 - last >= 7 * 86400 else { return }
        d.set(Date().timeIntervalSince1970, forKey: key)
        DispatchQueue.global(qos: .utility).async {
            let junk = CACHE_RULES.filter { $0.risk == .safe }.reduce(Int64(0)) { $0 + ruleSize($1) }
            let free = volumeFree()
            log("WEEKLY REPORT · \(human(junk)) safe caches · \(human(free)) free")
            notify("Your weekly Mac report",
                   junk > 200_000_000 ? "\(human(junk)) of safe caches can be cleaned. \(human(free)) free now."
                                      : "Your Mac is tidy. \(human(free)) free.")
        }
    }
}

// MARK: - Settings export / import

enum SettingsTransfer {
    /// Only plain preferences travel. No history, no scan results, nothing personal.
    static let keys = ["staleDays", "lowSpaceGB", "projectRoots", "deleteMode", "autoClean", "appearance", "weeklyReport", "autoUpdateCheck"]

    static func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Wasevo Cleaner Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var out: [String: Any] = ["app": "Wasevo Cleaner", "version": 1]
        for k in keys { if let v = UserDefaults.standard.object(forKey: k) { out[k] = v } }
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
            log("SETTINGS EXPORTED \(url.path)")
        }
    }

    /// Returns a message for the user. Unknown keys and wrong types are ignored.
    static func importFile() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["app"] as? String == "Wasevo Cleaner" else { return "That file is not a Wasevo Cleaner settings file." }
        var n = 0
        for k in keys {
            guard let v = json[k] else { continue }
            if v is String || v is NSNumber { UserDefaults.standard.set(v, forKey: k); n += 1 }
        }
        AppAppearance.current.apply()
        log("SETTINGS IMPORTED \(n) values from \(url.path)")
        return "Imported \(n) settings."
    }
}
