import Foundation
import CryptoKit

// Wasevo Cleaner — Duplicate Finder. Files count as duplicates only when every byte is identical
// (same size, same SHA-256). One copy in each group is always kept.

struct DupGroup: Identifiable {
    let id = UUID()
    let size: Int64
    var files: [UserFile]
    var wasted: Int64 { size * Int64(max(0, files.count - 1)) }
    var kind: String {
        let e = (files.first?.path as NSString?)?.pathExtension.lowercased() ?? ""
        if ["jpg", "jpeg", "png", "heic", "gif", "tiff", "webp", "raw", "cr2", "nef", "dng"].contains(e) { return "Image" }
        if ["mp4", "mov", "m4v", "avi", "mkv"].contains(e) { return "Video" }
        if ["mp3", "m4a", "wav", "aac", "flac"].contains(e) { return "Audio" }
        if ["zip", "dmg", "pkg", "rar", "7z", "tar", "gz", "iso", "apk"].contains(e) { return "Archive" }
        if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "csv"].contains(e) { return "Document" }
        return "Other"
    }
}

/// SHA-256 of a file (or only its first `limit` bytes), read in 1 MB chunks.
func fileHash(_ path: String, limit: Int64? = nil) -> String? {
    guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? fh.close() }
    var hasher = SHA256()
    var read: Int64 = 0
    while true {
        let want = limit.map { Int(min(1 << 20, $0 - read)) } ?? (1 << 20)
        if want <= 0 { break }
        guard let chunk = try? fh.read(upToCount: want), !chunk.isEmpty else { break }
        hasher.update(data: chunk)
        read += Int64(chunk.count)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func findDuplicates(minSize: Int64, progress: @escaping (String) -> Void) -> [DupGroup] {
    // 1. group by exact size (different sizes can never be duplicates)
    var bySize: [Int64: [UserFile]] = [:]
    var inodes = Set<String>()
    var count = 0
    walkUserFiles(minSize: minSize) { f in
        // hard links point at the same data: not a real duplicate
        if let id = try? URL(fileURLWithPath: f.path).resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier {
            let key = "\(id)"
            if inodes.contains(key) { return }
            inodes.insert(key)
        }
        bySize[f.size, default: []].append(f)
        count += 1
        if count % 500 == 0 { progress("Looked at \(count) files…") }
    }
    let candidates = bySize.values.filter { $0.count > 1 }
    let total = candidates.reduce(0) { $0 + $1.count }
    var hashed = 0
    var groups: [DupGroup] = []

    for same in candidates {
        // 2. quick check on the first 64 KB, 3. full hash only for files that still match
        var byQuick: [String: [UserFile]] = [:]
        for f in same {
            hashed += 1
            if hashed % 50 == 0 { progress("Comparing \(hashed) of \(total) possible copies…") }
            if let q = fileHash(f.path, limit: 65_536) { byQuick[q, default: []].append(f) }
        }
        for quick in byQuick.values where quick.count > 1 {
            var byFull: [String: [UserFile]] = [:]
            for f in quick {
                if let full = f.size <= 65_536 ? fileHash(f.path, limit: 65_536) : fileHash(f.path) {
                    byFull[full, default: []].append(f)
                }
            }
            for list in byFull.values where list.count > 1 {
                groups.append(DupGroup(size: list[0].size, files: list.sorted { $0.modified < $1.modified }))
            }
        }
    }
    return groups.sorted { $0.wasted > $1.wasted }
}

/// Re-checks a group right before trashing: every file to remove must still be byte-identical to a copy
/// that stays. Returns how many were trashed.
func trashDuplicates(group: DupGroup, remove: Set<String>) -> Int {
    let keep = group.files.filter { !remove.contains($0.path) }
    guard let kept = keep.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
          let keptHash = fileHash(kept.path) else {
        log("REFUSED duplicates: no copy would remain"); return 0
    }
    var done = 0
    for f in group.files where remove.contains(f.path) {
        guard fileHash(f.path) == keptHash else { log("SKIPPED (changed since scan) \(f.path)"); continue }
        if trashUserFile(f.path) { done += 1 }
    }
    return done
}
