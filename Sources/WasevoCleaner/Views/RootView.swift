import SwiftUI

// App shell: native split view (sidebar + page) with a real window toolbar:
// back / forward, page title and the appearance switch live in the toolbar.

enum Page: String, CaseIterable, Identifiable {
    case scan = "Smart Scan", map = "Space Map", projects = "Projects", duplicates = "Duplicates"
    case photos = "Photo Cleaner", downloads = "Old Downloads", uninstaller = "Uninstaller"
    case privacy = "Browser Privacy", startup = "Startup Items", monitor = "System Monitor"
    case maintenance = "Maintenance", updates = "App Updates"
    case large = "Large Files", protected = "Protected", history = "History", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .scan: return "sparkles"
        case .map: return "square.grid.2x2"
        case .projects: return "folder"
        case .uninstaller: return "trash.square"
        case .duplicates: return "doc.on.doc"
        case .photos: return "photo.stack"
        case .downloads: return "arrow.down.circle"
        case .privacy: return "hand.raised"
        case .startup: return "power"
        case .monitor: return "waveform.path.ecg"
        case .maintenance: return "wrench.and.screwdriver"
        case .updates: return "arrow.triangle.2.circlepath"
        case .large: return "doc.text.magnifyingglass"
        case .protected: return "lock.shield"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
    /// Each module has its own colour world (like CleanMyMac): sidebar icon, glossy header icon, backdrop glow.
    var tint: Color {
        switch self {
        case .scan: return Color(hex: 0xFD5E15)
        case .map: return Color(hex: 0x8B5CF6)
        case .projects: return Color(hex: 0x6366F1)
        case .duplicates: return Color(hex: 0x14B8A6)
        case .photos: return Color(hex: 0xEC4899)
        case .downloads: return Color(hex: 0x0EA5E9)
        case .uninstaller: return Color(hex: 0x3B82F6)
        case .privacy: return Color(hex: 0xD946EF)
        case .startup: return Color(hex: 0xF59E0B)
        case .monitor: return Color(hex: 0x22C55E)
        case .maintenance: return Color(hex: 0x06B6D4)
        case .updates: return Color(hex: 0x2563EB)
        case .large: return Color(hex: 0xF97316)
        case .protected: return Color(hex: 0xEF4444)
        case .history, .settings: return Color(hex: 0x64748B)
        }
    }
    var section: String {
        switch self {
        case .scan, .map, .projects, .duplicates, .photos, .downloads, .uninstaller: return "CLEAN"
        case .privacy, .startup, .monitor, .maintenance, .updates: return "OPTIMIZE"
        case .large, .protected: return "INSPECT"
        case .history, .settings: return "APP"
        }
    }
}

struct SidebarItem: View {
    let page: Page
    let selected: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hover = false
    @ObservedObject private var act = Activity.shared
    var body: some View {
        HStack(spacing: 10) {
            // small glossy colour chip per module, like the system Settings sidebar
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [page.tint.opacity(0.85), page.tint], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
                .overlay(Image(systemName: page.icon).font(.system(size: 11, weight: .semibold)).foregroundColor(.white))
                .frame(width: 22, height: 22)
            Text(page.rawValue).font(W.body(13, selected ? .semibold : .regular))
            Spacer()
            if act.running[page] != nil {
                ProgressView().controlSize(.mini).help(act.running[page] ?? "")
                    .transition(.scale.combined(with: .opacity))
            } else if act.finished.contains(page) {
                Circle().fill(page.tint).frame(width: 7, height: 7).help("Finished")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: act.running[page] != nil)
        .animation(.spring(response: 0.3), value: act.finished.contains(page))
        .foregroundColor(selected || hover ? W.text : W.muted)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(page.tint.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(page.tint.opacity(0.22), lineWidth: 1))
                    .matchedGeometryEffect(id: "sidebar-selection", in: ns)
            } else if hover {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(W.line)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var page: Page = .scan
    @State private var back: [Page] = []
    @State private var forward: [Page] = []
    @Namespace private var ns
    @AppStorage("appearance") private var appearance = AppAppearance.light.rawValue
    @AppStorage("onboarded") private var onboarded = false
    @State private var showOnboarding = false
    @ObservedObject private var nav = Nav.shared
    @ObservedObject private var undo = UndoLog.shared
    @State private var undoMessage: String?
    @AppStorage("sidebarRail") private var rail = false

    func go(_ p: Page, record: Bool = true) {
        guard p != page else { return }
        if record { back.append(page); forward.removeAll() }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { page = p }
        Activity.shared.current = p
    }
    @ObservedObject private var act = Activity.shared

    var body: some View {
        HStack(spacing: 0) {
            // our own sidebar: full list or slim icon rail, animated
            Group {
                if rail { railView.transition(.opacity) } else { sidebar.transition(.opacity) }
            }
            .frame(width: rail ? 76 : 228)
            .frame(maxHeight: .infinity)
            .background(SidebarBackground().ignoresSafeArea())
            .overlay(Rectangle().fill(W.line).frame(width: 1).ignoresSafeArea(), alignment: .trailing)
            .clipped()

            VStack(spacing: 0) {
                topBar
                detail
                    .id(page)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Backdrop())
            .environment(\.pageTint, page.tint)
            .environment(\.pageIcon, page.icon)
            .overlay(alignment: .bottom) { undoBar }
        }
        .ignoresSafeArea(.container, edges: .top)   // sidebar and page reach the window's top edge
        .frame(minWidth: 1040, minHeight: 680)
        .onChange(of: appearance) { v in AppAppearance(rawValue: v)?.apply() }
        .onReceive(nav.$goTo) { p in if let p { go(p); nav.goTo = nil } }
        .onChange(of: nav.refresh) { _ in rescanCurrent() }
        .onChange(of: nav.showTour) { v in if v { showOnboarding = true; nav.showTour = false } }
        .sheet(isPresented: $showOnboarding, onDismiss: { onboarded = true }) { Onboarding(isPresented: $showOnboarding) }
        .onAppear {
            AppAppearance.current.apply()
            if !onboarded { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showOnboarding = true } }
            // `--scan` starts a Smart Scan on launch (handy for scripts and screenshots)
            if CommandLine.arguments.contains("--scan") && store.phase == .idle { store.scan() }
            // `--page "<page name>"` opens that page and `--rescan` scans it (for scripted screenshots and videos)
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--page"), i + 1 < args.count, let p = Page(rawValue: args[i + 1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    nav.open(p)
                    if args.contains("--rescan") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { nav.rescan() } }
                }
            }
            // `--preview "<file>"` opens Quick Look on a file (for scripted checks)
            if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { quickLook(args[i + 1]) }
            }
        }
    }

    /// ⌘R: rescan whatever page is open.
    func rescanCurrent() {
        switch page {
        case .scan: scanEverything(store)
        case .map: SpaceMapModel.shared.open(SpaceMapModel.shared.path, force: true)
        case .projects: ProjectsModel.shared.load()
        case .duplicates: DupModel.shared.scan()
        case .photos: PhotosModel.shared.scan()
        case .downloads: DownloadsModel.shared.scan()
        case .uninstaller: UninstallModel.shared.load()
        case .privacy: PrivacyModel.shared.load()
        case .startup: StartupModel.shared.load()
        case .updates: UpdatesModel.shared.check()
        case .large: store.loadBigFiles()
        default: break
        }
    }

    /// "Put back" bar after anything was moved to the Trash.
    @ViewBuilder var undoBar: some View {
        if let msg = undoMessage {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(W.green)
                Text(msg).font(W.body(12.5, .medium)).foregroundColor(W.text)
            }
            .padding(.horizontal, 16).frame(height: 40)
            .glassCard(radius: 20)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { undoMessage = nil } } }
        } else if undo.canUndo {
            HStack(spacing: 12) {
                Image(systemName: "trash").foregroundColor(W.faint)
                Text("\(undo.batch.count) item\(undo.batch.count == 1 ? "" : "s") moved to the Trash")
                    .font(W.body(12.5, .medium)).foregroundColor(W.text)
                Button {
                    undo.putBack { ok, skipped in
                        withAnimation(.spring(response: 0.4)) {
                            undoMessage = "Put back \(ok) item\(ok == 1 ? "" : "s")" + (skipped > 0 ? " · \(skipped) skipped" : "")
                        }
                    }
                } label: {
                    Label("Put back", systemImage: "arrow.uturn.backward").font(W.body(12.5, .semibold)).foregroundColor(W.orange300)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 16).frame(height: 40)
            .glassCard(radius: 20)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder var detail: some View {
        switch page {
        case .scan: ScanView()
        case .map: SpaceMapView()
        case .projects: ProjectsView()
        case .uninstaller: UninstallerView()
        case .duplicates: DuplicatesView()
        case .photos: PhotosView()
        case .downloads: DownloadsView()
        case .privacy: PrivacyView()
        case .startup: StartupView()
        case .monitor: MonitorView()
        case .maintenance: MaintenanceView()
        case .updates: UpdatesView()
        case .large: LargeFilesView()
        case .protected: ProtectedView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }

    /// Top bar of the main area: sidebar toggle, back / forward, page title, running tasks, appearance, settings.
    var topBar: some View {
        HStack(spacing: 6) {
            barButton("sidebar.left", rail ? "Show full sidebar (⌃⌘S)" : "Collapse to icons (⌃⌘S)") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { rail.toggle() }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            barButton("chevron.left", "Back (⌘[)", disabled: back.isEmpty) {
                guard let p = back.popLast() else { return }
                forward.append(page); go(p, record: false)
            }
            .keyboardShortcut("[", modifiers: .command)
            barButton("chevron.right", "Forward (⌘])", disabled: forward.isEmpty) {
                guard let p = forward.popLast() else { return }
                back.append(page); go(p, record: false)
            }
            .keyboardShortcut("]", modifiers: .command)
            Text(page.rawValue).font(W.body(14, .semibold)).foregroundColor(W.text).padding(.leading, 6)
                .id(page).transition(.opacity)
            Spacer()
            if let (p, what) = act.running.first {
                Button { go(p) } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(act.running.count > 1 ? "\(act.running.count) tasks running" : "\(what)…").font(W.body(11.5, .medium))
                            .foregroundColor(W.muted)
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    .liquidCapsule(hover: false)
                }
                .buttonStyle(PressStyle()).help("Running in the background. Click to open.")
                .transition(.scale.combined(with: .opacity))
            }
            // appearance: System / Light / Dark
            HStack(spacing: 2) {
                ForEach(AppAppearance.allCases, id: \.self) { a in
                    let on = appearance == a.rawValue
                    Button { withAnimation(.easeInOut(duration: 0.25)) { appearance = a.rawValue } } label: {
                        Image(systemName: a.icon).font(.system(size: 12, weight: .semibold))
                            .foregroundColor(on ? W.text : W.faint)
                            .frame(width: 30, height: 24)
                            .background(RoundedRectangle(cornerRadius: 7).fill(on ? W.panel : Color.clear)
                                .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 2, y: 1))
                    }
                    .buttonStyle(PressStyle()).help(a.rawValue)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(W.line))
            barButton("gearshape", "Settings (⌘,)") { go(.settings) }
        }
        .padding(.horizontal, 16).padding(.top, 6).frame(height: 58)   // in line with the window buttons
        .animation(.spring(response: 0.3), value: act.running.count)
    }

    func barButton(_ icon: String, _ help: String, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                .foregroundColor(disabled ? W.faint.opacity(0.45) : W.muted)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle()).disabled(disabled).help(help)
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Logo(size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wasevo").font(W.display(17)).foregroundColor(W.text).fixedSize()
                    Text("CLEANER").font(.system(size: 9.5, weight: .bold)).tracking(2.5).foregroundColor(W.orange).fixedSize()
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.top, 44).padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(["CLEAN", "OPTIMIZE", "INSPECT", "APP"], id: \.self) { sec in
                        Text(sec).font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundColor(W.faint)
                            .padding(.horizontal, 10).padding(.top, sec == "CLEAN" ? 0 : 8).padding(.bottom, 2)
                        ForEach(Page.allCases.filter { $0.section == sec }) { p in
                            SidebarItem(page: p, selected: page == p, ns: ns) { go(p) }
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            diskMini
            Button { NSWorkspace.shared.open(WASEVO_URL) } label: {
                HStack(spacing: 4) {
                    Text("by").foregroundColor(W.faint)
                    Text("Wasevo").foregroundColor(W.orange300).fontWeight(.semibold)
                    Text("·  wasevo.com").foregroundColor(W.faint)
                }
                .font(W.body(10.5))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PressStyle()).padding(.top, 4).help("Built by Waqas Ahmed Waseer, CEO of Wasevo")
        }
        .padding(.horizontal, 10).padding(.bottom, 14)
    }

    /// Collapsed sidebar: logo, one glossy icon per page (with tooltips), disk usage ring.
    var railView: some View {
        VStack(spacing: 6) {
            Logo(size: 30).padding(.top, 44).padding(.bottom, 8).help("Wasevo Cleaner")
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(["CLEAN", "OPTIMIZE", "INSPECT", "APP"], id: \.self) { sec in
                        if sec != "CLEAN" { Divider().overlay(W.line).frame(width: 30).padding(.vertical, 4) }
                        ForEach(Page.allCases.filter { $0.section == sec }) { p in railItem(p) }
                    }
                }
                .padding(.vertical, 2)
            }
            Spacer(minLength: 6)
            ZStack {
                Circle().stroke(W.line, lineWidth: 4)
                Circle().trim(from: 0, to: store.usedFraction)
                    .stroke(store.isLow ? AnyShapeStyle(W.red) : AnyShapeStyle(W.accent), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(store.usedFraction * 100))").font(.system(size: 10, weight: .semibold)).foregroundColor(W.text)
            }
            .frame(width: 34, height: 34)
            .help("\(human(store.free)) free of \(human(store.total))")
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    func railItem(_ p: Page) -> some View {
        let on = page == p
        return Button { go(p) } label: {
            GlossyIcon(icon: p.icon, tint: p.tint, size: 30, glow: false)
                .frame(width: 46, height: 40)
                .background {
                    if on {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.tint.opacity(0.16))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.tint.opacity(0.3), lineWidth: 1))
                            .matchedGeometryEffect(id: "rail-selection", in: ns)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if act.running[p] != nil { ProgressView().controlSize(.mini).offset(x: -2, y: 2) }
                    else if act.finished.contains(p) { Circle().fill(p.tint).frame(width: 7, height: 7).offset(x: -5, y: 5) }
                }
        }
        .buttonStyle(PressStyle())
        .help(p.rawValue)
    }

    var diskMini: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "internaldrive").foregroundColor(W.faint)
                Text("Macintosh HD").font(W.body(11, .semibold)).foregroundColor(W.muted)
                Spacer()
                Text("\(Int(store.usedFraction * 100))%").font(W.body(11, .bold)).foregroundColor(store.isLow ? W.red : W.orange300)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.line)
                    Capsule().fill(store.isLow ? AnyShapeStyle(W.red) : AnyShapeStyle(W.accent)).frame(width: g.size.width * store.usedFraction)
                }
            }
            .frame(height: 5)
            Text("\(human(store.free)) free of \(human(store.total))").font(W.body(11)).foregroundColor(store.isLow ? W.red : W.faint)
        }
        .padding(10)
        .glassCard(radius: 12)
    }
}



/// Soft solid sidebar (no see-through blur): warm off-white in light mode, deep ink in dark mode.
struct SidebarBackground: View {
    var body: some View {
        LinearGradient(colors: [Color.dyn(0xF8F6F3, 0x16151B), Color.dyn(0xF2EFEB, 0x121117)], startPoint: .top, endPoint: .bottom)
    }
}
