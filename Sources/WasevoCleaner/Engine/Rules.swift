import Foundation

// Wasevo Cleaner — the registry of what may be cleaned. Every rule regenerates by itself.

let home = NSHomeDirectory()
func h(_ p: String) -> String { p.hasPrefix("~") ? home + String(p.dropFirst()) : p }

/// Sibling of the per-user temp dir (…/T/), e.g. "X" where macOS keeps code-sign clones.
func darwinUserDir(_ sub: String) -> String {
    URL(fileURLWithPath: NSTemporaryDirectory()).deletingLastPathComponent().appendingPathComponent(sub).path
}

// MARK: settings (UserDefaults-backed so the Settings screen can change them)

enum Prefs {
    static var staleDays: Double {
        let v = UserDefaults.standard.double(forKey: "staleDays"); return v > 0 ? v : 14
    }
    static var lowSpaceGB: Double {
        let v = UserDefaults.standard.double(forKey: "lowSpaceGB"); return v > 0 ? v : 15
    }
    static var projectRoots: [String] {
        let v = UserDefaults.standard.string(forKey: "projectRoots") ?? ""
        let list = v.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return list.isEmpty ? ["~/Documents", "~/Desktop", "~/Local Sites", "~/tools", "~/Projects", "~/Developer", "~/code"] : list
    }
}

let MIN_ARTIFACT_BYTES: Int64 = 20_000_000
let LOG_PATH = h("~/Library/Logs/WasevoCleaner.log")

// MARK: categories & risk

enum Category: String, CaseIterable, Identifiable {
    case system = "System & app caches"
    case developer = "Developer caches"
    case projects = "Project build files"
    case downloads = "Downloads & logs"
    case tools = "Tool cleanups"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .system: return "macwindow"
        case .developer: return "hammer"
        case .projects: return "folder.badge.gearshape"
        case .downloads: return "arrow.down.circle"
        case .tools: return "wrench.and.screwdriver"
        }
    }
    var blurb: String {
        switch self {
        case .system: return "Caches apps rebuild by themselves."
        case .developer: return "Package-manager and compiler caches. Downloaded or rebuilt when needed."
        case .projects: return "node_modules, Rust target, .next inside your projects. Your code is never touched."
        case .downloads: return "Old installers and crash reports."
        case .tools: return "Cleanups run through each tool's own safe command."
        }
    }
}

enum Risk: Int, Comparable {
    case safe = 0        // rebuilds automatically
    case redownload = 1  // comes back on next download/install
    case review = 2      // your own files: check before deleting
    static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }
    var label: String { ["Safe", "Re-downloads", "Review"][rawValue] }
}

/// Things other cleaners offer to delete that would destroy real work. Never touched.
func protectedReason(_ path: String) -> String? {
    let p = path.lowercased()
    if p.hasSuffix("docker.raw") || p.contains("/com.docker.docker/") { return "Docker's whole disk: images, containers, databases" }
    if p.contains("/var/mysql/") || p.contains("/mysql-data/") || p.hasSuffix(".ibd") || p.contains("/binlog.") { return "MySQL database files" }
    if p.hasSuffix("system.img") || p.contains(".avd/") || p.contains("/system-images/") { return "Android emulator" }
    if p.contains("/.claude-mem/") || p.contains("/.ssh/") || p.contains("/keychains/") || p.contains("/.gnupg/") { return "personal data / credentials" }
    if ["auth.json", "oauth_creds.json", "google_accounts.json", "credentials.json"].contains((p as NSString).lastPathComponent) { return "login credentials" }
    if p.hasSuffix(".sqlite") || p.hasSuffix(".db") || p.hasSuffix(".sql") { return "a database file" }
    return nil
}

// MARK: cache rules

struct CacheRule {
    let category: Category
    let risk: Risk
    let name: String
    let paths: [String]
    let note: String
    var contentsOnly = false            // keep the folder itself, clear what is inside
    var skipPrefixes: [String] = []     // children to leave alone (contentsOnly mode)
    var onlyExtensions: [String] = []   // contentsOnly: only these file types
    var olderThanDays: Double = 0       // contentsOnly: only items older than this
    var blockIfRunning: [String] = []   // skip while any of these processes run
    var selectedByDefault = true
}

let CACHE_RULES: [CacheRule] = [
    // System & app caches
    CacheRule(category: .system, risk: .safe, name: "App caches", paths: ["~/Library/Caches"],
              note: "Apps rebuild their caches. Apple system caches are left alone.",
              contentsOnly: true, skipPrefixes: ["com.apple."]),
    CacheRule(category: .system, risk: .redownload, name: "Chrome on-device AI model",
              paths: ["~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel"],
              note: "Chrome's built-in AI model (weights.bin). Re-downloaded only if you use Chrome's AI features.",
              blockIfRunning: ["Google Chrome"]),
    CacheRule(category: .system, risk: .redownload, name: "Google Updater downloads",
              paths: ["~/Library/Application Support/Google/GoogleUpdater/crx_cache"],
              note: "Already-installed update packages.", contentsOnly: true),
    CacheRule(category: .system, risk: .safe, name: "VS Code extension installers",
              paths: ["~/Library/Application Support/Code/CachedExtensionVSIXs"],
              note: "Old installer copies only. Your extensions stay.", contentsOnly: true),
    CacheRule(category: .system, risk: .safe, name: "Chrome leftover update copies",
              paths: [darwinUserDir("X") + "/com.google.Chrome.code_sign_clone"],
              note: "Size can look bigger than it is (APFS clones share space).", contentsOnly: true,
              blockIfRunning: ["Google Chrome"]),
    CacheRule(category: .system, risk: .safe, name: "Brave leftover update copies",
              paths: [darwinUserDir("X") + "/com.brave.Browser.code_sign_clone"],
              note: "Size can look bigger than it is (APFS clones share space).", contentsOnly: true,
              blockIfRunning: ["Brave Browser"]),

    // Developer caches
    CacheRule(category: .developer, risk: .redownload, name: "npm cache", paths: ["~/.npm/_cacache", "~/.npm/_npx", "~/.npm/_logs"],
              note: "npm/npx download packages again when needed.", blockIfRunning: ["npm", "npx"]),
    CacheRule(category: .developer, risk: .redownload, name: "uv (Python) cache", paths: ["~/.cache/uv"],
              note: "uv downloads again when needed.", blockIfRunning: ["uv", "uvx"]),
    CacheRule(category: .developer, risk: .redownload, name: "Bun / Composer / Yarn caches",
              paths: ["~/.bun/install/cache", "~/.composer/cache", "~/.yarn/berry/cache"],
              note: "Package managers download again when needed.", blockIfRunning: ["bun", "composer", "yarn"]),
    CacheRule(category: .developer, risk: .redownload, name: "Cargo download cache", paths: ["~/.cargo/registry/cache"],
              note: "cargo downloads crates again when needed.", blockIfRunning: ["cargo"]),
    CacheRule(category: .developer, risk: .safe, name: "Shared Tauri/Rust build", paths: ["~/.cache/pospro-tauri-target"],
              note: "cargo rebuilds it on the next build.", blockIfRunning: ["cargo", "rustc"]),
    CacheRule(category: .developer, risk: .redownload, name: "Playwright / Puppeteer browsers",
              paths: ["~/.cache/ms-playwright", "~/.cache/puppeteer"], note: "Downloaded again on the next test run."),
    CacheRule(category: .developer, risk: .safe, name: "Gradle cache", paths: ["~/.gradle/caches"],
              note: "Rebuilt on the next Gradle/Android build.", blockIfRunning: ["java", "gradle"]),
    CacheRule(category: .developer, risk: .safe, name: "Xcode DerivedData", paths: ["~/Library/Developer/Xcode/DerivedData"],
              note: "Xcode rebuilds it.", blockIfRunning: ["Xcode", "xcodebuild"]),
    CacheRule(category: .developer, risk: .redownload, name: "Arduino download archives", paths: ["~/Library/Arduino15/staging"],
              note: "Archives of already-installed boards/tools.", contentsOnly: true, blockIfRunning: ["Arduino IDE"]),

    // Downloads & logs
    CacheRule(category: .downloads, risk: .safe, name: "Crash reports older than 7 days", paths: ["~/Library/Logs/DiagnosticReports"],
              note: "Old app crash reports. Nothing uses them.", contentsOnly: true, olderThanDays: 7),
    CacheRule(category: .downloads, risk: .review, name: "Old installers in Downloads (30+ days)", paths: ["~/Downloads"],
              note: ".dmg/.pkg/.iso installers. Check you don't need them again.",
              contentsOnly: true, onlyExtensions: ["dmg", "pkg", "iso", "mpkg"], olderThanDays: 30, selectedByDefault: false),
]

// MARK: tool cleanups (each uses the tool's own safe command)

struct ToolTask {
    let name: String
    let binary: String
    let command: String
    let note: String
    var selectedByDefault = true
}

let TOOL_TASKS: [ToolTask] = [
    ToolTask(name: "Docker build cache", binary: "docker",
             command: "docker builder prune -f && docker image prune -f",
             note: "Build cache and untagged images only. Images, containers and volumes stay."),
    ToolTask(name: "pnpm unused packages", binary: "pnpm", command: "pnpm store prune",
             note: "Removes only packages no project uses."),
    ToolTask(name: "Homebrew old versions", binary: "brew", command: "brew cleanup -s",
             note: "Old formula versions and downloads."),
    ToolTask(name: "MySQL binary logs older than 3 days", binary: "mysql",
             command: "mysql -e 'PURGE BINARY LOGS BEFORE NOW() - INTERVAL 3 DAY'",
             note: "MySQL's own PURGE command keeps the database healthy. Needs your login in ~/.my.cnf.",
             selectedByDefault: false),
    ToolTask(name: "Xcode simulators for removed iOS versions", binary: "xcrun",
             command: "xcrun simctl delete unavailable",
             note: "Only simulators whose iOS runtime is no longer installed.", selectedByDefault: false),
]
