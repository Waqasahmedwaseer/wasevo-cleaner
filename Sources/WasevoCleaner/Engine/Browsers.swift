import Foundation

// Wasevo Cleaner — Browser privacy. Clears history, cookies and caches per browser, only while that
// browser is closed, and moves the files to the Trash (restorable).
// Never touched: saved passwords (Login Data), bookmarks, autofill/cards (Web Data), extensions, settings.

enum PrivacyKind: String, CaseIterable { case cache = "Cache", history = "History", cookies = "Cookies", forms = "Form history" }

struct BrowserSpec {
    let name: String
    let process: [String]
    let root: String           // profile parent (~/Library/Application Support/…)
    let cacheRoot: String      // ~/Library/Caches/…
    let firefox: Bool
}

let BROWSERS: [BrowserSpec] = [
    BrowserSpec(name: "Google Chrome", process: ["Google Chrome"], root: "~/Library/Application Support/Google/Chrome",
                cacheRoot: "~/Library/Caches/Google/Chrome", firefox: false),
    BrowserSpec(name: "Brave", process: ["Brave Browser"], root: "~/Library/Application Support/BraveSoftware/Brave-Browser",
                cacheRoot: "~/Library/Caches/BraveSoftware/Brave-Browser", firefox: false),
    BrowserSpec(name: "Microsoft Edge", process: ["Microsoft Edge"], root: "~/Library/Application Support/Microsoft Edge",
                cacheRoot: "~/Library/Caches/Microsoft Edge", firefox: false),
    BrowserSpec(name: "Arc", process: ["Arc"], root: "~/Library/Application Support/Arc/User Data",
                cacheRoot: "~/Library/Caches/Arc/User Data", firefox: false),
    BrowserSpec(name: "Vivaldi", process: ["Vivaldi"], root: "~/Library/Application Support/Vivaldi",
                cacheRoot: "~/Library/Caches/Vivaldi", firefox: false),
    BrowserSpec(name: "Firefox", process: ["firefox", "Firefox"], root: "~/Library/Application Support/Firefox/Profiles",
                cacheRoot: "~/Library/Caches/Firefox/Profiles", firefox: true),
]

/// Exact file names that may be removed for each kind. Anything else in a profile is never touched.
private let CHROMIUM_FILES: [PrivacyKind: [String]] = [
    .history: ["History", "History-journal", "Visited Links", "Top Sites", "Top Sites-journal"],
    .cookies: ["Cookies", "Cookies-journal", "Network/Cookies", "Network/Cookies-journal"],
]
private let FIREFOX_FILES: [PrivacyKind: [String]] = [
    .cookies: ["cookies.sqlite", "cookies.sqlite-wal", "cookies.sqlite-shm"],
    .forms: ["formhistory.sqlite", "formhistory.sqlite-wal", "formhistory.sqlite-shm"],
]
private let NEVER = ["Login Data", "Web Data", "Bookmarks", "places.sqlite", "logins.json", "key4.db", "Preferences", "Extensions"]

struct PrivacyItem: Identifiable, Hashable {
    var id: String { browser + "|" + profile + "|" + kind.rawValue }
    let browser: String
    let profile: String
    let kind: PrivacyKind
    let paths: [String]
    let size: Int64
    var detail: String {
        switch kind {
        case .cache: return "Pages load a little slower the first time."
        case .history: return "Sites you visited and the new-tab shortcuts."
        case .cookies: return "You will be signed out of websites."
        case .forms: return "Things you typed into forms."
        }
    }
}

private func profiles(of b: BrowserSpec) -> [String] {
    let fm = FileManager.default
    let root = h(b.root)
    return ((try? fm.contentsOfDirectory(atPath: root)) ?? []).filter { p in
        b.firefox ? fm.fileExists(atPath: "\(root)/\(p)/prefs.js")
                  : fm.fileExists(atPath: "\(root)/\(p)/Preferences") && (p == "Default" || p.hasPrefix("Profile "))
    }.sorted()
}

/// Browsers installed with data on this Mac.
func installedBrowsers() -> [BrowserSpec] { BROWSERS.filter { !profiles(of: $0).isEmpty } }

func privacyItems(for b: BrowserSpec) -> [PrivacyItem] {
    let fm = FileManager.default
    var out: [PrivacyItem] = []
    for prof in profiles(of: b) {
        let dir = "\(h(b.root))/\(prof)"
        let profName = b.firefox ? String(prof.split(separator: ".").last ?? "") : prof
        let cache = b.firefox ? "\(h(b.cacheRoot))/\(prof)/cache2" : "\(h(b.cacheRoot))/\(prof)"
        if fm.fileExists(atPath: cache) {
            out.append(PrivacyItem(browser: b.name, profile: profName, kind: .cache, paths: [cache], size: duSize(cache)))
        }
        for (kind, names) in (b.firefox ? FIREFOX_FILES : CHROMIUM_FILES) {
            let paths = names.map { "\(dir)/\($0)" }.filter { fm.fileExists(atPath: $0) }
            if !paths.isEmpty {
                out.append(PrivacyItem(browser: b.name, profile: profName, kind: kind, paths: paths,
                                       size: paths.reduce(0) { $0 + dirSize($1) }))
            }
        }
    }
    return out.sorted { ($0.profile, PrivacyKind.allCases.firstIndex(of: $0.kind)!) < ($1.profile, PrivacyKind.allCases.firstIndex(of: $1.kind)!) }
}

/// Moves the chosen items to the Trash. Refuses while the browser is open, and refuses any path that
/// is not exactly one of the allowed files inside that browser's own folders.
func clearPrivacy(_ items: [PrivacyItem], browser b: BrowserSpec) -> (done: Int, error: String?) {
    if ProcSnapshot.take().running(b.process) != nil { return (0, "Quit \(b.name) first, then try again.") }
    let allowed = Set((b.firefox ? FIREFOX_FILES : CHROMIUM_FILES).values.flatMap { $0 })
    var done = 0
    for item in items {
        for p in item.paths {
            let name = item.kind == .cache ? nil : p.replacingOccurrences(of: h(b.root) + "/", with: "")
                .split(separator: "/", maxSplits: 1).last.map(String.init)
            let inside = p.hasPrefix(h(b.root) + "/") || p.hasPrefix(h(b.cacheRoot) + "/")
            let ok = inside && !NEVER.contains(where: { p.hasSuffix("/" + $0) })
                && (item.kind == .cache || (name.map { allowed.contains($0) } ?? false))
            guard ok else { log("REFUSED (browser) \(p)"); continue }
            do {
                try trashWithUndo(URL(fileURLWithPath: p))
                log("TRASHED (\(b.name) \(item.kind.rawValue)) \(p)")
                done += 1
            } catch { log("FAILED \(p): \(error.localizedDescription)") }
        }
    }
    return (done, nil)
}
