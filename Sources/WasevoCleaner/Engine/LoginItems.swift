import Foundation

// Wasevo Cleaner — Startup & background items. Items are switched off with macOS's own
// `launchctl disable` (fully reversible, no files are moved or deleted). System daemons are shown only.

enum LaunchScope: String { case user = "Your account", allUsers = "All users", system = "System daemon" }

struct LaunchItem: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let label: String
    let program: String
    let scope: LaunchScope
    var disabled: Bool
    var running: Bool

    /// App this helper belongs to, from its program path (e.g. "Zoom").
    var owner: String {
        if let r = program.range(of: ".app/") {
            return ((String(program[..<r.lowerBound]) as NSString).lastPathComponent)
        }
        if label.hasPrefix("homebrew.mxcl.") { return "Homebrew: " + label.dropFirst("homebrew.mxcl.".count) }
        let parts = label.split(separator: ".")
        return parts.count >= 2 ? String(parts[1]).capitalized : label
    }
    /// Can be switched on/off without an admin password.
    var canToggle: Bool { scope != .system && !label.hasPrefix("com.apple.") && !label.hasPrefix("com.wasevo.") }
    var note: String? {
        if label.hasPrefix("homebrew.mxcl.") { return "A dev service you started with brew services. Off = it stops until you turn it back on." }
        if label.lowercased().contains("update") || label.lowercased().contains("keystone") { return "Keeps the app up to date. Off = check for updates inside the app yourself." }
        return nil
    }
}

private var uid: String { String(getuid()) }

private func disabledLabels(_ domain: String) -> Set<String> {
    var out = Set<String>()
    for line in sh("launchctl print-disabled \(domain)", timeout: 10).out.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("\""), t.hasSuffix("disabled") || t.hasSuffix("true") else { continue }
        if let end = t.dropFirst().firstIndex(of: "\"") { out.insert(String(t[t.index(after: t.startIndex)..<end])) }
    }
    return out
}

func listLaunchItems() -> [LaunchItem] {
    let running = Set(sh("launchctl list", timeout: 10).out.split(separator: "\n").compactMap { l -> String? in
        let c = l.split(separator: "\t")
        return c.count == 3 && c[0] != "-" && c[0] != "PID" ? String(c[2]) : nil
    })
    let userOff = disabledLabels("gui/\(uid)")
    let sysOff = disabledLabels("system")
    var out: [LaunchItem] = []
    for (dir, scope) in [(h("~/Library/LaunchAgents"), LaunchScope.user), ("/Library/LaunchAgents", .allUsers), ("/Library/LaunchDaemons", .system)] {
        for f in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted() where f.hasSuffix(".plist") {
            let p = (dir as NSString).appendingPathComponent(f)
            guard let d = NSDictionary(contentsOfFile: p) as? [String: Any] else { continue }
            let label = d["Label"] as? String ?? String(f.dropLast(6))
            let prog = d["Program"] as? String ?? (d["ProgramArguments"] as? [String])?.first ?? ""
            let off = (d["Disabled"] as? Bool ?? false) || (scope == .system ? sysOff : userOff).contains(label)
            out.append(LaunchItem(path: p, label: label, program: prog, scope: scope, disabled: off, running: running.contains(label)))
        }
    }
    return out
}

/// Turns a startup item off (and stops it now) or back on. Returns an error message, or nil.
func setLaunchItem(_ item: LaunchItem, enabled: Bool) -> String? {
    guard item.canToggle else { return "This item needs an admin to change." }
    let target = "gui/\(uid)/\(item.label)"
    let q = "'" + item.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    if enabled {
        let r = sh("launchctl enable \(target)", timeout: 15)
        guard r.code == 0 else { return r.out }
        sh("launchctl bootstrap gui/\(uid) \(q) 2>/dev/null", timeout: 15)   // "already loaded" is fine
        log("STARTUP ON \(item.label)")
    } else {
        let r = sh("launchctl disable \(target)", timeout: 15)
        guard r.code == 0 else { return r.out }
        sh("launchctl bootout \(target) 2>/dev/null", timeout: 15)           // stop it now if running
        log("STARTUP OFF \(item.label)")
    }
    return nil
}
