import Foundation
import UserNotifications

// Wasevo Cleaner — scheduled auto-clean. Only rules marked Safe AND on by default; never projects,
// Docker/MySQL/tools, downloads that need review, or anything whose app is running.

enum AutoSchedule: String, CaseIterable {
    case off = "Off", daily = "Daily", weekly = "Weekly"
    var interval: TimeInterval? { self == .daily ? 86400 : self == .weekly ? 7 * 86400 : nil }
}

enum AutoClean {
    static var schedule: AutoSchedule {
        AutoSchedule(rawValue: UserDefaults.standard.string(forKey: "autoClean") ?? "") ?? .off
    }
    static var last: Date? {
        let t = UserDefaults.standard.double(forKey: "lastAutoClean")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    static var rules: [CacheRule] { CACHE_RULES.filter(\.autoClean) }

    static var isDue: Bool {
        guard let every = schedule.interval else { return false }
        guard let last else { return true }
        return Date().timeIntervalSince(last) >= every
    }

    /// Runs on a background thread. Returns bytes freed.
    @discardableResult
    static func run(reason: String) -> Int64 {
        let before = volumeFree()
        let snap = ProcSnapshot.take()
        var cleaned = 0
        for r in rules {
            if snap.running(r.blockIfRunning) != nil { continue }
            if clearRule(r, .permanent) == 0 { cleaned += 1 }
        }
        let freed = max(0, volumeFree() - before)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastAutoClean")
        log("AUTO-CLEAN (\(reason)) · \(cleaned) rules · freed \(human(freed))")
        if freed > 50_000_000 { notify("Wasevo Cleaner freed \(human(freed))", "Safe caches were cleaned automatically.") }
        return freed
    }
}

func notify(_ title: String, _ body: String) {
    let c = UNUserNotificationCenter.current()
    c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
        guard ok else { return }
        let n = UNMutableNotificationContent()
        n.title = title
        n.body = body
        c.add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil))
    }
}
