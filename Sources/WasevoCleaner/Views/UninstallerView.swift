import SwiftUI
import AppKit

// App Uninstaller: remove an app and the files it leaves behind. Everything goes to the Trash.

final class UninstallModel: ObservableObject {
    static let shared = UninstallModel()
    @Published var apps: [InstalledApp] = []
    @Published var loading = false
    @Published var selected: InstalledApp?
    @Published var leftovers: [Leftover] = []
    @Published var chosen: Set<String> = []
    @Published var findingLeftovers = false
    @Published var message: String?
    @Published var working = false

    func load() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let list = listApps()
            DispatchQueue.main.async { self.apps = list; self.loading = false }
            // sizes after the list is on screen
            for (i, a) in list.enumerated() {
                let s = duSize(a.path)
                DispatchQueue.main.async {
                    if i < self.apps.count, self.apps[i].path == a.path { self.apps[i].size = s }
                }
            }
        }
    }

    func select(_ a: InstalledApp) {
        selected = a
        leftovers = []
        chosen = []
        message = nil
        findingLeftovers = true
        DispatchQueue.global(qos: .userInitiated).async {
            let l = findLeftovers(a)
            DispatchQueue.main.async {
                guard self.selected?.path == a.path else { return }
                self.leftovers = l
                self.chosen = Set(l.filter { $0.protected == nil }.map(\.path))
                self.findingLeftovers = false
            }
        }
    }

    var totalSize: Int64 {
        (selected?.size ?? 0) + leftovers.filter { chosen.contains($0.path) }.reduce(0) { $0 + $1.size }
    }

    func uninstall() {
        guard let a = selected else { return }
        working = true
        let items = leftovers.filter { chosen.contains($0.path) && $0.protected == nil }
        DispatchQueue.global(qos: .userInitiated).async {
            var msg: String
            if let err = trashApp(a) {
                msg = err
            } else {
                let failed = items.filter { !removePath($0.path, .trash) }.count
                msg = "\(a.name) and \(items.count - failed) leftover item\(items.count - failed == 1 ? "" : "s") moved to the Trash."
                if failed > 0 { msg += " \(failed) could not be moved." }
                log("UNINSTALL \(a.name) · \(items.count - failed) leftovers")
            }
            DispatchQueue.main.async {
                self.working = false
                self.message = msg
                if !FileManager.default.fileExists(atPath: a.path) {
                    self.apps.removeAll { $0.path == a.path }
                    self.selected = nil
                    self.leftovers = []
                }
            }
        }
    }
}

struct UninstallerView: View {
    @ObservedObject private var model = UninstallModel.shared
    @State private var query = ""
    @State private var confirm = false

    var filtered: [InstalledApp] {
        let list = model.apps.filter { !$0.isApple && !$0.isSelf }
        return query.isEmpty ? list : list.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Uninstaller", subtitle: "Remove an app and the files it leaves behind. Everything goes to the Trash, so you can put it back.")
            HStack(spacing: 16) {
                appList.frame(width: 340)
                detail
            }
            .padding(.horizontal, 28).padding(.bottom, 22)
        }
        .onAppear { if model.apps.isEmpty { model.load() } }
        .alert("Move \(model.selected?.name ?? "") to the Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { model.uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app and \(model.chosen.count) leftover item(s) go to the Trash (\(human(model.totalSize))). You can restore them from the Trash.")
        }
    }

    var appList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(W.faint)
                TextField("Search apps", text: $query).textFieldStyle(.plain).foregroundColor(W.text)
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(W.bg)).padding(10)
            Divider().overlay(W.line)
            if model.loading {
                Spacer(); ProgressView(); Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { a in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.name).font(W.body(13, .semibold)).foregroundColor(W.text).lineLimit(1)
                                    Text(a.version.isEmpty ? a.bundleId : "v\(a.version)").font(W.body(10)).foregroundColor(W.faint).lineLimit(1)
                                }
                                Spacer()
                                Text(a.size > 0 ? human(a.size) : "…").font(W.body(11, .semibold)).foregroundColor(W.muted)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(model.selected?.path == a.path ? W.panel2 : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.selected?.path == a.path ? W.orange.opacity(0.4) : Color.clear, lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(a) }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .glassCard(radius: 14)
    }

    @ViewBuilder var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let a = model.selected {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.name).font(W.display(22)).foregroundColor(W.text)
                        Text(a.path).font(W.mono).foregroundColor(W.faint).lineLimit(1).truncationMode(.middle)
                        if a.running { Label("Running: quit it before uninstalling", systemImage: "pause.circle").font(W.body(11, .semibold)).foregroundColor(W.amber) }
                    }
                    Spacer()
                }
                .padding(18)
                Divider().overlay(W.line)
                Text("Leftover files").font(W.body(12, .semibold)).foregroundColor(W.faint).padding(.horizontal, 18).padding(.top, 12)
                if model.findingLeftovers {
                    ProgressView().padding(18)
                } else if model.leftovers.isEmpty {
                    Text("No leftovers found in your Library.").font(W.body(12)).foregroundColor(W.muted).padding(18)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.leftovers) { l in leftoverRow(l) }
                    }
                }
                Spacer(minLength: 0)
                Divider().overlay(W.line)
                HStack {
                    if let m = model.message {
                        Text(m).font(W.body(12, .semibold)).foregroundColor(W.green).lineLimit(2)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(human(model.totalSize)).font(W.display(20)).foregroundColor(W.text)
                            Text("App + \(model.chosen.count) leftover item(s) go to the Trash").font(W.body(11)).foregroundColor(W.faint)
                        }
                    }
                    Spacer()
                    PrimaryButton(title: model.working ? "Removing…" : "Uninstall", icon: "trash",
                                  disabled: model.working || a.running || model.findingLeftovers) { confirm = true }
                }
                .padding(18)
            } else {
                VStack(spacing: 10) {
                    EmptyState(icon: "shippingbox", title: "Pick an app",
                               text: "See the app and every file it left in your Library. Everything goes to the Trash, so you can put it back.")
                    if let m = model.message { Text(m).font(W.body(12, .semibold)).foregroundColor(W.green).padding(.bottom, 30) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(radius: 14)
    }

    func leftoverRow(_ l: Leftover) -> some View {
        let on = model.chosen.contains(l.path)
        return HStack(spacing: 12) {
            CheckBox(on: on, enabled: l.protected == nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(l.kind).font(W.body(12, .semibold)).foregroundColor(W.text)
                Text(l.path.replacingOccurrences(of: home, with: "~")).font(W.mono).foregroundColor(W.faint)
                    .lineLimit(1).truncationMode(.middle)
                if let p = l.protected { Text("Kept: \(p)").font(W.body(11, .semibold)).foregroundColor(W.red) }
            }
            Spacer()
            Button { revealInFinder(l.path) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain).foregroundColor(W.muted)
            Text(human(l.size)).font(W.body(12, .semibold)).foregroundColor(W.muted).frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard l.protected == nil else { return }
            if on { model.chosen.remove(l.path) } else { model.chosen.insert(l.path) }
        }
    }
}
