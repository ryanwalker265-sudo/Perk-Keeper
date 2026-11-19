import SwiftUI
import WebKit

// MARK: - Choosing what to sync

struct SyncHubView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var session: SyncSession?
    @State private var askOther = false
    @State private var otherURL = ""

    var body: some View {
        NavigationStack {
            List {
                if store.syncableCards.isEmpty {
                    Section {
                        Text("Add an American Express, Chase, Citi, Bank of America, Wells Fargo or U.S. Bank card on the Cards tab and it shows up here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(store.syncableCards) { card in
                            Button { open(card) } label: { SyncCardRow(card: card) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Your cards")
                    } footer: {
                        Text(Prefs.autoAdd
                             ? "Auto-add is on: Perk Keeper adds every new offer while it looks, one at a time. Change it in Settings."
                             : "Perk Keeper reads your offers, shows what's new and adds them all when you tap Add all. Turn on auto-add in Settings to skip the tap.")
                    }
                }
                Section {
                    Button { askOther = true } label: { Label("Another bank's offers page…", systemImage: "globe") }
                    Button {
                        session = SyncSession(adapter: AdapterStore.shared.demoAdapter, cardID: nil, autoAdd: false, demo: true)
                    } label: {
                        Label("Try it on a practice page", systemImage: "graduationcap")
                    }
                } footer: {
                    Text("You sign in to your bank inside Perk Keeper's browser, the same way as in Safari, and you can use your saved passwords. Perk Keeper never reads the sign-in form or stores your password, and nothing leaves this iPhone.")
                }
            }
            .navigationTitle("Sync offers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(item: $session) { s in SyncBrowserView(session: s) }
            .alert("Bank offers page", isPresented: $askOther) {
                TextField("https://", text: $otherURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Open") { openOther() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Paste the address of your bank's offers or deals page. Perk Keeper looks for buttons like Add, Activate or Enroll.")
            }
        }
    }

    private func open(_ card: Card) {
        session = SyncSession(adapter: AdapterStore.shared.adapter(for: card.issuer), cardID: card.id, autoAdd: Prefs.autoAdd(for: card.issuer))
    }

    private func openOther() {
        var s = otherURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard let url = URL(string: s), url.scheme == "https" else { return }
        session = SyncSession(adapter: AdapterStore.shared.adapter(for: .other), cardID: nil, autoAdd: false, startURL: url)
    }
}

private struct SyncCardRow: View {
    let card: Card
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            CardArt(card: card, width: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayName).font(.subheadline.weight(.semibold))
                if let last = store.lastSync(issuer: card.issuer, cardID: card.id) {
                    Text("Synced \(last.date.formatted(.relative(presentation: .named))) · \(last.found) offers")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Not synced yet").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - The in-app browser

struct SyncBrowserView: View {
    @State private var controller: SyncController
    @Environment(\.dismiss) private var dismiss
    @State private var diagnostics: DiagnosticsText?
    @State private var panelCollapsed = false

    init(session: SyncSession) {
        _controller = State(initialValue: SyncController(session: session, store: AppStore.shared))
    }

    var body: some View {
        NavigationStack {
            WebViewHost(controller: controller)
                .ignoresSafeArea(.container, edges: .bottom)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    SyncPanel(controller: controller, collapsed: $panelCollapsed, onDone: { dismiss() })
                }
                .navigationTitle(controller.adapter.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { controller.goBack() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!controller.canGoBack)
                            .accessibilityLabel("Back")
                        Menu {
                            Button { controller.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                            ForEach(Array(controller.adapter.steps.enumerated()), id: \.offset) { i, step in
                                Button { controller.goToStep(i) } label: { Label(step.label, systemImage: "arrow.right.circle") }
                            }
                            Divider()
                            Button {
                                Task { diagnostics = DiagnosticsText(text: await controller.diagnostics()) }
                            } label: {
                                Label("Page diagnostics", systemImage: "stethoscope")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.close() }
        .alert(controller.dialog?.isConfirm == true ? "Confirm" : "Message from the website",
               isPresented: Binding(get: { controller.dialog != nil }, set: { if !$0 { controller.dialog?.complete(false); controller.dialog = nil } })) {
            if controller.dialog?.isConfirm == true {
                Button("Cancel", role: .cancel) { controller.dialog?.complete(false); controller.dialog = nil }
                Button("OK") { controller.dialog?.complete(true); controller.dialog = nil }
            } else {
                Button("OK") { controller.dialog?.complete(true); controller.dialog = nil }
            }
        } message: {
            Text(controller.dialog?.message ?? "")
        }
        .sheet(item: $diagnostics) { d in DiagnosticsSheet(text: d.text) }
    }
}

struct DiagnosticsText: Identifiable {
    let id = UUID()
    let text: String
}

private struct DiagnosticsSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Page diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = text
                        copied = true
                    }
                }
            }
        }
    }
}

struct WebViewHost: UIViewRepresentable {
    let controller: SyncController
    func makeUIView(context: Context) -> WKWebView { controller.makeWebView() }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Bottom panel

struct SyncPanel: View {
    let controller: SyncController
    @Binding var collapsed: Bool
    var onDone: () -> Void
    @AppStorage("amexTermsAcknowledged") private var amexAcknowledged = false
    @State private var askAmex = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                statusIcon.frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { collapsed.toggle() }
                } label: {
                    Image(systemName: collapsed ? "chevron.up" : "chevron.down").font(.caption.weight(.bold)).padding(6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(collapsed ? "Show controls" : "Hide controls")
            }
            if !collapsed {
                if case .adding = controller.phase {
                    ProgressView(value: Double(controller.progress.done), total: Double(max(controller.progress.total, 1)))
                        .tint(Theme.accent)
                }
                if let notice = controller.notice {
                    Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(Theme.warn)
                }
                if controller.adapter.steps.count > 1 && controller.phase != .adding {
                    Picker("Page", selection: Binding(get: { controller.stepIndex }, set: { controller.goToStep($0) })) {
                        ForEach(Array(controller.adapter.steps.enumerated()), id: \.offset) { i, s in Text(s.label).tag(i) }
                    }
                    .pickerStyle(.segmented)
                }
                actions
                cardLine
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 26)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .alert("Add all Amex Offers?", isPresented: $askAmex) {
            Button("Add all") {
                amexAcknowledged = true
                Task { await controller.addAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AmexTerms.warning)
        }
    }

    private func addAllTapped() {
        if controller.adapter.issuer == .amex && !amexAcknowledged && !controller.session.demo {
            askAmex = true
        } else {
            Task { await controller.addAll() }
        }
    }

    private var issuerName: String { controller.adapter.name }

    @ViewBuilder
    private var statusIcon: some View {
        switch controller.phase {
        case .opening, .scanning, .adding: ProgressView()
        case .login: Image(systemName: "lock.fill").foregroundStyle(Theme.accent)
        case .looking: Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        case .ready: Image(systemName: "tag.fill").foregroundStyle(Theme.accent)
        case .finished: Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.good)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
        }
    }

    private var title: String {
        let s = controller.lastScan
        switch controller.phase {
        case .opening: return "Opening \(issuerName)…"
        case .login: return "Sign in to \(issuerName)"
        case .looking: return controller.adapter.steps.isEmpty ? "Open your offers page" : "Looking for offers…"
        case .scanning: return "Reading your offers…"
        case .ready:
            if s.found == 0 { return "\(controller.page.tiles) offers on this page" }
            return "\(s.found) offers · \(s.new) new · \(s.toAdd) to add"
        case .adding:
            let p = controller.progress
            return "Adding \(min(p.done + 1, max(p.total, 1))) of \(max(p.total, 1))" + (p.current.isEmpty ? "" : " · \(p.current)")
        case .finished:
            return controller.addedCount > 0 ? "Added \(controller.addedCount) offers" : "All caught up"
        case .failed(let msg): return msg
        }
    }

    private var subtitle: String? {
        switch controller.phase {
        case .login:
            return "Your password goes only to \(issuerName). Perk Keeper can't see it. Saved passwords appear above the keyboard."
        case .looking:
            return controller.adapter.tips.isEmpty ? "When your offers are on screen, Perk Keeper reads them." : controller.adapter.tips
        case .ready:
            let s = controller.lastScan
            var parts: [String] = []
            if s.added > 0 { parts.append("\(s.added) already added") }
            if s.used > 0 { parts.append("\(s.used) used") }
            if controller.addedCount > 0 { parts.append("\(controller.addedCount) added just now") }
            if controller.failedCount > 0 { parts.append("\(controller.failedCount) didn't stick") }
            if controller.skippedCount > 0 { parts.append("\(controller.skippedCount) skipped by your filter") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .adding:
            return "One at a time, like tapping each Add button yourself."
        case .finished:
            return controller.totalNew > 0 ? "Found \(controller.totalNew) new offers. Your offers list is up to date." : "Nothing new since your last sync."
        default:
            return nil
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch controller.phase {
        case .ready:
            HStack(spacing: 8) {
                if controller.lastScan.toAdd > 0 {
                    Button {
                        addAllTapped()
                    } label: {
                        Label("Add all \(controller.lastScan.toAdd)", systemImage: "plus.circle.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton(prominent: true)
                }
                Button { Task { await controller.scan() } } label: {
                    Label("Scan", systemImage: "arrow.clockwise").frame(maxWidth: controller.lastScan.toAdd > 0 ? nil : .infinity)
                }
                .glassButton()
                if controller.stepIndex + 1 < controller.adapter.steps.count {
                    Button { controller.goToStep(controller.stepIndex + 1) } label: {
                        Label(controller.adapter.steps[controller.stepIndex + 1].label, systemImage: "arrow.right")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    .glassButton()
                } else {
                    Button("Done", action: onDone).glassButton()
                }
            }
        case .adding:
            Button(role: .destructive) { controller.cancel() } label: {
                Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .glassButton()
        case .looking, .login, .failed:
            HStack(spacing: 8) {
                if let step = controller.adapter.steps.first, controller.phase != .login {
                    Button { controller.goToStep(0) } label: {
                        Label(step.label, systemImage: "arrow.right.circle").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .glassButton()
                }
                Button { Task { await controller.scan() } } label: {
                    Label("Scan this page", systemImage: "text.viewfinder").frame(maxWidth: .infinity)
                }
                .glassButton(prominent: controller.phase == .looking)
            }
        case .finished:
            Button(action: onDone) {
                Text("Done").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .glassButton(prominent: true)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var cardLine: some View {
        let cards = controller.cardsForIssuer
        if cards.count > 1 {
            HStack(spacing: 6) {
                Text("Saving to").font(.caption).foregroundStyle(.secondary)
                Menu {
                    ForEach(cards) { c in
                        Button { controller.choose(card: c.id) } label: {
                            if c.id == controller.cardID { Label(c.displayName, systemImage: "checkmark") } else { Text(c.displayName) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let card = controller.card { CardArt(card: card, width: 22) }
                        Text(controller.card?.displayName ?? "Choose a card").font(.caption.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
                Spacer()
            }
        } else if let card = controller.card {
            HStack(spacing: 6) {
                CardArt(card: card, width: 22)
                Text("Saving to \(card.displayName)").font(.caption).foregroundStyle(.secondary)
                if controller.autoAdd { Pill(text: "Auto-add on", color: Theme.accent) }
            }
        } else if controller.session.demo {
            Text("Practice page: nothing here touches a real account.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
