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

func blockReason(path: String, project: String, kind: String, snap: ProcSnapshot) -> String? {
    if snap.hasExe(inside: path) { return "an app is running from it" }
    if let tools = buildRule(forKind: kind)?.blockIfRunning, !tools.isEmpty, let p = snap.running(tools) { return "\(p) is running" }
    if snap.hasCwd(inside: project) { return "a terminal/dev server is open in it" }
    return nil
}

/// One kind of rebuildable build folder. It is offered only when the files that rebuild it sit next to it
/// (`needs`: all of them, `needsAny`: at least one), and never when the folder is committed to git.
struct BuildRule {
    let dir: String                 // folder name (or prefix when `prefix` is true)
    let kind: String
    var needs: [String] = []
    var needsAny: [String] = []
    var prefix = false
    let rebuild: String             // how you get it back
    var blockIfRunning: [String] = []
}

let BUILD_RULES: [BuildRule] = [
    BuildRule(dir: "node_modules", kind: "node_modules", needs: ["package.json"], rebuild: "npm / pnpm / yarn install"),
    BuildRule(dir: ".next", kind: ".next", needs: ["package.json"], rebuild: "next build or next dev"),
    BuildRule(dir: ".nuxt", kind: ".nuxt", needs: ["package.json"], rebuild: "nuxt dev or nuxt build"),
    BuildRule(dir: ".output", kind: "Nuxt output", needs: ["package.json"], needsAny: ["nuxt.config.ts", "nuxt.config.js", "nuxt.config.mjs"], rebuild: "nuxt build"),
    BuildRule(dir: ".turbo", kind: ".turbo", needs: ["package.json"], rebuild: "the next turbo run"),
    BuildRule(dir: ".svelte-kit", kind: ".svelte-kit", needs: ["package.json"], rebuild: "vite dev or vite build"),
    BuildRule(dir: ".parcel-cache", kind: "Parcel cache", needs: ["package.json"], rebuild: "the next parcel build"),
    BuildRule(dir: ".angular", kind: "Angular cache", needs: ["angular.json"], rebuild: "the next ng build"),
    BuildRule(dir: ".expo", kind: "Expo cache", needs: ["package.json"], rebuild: "the next expo start"),
    BuildRule(dir: ".docusaurus", kind: "Docusaurus cache", needs: ["package.json"], rebuild: "the next docusaurus build"),
    BuildRule(dir: "target", kind: "Rust target", needs: ["Cargo.toml"], prefix: true, rebuild: "cargo build", blockIfRunning: ["cargo", "rustc"]),
    BuildRule(dir: "vendor", kind: "PHP vendor", needs: ["composer.json", "composer.lock"], rebuild: "composer install", blockIfRunning: ["composer"]),
    BuildRule(dir: ".venv", kind: "Python venv", needsAny: ["uv.lock", "poetry.lock", "Pipfile.lock", "pdm.lock"], rebuild: "uv sync / poetry install / pipenv install"),
    BuildRule(dir: "venv", kind: "Python venv", needsAny: ["uv.lock", "poetry.lock", "Pipfile.lock", "pdm.lock"], rebuild: "uv sync / poetry install / pipenv install"),
    BuildRule(dir: "Pods", kind: "CocoaPods", needs: ["Podfile.lock"], rebuild: "pod install", blockIfRunning: ["pod", "xcodebuild"]),
    BuildRule(dir: ".build", kind: "Swift build", needs: ["Package.swift"], rebuild: "swift build", blockIfRunning: ["swift-build", "swift-frontend"]),
    BuildRule(dir: ".dart_tool", kind: "Dart tool", needs: ["pubspec.yaml"], rebuild: "flutter pub get"),
    BuildRule(dir: "build", kind: "Flutter build", needs: ["pubspec.yaml"], rebuild: "flutter build"),
    BuildRule(dir: "build", kind: "Gradle build", needsAny: ["build.gradle", "build.gradle.kts"], rebuild: "the next Gradle build"),
    BuildRule(dir: ".gradle", kind: "Gradle project cache", needsAny: ["settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts"], rebuild: "the next Gradle build"),
    BuildRule(dir: "_build", kind: "Elixir build", needs: ["mix.exs"], rebuild: "mix compile"),
    BuildRule(dir: "deps", kind: "Elixir deps", needs: ["mix.exs", "mix.lock"], rebuild: "mix deps.get"),
    BuildRule(dir: ".zig-cache", kind: "Zig cache", needs: ["build.zig"], rebuild: "zig build"),
    BuildRule(dir: "zig-cache", kind: "Zig cache", needs: ["build.zig"], rebuild: "zig build"),
    BuildRule(dir: "cmake-build-", kind: "CMake build", needs: ["CMakeLists.txt"], prefix: true, rebuild: "the next CMake build"),
]
private let BUILD_DIR_NAMES = Set(BUILD_RULES.filter { !$0.prefix }.map(\.dir))

func buildRule(forKind k: String) -> BuildRule? { BUILD_RULES.first { $0.kind == k } }
func rebuildHint(_ kind: String) -> String { buildRule(forKind: kind).map { "Rebuilt by \($0.rebuild)." } ?? "Rebuilt on the next build." }

/// The rule a folder matches, if its project really can rebuild it.
func matchBuildRule(name: String, project: String) -> BuildRule? {
    let fm = FileManager.default
    let has = { (f: String) in fm.fileExists(atPath: (project as NSString).appendingPathComponent(f)) }
    for r in BUILD_RULES where r.prefix ? name.hasPrefix(r.dir) : name == r.dir {
        guard r.needs.allSatisfy(has), r.needsAny.isEmpty || r.needsAny.contains(where: has) else { continue }
        if r.dir == "node_modules" && !hasLockfile(from: project) { continue }
        return r
    }
    return nil
}

/// A build folder that is committed to git is part of the source; never offer it.
func isTrackedInGit(_ path: String, project: String) -> Bool {
    let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    let r = sh("git -C \(q(project)) ls-files -- \(q(path)) 2>/dev/null | head -1", timeout: 10)
    return r.code == 0 && !r.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            let candidate = BUILD_DIR_NAMES.contains(name) || name.hasPrefix("target-") || name.hasPrefix("cmake-build-")
            let project = u.deletingLastPathComponent().path
            if candidate, let rule = matchBuildRule(name: name, project: project) {
                en.skipDescendants()
                guard !isTrackedInGit(u.path, project: project) else { continue }
                let size = dirSize(u.path)
                guard size >= MIN_ARTIFACT_BYTES else { continue }
                out.append(Artifact(path: u.path, kind: rule.kind, project: project, size: size,
                                    lastEdit: lastEdit(of: project),
                                    blocked: blockReason(path: u.path, project: project, kind: rule.kind, snap: snap)))
                continue
            }
            if SKIP_DIRS.contains(name) || ARTIFACT_DIRS.contains(name) || (name.hasPrefix(".") && name != ".claude") { en.skipDescendants() }
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
