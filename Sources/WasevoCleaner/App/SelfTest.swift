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

        // Build-folder rules: offered only when the project can rebuild them, never when committed to git.
        let bt = NSTemporaryDirectory() + "wasevo-rules-\(UUID().uuidString.prefix(6))"
        let mk = { (rel: String, file: Bool) in
            let p = bt + "/" + rel
            if file { try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                      FileManager.default.createFile(atPath: p, contents: Data("x".utf8)) }
            else { try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true) }
        }
        mk("laravel/composer.json", true); mk("laravel/composer.lock", true); mk("laravel/vendor", false)
        mk("nolock/composer.json", true); mk("nolock/vendor", false)
        mk("py/uv.lock", true); mk("py/.venv", false); mk("pyloose/requirements.txt", true); mk("pyloose/.venv", false)
        mk("flutter/pubspec.yaml", true); mk("flutter/build", false); mk("plain/build", false)
        mk("android/app/build.gradle.kts", true); mk("android/app/build", false)
        check(matchBuildRule(name: "vendor", project: bt + "/laravel")?.kind == "PHP vendor", "projects: PHP vendor with composer.lock is rebuildable")
        check(matchBuildRule(name: "vendor", project: bt + "/nolock") == nil, "projects: vendor without composer.lock is left alone")
        check(matchBuildRule(name: ".venv", project: bt + "/py")?.kind == "Python venv", "projects: venv with a lockfile is rebuildable")
        check(matchBuildRule(name: ".venv", project: bt + "/pyloose") == nil, "projects: venv with only requirements.txt is left alone")
        check(matchBuildRule(name: "build", project: bt + "/flutter")?.kind == "Flutter build" && matchBuildRule(name: "build", project: bt + "/plain") == nil,
              "projects: a plain build folder is never offered")
        check(matchBuildRule(name: "build", project: bt + "/android/app")?.kind == "Gradle build", "projects: Gradle build folder detected")
        _ = sh("cd '\(bt)/laravel' && git init -q && mkdir -p vendor/a && echo x > vendor/a/f && git add vendor && git -c user.email=t@t -c user.name=t commit -qm t", timeout: 20)
        check(isTrackedInGit(bt + "/laravel/vendor", project: bt + "/laravel"), "projects: a build folder committed to git is detected (and skipped)")
        // Old editor extension versions: only ones the editor marked obsolete and no longer lists as installed.
        mk("ext/pub.tool-1.0.0", false); mk("ext/pub.tool-1.1.0", false); mk("ext/pub.other-2.0.0", false)
        try? Data(#"{"pub.tool-1.0.0":true,"pub.other-2.0.0":true}"#.utf8).write(to: URL(fileURLWithPath: bt + "/ext/.obsolete"))
        try? Data(#"[{"identifier":{"id":"pub.tool"},"relativeLocation":"pub.tool-1.1.0"},{"identifier":{"id":"pub.other"},"relativeLocation":"pub.other-2.0.0"}]"#.utf8)
            .write(to: URL(fileURLWithPath: bt + "/ext/extensions.json"))
        check(isObsoleteExtension(bt + "/ext/pub.tool-1.0.0") && !isObsoleteExtension(bt + "/ext/pub.tool-1.1.0")
              && !isObsoleteExtension(bt + "/ext/pub.other-2.0.0"), "extensions: only replaced versions are offered, never the installed one")
        try? FileManager.default.removeItem(atPath: bt)
        let extRule = CACHE_RULES.first { $0.name == "Old editor extension versions" }!
        check(true, "extensions: live", "\(ruleTargets(extRule).count) old versions, \(human(ruleSize(extRule)))")

        let (arts, t6) = timed { scanProjects(snap: ProcSnapshot.take()) }
        var byKind: [String: (Int, Int64)] = [:]
        for x in arts { let e = byKind[x.kind] ?? (0, 0); byKind[x.kind] = (e.0 + 1, e.1 + x.size) }
        check(!arts.contains { $0.kind == "PHP vendor" && isTrackedInGit($0.path, project: $0.project) }, "projects: live scan", "\(arts.count) build folders, \(human(arts.reduce(0) { $0 + $1.size })), \(t6)")
        for (k, v) in byKind.sorted(by: { $0.value.1 > $1.value.1 }) { print("     · \(k) ×\(v.0)  \(human(v.1))") }

        // Running Services: parsers on fixed lsof output, then a live scan (read-only).
        let held = parseHidden("p100\nf5w\ns94600000000\ni42\nn/private/tmp/x/mysqld.log\nf6w\ns94600000000\ni42\nn/private/tmp/x/mysqld.log\np200\nf3r\ns1000\ni7\nn/tmp/small\n")
        check(held[100]?.bytes == 94_600_000_000 && held[100]?.files.count == 1, "services: held space counts a file opened twice once")
        let ports = parseListening("p300\nn127.0.0.1:3399\nn*:3399\nn[::1]:5173\n")
        check(ports[300] == [3399, 5173], "services: listening ports parsed", "\(ports[300] ?? [])")
        let longRun: TimeInterval = 183_845
        check(parseElapsed("2-03:04:05") == longRun && parseElapsed("04:05") == 245, "services: elapsed time parsed")
        let orphan = analyze(name: "mysqld", command: "mysqld --datadir=/private/tmp/gone-\(UUID().uuidString)/data --port=3399", kind: .database,
                             cwd: "/", ppid: 1, cpu: 40, runningFor: 3600, written: 95_000_000_000, hidden: 94_600_000_000)
        check(orphan.contains { $0.level == .problem && $0.text.contains("data folder was deleted") }, "services: deleted data folder flags a leftover")
        check(orphan.contains { $0.level == .problem && $0.text.contains("deleted files") }, "services: held deleted files are flagged")
        let healthy = analyze(name: "mysqld", command: "mysqld --datadir=/usr/local/var/mysql", kind: .database, cwd: "/usr/local/var/mysql",
                              ppid: 1, cpu: 1, runningFor: 3600, written: 1_000, hidden: 0, fileExists: { _ in true })
        check(!healthy.contains { $0.level == .problem }, "services: a normal database is not called a leftover")
        let (svcs, t5) = timed { scanServices() }
        check(!svcs.contains { $0.pid == ProcessInfo.processInfo.processIdentifier }, "services: live scan",
              "\(svcs.count) running, \(svcs.filter(\.isLeftover).count) leftovers, \(human(svcs.reduce(0) { $0 + $1.hiddenSpace })) held, \(t5)")
        // End to end: a throw-away process keeps a 60 MB deleted file open from a deleted folder (last night's case, small).
        let tdir = NSTemporaryDirectory() + "wasevo-held-\(UUID().uuidString.prefix(6))"
        try? FileManager.default.createDirectory(atPath: tdir, withIntermediateDirectories: true)
        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/bin/sh")
        holder.currentDirectoryURL = URL(fileURLWithPath: tdir)
        holder.arguments = ["-c", "dd if=/dev/zero of=held.bin bs=1048576 count=60 2>/dev/null; exec 3<held.bin; rm held.bin; cd /; rmdir \(tdir); exec sleep 120"]
        try? holder.run()
        Thread.sleep(forTimeInterval: 2)
        if let found = scanServices().first(where: { $0.pid == holder.processIdentifier }) {
            check(found.isLeftover && found.hiddenSpace >= 60_000_000, "services: catches a process holding a deleted file",
                  "\(human(found.hiddenSpace)) held, \(found.warnings.count) warnings")
            if case .stopped = stopService(found, force: false) { check(!holder.isRunning || kill(holder.processIdentifier, 0) != 0, "services: Stop ends it") }
            else { check(false, "services: Stop ends it") }
        } else {
            check(false, "services: catches a process holding a deleted file", "not found")
        }
        if holder.isRunning { holder.terminate() }
        for s in svcs.prefix(12) { print("     · \(s.name) [\(s.kind.label)] ports \(s.ports) cpu \(Int(s.cpu))% mem \(human(s.memory)) wrote \(human(s.diskWritten)) held \(human(s.hiddenSpace)) \(s.isLeftover ? "LEFTOVER" : "")") }

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

        // updater: version compare and GitHub release parsing
        check(isNewer("0.10.0", than: "0.9.1") && !isNewer("0.5.0", than: "0.5.0") && !isNewer("0.6.0", than: "dev"), "update: version compare")
        let json = #"{"tag_name":"v0.6.0","html_url":"https://github.com/x/y/releases/tag/v0.6.0","body":"notes","assets":[{"name":"W.dmg","size":5,"digest":"sha256:ABC","browser_download_url":"https://github.com/x/y/releases/download/v0.6.0/W.dmg"}]}"#
        let rel = SelfUpdate.parse(Data(json.utf8))
        check(rel?.version == "0.6.0" && rel?.sha256 == "abc" && rel?.size == 5, "update: parses GitHub release")
        let evilJSON = json.replacingOccurrences(of: "https://github.com/x/y/releases/download", with: "https://evil.example")
        check(SelfUpdate.parse(Data(evilJSON.utf8)) == nil, "update: refuses downloads not hosted on GitHub")

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
