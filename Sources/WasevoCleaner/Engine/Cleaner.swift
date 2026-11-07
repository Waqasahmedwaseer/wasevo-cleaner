import Foundation

// Wasevo Cleaner — shell helper, deletion with safety rails, logging.

/// Run a command through a login zsh with a hard timeout. Never blocks forever.
@discardableResult
func sh(_ cmd: String, timeout: TimeInterval = 120) -> (code: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", "export PATH=\"$HOME/Library/pnpm:/usr/local/bin:/opt/homebrew/bin:$PATH\"; " + cmd]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    var data = Data()
    let done = DispatchSemaphore(value: 0)
    do { try p.run() } catch { return (-1, error.localizedDescription) }
    DispatchQueue.global().async {
        data = pipe.fileHandleForReading.readDataToEndOfFile()
        done.signal()
    }
    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    if p.isRunning {
        p.terminate()
        _ = done.wait(timeout: .now() + 2)
        return (-2, "timed out after \(Int(timeout))s")
    }
    _ = done.wait(timeout: .now() + 5)
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

func volumeFree() -> Int64 {
    let v = try? URL(fileURLWithPath: home).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return v?.volumeAvailableCapacityForImportantUsage ?? 0
}

func human(_ b: Int64) -> String {
    if b <= 0 { return "empty" }
    let u = ["B", "KB", "MB", "GB", "TB"]
    var d = Double(b), i = 0
    while d >= 1000 && i < u.count - 1 { d /= 1000; i += 1 }  // decimal, like Finder
    return String(format: i >= 3 ? "%.1f %@" : "%.0f %@", d, u[i])
}

func log(_ s: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(s)\n"
    if let fh = FileHandle(forWritingAtPath: LOG_PATH) {
        fh.seekToEndOfFile()
        fh.write(Data(line.utf8))
        fh.closeFile()
    } else {
        try? line.write(toFile: LOG_PATH, atomically: true, encoding: .utf8)
    }
}

enum DeleteMode { case permanent, trash }

/// Last line of defence: refuse anything that is not clearly a cache/build folder.
func isSafeTarget(_ path: String) -> Bool {
    let p = (path as NSString).standardizingPath
    let protected = [home, h("~/Documents"), h("~/Desktop"), h("~/Downloads"), h("~/Library"),
                     h("~/Library/Application Support"), h("~/Local Sites"), h("~/.cargo"), h("~/.npm")]
    if p.isEmpty || protected.contains(p) { return false }
    if p.contains("/.git/") || p.hasSuffix("/.git") { return false }
    if protectedReason(p) != nil || protectedReason(p + "/") != nil { return false }
    let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory()).deletingLastPathComponent().path
    return p.hasPrefix(home + "/") || p.hasPrefix(tmpRoot + "/") || p.hasPrefix("/private" + tmpRoot + "/")
}

@discardableResult
func removePath(_ path: String, _ mode: DeleteMode) -> Bool {
    guard isSafeTarget(path) else { log("REFUSED (unsafe path) \(path)"); return false }
    let fm = FileManager.default
    guard fm.fileExists(atPath: path) else { return true }
    do {
        if mode == .trash {
            try trashWithUndo(URL(fileURLWithPath: path))
        } else {
            try fm.removeItem(atPath: path)
        }
        log("\(mode == .trash ? "TRASHED" : "DELETED") \(path)")
        return true
    } catch {
        log("FAILED \(path): \(error.localizedDescription)")
        return false
    }
}

/// The concrete items a rule would remove (respecting skip/extension/age/depth filters).
func ruleTargets(_ r: CacheRule) -> [String] {
    let fm = FileManager.default
    var out: [String] = []
    func walk(_ dir: String, _ level: Int) {
        for k in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
            if k == ".DS_Store" || r.skipPrefixes.contains(where: { k.hasPrefix($0) })
                || r.skipContaining.contains(where: { k.contains($0) }) { continue }
            let p = (dir as NSString).appendingPathComponent(k)
            if level < r.depth {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue { walk(p, level + 1) }
                continue
            }
            if !r.onlyExtensions.isEmpty && !r.onlyExtensions.contains((k as NSString).pathExtension.lowercased()) { continue }
            if r.olderThanDays > 0 {
                let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date ?? Date()
                if -m.timeIntervalSinceNow < r.olderThanDays * 86400 { continue }
            }
            if protectedReason(p) != nil { continue }
            out.append(p)
        }
    }
    for raw in r.paths {
        let full = h(raw)
        guard fm.fileExists(atPath: full) else { continue }
        if r.contentsOnly { walk(full, 1) } else if protectedReason(full) == nil { out.append(full) }
    }
    return out
}

func ruleSize(_ r: CacheRule) -> Int64 { ruleTargets(r).reduce(0) { $0 + dirSize($1) } }

/// Clears one cache rule. Returns how many items could not be removed.
func clearRule(_ r: CacheRule, _ mode: DeleteMode) -> Int {
    ruleTargets(r).filter { !removePath($0, mode) }.count
}

func volumeTotal() -> Int64 {
    let v = try? URL(fileURLWithPath: home).resourceValues(forKeys: [.volumeTotalCapacityKey])
    return Int64(v?.volumeTotalCapacity ?? 0)
}

/// "12.26GB" / "585.3MB" (docker style) → bytes.
func parseSize(_ s: String) -> Int64 {
    let t = s.trimmingCharacters(in: .whitespaces).uppercased()
    let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("B", 1)]
    for (u, m) in units where t.hasSuffix(u) {
        return Int64((Double(t.dropLast(u.count).trimmingCharacters(in: .whitespaces)) ?? 0) * m)
    }
    return 0
}
