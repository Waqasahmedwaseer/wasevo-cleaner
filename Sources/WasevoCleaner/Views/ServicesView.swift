import SwiftUI
import AppKit

// Running Services page: local servers, databases, dev servers and containers, with leftovers
// (deleted folder, held deleted files, temporary agent runs) listed first.

final class ServicesModel: ObservableObject {
    static let shared = ServicesModel()
    @Published var services: [LocalService] = []
    @Published var loading = false
    @Published var loaded = false
    @Published var lastMessage: String?
    private var timer: Timer?

    var leftovers: [LocalService] { services.filter(\.isLeftover) }
    var hiddenTotal: Int64 { services.reduce(0) { $0 + $1.hiddenSpace } }
    var portCount: Int { services.reduce(0) { $0 + $1.ports.count } }

    func load() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let s = scanServices()
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.45)) { self.services = s }
                self.loading = false
                self.loaded = true
            }
        }
    }
    func startAuto() {
        load()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.load() }
    }
    func stopAuto() { timer?.invalidate(); timer = nil }

    /// Runs off the main thread; reports back a short message and whether a force stop is needed.
    func stop(_ s: LocalService, force: Bool, done: @escaping (StopResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = stopService(s, force: force)
            DispatchQueue.main.async {
                switch r {
                case .stopped:
                    self.lastMessage = s.hiddenSpace > 0 ? "Stopped \(s.name). \(human(s.hiddenSpace)) is being given back (it can take a minute to show)."
                                                         : "Stopped \(s.name)."
                case .stillRunning: break
                case .refused(let why): self.lastMessage = why
                }
                done(r)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.load() }
            }
        }
    }
}

enum ServiceFilter: String, CaseIterable { case all = "All", leftovers = "Leftovers", database = "Databases", dev = "Dev servers", container = "Containers", other = "Other" }

struct ServicesView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var m = ServicesModel.shared
    @State private var filter: ServiceFilter = .all
    @State private var confirm: LocalService?
    @State private var forceAsk: LocalService?
    @State private var confirmAll = false
    @State private var expanded: Set<pid_t> = []

    var shown: [LocalService] {
        switch filter {
        case .all: return m.services
        case .leftovers: return m.leftovers
        case .database: return m.services.filter { $0.kind == .database }
        case .dev: return m.services.filter { $0.kind == .devServer }
        case .container: return m.services.filter { $0.kind == .container }
        case .other: return m.services.filter { $0.kind == .other || $0.kind == .ai }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "Running Services",
                       subtitle: "Servers, databases and dev servers running on this Mac, with ports and usage. Stopping never deletes files.") {
                HStack(spacing: 8) {
                    if m.loading { ProgressView().controlSize(.small) }
                    SecondaryButton(title: "Rescan", icon: "arrow.clockwise") { m.load() }
                }
            }
            if !m.loaded && m.loading {
                BusyPanel(text: "Looking at what is running: ports, memory, disk writes and held space")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        summary
                        if !m.leftovers.isEmpty { leftoverBanner }
                        if let msg = m.lastMessage { messageBar(msg) }
                        filterBar
                        if shown.isEmpty {
                            EmptyState(icon: "checkmark.seal", title: filter == .leftovers ? "No leftovers" : "Nothing here",
                                       text: filter == .leftovers ? "Nothing is running from a deleted folder or holding deleted files." : "No running services in this group.")
                                .frame(height: 220)
                        }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in row(s).staggerIn(i) }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 24)
                }
            }
        }
        .onAppear { m.startAuto() }
        .onDisappear { m.stopAuto() }
        .alert("Stop \(confirm?.name ?? "")?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Stop") { if let s = confirm { stop(s, force: false) }; confirm = nil }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { Text(confirmText(confirm)) }
        .alert("\(forceAsk?.name ?? "") is not responding", isPresented: Binding(get: { forceAsk != nil }, set: { if !$0 { forceAsk = nil } })) {
            Button("Force stop", role: .destructive) { if let s = forceAsk { stop(s, force: true) }; forceAsk = nil }
            Button("Leave it running", role: .cancel) { forceAsk = nil }
        } message: { Text("It did not quit when asked. Force stop ends it right away. Files on disk are not touched.") }
        .alert("Stop \(m.leftovers.count) leftover\(m.leftovers.count == 1 ? "" : "s")?", isPresented: $confirmAll) {
            Button("Stop all") { for s in m.leftovers { stop(s, force: false) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("These run from deleted folders or hold deleted files. Stopping them frees \(human(m.leftovers.reduce(0) { $0 + $1.hiddenSpace })). Nothing on disk is deleted.") }
    }

    func stop(_ s: LocalService, force: Bool) {
        m.stop(s, force: force) { r in
            if case .stillRunning = r, !force { forceAsk = s }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { store.refreshDisk() }
        }
    }

    func confirmText(_ s: LocalService?) -> String {
        guard let s else { return "" }
        var t = "It is asked to quit normally. Its files are not deleted."
        if s.kind == .database && !s.isLeftover { t += " Apps or sites that use this database stop working until you start it again." }
        if let b = s.brewService { t += " This is a Homebrew service, so it starts again at login. To turn it off for good, run: brew services stop \(b)" }
        if s.hiddenSpace > 0 { t += " This gives back \(human(s.hiddenSpace))." }
        return t
    }

    // MARK: Pieces

    var summary: some View {
        HStack(spacing: 8) {
            StatChip(value: "\(m.services.count)", label: "running")
            StatChip(value: "\(m.portCount)", label: m.portCount == 1 ? "port open" : "ports open")
            StatChip(value: "\(m.leftovers.count)", label: m.leftovers.count == 1 ? "leftover" : "leftovers", color: m.leftovers.isEmpty ? W.text : W.red)
            StatChip(value: m.hiddenTotal > 0 ? human(m.hiddenTotal) : "Nothing", label: "held by deleted files", color: m.hiddenTotal > 1_000_000_000 ? W.red : W.text)
            Spacer()
        }
    }

    var leftoverBanner: some View {
        Card {
            HStack(spacing: 14) {
                IconBadge(icon: "exclamationmark.triangle.fill", color: W.red, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.hiddenTotal > 0 ? "\(human(m.hiddenTotal)) of disk is held by processes that should not be running"
                                           : "\(m.leftovers.count) process\(m.leftovers.count == 1 ? " is" : "es are") left over")
                        .font(W.body(14, .semibold)).foregroundColor(W.text)
                    Text("Folder scans can't see this space: the files are already deleted, but a running process keeps them open. Stopping it gives the space back.")
                        .font(W.body(11.5)).foregroundColor(W.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                PrimaryButton(title: "Stop leftovers", icon: "stop.circle") { confirmAll = true }
            }
        }
    }

    func messageBar(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundColor(W.orange)
            Text(msg).font(W.body(12)).foregroundColor(W.text)
            Spacer()
            Button { m.lastMessage = nil } label: { Image(systemName: "xmark").foregroundColor(W.faint) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassCard(radius: 12)
    }

    var filterBar: some View {
        Picker("", selection: $filter) {
            ForEach(ServiceFilter.allCases, id: \.self) { f in Text(f.rawValue).tag(f) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func row(_ s: LocalService) -> some View {
        let open = expanded.contains(s.pid)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(icon: s.kind.icon, color: s.isLeftover ? W.red : W.orange, size: 36)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(s.name).font(W.body(13.5, .semibold)).foregroundColor(W.text).lineLimit(1)
                            Pill(s.kind.label, W.faint)
                            ForEach(s.ports.prefix(4), id: \.self) { p in Pill(":\(p)", W.orange300) }
                            if s.isLeftover { Pill("Leftover", W.red, icon: "exclamationmark.triangle.fill") }
                        }
                        HStack(spacing: 14) {
                            metric("CPU", String(format: "%.0f%%", s.cpu), warn: s.cpu > 80)
                            metric("Memory", human(s.memory), warn: s.memory > 2_000_000_000)
                            metric("Written", human(s.diskWritten), warn: s.diskWritten > 10_000_000_000)
                            if s.hiddenSpace > 0 { metric("Held", human(s.hiddenSpace), warn: true) }
                            metric("Running", duration(s.runningFor), warn: false)
                        }
                        ForEach(s.warnings, id: \.self) { w in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: w.level == .problem ? "exclamationmark.triangle.fill" : w.level == .notice ? "info.circle.fill" : "clock")
                                    .font(.system(size: 10)).foregroundColor(color(w.level)).padding(.top, 2)
                                Text(w.text).font(W.body(11.5)).foregroundColor(w.level == .problem ? W.text : W.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        if s.kind == .devServer, let p = s.ports.first, let url = URL(string: "http://localhost:\(p)") {
                            SecondaryButton(title: "Open", icon: "safari") { NSWorkspace.shared.open(url) }
                        }
                        SecondaryButton(title: "Stop", icon: "stop.fill") { confirm = s }
                    }
                }
                Button {
                    withAnimation(.spring(response: 0.35)) { if open { expanded.remove(s.pid) } else { expanded.insert(s.pid) } }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                        Text(open ? "Hide details" : "Details").font(W.body(11))
                    }
                    .foregroundColor(W.faint)
                }
                .buttonStyle(.plain)
                if open { details(s) }
            }
        }
    }

    func details(_ s: LocalService) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailLine("Process id", "\(s.pid)")
            if let c = s.cwd {
                HStack(spacing: 6) {
                    detailLine("Folder", c)
                    if FileManager.default.fileExists(atPath: c) {
                        Button("Show in Finder") { revealInFinder(c) }.buttonStyle(.link).font(W.body(11))
                    }
                }
            }
            detailLine("Command", s.command)
            if !s.hiddenFiles.isEmpty {
                detailLine("Deleted files it holds", s.hiddenFiles.prefix(5).joined(separator: "\n"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(W.bg))
    }

    func detailLine(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(k).font(W.body(11, .semibold)).foregroundColor(W.faint).frame(width: 130, alignment: .leading)
            Text(v).font(W.mono).foregroundColor(W.muted).textSelection(.enabled).lineLimit(6)
        }
    }

    func metric(_ k: String, _ v: String, warn: Bool) -> some View {
        HStack(spacing: 4) {
            Text(k).font(W.body(10.5)).foregroundColor(W.faint)
            Text(v).font(W.body(11.5, .semibold)).foregroundColor(warn ? W.red : W.muted)
        }
    }

    func color(_ l: ServiceWarning.Level) -> Color { l == .problem ? W.red : l == .notice ? W.amber : W.faint }

    func duration(_ t: TimeInterval) -> String {
        if t >= 86400 { return "\(Int(t / 86400))d \(Int(t.truncatingRemainder(dividingBy: 86400) / 3600))h" }
        if t >= 3600 { return "\(Int(t / 3600))h \(Int(t.truncatingRemainder(dividingBy: 3600) / 60))m" }
        return "\(max(1, Int(t / 60)))m"
    }
}
