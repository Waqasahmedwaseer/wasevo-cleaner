import Foundation
import AppKit
import CryptoKit

// Wasevo Cleaner — updates itself from GitHub Releases.
// Checks the latest release, downloads its DMG, verifies the SHA-256 GitHub publishes for it,
// checks the app inside is really Wasevo Cleaner and really newer, then swaps it in and relaunches.
// If anything looks wrong it stops and opens the release page instead.

let GITHUB_REPO = "Waqasahmedwaseer/wasevo-cleaner"

struct Release: Equatable {
    let version: String
    let notes: String
    let page: URL
    let dmg: URL
    let size: Int64
    let sha256: String?   // from GitHub's asset "digest"
}

func isNewer(_ a: String, than b: String) -> Bool {
    !a.isEmpty && !b.isEmpty && b != "dev" && a.compare(b, options: .numeric) == .orderedDescending
}

final class SelfUpdate: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = SelfUpdate()

    enum State: Equatable {
        case idle, checking, upToDate, available, downloading(Double), installing, failed(String)
    }
    @Published var state: State = .idle
    @Published var latest: Release?

    static var autoCheck: Bool { UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true }
    private let lastCheckKey = "lastUpdateCheck", skipKey = "skippedVersion", notifiedKey = "notifiedVersion"

    var lastCheck: Date? {
        let t = UserDefaults.standard.double(forKey: lastCheckKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    var isAvailable: Bool { if case .available = state { return true }; return false }

    // MARK: check

    /// Background check: once a day, only when the setting is on.
    func checkIfDue(atLaunch: Bool = false) {
        guard Self.autoCheck, appVersion != "dev" else { return }
        if !atLaunch, let last = lastCheck, Date().timeIntervalSince(last) < 86400 { return }
        check(background: true)
    }

    func check(background: Bool = false, then: (() -> Void)? = nil) {
        if case .downloading = state { return }
        if state == .installing || state == .checking { return }
        state = .checking
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(GITHUB_REPO)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("WasevoCleaner/\(appVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let rel = data.flatMap(Self.parse)
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self.lastCheckKey)
                guard let rel else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    self.state = background ? .idle : .failed(err != nil ? "No internet connection." : "GitHub did not answer (\(code)). Try again later.")
                    return
                }
                self.latest = rel
                let skipped = UserDefaults.standard.string(forKey: self.skipKey)
                if isNewer(rel.version, than: appVersion) && !(background && skipped == rel.version) {
                    self.state = .available
                    log("UPDATE AVAILABLE v\(rel.version) (running v\(appVersion))")
                    if background, UserDefaults.standard.string(forKey: self.notifiedKey) != rel.version {
                        UserDefaults.standard.set(rel.version, forKey: self.notifiedKey)
                        notify("Wasevo Cleaner \(rel.version) is available", "Open Wasevo Cleaner to update. It takes a few seconds.")
                    }
                } else {
                    self.state = .upToDate
                }
                then?()
            }
        }.resume()
    }

    static func parse(_ data: Data) -> Release? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = j["tag_name"] as? String,
              let page = (j["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = j["assets"] as? [[String: Any]],
              let dmg = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }),
              let url = (dmg["browser_download_url"] as? String).flatMap(URL.init(string:)),
              url.host?.hasSuffix("github.com") == true
        else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let digest = (dmg["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
        return Release(version: version, notes: (j["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                       page: page, dmg: url, size: (dmg["size"] as? NSNumber)?.int64Value ?? 0, sha256: digest)
    }

    func skipThisVersion() {
        guard let v = latest?.version else { return }
        UserDefaults.standard.set(v, forKey: skipKey)
        state = .upToDate
    }

    // MARK: install

    /// Where the running app lives, if we are allowed to replace it in place.
    var installTarget: String? {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app"),
              !path.contains("/AppTranslocation/"), !path.hasPrefix("/Volumes/"),
              FileManager.default.isWritableFile(atPath: (path as NSString).deletingLastPathComponent)
        else { return nil }
        return path
    }

    private var session: URLSession?

    func install() {
        guard let rel = latest else { return }
        guard installTarget != nil else {
            // running from the DMG or a read-only place: let the person drag the new version in
            NSWorkspace.shared.open(rel.dmg)
            state = .failed("Opened the download. Drag Wasevo Cleaner into Applications to finish.")
            return
        }
        state = .downloading(0)
        log("UPDATE DOWNLOAD v\(rel.version) \(rel.dmg.absoluteString)")
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = s
        s.downloadTask(with: rel.dmg).resume()
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite t: Int64) {
        let total = t > 0 ? t : (latest?.size ?? 0)
        guard total > 0 else { return }
        DispatchQueue.main.async { self.state = .downloading(min(1, Double(w) / Double(total))) }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
        // the temp file disappears when this returns, so move it first
        let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("WasevoCleaner-update-\(UUID().uuidString).dmg")
        do { try FileManager.default.moveItem(at: loc, to: dmg) } catch { fail("Could not save the download."); return }
        if let code = (downloadTask.response as? HTTPURLResponse)?.statusCode, code != 200 {
            fail("Download failed (\(code))."); return
        }
        DispatchQueue.main.async { self.state = .installing }
        DispatchQueue.global(qos: .userInitiated).async { self.verifyAndSwap(dmg) }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { fail("Download failed: \(error.localizedDescription)") }
        s.finishTasksAndInvalidate()
    }

    private func fail(_ msg: String) {
        log("UPDATE FAILED · \(msg)")
        DispatchQueue.main.async { self.state = .failed(msg) }
    }

    private func verifyAndSwap(_ dmg: URL) {
        guard let rel = latest, let target = installTarget else { fail("Can't replace the app here."); return }
        defer { try? FileManager.default.removeItem(at: dmg) }

        // 1. the file is exactly what GitHub says it published
        if let want = rel.sha256 {
            guard let data = try? Data(contentsOf: dmg, options: .mappedIfSafe) else { fail("Could not read the download."); return }
            let got = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard got == want else { fail("The download did not match GitHub's checksum. Nothing was changed."); return }
        }

        // 2. mount it privately and find the app
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("wc-mount-\(UUID().uuidString)").path
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        guard sh("/usr/bin/hdiutil attach -nobrowse -noautoopen -readonly -mountpoint \(q(mount)) \(q(dmg.path))", timeout: 90).code == 0 else {
            fail("Could not open the downloaded DMG."); return
        }
        defer { _ = sh("/usr/bin/hdiutil detach -force \(q(mount))", timeout: 30) }
        let apps = (try? FileManager.default.contentsOfDirectory(atPath: mount))?.filter { $0.hasSuffix(".app") } ?? []
        guard let name = apps.first else { fail("No app found in the download."); return }
        let newApp = mount + "/" + name

        // 3. it is really Wasevo Cleaner, and really the newer version
        let info = NSDictionary(contentsOfFile: newApp + "/Contents/Info.plist")
        let id = info?["CFBundleIdentifier"] as? String
        let ver = info?["CFBundleShortVersionString"] as? String ?? ""
        guard id == Bundle.main.bundleIdentifier else { fail("The download is not Wasevo Cleaner. Nothing was changed."); return }
        guard isNewer(ver, than: appVersion) else { fail("The download is not newer than this version."); return }

        // 4. copy it next to us, then swap after we quit (old copy is kept until the new one is in place)
        let staged = (target as NSString).deletingLastPathComponent + "/.Wasevo Cleaner.update.app"
        try? FileManager.default.removeItem(atPath: staged)
        guard sh("/usr/bin/ditto \(q(newApp)) \(q(staged))", timeout: 120).code == 0 else {
            try? FileManager.default.removeItem(atPath: staged)
            fail("Could not copy the new version."); return
        }
        _ = sh("/usr/bin/xattr -dr com.apple.quarantine \(q(staged))")

        let script = """
        PID=$1; DEST=$2; NEW=$3; BAK="$DEST.previous"
        for i in $(seq 1 150); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        rm -rf "$BAK"
        if mv "$DEST" "$BAK" && mv "$NEW" "$DEST"; then rm -rf "$BAK"; else rm -rf "$DEST"; mv "$BAK" "$DEST"; rm -rf "$NEW"; fi
        open "$DEST"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script, "wasevo-update", String(ProcessInfo.processInfo.processIdentifier), target, staged]
        do { try p.run() } catch { try? FileManager.default.removeItem(atPath: staged); fail("Could not start the installer."); return }
        log("UPDATE INSTALLING v\(ver) → \(target)")
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}
