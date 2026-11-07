import Foundation

// Wasevo Cleaner — App updates (check only). Reads each app's own update feed (Sparkle appcast) and
// Homebrew's local list. Nothing is downloaded or installed: you update in the app itself.

struct AppUpdate: Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let installed: String
    let latest: String
    let source: String         // "App's update feed" / "Homebrew" / "App Store"
    var command: String?       // e.g. brew upgrade --cask x
}

/// Newest version in a Sparkle appcast: (shortVersion, buildVersion).
private final class AppcastParser: NSObject, XMLParserDelegate {
    var best: (short: String, build: String)?
    private var inItem = false, el = "", short = "", build = ""
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
        el = e
        if e == "item" { inItem = true; short = ""; build = "" }
        if inItem, e == "enclosure" {
            if let s = a["sparkle:shortVersionString"] { short = s }
            if let v = a["sparkle:version"] { build = v }
        }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inItem, !t.isEmpty else { return }
        if el == "sparkle:shortVersionString" { short += t }
        if el == "sparkle:version" { build += t }
    }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) {
        guard e == "item" else { return }
        inItem = false
        let cand = (short, build)
        if let b = best {
            let key = { (x: (String, String)) in x.0.isEmpty ? x.1 : x.0 }
            if key(cand).compare(key(b), options: .numeric) == .orderedDescending { best = cand }
        } else if !short.isEmpty || !build.isEmpty { best = cand }
    }
}

private func newer(_ a: String, than b: String) -> Bool {
    !a.isEmpty && !b.isEmpty && a.compare(b, options: .numeric) == .orderedDescending
}

func checkUpdates(progress: @escaping (String) -> Void) -> [AppUpdate] {
    var out: [AppUpdate] = []
    let apps = listApps().filter { !$0.isApple && !$0.isSelf }
    let group = DispatchGroup()
    let lock = NSLock()
    for app in apps {
        guard let info = Bundle(path: app.path)?.infoDictionary,
              let feed = info["SUFeedURL"] as? String, let url = URL(string: feed), url.scheme == "https" else { continue }
        group.enter()
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Wasevo Cleaner update check", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { group.leave() }
            guard let data else { return }
            let parser = AppcastParser()
            let x = XMLParser(data: data); x.delegate = parser; x.parse()
            guard let best = parser.best else { return }
            let short = info["CFBundleShortVersionString"] as? String ?? ""
            let build = info["CFBundleVersion"] as? String ?? ""
            // Same rule Sparkle uses: compare build numbers (sparkle:version vs CFBundleVersion) when both exist.
            let isNewer = !best.build.isEmpty && !build.isEmpty ? newer(best.build, than: build) : newer(best.short, than: short)
            if isNewer {
                lock.lock()
                out.append(AppUpdate(name: app.name, path: app.path, installed: short.isEmpty ? build : short,
                                     latest: best.short.isEmpty ? best.build : best.short, source: "App's update feed"))
                lock.unlock()
            }
        }.resume()
    }
    progress("Checking each app's update feed…")
    _ = group.wait(timeout: .now() + 30)

    progress("Checking Homebrew…")
    let brew = sh("HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --json=v2 2>/dev/null", timeout: 60)
    // formulae: only the ones you installed yourself, not libraries pulled in as dependencies
    let mine = Set(sh("brew leaves --installed-on-request 2>/dev/null", timeout: 30).out.split(separator: "\n").map(String.init))
    if brew.code == 0, let data = brew.out.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        for (key, flag) in [("casks", " --cask"), ("formulae", "")] {
            for item in json[key] as? [[String: Any]] ?? [] {
                let name = item["name"] as? String ?? ""
                if key == "formulae" && !mine.contains(name) && !mine.contains(where: { $0.hasSuffix("/" + name) }) { continue }
                let inst = (item["installed_versions"] as? [String])?.last ?? ""
                lock.lock()
                out.append(AppUpdate(name: name, path: "brew:\(name)", installed: inst,
                                     latest: item["current_version"] as? String ?? "", source: "Homebrew",
                                     command: "brew upgrade\(flag) \(name)"))
                lock.unlock()
            }
        }
    }
    lock.lock(); let result = out; lock.unlock()   // late feed replies may still arrive
    return result.sorted { ($0.source, $0.name.lowercased()) < ($1.source, $1.name.lowercased()) }
}

/// Apps installed from the Mac App Store (updated through the App Store).
func appStoreAppCount() -> Int {
    listApps().filter { FileManager.default.fileExists(atPath: $0.path + "/Contents/_MASReceipt/receipt") }.count
}
