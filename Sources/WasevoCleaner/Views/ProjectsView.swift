import SwiftUI

// Projects: every project with its size, build files and last edit. Clean build files or archive old ones.

final class ProjectsModel: ObservableObject {
    static let shared = ProjectsModel()
    @Published var projects: [Project] = []
    @Published var loading = false
    @Published var progress = ""
    @Published var busy: String?          // path being worked on
    @Published var message: String?

    func load() {
        guard !loading else { return }
        loading = true
        Activity.shared.start(.projects, "Measuring projects")
        progress = "Finding projects…"
        DispatchQueue.global(qos: .userInitiated).async {
            let list = scanAllProjects { d, t in DispatchQueue.main.async { self.progress = "Measuring \(d) of \(t) projects…" } }
            DispatchQueue.main.async {
                self.projects = list; self.loading = false
                Activity.shared.finish(.projects, "\(list.count) projects measured.")
            }
        }
    }

    func clean(_ p: Project) {
        busy = p.path
        let mode: DeleteMode = UserDefaults.standard.object(forKey: "deleteMode") as? Bool == false ? .trash : .permanent
        DispatchQueue.global(qos: .userInitiated).async {
            let r = cleanBuildFiles(p, mode)
            DispatchQueue.main.async {
                self.busy = nil
                self.message = "\(p.name): removed \(human(r.freed)) of build files" + (r.skipped > 0 ? " (\(r.skipped) skipped: in use)." : ".")
                self.refresh(p.path)
            }
        }
    }

    func archive(_ p: Project) {
        busy = p.path
        DispatchQueue.global(qos: .userInitiated).async {
            let r = archiveProject(p)
            DispatchQueue.main.async {
                self.busy = nil
                if let e = r.error { self.message = e } else {
                    self.message = "\(p.name) archived to ~/Wasevo Archives. The original is in the Trash."
                    self.projects.removeAll { $0.path == p.path }
                }
            }
        }
    }

    /// One click: clean the build files of every project in `list` that nothing is using right now.
    /// Projects open in a terminal, dev server or app are skipped, and every folder is re-checked just before removal.
    func cleanAll(_ list: [Project]) {
        let targets = list.filter { $0.buildSize > 0 && !$0.inUse }
        guard !targets.isEmpty, busy == nil else { return }
        busy = "__all__"
        Activity.shared.start(.projects, "Cleaning build files")
        let mode: DeleteMode = UserDefaults.standard.object(forKey: "deleteMode") as? Bool == false ? .trash : .permanent
        DispatchQueue.global(qos: .userInitiated).async {
            var freed: Int64 = 0, skipped = 0
            for (i, p) in targets.enumerated() {
                DispatchQueue.main.async { self.progress = "Cleaning \(p.name) (\(i + 1) of \(targets.count))…"; self.message = self.progress }
                let r = cleanBuildFiles(p, mode)
                freed += r.freed; skipped += r.skipped
            }
            log("CLEAN ALL PROJECTS \(targets.count) projects · \(human(freed)) freed · \(skipped) skipped")
            DispatchQueue.main.async {
                self.busy = nil
                let left = list.filter { $0.inUse && $0.buildSize > 0 }.count
                self.message = "Cleaned \(targets.count) projects: \(human(freed)) freed."
                    + (skipped > 0 ? " \(skipped) folders skipped because they came into use." : "")
                    + (left > 0 ? " \(left) open projects were left alone." : "")
                Activity.shared.finish(.projects, "\(human(freed)) of build files removed.")
                self.load()
            }
        }
    }

    private func refresh(_ path: String) {
        DispatchQueue.global().async {
            let snap = ProcSnapshot.take()
            let arts = scanProjects(snap: snap).filter { $0.project == path || $0.project.hasPrefix(path + "/") }
            let size = duSize(path)
            DispatchQueue.main.async {
                guard let i = self.projects.firstIndex(where: { $0.path == path }) else { return }
                let o = self.projects[i]
                self.projects[i] = Project(path: o.path, size: size, buildFiles: arts, lastEdit: o.lastEdit,
                                           isGit: o.isGit, uncommitted: o.uncommitted, inUse: o.inUse)
            }
        }
    }
}

enum ProjectSort: String, CaseIterable { case size = "Biggest", age = "Oldest", build = "Most build files" }

struct ProjectsView: View {
    @ObservedObject private var model = ProjectsModel.shared
    @State private var sort: ProjectSort = .size
    @State private var onlyOld = false
    @State private var toArchive: Project?
    @State private var toClean: Project?
    @State private var askAll = false

    var list: [Project] {
        let l = model.projects.filter { !onlyOld || $0.stale }
        switch sort {
        case .size: return l.sorted { $0.size > $1.size }
        case .age: return l.sorted { $0.lastEdit < $1.lastEdit }
        case .build: return l.sorted { $0.buildSize > $1.buildSize }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                PageHeader(title: "Projects", subtitle: "Every project on your Mac. Clean rebuildable build files, or zip old projects you're not using.")
                HStack(spacing: 8) {
                    SecondaryButton(title: "Rescan", icon: "arrow.clockwise") { model.load() }
                    if !model.loading && allSize > 0 {
                        PrimaryButton(title: "Clean all · \(human(allSize))", icon: "sparkles", disabled: model.busy != nil) { askAll = true }
                    }
                }
                .padding(.trailing, 28).padding(.bottom, 14)
            }
            toolbar
            if model.loading {
                Spacer()
                VStack(spacing: 10) { ProgressView().controlSize(.large); Text(model.progress).font(W.body(12)).foregroundColor(W.faint) }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(list) { p in row(p); Divider().overlay(W.line) }
                    }
                    .padding(.horizontal, 16)
                }
            }
            if let m = model.message {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(W.green)
                    Text(m).font(W.body(12, .semibold)).foregroundColor(W.text)
                    Spacer()
                    Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundColor(W.faint)
                }
                .padding(14).background(.regularMaterial)
            }
        }
        .onAppear { if model.projects.isEmpty { model.load() } }
        .alert("Clean the build files of \(cleanable.count) projects?", isPresented: $askAll) {
            Button("Clean all · \(human(allSize))") { model.cleanAll(list) }
            if idleSize > 0 && idleSize < allSize {
                Button("Only idle \(Int(Prefs.staleDays))+ days · \(human(idleSize))") { model.cleanAll(list.filter(\.stale)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text(allMessage) }
        .alert("Archive \(toArchive?.name ?? "")?", isPresented: Binding(get: { toArchive != nil }, set: { if !$0 { toArchive = nil } })) {
            Button("Zip and move to Trash") { if let p = toArchive { model.archive(p) }; toArchive = nil }
            Button("Cancel", role: .cancel) { toArchive = nil }
        } message: {
            Text(archiveMessage)
        }
        .alert("Clean build files of \(toClean?.name ?? "")?", isPresented: Binding(get: { toClean != nil }, set: { if !$0 { toClean = nil } })) {
            Button("Clean \(human(toClean?.buildSize ?? 0))") { if let p = toClean { model.clean(p) }; toClean = nil }
            Button("Cancel", role: .cancel) { toClean = nil }
        } message: {
            Text(Set(toClean?.buildFiles.map(\.kind) ?? []).sorted().map { "\($0): \(rebuildHint($0))" }.joined(separator: "\n") + "\n\nYour code is not touched.")
        }
    }

    /// Projects the one-click clean would touch (shown list, has build files, not open anywhere).
    var cleanable: [Project] { list.filter { $0.buildSize > 0 && !$0.inUse } }
    var allSize: Int64 { cleanable.reduce(0) { $0 + $1.buildSize } }
    var idleSize: Int64 { cleanable.filter(\.stale).reduce(0) { $0 + $1.buildSize } }

    var allMessage: String {
        var counts: [String: Int] = [:]
        for p in cleanable { for a in p.buildFiles where a.blocked == nil { counts[a.kind, default: 0] += 1 } }
        let kinds = counts.sorted { $0.value > $1.value }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
        let open = list.filter { $0.inUse && $0.buildSize > 0 }.count
        return "\(kinds)\n\nOnly folders that can be rebuilt (npm install, composer install, cargo build…) are removed. Your code, git history and settings stay."
            + (open > 0 ? " \(open) projects open in a terminal or dev server are skipped." : "")
            + " A project you open again just needs its install or build command."
    }

    var archiveMessage: String {
        guard let p = toArchive else { return "" }
        var s = "Your code and git history are zipped to ~/Wasevo Archives (build folders left out; they can be rebuilt). The zip is checked, then the original folder goes to the Trash."
        if p.uncommitted { s += "\n\nThis project has uncommitted git changes. They are inside the zip too." }
        return s
    }

    var toolbar: some View {
        HStack(spacing: 14) {
            Picker("", selection: $sort) { ForEach(ProjectSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).frame(width: 330).labelsHidden()
            Toggle("Only idle \(Int(Prefs.staleDays))+ days", isOn: $onlyOld).toggleStyle(.checkbox).foregroundColor(W.muted)
            Spacer()
            if !model.loading && !model.projects.isEmpty {
            let total = model.projects.reduce(Int64(0)) { $0 + $1.size }
            let build = model.projects.reduce(Int64(0)) { $0 + $1.buildSize }
            HStack(spacing: 8) {
                stat("\(model.projects.count)", "projects")
                stat(human(total), "total")
                stat(human(build), "rebuildable", W.orange300)
            }
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 10)
    }

    func row(_ p: Project) -> some View {
        HStack(spacing: 14) {
            IconBadge(icon: p.isGit ? "arrow.triangle.branch" : "folder.fill", color: p.inUse ? W.amber : W.orange, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(p.name).font(W.body(13, .semibold)).foregroundColor(W.text).lineLimit(1)
                    if p.inUse { Pill("In use", W.amber) }
                    if p.uncommitted { Pill("Uncommitted changes", W.amber) }
                    if p.stale { Pill("Idle \(p.ageDays) days", W.faint) }
                }
                Text(p.label).font(W.mono).foregroundColor(W.faint).lineLimit(1).truncationMode(.middle)
                (Text("Last edit \(daysAgo(p.ageDays))") + Text(p.buildSize > 0 ? "  ·  \(human(p.buildSize)) rebuildable" : "").foregroundColor(W.orange300))
                    .font(W.body(11)).foregroundColor(W.muted)
            }
            Spacer()
            Text(human(p.size)).font(W.body(14, .bold)).foregroundColor(W.text).frame(width: 80, alignment: .trailing)
            if model.busy == p.path {
                ProgressView().controlSize(.small).frame(width: 190)
            } else {
                HStack(spacing: 6) {
                    smallButton("Clean build", disabled: p.buildSize == 0 || p.inUse || model.busy != nil) { toClean = p }
                    smallButton("Archive", disabled: p.inUse || model.busy != nil) { toArchive = p }
                    Button { revealInFinder(p.path) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.plain).foregroundColor(W.muted)
                }
                .frame(width: 190, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
    }

    func stat(_ value: String, _ label: String, _ c: Color = W.text) -> some View {
        HStack(spacing: 5) {
            Text(value).font(W.body(12, .bold)).foregroundColor(c)
            Text(label).font(W.body(11)).foregroundColor(W.faint)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(W.panel))
        .overlay(Capsule().stroke(W.line, lineWidth: 1))
    }

    func smallButton(_ t: String, disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(W.body(11, .semibold)).foregroundColor(disabled ? W.faint.opacity(0.5) : W.text)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(disabled ? Color.clear : W.panel2.opacity(0.6)))
                .overlay(Capsule().stroke(disabled ? W.line : W.line.opacity(3), lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(disabled)
    }
}
