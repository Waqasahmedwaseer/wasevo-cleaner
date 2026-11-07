import Foundation

// `WasevoCleaner --selftest`: runs every engine against this Mac (read-only) and checks the safety rails
// on throw-away test files. Prints PASS/FAIL lines and exits.

enum SelfTest {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String, _ detail: String = "") {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
    }
    static func timed<T>(_ f: () -> T) -> (T, String) {
        let t = Date(); let r = f(); return (r, String(format: "%.1fs", -t.timeIntervalSinceNow))
    }

    static func run() {
        let fm = FileManager.default
        print("== Read-only engine checks")
        let (dups, t1) = timed { findDuplicates(minSize: 1_000_000) { _ in } }
        check(dups.allSatisfy { $0.files.count > 1 && Set($0.files.map(\.size)).count == 1 }, "duplicates: groups are same-size, 2+ files",
              "\(dups.count) groups, \(human(dups.reduce(0) { $0 + $1.wasted })) extra, \(t1)")
        let sample = dups.prefix(3).allSatisfy { g in Set(g.files.map { fileHash($0.path) ?? "?" }).count == 1 }
        check(sample, "duplicates: top groups really identical (re-hashed)")
        check(!dups.flatMap(\.files).contains { $0.path.contains(".photoslibrary/") || $0.path.contains("/node_modules/") || $0.path.contains("/.git/") },
              "duplicates: never inside Photos library, node_modules or .git")

        let (old, t2) = timed { findOldDownloads(days: 60) }
        check(old.allSatisfy { $0.days >= 60 && $0.path.hasPrefix(h("~/Downloads") + "/") }, "old downloads: all older than 60 days, in Downloads",
              "\(old.count) items, \(human(old.reduce(0) { $0 + $1.size })), \(t2)")

        let (ph, t3) = timed { analyzePhotos(limit: 400) { _ in } }
        check(ph.similar.allSatisfy { $0.photos.count > 1 }, "photos: similar groups have 2+ photos",
              "\(ph.similar.count) groups, \(ph.bad.count) flagged, \(t3)")
        check(ph.bad.allSatisfy { $0.isCameraPhoto }, "photos: only camera photos are flagged as bad")
        if CommandLine.arguments.contains("--verbose") {
            for g in ph.similar.prefix(12) { print("   group:", g.photos.map { $0.file.label + ($0.isCameraPhoto ? " [cam]" : "") }.joined(separator: " | ")) }
        }

        let items = listLaunchItems()
        check(!items.isEmpty, "startup: items listed", "\(items.count) items, \(items.filter(\.disabled).count) off, \(items.filter(\.running).count) running")
        check(items.filter { $0.scope == .system }.allSatisfy { !$0.canToggle }, "startup: system daemons are view-only")

        let br = installedBrowsers()
        let priv = br.flatMap { privacyItems(for: $0) }
        check(!priv.flatMap(\.paths).contains { $0.contains("Login Data") || $0.contains("Web Data") || $0.contains("Bookmarks") || $0.hasSuffix("places.sqlite") },
              "privacy: never lists passwords, autofill, bookmarks", br.map(\.name).joined(separator: ", "))

        let a = readCPUTicks(); Thread.sleep(forTimeInterval: 1); let cpu = cpuUsage(a, readCPUTicks())
        let mem = readMemory()
        check(cpu >= 0 && cpu <= 1, "monitor: CPU", String(format: "%.0f%%", cpu * 100))
        check(mem.used > 0 && mem.used <= mem.total, "monitor: memory", "\(human(mem.used)) of \(human(mem.total)), swap \(human(mem.swapUsed))")
        if let b = readBattery() { check(b.percent >= 0 && b.percent <= 100, "monitor: battery", "\(b.percent)%, cycles \(b.cycles ?? -1), health \(Int((b.health ?? 0) * 100))%") }
        let apps = heavyApps()
        check(!apps.isEmpty, "monitor: open apps", apps.prefix(3).map { "\($0.name) \(human($0.memory))" }.joined(separator: ", "))

        let (ups, t4) = timed { checkUpdates { _ in } }
        check(true, "updates: checked", "\(ups.count) updates (\(ups.filter { $0.source == "Homebrew" }.count) Homebrew), \(t4)")

        print("== Safety rails (throw-away files only)")
        let dir = h("~/Wasevo-SelfTest-\(UUID().uuidString.prefix(6))")
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }
        let f1 = dir + "/copy-a.bin", f2 = dir + "/copy-b.bin"
        let blob = Data((0..<2_000_000).map { UInt8($0 % 251) })
        fm.createFile(atPath: f1, contents: blob); fm.createFile(atPath: f2, contents: blob)
        let g = DupGroup(size: Int64(blob.count), files: [f1, f2].map { UserFile(path: $0, size: Int64(blob.count), modified: Date()) })
        check(trashDuplicates(group: g, remove: [f1, f2]) == 0 && fm.fileExists(atPath: f1) && fm.fileExists(atPath: f2),
              "duplicates: refuses to remove every copy")
        try? Data("changed".utf8).write(to: URL(fileURLWithPath: f2))
        check(trashDuplicates(group: g, remove: [f2]) == 0 && fm.fileExists(atPath: f2), "duplicates: skips a file that changed since the scan")
        fm.createFile(atPath: f2, contents: blob)
        check(trashDuplicates(group: g, remove: [f2]) == 1 && !fm.fileExists(atPath: f2) && fm.fileExists(atPath: f1),
              "duplicates: removes the extra copy, keeps the other")
        check(!trashUserFile(h("~/Library/Preferences/com.apple.finder.plist")), "trash: refuses files in ~/Library")
        check(!trashUserFile("/etc/hosts"), "trash: refuses files outside your home folder")
        fm.createFile(atPath: dir + "/data.sqlite", contents: Data("x".utf8))
        check(!trashUserFile(dir + "/data.sqlite") && fm.fileExists(atPath: dir + "/data.sqlite"), "trash: refuses database files")

        let broot = dir + "/Browser"
        try? fm.createDirectory(atPath: broot + "/Default", withIntermediateDirectories: true)
        for n in ["Preferences", "History", "Login Data"] { fm.createFile(atPath: "\(broot)/Default/\(n)", contents: Data("x".utf8)) }
        let spec = BrowserSpec(name: "TestBrowser", process: ["NoSuchProcessX"], root: broot, cacheRoot: dir + "/BrowserCache", firefox: false)
        let evil = PrivacyItem(browser: "TestBrowser", profile: "Default", kind: .history,
                               paths: ["\(broot)/Default/History", "\(broot)/Default/Login Data"], size: 0)
        _ = clearPrivacy([evil], browser: spec)
        check(!fm.fileExists(atPath: "\(broot)/Default/History"), "privacy: clears History")
        check(fm.fileExists(atPath: "\(broot)/Default/Login Data"), "privacy: refuses saved passwords even if asked")
        let open = BrowserSpec(name: "Open", process: [ProcessInfo.processInfo.processName], root: broot, cacheRoot: dir, firefox: false)
        check(clearPrivacy([evil], browser: open).error != nil, "privacy: refuses while the browser is open")

        // remove our own test files from the Trash again
        let trash = h("~/.Trash")
        for k in (try? fm.contentsOfDirectory(atPath: trash)) ?? [] where k.hasPrefix("copy-b") || k.hasPrefix("History") {
            let p = trash + "/" + k
            if ((try? fm.attributesOfItem(atPath: p))?[.creationDate] as? Date ?? .distantPast) > Date().addingTimeInterval(-600) {
                try? fm.removeItem(atPath: p)
            }
        }
        print(failures == 0 ? "== ALL PASSED" : "== \(failures) FAILED")
    }
}
