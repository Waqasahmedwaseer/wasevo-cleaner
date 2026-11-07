import SwiftUI

// Projects: every project with its size, build files and last edit. Clean build files or archive old ones.

final class ProjectsModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var loading = false
    @Published var progress = ""
    @Published var busy: String?          // path being worked on
    @Published var message: String?

    func load() {
        guard !loading else { return }
        loading = true
        progress = "Finding projects…"
        DispatchQueue.global(qos: .userInitiated).async {
            let list = scanAllProjects { d, t in DispatchQueue.main.async { self.progress = "Measuring \(d) of \(t) projects…" } }
            DispatchQueue.main.async { self.projects = list; self.loading = false }
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
    @StateObject private var model = ProjectsModel()
    @State private var sort: ProjectSort = .size
    @State private var onlyOld = false
    @State private var toArchive: Project?
    @State private var toClean: Project?

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
                SecondaryButton(title: "Rescan", icon: "arrow.clockwise") { model.load() }.padding(.trailing, 28).padding(.bottom, 14)
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
                .padding(14).background(W.panel)
            }
        }
        .onAppear { if model.projects.isEmpty { model.load() } }
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
            Text((toClean?.buildFiles.map { $0.kind }.joined(separator: ", ") ?? "") + " will be removed. They are rebuilt by npm/pnpm install or cargo build. Your code is not touched.")
        }
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
            Text("\(model.projects.count) projects · \(human(total)) · \(human(build)) build files")
                .font(W.body(12, .semibold)).foregroundColor(W.faint)
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 10)
    }

    func row(_ p: Project) -> some View {
        HStack(spacing: 14) {
            Image(systemName: p.isGit ? "arrow.triangle.branch" : "folder.fill").foregroundColor(W.orange300).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(p.name).font(W.body(13, .semibold)).foregroundColor(W.text).lineLimit(1)
                    if p.inUse { tag("In use", W.amber) }
                    if p.uncommitted { tag("Uncommitted changes", W.amber) }
                    if p.stale { tag("Idle \(p.ageDays) days", W.faint) }
                }
                Text(p.label).font(W.mono).foregroundColor(W.faint).lineLimit(1).truncationMode(.middle)
                Text("Last edit \(p.ageDays == 0 ? "today" : "\(p.ageDays) days ago")" + (p.buildSize > 0 ? " · \(human(p.buildSize)) rebuildable build files" : ""))
                    .font(W.body(11)).foregroundColor(W.muted)
            }
            Spacer()
            Text(human(p.size)).font(W.body(14, .bold)).foregroundColor(W.text).frame(width: 80, alignment: .trailing)
            if model.busy == p.path {
                ProgressView().controlSize(.small).frame(width: 190)
            } else {
                HStack(spacing: 6) {
                    smallButton("Clean build", disabled: p.buildSize == 0 || p.inUse) { toClean = p }
                    smallButton("Archive", disabled: p.inUse || model.busy != nil) { toArchive = p }
                    Button { revealInFinder(p.path) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.plain).foregroundColor(W.muted)
                }
                .frame(width: 190, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
    }

    func tag(_ s: String, _ c: Color) -> some View {
        Text(s).font(W.body(10, .semibold)).foregroundColor(c)
            .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(c.opacity(0.14)))
    }

    func smallButton(_ t: String, disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(W.body(11, .semibold)).foregroundColor(disabled ? W.faint.opacity(0.5) : W.text)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().stroke(W.line.opacity(3), lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(disabled)
    }
}
