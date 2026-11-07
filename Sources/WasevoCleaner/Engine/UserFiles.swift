import Foundation
import CoreServices

// Wasevo Cleaner — your own files (duplicates, photos, old downloads).
// Rules: review screens only, nothing is pre-deleted, and everything goes to the Trash (restorable).

let USER_FILE_ROOTS = ["~/Downloads", "~/Desktop", "~/Documents", "~/Pictures", "~/Movies", "~/Music"]

/// A folder holding any of these is a project or website: its files belong together and are never offered
/// for removal one by one (e.g. two copies of a website share identical images, and both are needed).
let WORK_FOLDER_MARKERS: Set<String> = Set(PROJECT_MARKERS).union([
    "index.html", "index.htm", "index.php", "wp-config.php", "Dockerfile", "docker-compose.yml", "compose.yaml",
    "Makefile", "CMakeLists.txt", "requirements.txt", "setup.py", "pom.xml", "build.gradle.kts", "angular.json",
    "vite.config.js", "vite.config.ts", "manifest.json", ".project", "Podfile", "pubspec.yaml"])

struct UserFile: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let size: Int64
    let modified: Date
    var name: String { (path as NSString).lastPathComponent }
    var label: String { path.replacingOccurrences(of: home, with: "~") }
    var folderLabel: String { (label as NSString).deletingLastPathComponent }
}

/// Walks your folders and calls `visit` for each regular file.
/// Never enters: hidden folders, app/library bundles (Photos library, .app, …), project folders
/// (their files belong to the project), build folders, symlinks, and iCloud files that are not downloaded.
func walkUserFiles(roots: [String] = USER_FILE_ROOTS, minSize: Int64, exts: Set<String>? = nil,
                   limit: Int = 300_000, visit: (UserFile) -> Void) {
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                                  .totalFileAllocatedSizeKey, .contentModificationDateKey]
    var seen = 0
    for root in roots.map(h) where fm.fileExists(atPath: root) {
        guard let en = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: keys,
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                     errorHandler: { _, _ in true }) else { continue }
        for case let url as URL in en {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true { continue }
            if v.isDirectory == true {
                let name = url.lastPathComponent
                if ARTIFACT_DIRS.contains(name) || SKIP_DIRS.contains(name) || name == "target" || name == "build" {
                    en.skipDescendants(); continue
                }
                let kids = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
                if kids.contains(where: { WORK_FOLDER_MARKERS.contains($0) || $0.hasSuffix(".xcodeproj") }) { en.skipDescendants() }
                continue
            }
            guard v.isRegularFile == true else { continue }
            let size = Int64(v.fileSize ?? 0)
            if size < minSize { continue }
            // iCloud "optimized" files take no disk space; reading them would download them.
            if Int64(v.totalFileAllocatedSize ?? 0) < size / 4 { continue }
            if let exts, !exts.contains(url.pathExtension.lowercased()) { continue }
            if protectedReason(url.path) != nil { continue }
            visit(UserFile(path: url.path, size: size, modified: v.contentModificationDate ?? .distantPast))
            seen += 1
            if seen >= limit { return }
        }
    }
}

/// Moves one of your files to the Trash. Refuses anything outside your home folder, inside ~/Library,
/// inside a git repo, or on the protected list. Never deletes permanently.
@discardableResult
func trashUserFile(_ path: String) -> Bool {
    let p = (path as NSString).standardizingPath
    let fm = FileManager.default
    guard p.hasPrefix(home + "/"), !p.hasPrefix(h("~/Library") + "/"), !p.contains("/.git/"),
          protectedReason(p) == nil, fm.fileExists(atPath: p) else {
        log("REFUSED (review file) \(p)"); return false
    }
    do {
        try fm.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil)
        log("TRASHED (review) \(p)")
        return true
    } catch {
        log("FAILED \(p): \(error.localizedDescription)")
        return false
    }
}

/// When you last opened a file (Spotlight's "Last opened"), falling back to when it was added or changed.
func lastUsed(_ path: String) -> Date {
    if let item = MDItemCreate(nil, path as CFString),
       let d = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { return d }
    let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey])
    return max(v?.addedToDirectoryDate ?? .distantPast, v?.contentModificationDate ?? .distantPast)
}

// MARK: old downloads

struct OldDownload: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let size: Int64
    let lastUsed: Date
    let isFolder: Bool
    var name: String { (path as NSString).lastPathComponent }
    var days: Int { max(0, Int(-lastUsed.timeIntervalSinceNow / 86400)) }
}

/// Top-level items in ~/Downloads you have not opened for `days` days, biggest first.
func findOldDownloads(days: Double) -> [OldDownload] {
    let dir = h("~/Downloads")
    let fm = FileManager.default
    var out: [OldDownload] = []
    for k in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where !k.hasPrefix(".") {
        let p = (dir as NSString).appendingPathComponent(k)
        if protectedReason(p) != nil || protectedReason(p + "/") != nil { continue }
        let used = lastUsed(p)
        guard -used.timeIntervalSinceNow >= days * 86400 else { continue }
        var isDir: ObjCBool = false
        fm.fileExists(atPath: p, isDirectory: &isDir)
        let size = isDir.boolValue ? duSize(p) : dirSize(p)
        if size < 1_000_000 { continue }
        out.append(OldDownload(path: p, size: size, lastUsed: used, isFolder: isDir.boolValue && !k.hasSuffix(".app")))
    }
    return out.sorted { $0.size > $1.size }
}
