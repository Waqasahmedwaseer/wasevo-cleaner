import SwiftUI

// Home dashboard (like CleanMyMac's Smart Care): one scan checks junk, duplicates, app updates and
// startup items together; each card shows the latest result and opens its page.

/// Runs every read-only check at once. Nothing is cleaned until you review and confirm.
func scanEverything(_ store: Store) {
    store.scan()
    if DupModel.shared.state != .busy { DupModel.shared.scan() }
    if UpdatesModel.shared.state != .busy { UpdatesModel.shared.check() }
    if !StartupModel.shared.loading { StartupModel.shared.load() }
}

struct HealthGrid: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var dup = DupModel.shared
    @ObservedObject private var upd = UpdatesModel.shared
    @ObservedObject private var startup = StartupModel.shared
    @ObservedObject private var mon = SystemMonitor.shared
    @ObservedObject private var act = Activity.shared

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 14) {
            card(.duplicates, "Duplicates",
                 value: dup.state == .done ? human(dup.wasted) : "Not checked",
                 sub: dup.state == .done ? "\(dup.groups.count) groups of identical files" : "Byte-for-byte copies")
            card(.updates, "App updates",
                 value: upd.state == .done ? "\(upd.list.count)" : "Not checked",
                 sub: upd.state == .done ? (upd.list.isEmpty ? "Everything is up to date" : "apps have a newer version") : "Apps and Homebrew")
            card(.startup, "Startup items",
                 value: startup.items.isEmpty ? "Not checked" : "\(startup.items.filter { !$0.disabled }.count) on",
                 sub: startup.items.isEmpty ? "Helpers that start by themselves" : "\(startup.items.filter(\.running).count) running now")
            card(.monitor, "Memory",
                 value: "\(Int(Double(mon.memory.used) / Double(max(1, mon.memory.total)) * 100))%",
                 sub: "\(human(mon.memory.used)) of \(human(mon.memory.total)) in use")
            card(.monitor, "Battery",
                 value: mon.battery.map { "\($0.percent)%" } ?? "No battery",
                 sub: mon.battery?.health.map { "Health \(Int($0 * 100))% · \(mon.battery?.cycles ?? 0) cycles" } ?? "Desktop Mac")
            card(.map, "Disk",
                 value: human(store.free),
                 sub: "free of \(human(store.total))")
        }
    }

    func card(_ p: Page, _ title: String, value: String, sub: String) -> some View {
        Button { Nav.shared.open(p) } label: {
            HStack(spacing: 12) {
                GlossyIcon(icon: p.icon, tint: p.tint, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(W.body(11.5, .medium)).foregroundColor(W.faint)
                    HStack(spacing: 6) {
                        Text(value).font(W.display(17)).foregroundColor(W.text).lineLimit(1).minimumScaleFactor(0.7)
                            .rollingNumber().animation(.spring(response: 0.4), value: value)
                        if act.running[p] != nil { ProgressView().controlSize(.mini) }
                    }
                    Text(sub).font(W.body(11)).foregroundColor(W.faint).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(W.faint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}
