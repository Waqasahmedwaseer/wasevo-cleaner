import SwiftUI
import Foundation

// Wasevo Cleaner — app state: scan results, selection, cleaning and reports.

enum ItemKind {
    case rule(Int)
    case artifact(Artifact)
    case tool(Int)
}

struct CleanItem: Identifiable {
    let id = UUID()
    let kind: ItemKind
    let category: Category
    let title: String
    let detail: String
    let size: Int64          // 0 = unknown
    let risk: Risk
    let blocked: String?     // why it is skipped right now
    var selected: Bool
    var revealPath: String?
    var isTool: Bool { if case .tool = kind { return true }; return false }
}

struct CleanReport {
    let freed: Int64
    let cleaned: Int
    let skipped: [String]
    let failed: Int
    let mode: DeleteMode
}

enum Phase: Equatable {
    case idle, scanning, results, cleaning, done
}

final class Store: ObservableObject {
    @Published var free: Int64 = volumeFree()
    @Published var total: Int64 = volumeTotal()
    @Published var phase: Phase = .idle
    @Published var status = ""
    @Published var items: [CleanItem] = []
    @Published var focus: Category = .system
    @Published var report: CleanReport?
    @Published var bigFiles: [BigFile] = []
    @Published var loadingBigFiles = false
    @Published var lastScan: Date?

    @Published var autoCleaning = false
    private var timer: Timer?
    private var autoTimer: Timer?
    private var lastLowWarning: Date?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refreshDisk() }
        autoTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.autoCleanIfDue() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.autoCleanIfDue() }
    }

    func refreshDisk() {
        free = volumeFree()
        total = volumeTotal()
        if isLow, lastLowWarning.map({ Date().timeIntervalSince($0) > 86400 }) ?? true {
            lastLowWarning = Date()
            notify("Disk space is low", "Only \(human(free)) free. Open Wasevo Cleaner and run a Smart Scan.")
        }
    }

    func autoCleanIfDue() {
        guard AutoClean.isDue else { return }
        runAutoClean(reason: "scheduled")
    }

    func runAutoClean(reason: String, done: ((Int64) -> Void)? = nil) {
        guard !autoCleaning, phase != .cleaning else { return }
        autoCleaning = true
        DispatchQueue.global(qos: .utility).async {
            let freed = AutoClean.run(reason: reason)
            DispatchQueue.main.async { self.autoCleaning = false; self.refreshDisk(); done?(freed) }
        }
    }

    var usedFraction: Double { total > 0 ? Double(total - free) / Double(total) : 0 }
    var isLow: Bool { Double(free) / 1e9 < Prefs.lowSpaceGB }

    // MARK: selection helpers

    func items(in c: Category) -> [CleanItem] { items.filter { $0.category == c } }
    func size(of c: Category, selectedOnly: Bool = false) -> Int64 {
        items(in: c).filter { !selectedOnly || $0.selected }.reduce(0) { $0 + $1.size }
    }
    var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.selected).count }
    var foundSize: Int64 { items.filter { $0.blocked == nil }.reduce(0) { $0 + $1.size } }

    func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].blocked == nil else { return }
        items[i].selected.toggle()
    }

    func setCategory(_ c: Category, _ on: Bool) {
        for i in items.indices where items[i].category == c && items[i].blocked == nil { items[i].selected = on }
    }

    func categoryState(_ c: Category) -> (on: Bool, mixed: Bool) {
        let list = items(in: c).filter { $0.blocked == nil }
        let n = list.filter(\.selected).count
        return (n > 0 && n == list.count, n > 0 && n < list.count)
    }

    // MARK: scan

    func scan() {
        guard phase != .scanning && phase != .cleaning else { return }
        phase = .scanning
        report = nil
        status = "Checking running apps…"
        DispatchQueue.global(qos: .userInitiated).async {
            let snap = ProcSnapshot.take()
            var found: [CleanItem] = []

            self.say("Measuring caches…")
            for (i, r) in CACHE_RULES.enumerated() {
                let s = ruleSize(r)
                guard s > 0 else { continue }
                let blocked = snap.running(r.blockIfRunning).map { "\($0) is running" }
                found.append(CleanItem(kind: .rule(i), category: r.category, title: r.name, detail: r.note, size: s,
                                       risk: r.risk, blocked: blocked, selected: blocked == nil && r.selectedByDefault,
                                       revealPath: h(r.paths[0])))
            }

            self.say("Looking through your projects…")
            for a in scanProjects(snap: snap) {
                let age = a.stale ? "untouched \(a.ageDays) days" : "edited \(a.ageDays == 0 ? "today" : "\(a.ageDays)d ago")"
                let how = a.kind == "node_modules" ? "Reinstall with npm/pnpm install." : a.kind == "Rust target" ? "Rebuilt by cargo." : "Rebuilt on next build."
                found.append(CleanItem(kind: .artifact(a), category: .projects, title: "\(a.kind) · \(a.projectLabel)",
                                       detail: "\(age). \(how)", size: a.size, risk: .safe, blocked: a.blocked,
                                       selected: a.blocked == nil && a.stale, revealPath: a.path))
            }

            self.say("Checking Docker, Homebrew, pnpm, MySQL…")
            let tools = availableTools()
            for (i, t) in TOOL_TASKS.enumerated() where tools.contains(t.binary) {
                var size: Int64 = 0
                var blocked: String?
                if t.binary == "docker" {
                    if let c = dockerBuildCache() { size = parseSize(c) } else { blocked = "Docker is not running" }
                } else if t.binary == "mysql" {
                    size = self.oldBinlogBytes()
                    if size == 0 { continue }
                } else if t.binary == "xcrun" && !FileManager.default.fileExists(atPath: "/Applications/Xcode.app") {
                    continue
                }
                found.append(CleanItem(kind: .tool(i), category: .tools, title: t.name, detail: t.note, size: size,
                                       risk: .safe, blocked: blocked, selected: blocked == nil && t.selectedByDefault))
            }

            found.sort { $0.size > $1.size }
            DispatchQueue.main.async {
                self.items = found
                self.lastScan = Date()
                self.phase = .results
                self.focus = Category.allCases.first { c in found.contains { $0.category == c } } ?? .system
                self.refreshDisk()
            }
        }
    }

    private func say(_ s: String) { DispatchQueue.main.async { self.status = s } }

    /// MySQL binlogs older than 3 days in a Homebrew MySQL data dir (what PURGE would remove).
    private func oldBinlogBytes() -> Int64 {
        let dir = ["/usr/local/var/mysql", "/opt/homebrew/var/mysql"].first { FileManager.default.fileExists(atPath: $0) }
        guard let dir, let kids = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return 0 }
        var total: Int64 = 0
        for k in kids where k.hasPrefix("binlog.") && k != "binlog.index" {
            let p = dir + "/" + k
            if let a = try? FileManager.default.attributesOfItem(atPath: p), let m = a[.modificationDate] as? Date,
               -m.timeIntervalSinceNow > 3 * 86400 { total += (a[.size] as? NSNumber)?.int64Value ?? 0 }
        }
        return total
    }

    // MARK: clean

    func clean(mode: DeleteMode) {
        let chosen = items.filter { $0.selected && $0.blocked == nil }
        guard !chosen.isEmpty, phase == .results else { return }
        phase = .cleaning
        let before = volumeFree()
        DispatchQueue.global(qos: .userInitiated).async {
            let snap = ProcSnapshot.take()   // re-check: things may have started since the scan
            var skipped: [String] = [], failed = 0, cleaned = 0
            for item in chosen {
                self.say("Cleaning \(item.title)…")
                switch item.kind {
                case .rule(let i):
                    let r = CACHE_RULES[i]
                    if let p = snap.running(r.blockIfRunning) { skipped.append("\(r.name): \(p) started"); continue }
                    failed += clearRule(r, mode)
                case .artifact(let a):
                    if let b = blockReason(path: a.path, project: a.project, isRust: a.kind == "Rust target", snap: snap) {
                        skipped.append("\(a.projectLabel): \(b)"); log("SKIPPED \(a.path): \(b)"); continue
                    }
                    if !removePath(a.path, mode) { failed += 1 }
                case .tool(let i):
                    let t = TOOL_TASKS[i]
                    let r = sh(t.command, timeout: 600)
                    log("TOOL \(t.command) → exit \(r.code)")
                    if r.code != 0 { skipped.append("\(t.name): \(r.out.split(separator: "\n").last ?? "failed")"); continue }
                }
                cleaned += 1
            }
            let freed = max(0, volumeFree() - before)
            log("CLEAN \(mode == .trash ? "trash" : "delete") · \(cleaned) items · freed \(human(freed))")
            DispatchQueue.main.async {
                self.report = CleanReport(freed: freed, cleaned: cleaned, skipped: skipped, failed: failed, mode: mode)
                self.phase = .done
                self.refreshDisk()
            }
        }
    }

    func emptyTrash(_ done: @escaping (Int64) -> Void) {
        let before = volumeFree()
        DispatchQueue.global().async {
            sh("osascript -e 'tell application \"Finder\" to empty trash'", timeout: 300)
            let freed = max(0, volumeFree() - before)
            log("EMPTY TRASH · freed \(human(freed))")
            DispatchQueue.main.async { self.refreshDisk(); done(freed) }
        }
    }

    // MARK: large files (view only)

    func loadBigFiles() {
        guard !loadingBigFiles else { return }
        loadingBigFiles = true
        DispatchQueue.global(qos: .userInitiated).async {
            let list = scanBigFiles(limit: 40)
            DispatchQueue.main.async { self.bigFiles = list; self.loadingBigFiles = false }
        }
    }
}
