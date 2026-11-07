import Foundation

// Wasevo Cleaner — Maintenance: Apple's own commands, run only when you click.
// Tasks that need admin rights show the standard macOS password dialog (Wasevo never sees the password).

struct MaintenanceTask: Identifiable {
    let id: String
    let title: String
    let icon: String
    let what: String
    let when: String
    let command: String
    let needsAdmin: Bool
    let heavy: Bool
}

let MAINTENANCE_TASKS: [MaintenanceTask] = [
    MaintenanceTask(id: "verify", title: "Check disk for errors", icon: "stethoscope",
                    what: "Runs Apple's read-only disk check on your system and data volumes. Nothing is changed or repaired.",
                    when: "If apps crash on files or Finder acts up.",
                    command: "diskutil verifyVolume / && diskutil verifyVolume /System/Volumes/Data", needsAdmin: false, heavy: false),
    MaintenanceTask(id: "dns", title: "Flush DNS cache", icon: "network",
                    what: "Clears macOS's remembered web addresses so sites are looked up fresh.",
                    when: "If one website will not load but others do, or after changing DNS or VPN.",
                    command: "dscacheutil -flushcache; killall -HUP mDNSResponder", needsAdmin: true, heavy: false),
    MaintenanceTask(id: "spotlight", title: "Rebuild Spotlight index", icon: "magnifyingglass",
                    what: "Deletes and rebuilds the search index of your main disk. Your files are not touched.",
                    when: "Only if Spotlight search misses files. Your Mac will be busy for a while afterwards.",
                    command: "mdutil -E /", needsAdmin: true, heavy: true),
]

/// Runs a task. Admin tasks go through macOS's own authorization dialog via osascript.
func runMaintenance(_ t: MaintenanceTask) -> (ok: Bool, output: String) {
    let r: (code: Int32, out: String)
    if t.needsAdmin {
        let escaped = t.command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        r = sh("osascript -e '\(script.replacingOccurrences(of: "'", with: "'\\''"))'", timeout: 300)
    } else {
        r = sh(t.command, timeout: 900)
    }
    log("MAINTENANCE \(t.id) exit \(r.code)")
    if r.out.contains("User canceled") || r.out.contains("(-128)") { return (false, "Cancelled.") }
    return (r.code == 0, r.out.trimmingCharacters(in: .whitespacesAndNewlines))
}
