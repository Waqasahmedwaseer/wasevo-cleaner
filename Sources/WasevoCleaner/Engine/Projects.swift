import Foundation

// Wasevo Cleaner — Projects: every project's size, build files and last edit, with safe actions.

let PROJECT_MARKERS = ["package.json", "Cargo.toml", "composer.json", "pyproject.toml", "go.mod", "pubspec.yaml",
                       "Gemfile", "build.gradle", "build.gradle.kts", "Package.swift", "mix.exs", "build.zig", "CMakeLists.txt", "Podfile", ".git"]
let ARCHIVE_DIR = h("~/Wasevo Archives")

struct Project: Identifiable {
    var id: String { path }
    let path: String
    let size: Int64
    let buildFiles: [Artifact]
    let lastEdit: Date
    let isGit: Bool
    let uncommitted: Bool
    let inUse: Bool

    var name: String { (path as NSString).lastPathComponent }
    var label: String { path.replacingOccurrences(of: home, with: "~") }
    var buildSize: Int64 { buildFiles.filter { $0.blocked == nil }.reduce(0) { $0 + $1.size } }
    var ageDays: Int { max(0, Int(-lastEdit.timeIntervalSinceNow / 86400)) }
    var stale: Bool { Double(ageDays) >= Prefs.staleDays }
}

/// Project folders under your project roots (a folder with package.json, Cargo.toml, .git, …). Not nested.
func findProjectDirs() -> [String] {
    let fm = FileManager.default
    var out: [String] = []
    func visit(_ dir: String, _ level: Int) {
        guard level <= 4, let kids = try? fm.contentsOfDirectory(atPath: dir) else { return }
        let isProject = PROJECT_MARKERS.contains(where: { kids.contains($0) }) || kids.contains(where: { $0.hasSuffix(".xcodeproj") })
        if level > 0 && isProject { out.append(dir); return }
        for k in kids where !k.hasPrefix(".") && !SKIP_DIRS.contains(k) && !ARTIFACT_DIRS.contains(k) {
            let p = (dir as NSString).appendingPathComponent(k)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue,
               (try? fm.destinationOfSymbolicLink(atPath: p)) == nil, !k.hasSuffix(".app") { visit(p, level + 1) }
        }
    }
    for root in Prefs.projectRoots.map(h) where fm.fileExists(atPath: root) { visit(root, 0) }
    return out
}

func scanAllProjects(progress: @escaping (Int, Int) -> Void) -> [Project] {
    let snap = ProcSnapshot.take()
    let dirs = findProjectDirs()
    let artifacts = scanProjects(snap: snap)
    var out = [Project?](repeating: nil, count: dirs.count)
    let lock = NSLock()
    var done = 0
    DispatchQueue.concurrentPerform(iterations: dirs.count) { i in
        let d = dirs[i]
        let isGit = FileManager.default.fileExists(atPath: d + "/.git")
        let dirty = isGit && !sh("git -C \"\(d)\" status --porcelain 2>/dev/null | head -1", timeout: 15).out
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let p = Project(path: d, size: duSize(d),
                        buildFiles: artifacts.filter { $0.project == d || $0.project.hasPrefix(d + "/") },
                        lastEdit: lastEdit(of: d), isGit: isGit, uncommitted: dirty,
                        inUse: snap.hasCwd(inside: d) || snap.hasExe(inside: d))
        lock.lock(); out[i] = p; done += 1; let n = done; lock.unlock()
        progress(n, dirs.count)
    }
    return out.compactMap { $0 }.filter { $0.size > 1_000_000 }.sorted { $0.size > $1.size }
}

/// Zips the project (without node_modules/target/build folders), checks the zip, then moves the
/// original to the Trash. Returns the zip path, or an error message.
func archiveProject(_ p: Project) -> (zip: String?, error: String?) {
    let snap = ProcSnapshot.take()
    if snap.hasCwd(inside: p.path) || snap.hasExe(inside: p.path) { return (nil, "A terminal or app is using this project.") }
    try? FileManager.default.createDirectory(atPath: ARCHIVE_DIR, withIntermediateDirectories: true)
    let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
    let zip = "\(ARCHIVE_DIR)/\(p.name)-\(stamp).zip"
    let parent = (p.path as NSString).deletingLastPathComponent
    let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    // leave out only the exact build folders we found (they can be rebuilt), never anything else
    let excludes = p.buildFiles.map { a -> String in
        let rel = p.name + String(a.path.dropFirst(p.path.count))
        return "-x " + q(rel + "/*")
    }.joined(separator: " ")
    let r = sh("cd \(q(parent)) && rm -f \(q(zip)) && zip -r -y -q \(q(zip)) \(q(p.name)) \(excludes)", timeout: 1800)
    guard r.code == 0, FileManager.default.fileExists(atPath: zip) else {
        return (nil, "Could not create the zip: \(r.out.split(separator: "\n").last ?? "")")
    }
    guard sh("unzip -tq \(q(zip))", timeout: 600).code == 0 else {
        return (nil, "The zip failed its check, so the project was left in place.")
    }
    do {
        try trashWithUndo(URL(fileURLWithPath: p.path))
        log("ARCHIVED \(p.path) → \(zip) (original moved to Trash)")
        return (zip, nil)
    } catch {
        return (zip, "Zip saved, but the original could not be moved to the Trash: \(error.localizedDescription)")
    }
}

/// Removes a project's build folders (node_modules, target, .next…), re-checking that nothing uses them.
func cleanBuildFiles(_ p: Project, _ mode: DeleteMode) -> (freed: Int64, skipped: Int) {
    let snap = ProcSnapshot.take()
    var freed: Int64 = 0, skipped = 0
    for a in p.buildFiles {
        if blockReason(path: a.path, project: a.project, kind: a.kind, snap: snap) != nil { skipped += 1; continue }
        if removePath(a.path, mode) { freed += a.size } else { skipped += 1 }
    }
    return (freed, skipped)
}
