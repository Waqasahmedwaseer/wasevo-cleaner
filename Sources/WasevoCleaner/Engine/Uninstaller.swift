import Foundation
import AppKit

// Wasevo Cleaner — App Uninstaller. Apps and their leftovers always go to the Trash (restorable).

struct InstalledApp: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let bundleId: String
    let version: String
    var size: Int64 = 0
    var isApple: Bool { bundleId.hasPrefix("com.apple.") }
    var isSelf: Bool { bundleId == Bundle.main.bundleIdentifier || bundleId == "com.wasevo.cleaner" }
    var running: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty }
    var canRemove: Bool { !isApple && !isSelf && !bundleId.isEmpty }
}

struct Leftover: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let kind: String
    let size: Int64
    var protected: String? { protectedReason(path + "/") ?? protectedReason(path) }
}

func listApps() -> [InstalledApp] {
    let fm = FileManager.default
    var out: [InstalledApp] = []
    for dir in ["/Applications", h("~/Applications")] {
        for k in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where k.hasSuffix(".app") {
            let p = (dir as NSString).appendingPathComponent(k)
            guard let b = Bundle(path: p) else { continue }
            let info = b.infoDictionary ?? [:]
            let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? String(k.dropLast(4))
            out.append(InstalledApp(name: name, path: p, bundleId: b.bundleIdentifier ?? "",
                                    version: (info["CFBundleShortVersionString"] as? String) ?? ""))
        }
    }
    return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

/// Files an app leaves behind in your Library. Matched by exact bundle id (or exact app name in a few places).
func findLeftovers(_ app: InstalledApp) -> [Leftover] {
    let fm = FileManager.default
    let id = app.bundleId
    guard id.count >= 6, id.contains(".") else { return [] }
    let fileName = ((app.path as NSString).lastPathComponent as NSString).deletingPathExtension
    let names = Set([app.name, fileName].filter { $0.count >= 4 })
    let L = h("~/Library")
    var hits: [(String, String)] = []

    func exact(_ dir: String, _ kind: String, _ candidates: [String]) {
        for c in candidates {
            let p = "\(L)/\(dir)/\(c)"
            if fm.fileExists(atPath: p) { hits.append((p, kind)) }
        }
    }
    func matching(_ dir: String, _ kind: String, _ test: (String) -> Bool) {
        for k in (try? fm.contentsOfDirectory(atPath: "\(L)/\(dir)")) ?? [] where test(k) {
            hits.append(("\(L)/\(dir)/\(k)", kind))
        }
    }

    exact("Application Support", "App data", [id] + names)
    exact("Caches", "Cache", [id] + names)
    exact("Containers", "Sandbox container", [id])
    exact("Application Scripts", "Scripts", [id])
    exact("Saved Application State", "Window state", ["\(id).savedState"])
    exact("HTTPStorages", "Web storage", [id, "\(id).binarycookies"])
    exact("WebKit", "Web data", [id])
    exact("Logs", "Logs", [id] + names)
    exact("Preferences", "Settings", ["\(id).plist"])
    matching("Preferences/ByHost", "Settings") { $0.hasPrefix(id + ".") && $0.hasSuffix(".plist") }
    matching("Group Containers", "Shared container") { $0.hasSuffix("." + id) || $0 == "group." + id }
    matching("LaunchAgents", "Login item") { $0.hasPrefix(id) && $0.hasSuffix(".plist") }

    var seen = Set<String>()
    return hits.compactMap { p, kind in
        guard seen.insert(p).inserted else { return nil }
        return Leftover(path: p, kind: kind, size: dirSize(p))
    }.sorted { $0.size > $1.size }
}

/// Moves the app bundle to the Trash. Falls back to Finder (which asks for your password) for admin-owned apps.
func trashApp(_ app: InstalledApp) -> String? {
    guard app.canRemove else { return "Apple and system apps are not removed." }
    guard !app.running else { return "\(app.name) is running. Quit it first." }
    let p = (app.path as NSString).standardizingPath
    guard p.hasSuffix(".app"), p.hasPrefix("/Applications/") || p.hasPrefix(h("~/Applications") + "/") else {
        return "Only apps in Applications can be removed."
    }
    do {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil)
        log("UNINSTALL TRASHED \(p)")
        return nil
    } catch {
        let escaped = p.replacingOccurrences(of: "\"", with: "\\\"")
        let r = sh("osascript -e 'tell application \"Finder\" to delete POSIX file \"\(escaped)\"'", timeout: 120)
        if r.code == 0 { log("UNINSTALL TRASHED (Finder) \(p)"); return nil }
        log("UNINSTALL FAILED \(p): \(r.out)")
        return "macOS would not move \(app.name) to the Trash. Drag it to the Trash in Finder."
    }
}
