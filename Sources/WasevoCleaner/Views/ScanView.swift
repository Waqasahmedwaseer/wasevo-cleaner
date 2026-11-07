import SwiftUI

// Smart Scan: idle → scanning → results (pick what to clean) → cleaning → done.

struct ScanView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        switch store.phase {
        case .idle: IdleView()
        case .scanning, .cleaning: WorkingView()
        case .results: ResultsView()
        case .done: DoneView()
        }
    }
}

// MARK: idle

struct IdleView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            DiskRing(used: store.usedFraction)
            VStack(spacing: 6) {
                Text("\(human(store.free)) free").font(W.display(30)).foregroundColor(store.isLow ? W.red : W.text)
                Text("of \(human(store.total)) on Macintosh HD").font(W.body(13)).foregroundColor(W.faint)
            }
            PrimaryButton(title: "Start Smart Scan", icon: "sparkles") { store.scan() }
            HStack(alignment: .top, spacing: 14) {
                Feature(icon: "lock.shield", title: "Never touches your code", text: "Source, .git, databases and Docker data are protected.")
                Feature(icon: "bolt.horizontal", title: "Knows what's in use", text: "Skips running apps, dev servers and builds.")
                Feature(icon: "ruler", title: "Real sizes", text: "Measures what files truly use on disk.")
            }
            .frame(maxWidth: 860)
            .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Feature: View {
    let icon: String, title: String, text: String
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                IconBadge(icon: icon, size: 32).padding(.bottom, 4)
                Text(title).font(W.body(13, .semibold)).foregroundColor(W.text)
                Text(text).font(W.body(12)).foregroundColor(W.faint).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        }
    }
}

// MARK: scanning / cleaning

struct WorkingView: View {
    @EnvironmentObject var store: Store
    @State private var spin = false
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().stroke(W.panel2, lineWidth: 10).frame(width: 150, height: 150)
                Circle().trim(from: 0, to: 0.28).stroke(W.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                Logo(size: 54)
            }
            Text(store.phase == .scanning ? "Scanning your Mac…" : "Cleaning…").font(W.display(24)).foregroundColor(W.text)
            Text(store.status).font(W.body(13)).foregroundColor(W.faint)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { spin = true }
    }
}

// MARK: results

struct ResultsView: View {
    @EnvironmentObject var store: Store
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                categoryList.frame(width: 300)
                Divider().overlay(W.line)
                itemList
            }
            bottomBar
        }
        .sheet(isPresented: $confirming) { ConfirmSheet(isPresented: $confirming) }
    }

    var header: some View {
        HStack(spacing: 14) {
            IconBadge(icon: store.foundSize > 0 ? "sparkles" : "checkmark.seal.fill",
                      color: store.foundSize > 0 ? W.orange : W.green, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                if store.foundSize > 0 {
                    (Text("We found ") + Text(human(store.foundSize)).foregroundColor(W.orange) + Text(" you can safely clean"))
                        .font(W.display(26)).foregroundColor(W.text)
                } else {
                    Text("Your Mac is already clean").font(W.display(26)).foregroundColor(W.text)
                }
                Text("Nothing irreplaceable is listed here. Items in use are skipped automatically.")
                    .font(W.body(12)).foregroundColor(W.faint)
            }
            Spacer()
            SecondaryButton(title: "Rescan", icon: "arrow.clockwise") { store.scan() }
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
    }

    var categoryList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Category.allCases) { c in
                    let list = store.items(in: c)
                    if !list.isEmpty {
                        let st = store.categoryState(c)
                        HStack(spacing: 12) {
                            CheckBox(on: st.on, mixed: st.mixed)
                                .onTapGesture { store.setCategory(c, !(st.on || st.mixed)) }
                            IconBadge(icon: c.icon, color: store.focus == c ? W.orange : W.faint, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.rawValue).font(W.body(14, .semibold)).foregroundColor(W.text)
                                Text(human(store.size(of: c))).font(W.body(12, .semibold))
                                    .foregroundColor(store.size(of: c) > 0 ? W.orange300 : W.faint)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(W.faint)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(store.focus == c ? W.panel2 : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(store.focus == c ? W.orange.opacity(0.35) : Color.clear, lineWidth: 1))
                        .contentShape(Rectangle())
                        .onTapGesture { store.focus = c }
                    }
                }
            }
            .padding(12)
        }
        .background(W.panel.opacity(0.5))
    }

    var itemList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.focus.rawValue).font(W.display(18, .semibold)).foregroundColor(W.text)
                Text(store.focus.blurb).font(W.body(12)).foregroundColor(W.faint)
            }
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 10)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.items(in: store.focus)) { item in
                        ItemRow(item: item)
                        Divider().overlay(W.line).padding(.leading, 56)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    var bottomBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(human(store.selectedSize)) selected").font(W.display(22)).foregroundColor(W.text)
                Text("\(store.selectedCount) items · you choose Trash or delete on the next step")
                    .font(W.body(12)).foregroundColor(W.faint)
            }
            Spacer()
            PrimaryButton(title: "Clean", icon: "sparkles", disabled: store.selectedCount == 0) { confirming = true }
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .background(.regularMaterial)
        .overlay(Rectangle().fill(W.line).frame(height: 1), alignment: .top)
    }
}

struct ItemRow: View {
    @EnvironmentObject var store: Store
    let item: CleanItem
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            CheckBox(on: item.selected, enabled: item.blocked == nil)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.title).font(W.body(13, .semibold)).foregroundColor(item.blocked == nil ? W.text : W.faint)
                        .lineLimit(1)
                    RiskBadge(risk: item.risk)
                }
                if let b = item.blocked {
                    Label("Skipped: \(b)", systemImage: "pause.circle").font(W.body(11)).foregroundColor(W.amber)
                } else {
                    Text(item.detail).font(W.body(11)).foregroundColor(W.faint).lineLimit(2)
                }
            }
            Spacer()
            if hover, let p = item.revealPath {
                Button { revealInFinder(p) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.plain).foregroundColor(W.muted).help("Show in Finder")
            }
            Text(item.size > 0 ? human(item.size) : (item.isTool ? "varies" : "—")).font(W.body(13, .semibold)).foregroundColor(W.muted)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 22).padding(.vertical, 11)
        .background(hover ? W.panel2.opacity(0.6) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { store.toggle(item.id) }
        .onHover { hover = $0 }
    }
}

// MARK: confirm

struct ConfirmSheet: View {
    @EnvironmentObject var store: Store
    @Binding var isPresented: Bool
    @AppStorage("deleteMode") private var permanent = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Logo(size: 30)
                Text("Clean \(human(store.selectedSize))?").font(W.display(22)).foregroundColor(W.text)
            }
            Text("\(store.selectedCount) items will be cleaned. Your code, git history, databases, Docker images and volumes are never touched.")
                .font(W.body(13)).foregroundColor(W.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ModeOption(on: permanent, title: "Delete now", text: "Frees the space immediately. Everything here regenerates by itself.") { permanent = true }
                ModeOption(on: !permanent, title: "Move to Trash", text: "Can be restored, but space is only freed when you empty the Trash.") { permanent = false }
            }
            HStack {
                Spacer()
                SecondaryButton(title: "Cancel") { isPresented = false }
                PrimaryButton(title: permanent ? "Delete & free space" : "Move to Trash", icon: "sparkles") {
                    isPresented = false
                    store.clean(mode: permanent ? .permanent : .trash)
                }
            }
        }
        .padding(26)
        .frame(width: 480)
        .background(W.bg)
    }
}

struct ModeOption: View {
    let on: Bool, title: String, text: String
    let action: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().stroke(on ? W.orange : W.faint, lineWidth: 2).frame(width: 18, height: 18)
                .overlay(Circle().fill(W.orange).frame(width: 9, height: 9).opacity(on ? 1 : 0))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(W.body(13, .semibold)).foregroundColor(W.text)
                Text(text).font(W.body(12)).foregroundColor(W.faint)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(on ? W.panel2 : W.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? W.orange.opacity(0.6) : W.line, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

// MARK: done

struct DoneView: View {
    @EnvironmentObject var store: Store
    @State private var trashFreed: Int64?
    @State private var emptying = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            IconBadge(icon: "checkmark", color: W.green, size: 84)
                .shadow(color: W.green.opacity(0.3), radius: 24)
            if let r = store.report {
                if r.mode == .trash {
                    Text("Moved to Trash").font(W.display(30)).foregroundColor(W.text)
                    Text("Empty the Trash to get the space back.").font(W.body(13)).foregroundColor(W.faint)
                } else {
                    (Text("Freed ") + Text(human(r.freed)).foregroundColor(W.orange)).font(W.display(34)).foregroundColor(W.text)
                    Text("\(r.cleaned) items cleaned · now \(human(store.free)) free").font(W.body(13)).foregroundColor(W.faint)
                }
                if !r.skipped.isEmpty || r.failed > 0 {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Left alone for safety").font(W.body(13, .semibold)).foregroundColor(W.amber)
                            ForEach(r.skipped, id: \.self) { Text("• \($0)").font(W.body(12)).foregroundColor(W.muted) }
                            if r.failed > 0 { Text("• \(r.failed) items were in use or protected by macOS").font(W.body(12)).foregroundColor(W.muted) }
                        }
                        .frame(maxWidth: 460, alignment: .leading)
                    }
                }
            }
            HStack(spacing: 12) {
                if store.report?.mode == .trash {
                    if let f = trashFreed {
                        Text("Trash emptied · freed \(human(f))").font(W.body(13, .semibold)).foregroundColor(W.green)
                    } else {
                        PrimaryButton(title: emptying ? "Emptying…" : "Empty Trash", icon: "trash", disabled: emptying) {
                            emptying = true
                            store.emptyTrash { trashFreed = $0; emptying = false }
                        }
                    }
                }
                SecondaryButton(title: "Scan again", icon: "arrow.clockwise") { store.scan() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
