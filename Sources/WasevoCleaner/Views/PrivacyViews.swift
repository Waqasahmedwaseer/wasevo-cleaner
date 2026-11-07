import SwiftUI
import AppKit

// Browser privacy and startup items.

final class PrivacyModel: ObservableObject {
    static let shared = PrivacyModel()
    @Published var browsers: [BrowserSpec] = []
    @Published var items: [String: [PrivacyItem]] = [:]
    @Published var chosen: Set<String> = []
    @Published var loading = false
    @Published var running: Set<String> = []
    @Published var message: String?
    @Published var messageIsError = false

    func load() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let b = installedBrowsers()
            var map: [String: [PrivacyItem]] = [:]
            for x in b { map[x.name] = privacyItems(for: x) }
            let snap = ProcSnapshot.take()
            let run = Set(b.filter { snap.running($0.process) != nil }.map(\.name))
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5)) { self.browsers = b; self.items = map; self.running = run; self.loading = false }
                // only caches are pre-selected; history and cookies are your choice
                self.chosen = Set(map.values.flatMap { $0 }.filter { $0.kind == .cache }.map(\.id))
            }
        }
    }

    func size(_ b: BrowserSpec) -> Int64 { (items[b.name] ?? []).filter { chosen.contains($0.id) }.reduce(0) { $0 + $1.size } }

    func clean(_ b: BrowserSpec) {
        let pick = (items[b.name] ?? []).filter { chosen.contains($0.id) }
        DispatchQueue.global(qos: .userInitiated).async {
            let r = clearPrivacy(pick, browser: b)
            DispatchQueue.main.async {
                self.messageIsError = r.error != nil
                self.message = r.error ?? "\(b.name): \(pick.map(\.kind.rawValue.localizedLowercase).joined(separator: ", ")) moved to the Trash."
                if r.error == nil { self.load() }
            }
        }
    }
}

struct PrivacyView: View {
    @ObservedObject private var m = PrivacyModel.shared
    @State private var confirm: BrowserSpec?

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "Browser Privacy", subtitle: "Clear caches, history and cookies per browser. Saved passwords, bookmarks and autofill are never touched.") {
                SecondaryButton(title: "Refresh", icon: "arrow.clockwise") { m.load() }
            }
            if m.loading && m.browsers.isEmpty {
                BusyPanel(text: "Looking at your browsers…")
            } else if m.browsers.isEmpty {
                EmptyState(icon: "globe", title: "No supported browsers", text: "Chrome, Brave, Edge, Arc, Vivaldi and Firefox are supported. For Safari, use History > Clear History in Safari.")
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(Array(m.browsers.enumerated()), id: \.element.name) { i, b in card(b).staggerIn(i) }
                        Text("Safari keeps its data behind macOS privacy protection. In Safari, use History > Clear History.")
                            .font(W.body(11)).foregroundColor(W.faint)
                    }
                    .padding(.horizontal, 28).padding(.bottom, 20)
                }
            }
            if let msg = m.message { Toast(text: msg, color: m.messageIsError ? W.amber : W.green) { m.message = nil } }
        }
        .animation(.spring(response: 0.4), value: m.message)
        .onAppear { if m.browsers.isEmpty { m.load() } }
        .alert("Clean \(confirm?.name ?? "")?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Move to Trash") { if let b = confirm { m.clean(b) }; confirm = nil }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: {
            Text(cookiesChosen(confirm) ? "Cookies are included: you will be signed out of websites in this browser." : "The chosen data moves to the Trash.")
        }
    }

    func cookiesChosen(_ b: BrowserSpec?) -> Bool {
        guard let b else { return false }
        return (m.items[b.name] ?? []).contains { $0.kind == .cookies && m.chosen.contains($0.id) }
    }

    func card(_ b: BrowserSpec) -> some View {
        let list = m.items[b.name] ?? []
        let open = m.running.contains(b.name)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    browserIcon(b).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.name).font(W.body(15, .semibold)).foregroundColor(W.text)
                        if open { Label("Open: quit it to clean", systemImage: "pause.circle").font(W.body(11, .semibold)).foregroundColor(W.amber) }
                    }
                    Spacer()
                    Text(m.size(b) > 0 ? human(m.size(b)) : "Nothing selected").font(W.display(m.size(b) > 0 ? 16 : 13))
                        .foregroundColor(m.size(b) > 0 ? W.orange300 : W.faint).rollingNumber()
                        .animation(.spring(response: 0.3), value: m.size(b))
                    PrimaryButton(title: "Clean", icon: "sparkles", disabled: open || m.size(b) == 0) { confirm = b }
                }
                ForEach(list) { it in
                    let on = m.chosen.contains(it.id)
                    HStack(spacing: 12) {
                        CheckBox(on: on)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(it.kind.rawValue).font(W.body(13, .semibold)).foregroundColor(W.text)
                                if list.map(\.profile).uniqued().count > 1 { Pill(it.profile, W.faint) }
                                if it.kind == .cookies { Pill("Signs you out", W.amber) }
                            }
                            Text(it.detail).font(W.body(11)).foregroundColor(W.faint)
                        }
                        Spacer()
                        Text(human(it.size)).font(W.body(12, .semibold)).foregroundColor(W.muted)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { if on { m.chosen.remove(it.id) } else { m.chosen.insert(it.id) } } }
                }
            }
        }
    }

    @ViewBuilder func browserIcon(_ b: BrowserSpec) -> some View {
        let ids = ["Google Chrome": "com.google.Chrome", "Brave": "com.brave.Browser", "Microsoft Edge": "com.microsoft.edgemac",
                   "Arc": "company.thebrowser.Browser", "Vivaldi": "com.vivaldi.Vivaldi", "Firefox": "org.mozilla.firefox"]
        if let id = ids[b.name], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else { IconBadge(icon: "globe") }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] { var s = Set<Element>(); return filter { s.insert($0).inserted } }
}

// MARK: - Startup items

final class StartupModel: ObservableObject {
    static let shared = StartupModel()
    @Published var items: [LaunchItem] = []
    @Published var loading = false
    @Published var busy: String?
    @Published var message: String?

    func load() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let l = listLaunchItems()
            DispatchQueue.main.async { withAnimation(.spring(response: 0.5)) { self.items = l; self.loading = false } }
        }
    }

    func set(_ it: LaunchItem, on: Bool) {
        busy = it.id
        DispatchQueue.global(qos: .userInitiated).async {
            let err = setLaunchItem(it, enabled: on)
            let fresh = listLaunchItems()
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35)) { self.items = fresh }
                self.busy = nil
                self.message = err ?? "\(it.owner) helper turned \(on ? "on" : "off"). \(on ? "" : "Turn it back on here anytime.")"
            }
        }
    }
}

struct StartupView: View {
    @ObservedObject private var m = StartupModel.shared

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "Startup Items", subtitle: "Helpers that start by themselves in the background. Turning one off is fully reversible; nothing is deleted.") {
                HStack(spacing: 10) {
                    SecondaryButton(title: "Open at Login apps", icon: "arrow.up.forward.app") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    SecondaryButton(title: "Refresh", icon: "arrow.clockwise") { m.load() }
                }
            }
            if m.loading && m.items.isEmpty {
                BusyPanel(text: "Reading startup items…")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach([LaunchScope.user, .allUsers, .system], id: \.self) { scope in
                            let list = m.items.filter { $0.scope == scope }
                            if !list.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        Text(scope.rawValue.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundColor(W.faint)
                                        if scope == .system { Text("· shown only, needs an admin to change").font(W.body(10)).foregroundColor(W.faint) }
                                    }
                                    .padding(.bottom, 8)
                                    ForEach(Array(list.enumerated()), id: \.element.id) { i, it in row(it).staggerIn(i); Divider().overlay(W.line) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 20)
                }
            }
            if let msg = m.message { Toast(text: msg) { m.message = nil } }
        }
        .animation(.spring(response: 0.4), value: m.message)
        .onAppear { if m.items.isEmpty { m.load() } }
    }

    /// The owning app's icon when the helper lives inside an app, otherwise a symbol.
    @ViewBuilder func launchIcon(_ it: LaunchItem) -> some View {
        if let r = it.program.range(of: ".app/") {
            Image(nsImage: NSWorkspace.shared.icon(forFile: String(it.program[..<r.lowerBound]) + ".app")).resizable().frame(width: 34, height: 34)
        } else {
            IconBadge(icon: it.label.hasPrefix("homebrew.") ? "mug" : (it.scope == .system ? "gearshape.2" : "gearshape"),
                      color: it.disabled ? W.faint : W.orange, size: 34)
        }
    }

    func row(_ it: LaunchItem) -> some View {
        HStack(spacing: 14) {
            launchIcon(it).opacity(it.disabled ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(it.owner).font(W.body(13, .semibold)).foregroundColor(it.disabled ? W.faint : W.text)
                    if it.running { Pill("Running", W.green) }
                    if it.disabled { Pill("Off", W.faint) }
                }
                Text(it.label).font(W.mono).foregroundColor(W.faint).lineLimit(1).truncationMode(.middle)
                if let n = it.note { Text(n).font(W.body(11)).foregroundColor(W.amber.opacity(0.9)) }
            }
            Spacer()
            if m.busy == it.id {
                ProgressView().controlSize(.small)
            } else if it.canToggle {
                Toggle("", isOn: Binding(get: { !it.disabled }, set: { m.set(it, on: $0) }))
                    .toggleStyle(.switch).tint(W.orange).labelsHidden()
            } else {
                Image(systemName: "lock.fill").foregroundColor(W.faint).help("Needs an admin to change")
            }
        }
        .padding(.vertical, 10)
    }
}
