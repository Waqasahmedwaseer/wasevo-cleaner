import Foundation
import Darwin

// Wasevo Cleaner — Running Services: local servers, databases, dev servers and containers you started,
// with their ports, CPU, memory, how much they have written to disk, and "hidden space":
// files that were deleted but that a running process still keeps open. macOS only gives that space back
// when the process stops, so no folder scan can find it. (A leftover test database once held 95 GB this way.)
//
// Read-only except one action: stopping a process you own. Stop asks it to quit (SIGTERM); Force stop
// (SIGKILL) is offered only if it ignores that. Nothing on disk is deleted here, ever.

enum ServiceKind: String {
    case database, devServer, container, ai, other
    var label: String {
        switch self {
        case .database: return "Database"
        case .devServer: return "Dev server"
        case .container: return "Container / VM"
        case .ai: return "AI tool"
        case .other: return "Service"
        }
    }
    var icon: String {
        switch self {
        case .database: return "cylinder.split.1x2"
        case .devServer: return "chevron.left.forwardslash.chevron.right"
        case .container: return "shippingbox"
        case .ai: return "cpu"
        case .other: return "gearshape.2"
        }
    }
}

struct ServiceWarning: Hashable {
    enum Level: Int { case info = 0, notice = 1, problem = 2 }
    let level: Level
    let text: String
}

struct LocalService: Identifiable {
    var id: pid_t { pid }
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let command: String
    let kind: ServiceKind
    let ports: [Int]
    let cpu: Double             // percent of one core
    let memory: Int64           // resident bytes
    let runningFor: TimeInterval
    let cwd: String?
    let diskWritten: Int64      // bytes written since it started
    let hiddenSpace: Int64      // deleted files it still holds open
    let hiddenFiles: [String]
    let warnings: [ServiceWarning]

    var worst: ServiceWarning.Level? { warnings.map(\.level).max { $0.rawValue < $1.rawValue } }
    var isLeftover: Bool { warnings.contains { $0.level == .problem } }
    var brewService: String? {
        guard ppid == 1, let r = command.range(of: #"/(?:usr/local|opt/homebrew)/opt/([^/]+)/"#, options: .regularExpression) else { return nil }
        return command[r].split(separator: "/").dropLast().last.map(String.init)
    }
}

// MARK: - Known programs

private let DATABASES: Set<String> = ["mysqld", "mariadbd", "postgres", "postmaster", "redis-server", "mongod", "memcached",
                                      "clickhouse", "meilisearch", "typesense-server", "valkey-server", "influxd", "elasticsearch"]
private let CONTAINERS: Set<String> = ["com.docker.backend", "com.docker.vpnkit", "com.docker.virtualization", "vpnkit", "qemu-system-aarch64",
                                       "qemu-system-x86_64", "colima", "limactl", "orbstack", "com.apple.Virtualization.VirtualMachine"]
private let AI_TOOLS: Set<String> = ["ollama", "llama-server", "chroma", "lms", "LM Studio"]
private let DEV: Set<String> = ["node", "bun", "deno", "php", "php-fpm", "python", "python3", "ruby", "java", "esbuild", "nginx",
                                "httpd", "caddy", "uvicorn", "gunicorn", "rails", "puma", "dotnet", "go", "air", "hugo", "astro", "vite"]

func classify(_ exe: String) -> ServiceKind? {
    let e = exe.lowercased()
    if DATABASES.contains(exe) || DATABASES.contains(e) { return .database }
    if CONTAINERS.contains(exe) || e.hasPrefix("com.docker") || e.hasPrefix("qemu-system") { return .container }
    if AI_TOOLS.contains(exe) || e.hasPrefix("ollama") { return .ai }
    if DEV.contains(e) || e.hasPrefix("python3") || e.hasPrefix("php") || e.hasPrefix("next-") || e.hasPrefix("ruby") { return .devServer }
    return nil
}

/// "node /x/y/node_modules/.bin/next dev" → "node · next dev". Keeps names short and recognisable.
func friendlyName(exe: String, command: String) -> String {
    // Programs that rename themselves ("next-server (v16.4.6)") show that name.
    if !command.hasPrefix("/"), let first = command.split(separator: " ").first, String(first) != exe,
       !["node", "bun", "deno", "python", "python3", "ruby", "php", "java"].contains(String(first)) {
        let n = command.components(separatedBy: " (").first ?? command
        return String(n.prefix(40)).trimmingCharacters(in: .whitespaces)
    }
    let runtimes: Set<String> = ["node", "bun", "deno", "python", "python3", "ruby", "php", "java"]
    guard runtimes.contains(exe.lowercased()) || exe.lowercased().hasPrefix("python3") else { return exe }
    func match(_ pattern: String) -> String? {
        guard let r = command.range(of: pattern, options: .regularExpression) else { return nil }
        return String(command[r])
    }
    // npm tools: ".../node_modules/.bin/next dev" or ".../node_modules/next/dist/bin/next dev"
    if let m = match(#"node_modules/(?:\.bin/)?([\w@.-]+)(?:/[\w./-]*)?( [a-z][\w:-]*)?"#) {
        let parts = m.replacingOccurrences(of: "node_modules/", with: "").replacingOccurrences(of: ".bin/", with: "")
        let tool = parts.split(separator: "/").first.map(String.init) ?? parts
        let sub = m.split(separator: " ").dropFirst().first.map { " " + $0 } ?? ""
        return "\(exe) · \(tool.split(separator: " ").first ?? "")\(sub)"
    }
    if command.contains(" -e ") || command.contains(" -c ") { return "\(exe) · inline script" }
    if let m = match(#"[\w.-]+\.(?:m?js|cjs|ts|mts|py|php|rb|jar)\b"#) { return "\(exe) · \(m)" }
    let args = command.split(separator: " ").dropFirst().map(String.init).filter { !$0.hasPrefix("-") }
    guard let first = args.first else { return exe }
    return "\(exe) · \((first as NSString).lastPathComponent)"
}

/// "bun.exe" → "bun"; ".../claude/versions/2.1.322" → "claude".
func programName(_ path: String) -> String {
    var comps = (path as NSString).pathComponents
    var name = comps.last ?? path
    while let c = comps.last, c.first?.isNumber == true || ["versions", "bin", "current"].contains(c) {
        comps.removeLast(); name = comps.last ?? name
    }
    if name.hasSuffix(".exe") { name = String(name.dropLast(4)) }
    return name
}

/// ps elapsed time "[[dd-]hh:]mm:ss" → seconds.
func parseElapsed(_ s: String) -> TimeInterval {
    var days = 0.0, rest = Substring(s)
    if let dash = s.firstIndex(of: "-") { days = Double(s[..<dash]) ?? 0; rest = s[s.index(after: dash)...] }
    let parts = rest.split(separator: ":").compactMap { Double($0) }
    var secs = 0.0
    for p in parts { secs = secs * 60 + p }
    return days * 86400 + secs
}

/// Real executable path (command lines split badly when the path has spaces, like "Visual Studio Code.app").
func exePath(_ pid: pid_t, fallback: String) -> String {
    var buf = [CChar](repeating: 0, count: 4096)
    let n = proc_pidpath(pid, &buf, UInt32(buf.count))
    return n > 0 ? String(cString: buf) : String(fallback.split(separator: " ").first ?? "")
}

/// Bytes the process has written to disk since it started (works for your own processes, no password).
func diskBytesWritten(_ pid: pid_t) -> Int64 {
    var info = rusage_info_v2()
    let r = withUnsafeMutablePointer(to: &info) { p in
        p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
    }
    return r == 0 ? Int64(clamping: info.ri_diskio_byteswritten) : 0
}

// MARK: - lsof parsing (field output, -F)

/// `lsof -F pn` listening sockets → pid: [ports]
func parseListening(_ out: String) -> [pid_t: [Int]] {
    var map: [pid_t: Set<Int>] = [:], pid: pid_t = 0
    for line in out.split(separator: "\n") {
        guard let tag = line.first else { continue }
        let v = line.dropFirst()
        if tag == "p" { pid = pid_t(v) ?? 0 }
        else if tag == "n", pid > 0, let colon = v.lastIndex(of: ":"), let port = Int(v[v.index(after: colon)...]) {
            map[pid, default: []].insert(port)
        }
    }
    return map.mapValues { $0.sorted() }
}

/// `lsof +L1 -F psin` deleted-but-open files → pid: (bytes, paths). The same file opened twice counts once.
func parseHidden(_ out: String) -> [pid_t: (bytes: Int64, files: [String])] {
    var res: [pid_t: (bytes: Int64, files: [String])] = [:]
    var seen = Set<String>()
    var pid: pid_t = 0, size: Int64 = 0, inode = ""
    for line in out.split(separator: "\n") {
        guard let tag = line.first else { continue }
        let v = String(line.dropFirst())
        switch tag {
        case "p": pid = pid_t(v) ?? 0
        case "f": size = 0; inode = ""
        case "s": size = Int64(v) ?? 0
        case "i": inode = v
        case "n":
            guard pid > 0, size > 0, seen.insert("\(pid):\(inode.isEmpty ? v : inode)").inserted else { continue }
            var e = res[pid] ?? (0, [])
            e.bytes += size
            e.files.append(v)
            res[pid] = e
        default: break
        }
    }
    return res
}

/// `lsof -d cwd -F pn` → pid: working folder
func parseCwd(_ out: String) -> [pid_t: String] {
    var map: [pid_t: String] = [:], pid: pid_t = 0
    for line in out.split(separator: "\n") {
        guard let tag = line.first else { continue }
        if tag == "p" { pid = pid_t(line.dropFirst()) ?? 0 }
        else if tag == "n", pid > 0 { map[pid] = String(line.dropFirst()) }
    }
    return map
}

// MARK: - Scan

private struct PSRow { let pid: pid_t; let ppid: pid_t; let cpu: Double; let rss: Int64; let elapsed: TimeInterval; let command: String }

private func psRows() -> [PSRow] {
    let uid = getuid()
    return sh("ps -axo pid=,ppid=,uid=,pcpu=,rss=,etime=,command=", timeout: 15).out.split(separator: "\n").compactMap { line in
        let f = line.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true)
        guard f.count == 7, let pid = pid_t(f[0]), let ppid = pid_t(f[1]), let u = UInt32(f[2]), u == uid else { return nil }
        return PSRow(pid: pid, ppid: ppid, cpu: Double(f[3]) ?? 0, rss: (Int64(f[4]) ?? 0) * 1024,
                     elapsed: parseElapsed(String(f[5])), command: String(f[6]))
    }
}

/// Folders a process says it works in (`--datadir=/x`, `--dir /x`). If one is gone, the process is a leftover.
func declaredFolders(_ command: String) -> [String] {
    let pattern = #"--(?:datadir|data-dir|dir|basedir-data|dbpath|socket)[= ]([^\s]+)"#
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = command as NSString
    return re.matches(in: command, range: NSRange(location: 0, length: ns.length)).compactMap { m in
        let p = ns.substring(with: m.range(at: 1))
        guard p.hasPrefix("/") else { return nil }
        return p.hasSuffix(".sock") ? (p as NSString).deletingLastPathComponent : p
    }
}

func analyze(name: String, command: String, kind: ServiceKind, cwd: String?, ppid: pid_t, cpu: Double,
             runningFor: TimeInterval, written: Int64, hidden: Int64, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [ServiceWarning] {
    var w: [ServiceWarning] = []
    let gone = declaredFolders(command).filter { !fileExists($0) }
    if let first = gone.first {
        w.append(.init(level: .problem, text: "Its data folder was deleted (\(first)). It is left over and safe to stop."))
    } else if let c = cwd, c != "/", !fileExists(c) {
        w.append(.init(level: .problem, text: "The folder it was started in no longer exists. It is left over and safe to stop."))
    }
    if hidden >= 50_000_000 {
        w.append(.init(level: .problem, text: "Holds \(human(hidden)) of deleted files. Stopping it gives that space back."))
    }
    let where_ = (command + " " + (cwd ?? "")).lowercased()
    if where_.contains("/tmp/") || where_.contains("/.claude/worktrees/") || where_.contains("/claude-") {
        w.append(.init(level: .notice, text: "Started from a temporary folder, usually by an AI agent or a script."))
    }
    if written >= 10_000_000_000 {
        w.append(.init(level: .notice, text: "Has written \(human(written)) to disk since it started."))
    }
    if kind == .devServer, runningFor > 3 * 86400, cpu < 0.5 {
        w.append(.init(level: .info, text: "Running for \(Int(runningFor / 86400)) days without doing much."))
    }
    return w
}

/// Everything you have running locally that acts like a service. Your own processes only.
func scanServices() -> [LocalService] {
    let uid = getuid()
    let rows = psRows()
    let listening = parseListening(sh("lsof -nP -a -u \(uid) -iTCP -sTCP:LISTEN -F pn", timeout: 20).out)
    let hidden = parseHidden(sh("lsof -nP -a -u \(uid) +L1 -F psin", timeout: 25).out)
    let me = ProcessInfo.processInfo.processIdentifier

    struct Pick { let row: PSRow; let exe: String; let kind: ServiceKind }
    var picks: [Pick] = []
    for r in rows where r.pid != me {
        let path = exePath(r.pid, fallback: r.command)
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/sbin/") || path.hasPrefix("/sbin/") { continue }
        let exe = programName(path)
        let known = classify(exe)
        let ports = listening[r.pid] ?? []
        let held = hidden[r.pid]?.bytes ?? 0
        let inApp = path.contains(".app/Contents/")
        // Plain apps belong on the System Monitor page; here only servers, known tools and anything holding space.
        let keep = held >= 50_000_000 || (known != nil && (!inApp || known == .container)) || (!ports.isEmpty && !inApp)
        if keep { picks.append(Pick(row: r, exe: exe, kind: known ?? .other)) }
    }
    let cwds = picks.isEmpty ? [:] : parseCwd(sh("lsof -nP -a -d cwd -p \(picks.map { String($0.row.pid) }.joined(separator: ",")) -F pn", timeout: 15).out)

    return picks.map { p in
        let r = p.row
        let written = diskBytesWritten(r.pid)
        var h = hidden[r.pid] ?? (0, [])
        if h.bytes < 1_000_000 { h = (0, []) }
        let cwd = cwds[r.pid]
        let name = friendlyName(exe: p.exe, command: r.command)
        return LocalService(pid: r.pid, ppid: r.ppid, name: name, command: r.command, kind: p.kind,
                            ports: listening[r.pid] ?? [], cpu: r.cpu, memory: r.rss, runningFor: r.elapsed, cwd: cwd,
                            diskWritten: written, hiddenSpace: h.bytes, hiddenFiles: h.files,
                            warnings: analyze(name: name, command: r.command, kind: p.kind, cwd: cwd, ppid: r.ppid, cpu: r.cpu,
                                              runningFor: r.elapsed, written: written, hidden: h.bytes))
    }
    .sorted { a, b in
        if a.isLeftover != b.isLeftover { return a.isLeftover }
        if a.hiddenSpace != b.hiddenSpace { return a.hiddenSpace > b.hiddenSpace }
        return a.memory > b.memory
    }
}

/// Background check (launch, hourly, and whenever free space suddenly drops): finds leftovers and held space,
/// feeds the dashboard card, and sends one notification (at most every 6 hours) when 2 GB or more is held.
final class ServiceWatch: ObservableObject {
    static let shared = ServiceWatch()
    @Published var running = 0
    @Published var leftovers = 0
    @Published var held: Int64 = 0
    @Published var checked = false
    private var busy = false
    private var lastNotice: Date?

    func check() {
        guard !busy else { return }
        busy = true
        DispatchQueue.global(qos: .utility).async {
            let s = scanServices()
            let held = s.reduce(0) { $0 + $1.hiddenSpace }
            DispatchQueue.main.async {
                self.busy = false
                self.running = s.count; self.leftovers = s.filter(\.isLeftover).count; self.held = held; self.checked = true
                guard held >= 2_000_000_000, self.lastNotice.map({ Date().timeIntervalSince($0) > 6 * 3600 }) ?? true else { return }
                self.lastNotice = Date()
                let who = s.first { $0.hiddenSpace > 0 }?.name ?? "A process"
                log("HELD SPACE \(human(held)) by \(who)")
                notify("\(human(held)) of disk is held by a leftover process",
                       "\(who) keeps deleted files open, so the space can't be reused. Open Running Services in Wasevo Cleaner to stop it.")
            }
        }
    }
}

// MARK: - Stop

enum StopResult { case stopped, stillRunning, refused(String) }

/// Asks a process to quit; with `force`, ends it (SIGKILL). Only your own, non-system processes, never this app.
func stopService(_ s: LocalService, force: Bool) -> StopResult {
    let path = exePath(s.pid, fallback: s.command)
    if s.pid <= 1 || s.pid == ProcessInfo.processInfo.processIdentifier { return .refused("That process can't be stopped from here.") }
    if path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/sbin/") { return .refused("macOS system processes are never stopped.") }
    // The process id could have been reused since the scan: only act if it is still the same program.
    let now = sh("ps -o command= -p \(s.pid)", timeout: 5).out.trimmingCharacters(in: .whitespacesAndNewlines)
    if now.isEmpty { return .stopped }
    guard now == s.command else { return .refused("It already stopped and something else now uses that id. Rescan and try again.") }
    guard kill(s.pid, force ? SIGKILL : SIGTERM) == 0 else {
        return errno == ESRCH ? .stopped : .refused("macOS did not allow stopping it (\(String(cString: strerror(errno)))).")
    }
    log("\(force ? "FORCE STOPPED" : "STOPPED") pid \(s.pid) \(s.name) · held \(human(s.hiddenSpace)) · \(s.command.prefix(200))")
    for _ in 0..<(force ? 10 : 30) {          // up to 1 s after SIGKILL, 3 s after SIGTERM
        if kill(s.pid, 0) != 0 { return .stopped }
        usleep(100_000)
    }
    return .stillRunning
}
