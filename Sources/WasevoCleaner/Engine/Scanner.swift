import Foundation

// Wasevo Cleaner — measuring sizes, finding project build folders, and knowing what is in use.

func dirSize(_ path: String) -> Int64 {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
    if !isDir.boolValue {
        let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys)
        return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
    }
    var total: Int64 = 0
    if let en = fm.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: Array(keys),
                              options: [], errorHandler: { _, _ in true }) {
        for case let u as URL in en {
            let v = try? u.resourceValues(forKeys: keys)
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
    }
    return total
}

/// What is running right now: process names, executable paths, and working directories.
struct ProcSnapshot {
    let names: Set<String>
    let exePaths: [String]
    let cwds: [String]

    static func take() -> ProcSnapshot {
        var names = Set<String>(), exes: [String] = []
        for line in sh("ps -axo comm=", timeout: 10).out.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { continue }
            exes.append(s)
            names.insert((s as NSString).lastPathComponent)
        }
        let cwds = sh("lsof -a -d cwd -Fn 2>/dev/null", timeout: 20).out
            .split(separator: "\n").filter { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
        return ProcSnapshot(names: names, exePaths: exes, cwds: cwds)
    }

    func running(_ list: [String]) -> String? { list.first { names.contains($0) } }
    func hasExe(inside dir: String) -> Bool { exePaths.contains { $0.hasPrefix(dir + "/") } }
    func hasCwd(inside dir: String) -> Bool { cwds.contains { $0 == dir || $0.hasPrefix(dir + "/") } }
}

struct Artifact {
    let path: String
    let kind: String        // "node_modules", "Rust target", ".next", …
    let project: String
    let size: Int64
    let lastEdit: Date
    let blocked: String?

    var ageDays: Int { max(0, Int(-lastEdit.timeIntervalSinceNow / 86400)) }
    var stale: Bool { Double(ageDays) >= Prefs.staleDays }
    var projectLabel: String {
        let rel = project.hasPrefix(home + "/") ? String(project.dropFirst(home.count + 1)) : project
        let parts = rel.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }
}

let ARTIFACT_DIRS: Set<String> = ["node_modules", ".next", ".nuxt", ".turbo", ".svelte-kit"]
let SKIP_DIRS: Set<String> = [".git", "vendor", "Library", ".Trash", "Pods", ".venv", "venv", "__pycache__"]
let LOCKFILES = ["package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb", "bun.lock"]

/// node_modules is only safe to delete when a lockfile can reinstall the exact same packages.
func hasLockfile(from dir: String) -> Bool {
    let fm = FileManager.default
    var d = URL(fileURLWithPath: dir)
    for _ in 0..<8 {
        if LOCKFILES.contains(where: { fm.fileExists(atPath: d.appendingPathComponent($0).path) }) { return true }
        if fm.fileExists(atPath: d.appendingPathComponent(".git").path) { break }
        let up = d.deletingLastPathComponent()
        if up.path == d.path || up.path == home { break }
        d = up
    }
    return false
}

/// Newest edit among the project's own files (build folders ignored).
func lastEdit(of project: String) -> Date {
    let fm = FileManager.default
    var newest = Date.distantPast
    func consider(_ dir: String) {
        guard let kids = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for k in kids where !ARTIFACT_DIRS.contains(k) && !k.hasPrefix("target") && k != ".git" && k != ".DS_Store" {
            let p = (dir as NSString).appendingPathComponent(k)
            if let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, m > newest { newest = m }
        }
    }
    consider(project)
    for sub in ["src", "app", "resources", "pages", "lib", "components", "routes"] {
        consider((project as NSString).appendingPathComponent(sub))
    }
    return newest == .distantPast ? Date() : newest
}

func blockReason(path: String, project: String, isRust: Bool, snap: ProcSnapshot) -> String? {
    if snap.hasExe(inside: path) { return "an app is running from it" }
    if isRust, let p = snap.running(["cargo", "rustc"]) { return "\(p) is running" }
    if snap.hasCwd(inside: project) { return "a terminal/dev server is open in it" }
    return nil
}

func scanProjects(snap: ProcSnapshot) -> [Artifact] {
    let fm = FileManager.default
    var out: [Artifact] = []
    for root in Prefs.projectRoots.map(h) where fm.fileExists(atPath: root) {
        guard let en = fm.enumerator(at: URL(fileURLWithPath: root),
                                     includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                     options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
        for case let u as URL in en {
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard v?.isDirectory == true, v?.isSymbolicLink != true else { continue }
            if en.level > 7 { en.skipDescendants(); continue }
            let name = u.lastPathComponent
            if SKIP_DIRS.contains(name) { en.skipDescendants(); continue }
            let isRust = name == "target" || name.hasPrefix("target-")
            guard isRust || ARTIFACT_DIRS.contains(name) else { continue }
            en.skipDescendants()

            let project = u.deletingLastPathComponent().path
            let has = { (f: String) in fm.fileExists(atPath: (project as NSString).appendingPathComponent(f)) }
            let kind: String
            if isRust {
                guard has("Cargo.toml") else { continue }
                kind = "Rust target"
            } else if name == "node_modules" {
                guard has("package.json"), hasLockfile(from: project) else { continue }
                kind = "node_modules"
            } else {
                guard has("package.json") else { continue }
                kind = name
            }
            let size = dirSize(u.path)
            guard size >= MIN_ARTIFACT_BYTES else { continue }
            out.append(Artifact(path: u.path, kind: kind, project: project, size: size,
                                lastEdit: lastEdit(of: project),
                                blocked: blockReason(path: u.path, project: project, isRust: isRust, snap: snap)))
        }
    }
    return out.sorted { $0.size > $1.size }
}

func availableTools() -> Set<String> {
    let bins = TOOL_TASKS.map(\.binary).joined(separator: " ")
    let out = sh("for b in \(bins); do command -v $b >/dev/null 2>&1 && echo $b; done", timeout: 15).out
    return Set(out.split(separator: "\n").map(String.init))
}

struct BigFile {
    let path: String
    let realSize: Int64     // bytes actually on disk (sparse files like Docker.raw report far less than ls)
    let shownSize: Int64    // size Finder/other cleaners show
    var protected: String? { protectedReason(path) }
}

/// View-only: the biggest files in your home folder, with their REAL on-disk size.
func scanBigFiles(limit: Int = 25) -> [BigFile] {
    let out = sh("mdfind -onlyin \"$HOME\" 'kMDItemFSSize > 500000000'", timeout: 30).out
    let fm = FileManager.default
    var files: [BigFile] = []
    for line in out.split(separator: "\n") {
        let p = String(line)
        var isDir: ObjCBool = false
        guard !p.contains("/Library/CloudStorage/"), fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue else { continue }
        let shown = ((try? fm.attributesOfItem(atPath: p))?[.size] as? NSNumber)?.int64Value ?? 0
        files.append(BigFile(path: p, realSize: dirSize(p), shownSize: shown))
    }
    return Array(files.sorted { $0.realSize > $1.realSize }.prefix(limit))
}

/// Reclaimable Docker build cache, or nil when Docker is not running.
func dockerBuildCache() -> String? {
    let r = sh("docker system df --format '{{.Type}}|{{.Reclaimable}}'", timeout: 10)
    guard r.code == 0 else { return nil }
    for line in r.out.split(separator: "\n") {
        let parts = line.split(separator: "|")
        if parts.count == 2 && parts[0] == "Build Cache" { return String(parts[1]) }
    }
    return "0B"
}
