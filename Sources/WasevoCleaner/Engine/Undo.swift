import Foundation

// Wasevo Cleaner — Undo. Every move to the Trash is recorded, so the last batch can be put back
// where it came from with one click. (Things deleted permanently cannot be undone.)

final class UndoLog: ObservableObject {
    static let shared = UndoLog()
    struct Item { let original: String; let trashed: URL }

    @Published private(set) var batch: [Item] = []
    @Published private(set) var batchTime = Date.distantPast
    private let lock = NSLock()

    /// Items moved within a few seconds of each other belong to the same batch.
    func record(_ original: String, _ trashed: URL) {
        DispatchQueue.main.async {
            if Date().timeIntervalSince(self.batchTime) > 8 { self.batch = [] }
            self.batch.append(Item(original: original, trashed: trashed))
            self.batchTime = Date()
        }
    }

    var canUndo: Bool { !batch.isEmpty && Date().timeIntervalSince(batchTime) < 600 }

    /// Moves the last batch back. Never overwrites: skips anything whose old place is taken again.
    func putBack(_ done: @escaping (_ restored: Int, _ skipped: Int) -> Void) {
        let items = batch
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var ok = 0, skipped = 0
            for it in items.reversed() {
                guard fm.fileExists(atPath: it.trashed.path), !fm.fileExists(atPath: it.original) else { skipped += 1; continue }
                do {
                    try fm.createDirectory(atPath: (it.original as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                    try fm.moveItem(at: it.trashed, to: URL(fileURLWithPath: it.original))
                    log("PUT BACK \(it.original)")
                    ok += 1
                } catch { skipped += 1; log("PUT BACK FAILED \(it.original): \(error.localizedDescription)") }
            }
            DispatchQueue.main.async { self.batch = []; done(ok, skipped) }
        }
    }
}

/// Moves to the Trash and remembers where it came from (for "Put back").
func trashWithUndo(_ url: URL) throws {
    var out: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &out)
    if let t = out as URL? { UndoLog.shared.record(url.path, t) }
}
