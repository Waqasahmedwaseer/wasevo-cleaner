import SwiftUI
import ServiceManagement

// Large files (view only), Protected, History, Settings.

struct PageHeader: View {
    let title: String, subtitle: String
    @Environment(\.pageTint) private var tint
    @Environment(\.pageIcon) private var icon
    var body: some View {
        HStack(spacing: 16) {
            GlossyIcon(icon: icon, tint: tint, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(W.display(26)).tracking(-0.5).foregroundColor(W.text)
                Text(subtitle).font(W.body(13)).foregroundColor(W.faint).lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 14)
    }
}

// MARK: Large files

struct LargeFilesView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                PageHeader(title: "Large files",
                           subtitle: "Your biggest files with their REAL size on disk. View only: Wasevo Cleaner never deletes these.")
                SecondaryButton(title: "Refresh", icon: "arrow.clockwise") { store.loadBigFiles() }.padding(.trailing, 28).padding(.bottom, 14)
            }
            if store.loadingBigFiles && store.bigFiles.isEmpty {
                Spacer(); ProgressView().controlSize(.large); Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.bigFiles, id: \.path) { f in BigFileRow(file: f); Divider().overlay(W.line) }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .onAppear { if store.bigFiles.isEmpty { store.loadBigFiles() } }
    }
}

struct BigFileRow: View {
    let file: BigFile
    @State private var hover = false
    var sparse: Bool { file.shownSize > file.realSize * 2 && file.shownSize > 1_000_000_000 }

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(icon: file.protected != nil ? "lock.fill" : "doc.fill",
                      color: file.protected != nil ? W.red : W.faint, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text((file.path as NSString).lastPathComponent).font(W.body(13, .semibold)).foregroundColor(W.text).lineLimit(1)
                Text(file.path.replacingOccurrences(of: home, with: "~")).font(W.mono).foregroundColor(W.faint)
                    .lineLimit(1).truncationMode(.middle)
                if let p = file.protected {
                    Text("Do not delete: \(p)").font(W.body(11, .semibold)).foregroundColor(W.red)
                }
                if sparse {
                    Text("Other apps show \(human(file.shownSize)); it really uses \(human(file.realSize)).")
                        .font(W.body(11)).foregroundColor(W.amber)
                }
            }
            Spacer()
            Text(human(file.realSize)).font(W.body(14, .semibold)).foregroundColor(W.muted)
            Button { revealInFinder(file.path) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).foregroundColor(hover ? W.orange : W.faint).help("Show in Finder")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(hover ? W.panel2.opacity(0.6) : Color.clear)
        .onHover { hover = $0 }
    }
}

// MARK: Protected

struct ProtectedView: View {
    let rows: [(String, String, String)] = [
        ("shippingbox.fill", "Docker data (Docker.raw, volumes)", "Other cleaners list Docker.raw as one huge file. It is ALL your images, containers and databases. Only the build cache is cleaned, through Docker itself."),
        ("cylinder.split.1x2.fill", "Databases (MySQL, SQLite, .sql)", "MySQL table files (.ibd) and binlogs are never deleted directly. Old binlogs are removed with MySQL's own PURGE command."),
        ("iphone", "Android emulators", "system.img and .avd folders hold your emulator phones."),
        ("chevron.left.forwardslash.chevron.right", "Your code and git history", "Only regenerable folders (node_modules, target, .next) are ever touched, and only when package.json / Cargo.toml / a lockfile can rebuild them."),
        ("key.fill", "Logins and credentials", "auth.json, oauth_creds.json, .ssh, keychains and AI-tool logins are never touched."),
        ("bolt.horizontal.circle", "Anything in use", "Projects with a running dev server or terminal, apps running from a build folder, and caches whose tool is running are skipped and re-checked right before deleting."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Protected", subtitle: "What Wasevo Cleaner will never delete, even if you ask.")
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(rows, id: \.1) { r in
                        Card {
                            HStack(alignment: .top, spacing: 14) {
                                IconBadge(icon: r.0, size: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(r.1).font(W.body(14, .semibold)).foregroundColor(W.text)
                                    Text(r.2).font(W.body(12)).foregroundColor(W.faint).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
    }
}

// MARK: History

struct HistoryView: View {
    @State private var lines: [String] = []
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                PageHeader(title: "History", subtitle: "Every deletion is logged to ~/Library/Logs/WasevoCleaner.log")
                SecondaryButton(title: "Open log", icon: "doc.text") {
                    if !FileManager.default.fileExists(atPath: LOG_PATH) { log("log created") }
                    NSWorkspace.shared.open(URL(fileURLWithPath: LOG_PATH))
                }
                .padding(.trailing, 28).padding(.bottom, 14)
            }
            if lines.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath", title: "Nothing cleaned yet",
                           text: "Every clean, archive and uninstall shows up here, with what was removed and how much space it freed.")
            } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        Text(l.replacingOccurrences(of: home, with: "~")).font(W.mono)
                            .foregroundColor(l.contains("FAILED") || l.contains("REFUSED") ? W.red
                                             : l.contains("CLEAN") || l.contains("EMPTY") ? W.orange300 : W.muted)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
            }
        }
        .onAppear(perform: load)
    }

    func load() {
        let text = (try? String(contentsOfFile: LOG_PATH, encoding: .utf8)) ?? ""
        lines = Array(text.split(separator: "\n").suffix(400).reversed().map(String.init))
    }
}

// MARK: Settings

struct SettingsView: View {
    @AppStorage("staleDays") private var staleDays = 14.0
    @AppStorage("lowSpaceGB") private var lowSpaceGB = 15.0
    @AppStorage("projectRoots") private var roots = ""
    @AppStorage("deleteMode") private var permanent = true
    @State private var login = SMAppService.mainApp.status == .enabled
    @AppStorage("autoClean") private var auto = AutoSchedule.off.rawValue
    @EnvironmentObject var store: Store
    @State private var autoResult: String?
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Settings", subtitle: "Tune how Wasevo Cleaner scans and cleans.")
            ScrollView {
                VStack(spacing: 12) {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            SettingRow("Appearance", "Light, dark, or follow your Mac.") {
                                HStack(spacing: 6) {
                                    ForEach(AppAppearance.allCases, id: \.self) { a in
                                        let on = appearance == a.rawValue
                                        Button { withAnimation(.easeInOut(duration: 0.25)) { appearance = a.rawValue } } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: a.icon)
                                                Text(a.rawValue).font(W.body(12, .semibold))
                                            }
                                            .foregroundColor(on ? .white : W.muted)
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(Capsule().fill(on ? AnyShapeStyle(W.accent) : AnyShapeStyle(W.line)))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            Divider().overlay(W.line)
                            SettingRow("Stop permission pop-ups", "Give Wasevo Cleaner Full Disk Access once in System Settings (Privacy & Security > Full Disk Access). macOS then stops asking about folders and other apps' data.") {
                                SecondaryButton(title: "Open Full Disk Access", icon: "lock.open") {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                                }
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            SettingRow("A project is \"old\" after \(Int(staleDays)) days", "Build files of old projects are pre-selected in Smart Scan.") {
                                Stepper("", value: $staleDays, in: 3...180, step: 1).labelsHidden()
                            }
                            Divider().overlay(W.line)
                            SettingRow("Warn when free space is below \(Int(lowSpaceGB)) GB", "Shown in the menu bar.") {
                                Stepper("", value: $lowSpaceGB, in: 5...100, step: 5).labelsHidden()
                            }
                            Divider().overlay(W.line)
                            SettingRow("Default: delete now (frees space)", "Off = move to Trash by default.") {
                                Toggle("", isOn: $permanent).labelsHidden()
                            }
                            Divider().overlay(W.line)
                            SettingRow("Open at login", "Keeps the menu-bar disk monitor running.") {
                                Toggle("", isOn: $login).labelsHidden()
                                    .onChange(of: login) { on in
                                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                                        catch { login = SMAppService.mainApp.status == .enabled }
                                    }
                            }
                        }
                        .toggleStyle(.switch).tint(W.orange)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            SettingRow("Auto-clean safe caches", "Only caches marked Safe that rebuild themselves. Never projects, Docker, databases or AI history. Skips apps that are running.") {
                                Picker("", selection: $auto) { ForEach(AutoSchedule.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) } }
                                    .pickerStyle(.segmented).labelsHidden().frame(width: 210)
                            }
                            HStack {
                                Text(autoResult ?? (AutoClean.last.map { "Last auto-clean: \(RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()))" } ?? "Not run yet"))
                                    .font(W.body(11)).foregroundColor(W.faint)
                                Spacer()
                                SecondaryButton(title: store.autoCleaning ? "Cleaning…" : "Run now", icon: "sparkles") {
                                    store.runAutoClean(reason: "manual") { autoResult = "Freed \(human($0)) just now." }
                                }
                            }
                            Text("Includes: " + AutoClean.rules.map(\.name).joined(separator: " · "))
                                .font(W.body(10)).foregroundColor(W.faint).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            SettingLabel("Project folders to scan", "One per line. Empty = default (~/Documents, ~/Desktop, ~/Local Sites, ~/tools, ~/Projects, ~/Developer, ~/code).")
                            TextEditor(text: $roots).font(W.mono).frame(height: 90)
                                .scrollContentBackground(.hidden).padding(6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(W.bg))
                        }
                    }
                    Text("Wasevo Cleaner · open source (MIT) · made by Wasevo").font(W.body(11)).foregroundColor(W.faint)
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
    }
}

struct SettingRow<Control: View>: View {
    let title: String, sub: String
    @ViewBuilder let control: Control
    init(_ t: String, _ s: String, @ViewBuilder control: () -> Control) { title = t; sub = s; self.control = control() }
    var body: some View {
        HStack(spacing: 16) { SettingLabel(title, sub); Spacer(); control }
    }
}

struct SettingLabel: View {
    let title: String, sub: String
    init(_ t: String, _ s: String) { title = t; sub = s }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(W.body(13, .semibold)).foregroundColor(W.text)
            Text(sub).font(W.body(11)).foregroundColor(W.faint)
        }
    }
}
