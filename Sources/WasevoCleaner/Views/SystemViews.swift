import SwiftUI
import Charts
import AppKit

// System monitor (live charts), maintenance tasks and app update check.

/// Animated ring gauge.
struct RingGauge: View {
    let value: Double          // 0…1
    let title: String, valueText: String, sub: String
    var color: Color = W.orange
    var body: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(W.panel2, lineWidth: 8)
                    Circle().trim(from: 0, to: max(0.001, min(1, value)))
                        .stroke(AngularGradient(colors: [color.opacity(0.6), color], center: .center),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.8, dampingFraction: 0.8), value: value)
                    Text("\(Int(value * 100))%").font(W.display(14)).foregroundColor(W.text).rollingNumber()
                        .animation(.spring(response: 0.5), value: Int(value * 100))
                }
                .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(W.body(11, .semibold)).foregroundColor(W.faint)
                    Text(valueText).font(W.display(16)).foregroundColor(W.text).lineLimit(1).minimumScaleFactor(0.7)
                    Text(sub).font(W.body(10)).foregroundColor(W.faint).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

final class HeavyAppsModel: ObservableObject {
    @Published var apps: [AppUsage] = []
    private var timer: Timer?
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func stop() { timer?.invalidate(); timer = nil }
    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let a = heavyApps()
            DispatchQueue.main.async { withAnimation(.spring(response: 0.5)) { self.apps = Array(a.prefix(8)) } }
        }
    }
}

struct MonitorView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var mon = SystemMonitor.shared
    @StateObject private var heavy = HeavyAppsModel()
    @State private var quitting: AppUsage?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "System Monitor", subtitle: "Live CPU, memory, disk and battery. Updates every 2 seconds. View only.")
            ScrollView {
                VStack(spacing: 14) {
                    gauges
                    chartCard
                    appsCard
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
        .onAppear { mon.start(); heavy.start() }
        .onDisappear { heavy.stop() }
        .alert("Quit \(quitting?.name ?? "")?", isPresented: Binding(get: { quitting != nil }, set: { if !$0 { quitting = nil } })) {
            Button("Quit") { if let a = quitting { _ = quitApp(pid: a.pid); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { heavy.refresh() } }; quitting = nil }
            Button("Cancel", role: .cancel) { quitting = nil }
        } message: { Text("Same as pressing ⌘Q in the app. If it has unsaved work, it will ask you first.") }
    }

    var gauges: some View {
        let mem = mon.memory
        let memFrac = mem.total > 0 ? Double(mem.used) / Double(mem.total) : 0
        return HStack(spacing: 12) {
            RingGauge(value: mon.cpu, title: "CPU", valueText: "\(Int(mon.cpu * 100))%", sub: thermalText,
                      color: mon.cpu > 0.8 ? W.red : W.orange)
            RingGauge(value: memFrac, title: "MEMORY", valueText: "\(human(mem.used))",
                      sub: "of \(human(mem.total)) · swap \(human(mem.swapUsed))", color: memFrac > 0.85 ? W.amber : W.orange)
            RingGauge(value: store.usedFraction, title: "DISK", valueText: "\(human(store.free))",
                      sub: "free of \(human(store.total))", color: store.isLow ? W.red : W.orange)
            if let b = mon.battery {
                RingGauge(value: Double(b.percent) / 100, title: "BATTERY",
                          valueText: "\(b.percent)%",
                          sub: [b.charging ? "Charging" : nil, b.health.map { "Health \(Int($0 * 100))%" }, b.cycles.map { "\($0) cycles" }].compactMap { $0 }.joined(separator: " · "),
                          color: b.percent < 20 ? W.red : W.green)
            }
        }
    }

    var thermalText: String {
        switch mon.thermal {
        case .nominal: return "Temperature normal"
        case .fair: return "Warm"
        case .serious: return "Hot: macOS is slowing the CPU"
        case .critical: return "Very hot: CPU heavily slowed"
        @unknown default: return ""
        }
    }

    var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Last 3 minutes").font(W.body(13, .semibold)).foregroundColor(W.text)
                    Spacer()
                    legend("CPU", W.orange); legend("Memory", Color(hex: 0x7C8CFF))
                }
                Chart {
                    ForEach(mon.samples) { s in
                        AreaMark(x: .value("Time", s.t), y: .value("CPU", s.cpu * 100), series: .value("Kind", "CPU"))
                            .foregroundStyle(LinearGradient(colors: [W.orange.opacity(0.35), W.orange.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Time", s.t), y: .value("CPU", s.cpu * 100), series: .value("Kind", "CPU"))
                            .foregroundStyle(W.orange).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.catmullRom)
                        LineMark(x: .value("Time", s.t), y: .value("Memory", s.mem * 100), series: .value("Kind", "Memory"))
                            .foregroundStyle(Color(hex: 0x7C8CFF)).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                    AxisGridLine().foregroundStyle(W.line)
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(W.body(9)).foregroundColor(W.faint) }
                } }
                .chartXAxis(.hidden)
                .frame(height: 180)
                .animation(.easeOut(duration: 0.4), value: mon.samples.count)
            }
        }
    }

    func legend(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 7, height: 7); Text(t).font(W.body(11)).foregroundColor(W.faint) }
    }

    var appsCard: some View {
        let maxMem = max(1, heavy.apps.first?.memory ?? 1)
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Open apps using the most").font(W.body(13, .semibold)).foregroundColor(W.text)
                Text("Memory and CPU include each app's helper processes. Quitting is the same as ⌘Q.").font(W.body(11)).foregroundColor(W.faint)
                ForEach(heavy.apps) { a in
                    HStack(spacing: 12) {
                        if let i = a.icon { Image(nsImage: i).resizable().frame(width: 26, height: 26) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(a.name).font(W.body(12, .semibold)).foregroundColor(W.text)
                            GeometryReader { g in
                                Capsule().fill(W.accent).frame(width: g.size.width * CGFloat(Double(a.memory) / Double(maxMem)))
                                    .animation(.spring(response: 0.6), value: a.memory)
                            }
                            .frame(height: 5)
                        }
                        Text(human(a.memory)).font(W.body(12, .semibold)).foregroundColor(W.muted).frame(width: 74, alignment: .trailing)
                        Text(String(format: "%.0f%% CPU", a.cpu)).font(W.body(11)).foregroundColor(a.cpu > 50 ? W.amber : W.faint).frame(width: 70, alignment: .trailing)
                        if a.bundleId == "com.apple.finder" { Text("").frame(width: 66) }
                        else { SecondaryButton(title: "Quit") { quitting = a } }
                    }
                    .padding(.vertical, 4)
                    .transition(.opacity)
                }
            }
        }
    }
}

// MARK: - Maintenance

final class MaintenanceModel: ObservableObject {
    static let shared = MaintenanceModel()
    @Published var running: String?
    @Published var results: [String: (ok: Bool, output: String)] = [:]
}

struct MaintenanceView: View {
    @ObservedObject private var m = MaintenanceModel.shared
    private var running: String? { m.running }
    private var results: [String: (ok: Bool, output: String)] { m.results }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Maintenance", subtitle: "Apple's own maintenance commands, run only when you click. Nothing here deletes your files.")
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(MAINTENANCE_TASKS.enumerated()), id: \.element.id) { i, t in card(t).staggerIn(i) }
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
    }

    func card(_ t: MaintenanceTask) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    IconBadge(icon: t.icon, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(t.title).font(W.body(14, .semibold)).foregroundColor(W.text)
                            if t.needsAdmin { Pill("Asks for your Mac password", W.faint) }
                            if t.heavy { Pill("Heavy", W.amber) }
                        }
                        Text(t.what).font(W.body(12)).foregroundColor(W.muted).fixedSize(horizontal: false, vertical: true)
                        Text("When: \(t.when)").font(W.body(11)).foregroundColor(W.faint)
                    }
                    Spacer()
                    if running == t.id { ProgressView().controlSize(.small).padding(.top, 8) }
                    else { SecondaryButton(title: "Run", icon: "play.fill") { run(t) }.disabled(running != nil) }
                }
                if let r = results[t.id] {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundColor(r.ok ? W.green : W.amber)
                        Text(r.output.isEmpty ? (r.ok ? "Done." : "Did not finish.") : String(r.output.suffix(600)))
                            .font(W.mono).foregroundColor(W.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(W.bg))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    func run(_ t: MaintenanceTask) {
        let m = self.m
        m.running = t.id
        Activity.shared.start(.maintenance, t.title)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = runMaintenance(t)
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4)) { m.results[t.id] = r; m.running = nil }
                Activity.shared.finish(.maintenance, "\(t.title): \(r.ok ? "done" : "did not finish").")
            }
        }
    }
}

// MARK: - Updates

final class UpdatesModel: ObservableObject {
    static let shared = UpdatesModel()
    @Published var list: [AppUpdate] = []
    @Published var state: ToolState = .idle
    @Published var progress = ""
    @Published var storeApps = 0
    @Published var copied: String?

    func check() {
        state = .busy
        Activity.shared.start(.updates, "Checking updates")
        DispatchQueue.global(qos: .userInitiated).async {
            let l = checkUpdates { p in DispatchQueue.main.async { self.progress = p } }
            let n = appStoreAppCount()
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5)) { self.list = l; self.storeApps = n; self.state = .done }
                Activity.shared.finish(.updates, "\(l.count) updates available.")
            }
        }
    }
}

struct UpdatesView: View {
    @ObservedObject private var m = UpdatesModel.shared

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "App Updates", subtitle: "Which apps have a newer version. Check only: nothing is downloaded or installed by Wasevo.") {
                if m.state == .done { SecondaryButton(title: "Check again", icon: "arrow.clockwise") { m.check() } }
            }
            switch m.state {
            case .idle:
                StartPanel(icon: "arrow.triangle.2.circlepath", title: "Check for app updates",
                           text: "Reads each app's own update feed and your Homebrew list. You then update in the app itself.",
                           button: "Check for updates") { m.check() }
            case .busy: BusyPanel(text: m.progress)
            case .done:
                ScrollView {
                    VStack(spacing: 0) {
                        if m.storeApps > 0 {
                            HStack {
                                IconBadge(icon: "bag", color: Color(hex: 0x4DA3FF), size: 34)
                                Text("\(m.storeApps) apps come from the App Store and update there.").font(W.body(12)).foregroundColor(W.muted)
                                Spacer()
                                SecondaryButton(title: "Open App Store updates", icon: "arrow.up.forward") {
                                    NSWorkspace.shared.open(URL(string: "macappstore://showUpdatesPage")!)
                                }
                            }
                            .padding(.vertical, 10)
                            Divider().overlay(W.line)
                        }
                        if m.list.isEmpty {
                            EmptyState(icon: "checkmark.seal", title: "Everything is up to date", text: "No newer versions were found.").frame(height: 300)
                        }
                        ForEach(Array(m.list.enumerated()), id: \.element.id) { i, u in row(u).staggerIn(i); Divider().overlay(W.line) }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 20)
                }
            }
            if let c = m.copied { Toast(text: "Copied: \(c). Paste it in Terminal.") { m.copied = nil } }
        }
        .animation(.spring(response: 0.4), value: m.copied)
    }

    func row(_ u: AppUpdate) -> some View {
        HStack(spacing: 14) {
            if u.path.hasPrefix("/") { Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 32, height: 32) }
            else { IconBadge(icon: "shippingbox", color: W.amber, size: 32) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) { Text(u.name).font(W.body(13, .semibold)).foregroundColor(W.text); Pill(u.source, W.faint) }
                HStack(spacing: 6) {
                    Text(u.installed).font(W.mono).foregroundColor(W.faint)
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundColor(W.orange)
                    Text(u.latest).font(W.mono).foregroundColor(W.orange300)
                }
            }
            Spacer()
            if let cmd = u.command {
                SecondaryButton(title: "Copy command", icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cmd, forType: .string); m.copied = cmd
                }
            } else {
                SecondaryButton(title: "Open app", icon: "arrow.up.forward.app") { NSWorkspace.shared.open(URL(fileURLWithPath: u.path)) }
            }
        }
        .padding(.vertical, 10)
    }
}
