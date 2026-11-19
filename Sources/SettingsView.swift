import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthModel.self) private var auth

    @AppStorage("notify.on") private var notifyOn = false
    @AppStorage("notify.creditDays") private var creditDays = 3
    @AppStorage("notify.offerDays") private var offerDays = 3
    @AppStorage("notify.hour") private var hour = 9
    @AppStorage("notify.syncEvery") private var syncEvery = 3
    @AppStorage("notify.syncHour") private var syncHour = 19
    @AppStorage("notify.fees") private var feeReminders = true
    @AppStorage("sync.autoAdd") private var autoAdd = true
    @AppStorage("sync.careful") private var careful = false
    @AppStorage("sync.skip") private var skipWords = ""
    @AppStorage("amexTermsAcknowledged") private var amexAcknowledged = false
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("haptics") private var haptics = true

    @State private var denied = false
    @State private var testSent: Bool?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingImport: AppData?
    @State private var importError: String?
    @State private var confirmWipe = false
    @State private var confirmClearLogins = false
    @State private var loginsCleared = false
    @State private var checkingAdapters = false
    @State private var askAmex = false

    var body: some View {
        NavigationStack {
            Form {
                remindersSection
                syncSection
                securitySection
                dataSection
                appearanceSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Settings")
            .onChange(of: [creditDays, offerDays, hour, syncEvery, syncHour]) { _, _ in reschedule() }
            .onChange(of: feeReminders) { _, _ in reschedule() }
            .task { denied = await Notifier.shared.permissionDenied }
            .fileExporter(isPresented: $exporting, document: BackupDocument(data: store.data), contentType: .json,
                          defaultFilename: "Perk Keeper Backup \(Date().formatted(.iso8601.year().month().day()))") { _ in }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in readImport(result) }
            .alert("Replace everything with this backup?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
                Button("Replace", role: .destructive) {
                    if let d = pendingImport { store.replaceAll(with: d) }
                    pendingImport = nil
                }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: {
                Text("The backup has \(pendingImport?.cards.count ?? 0) cards and \(pendingImport?.offers.count ?? 0) offers. What's in the app now will be replaced.")
            }
            .alert("Couldn't open that file", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError ?? "") }
            .confirmationDialog("Delete all Perk Keeper data?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete cards, credits and offers", role: .destructive) { store.replaceAll(with: AppData()) }
            }
            .confirmationDialog("Sign out of every bank in Perk Keeper's browser?", isPresented: $confirmClearLogins, titleVisibility: .visible) {
                Button("Clear website data", role: .destructive) {
                    Task {
                        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                        loginsCleared = true
                    }
                }
            }
            .alert("About adding Amex Offers automatically", isPresented: $askAmex) {
                Button("Turn on anyway") { amexAcknowledged = true; autoAdd = true }
                Button("Not for Amex") {
                    amexAcknowledged = true
                    autoAdd = true
                    var off = Prefs.autoAddOff
                    off.insert(Issuer.amex.rawValue)
                    UserDefaults.standard.set(Array(off), forKey: "sync.autoAddOff")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(AmexTerms.warning)
            }
        }
    }

    private func reschedule() { Task { await Notifier.shared.reschedule(store: store) } }

    // MARK: Reminders

    private var remindersSection: some View {
        Section {
            Toggle(isOn: Binding(get: { notifyOn }, set: { on in
                Task {
                    if on {
                        let ok = await Notifier.shared.requestPermission()
                        notifyOn = ok
                        denied = !ok
                    } else {
                        notifyOn = false
                    }
                    reschedule()
                }
            })) {
                Label("Reminders", systemImage: "bell.badge.fill")
            }
            if denied {
                Button("Notifications are off for Perk Keeper. Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.footnote)
            }
            if notifyOn {
                Picker("Credits about to reset", selection: $creditDays) {
                    Text("Last day").tag(1); Text("3 days before").tag(3); Text("5 days before").tag(5); Text("A week before").tag(7)
                }
                Picker("Added offers expiring", selection: $offerDays) {
                    Text("1 day before").tag(1); Text("3 days before").tag(3); Text("5 days before").tag(5); Text("A week before").tag(7)
                }
                Picker("Check for new offers", selection: $syncEvery) {
                    Text("Never").tag(0); Text("Every 2 days").tag(2); Text("Every 3 days").tag(3); Text("Every 5 days").tag(5); Text("Weekly").tag(7)
                }
                Picker("Reminder time", selection: $hour) {
                    ForEach([7, 8, 9, 10, 12, 17, 18, 20], id: \.self) { h in Text(hourLabel(h)).tag(h) }
                }
                if syncEvery > 0 {
                    Picker("New-offer check time", selection: $syncHour) {
                        ForEach([8, 12, 17, 18, 19, 20, 21], id: \.self) { h in Text(hourLabel(h)).tag(h) }
                    }
                }
                Toggle("Annual fee heads-up", isOn: $feeReminders)
                Button(testSent == true ? "Test sent" : "Send a test notification") {
                    Task { testSent = await Notifier.shared.sendTest() }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Banks don't let apps check your offers in the background, so Perk Keeper reminds you to sync every few days. Each sync shows exactly what's new and can add it all for you.")
        }
    }

    private func hourLabel(_ h: Int) -> String {
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now) ?? .now
        return d.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Sync

    private var syncSection: some View {
        Section {
            Toggle(isOn: Binding(get: { autoAdd }, set: { on in
                if on && !amexAcknowledged && store.cards.contains(where: { $0.issuer == .amex }) {
                    askAmex = true
                } else {
                    autoAdd = on
                }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-add new offers")
                    Text("Adds every offer while it syncs, one at a time.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if autoAdd {
                ForEach(Issuer.allCases.filter(\.supportsSync)) { issuer in
                    Toggle(issuer.name, isOn: Binding(get: { !Prefs.autoAddOff.contains(issuer.rawValue) }, set: { on in
                        var off = Prefs.autoAddOff
                        if on { off.remove(issuer.rawValue) } else { off.insert(issuer.rawValue) }
                        UserDefaults.standard.set(Array(off), forKey: "sync.autoAddOff")
                    }))
                    .padding(.leading, 12)
                }
            }
            Toggle(isOn: $careful) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Careful pace")
                    Text("Waits about 2–3 seconds between adds instead of 1–2.").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("Skip offers containing (comma separated)", text: $skipWords)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("e.g. \"lululemon, oura\". Matching offers are listed but never added.").font(.caption).foregroundStyle(.secondary)
            }
            adapterRow
            Button(loginsCleared ? "Signed out of all banks" : "Sign out of banks in Perk Keeper", role: .destructive) { confirmClearLogins = true }
                .disabled(loginsCleared)
        } header: {
            Text("Offer sync")
        } footer: {
            Text(AmexTerms.footer)
        }
    }

    private var adapterRow: some View {
        let a = AdapterStore.shared
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bank page rules")
                Text("Version \(a.version) (\(a.source)) · \(a.lastChecked.map { "checked \($0.formatted(.relative(presentation: .named)))" } ?? "not checked yet")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if checkingAdapters {
                ProgressView()
            } else {
                Button("Check") {
                    checkingAdapters = true
                    Task {
                        await a.refreshIfNeeded(force: true)
                        checkingAdapters = false
                    }
                }
            }
        }
    }

    // MARK: Security

    private var securitySection: some View {
        Section("Security") {
            Toggle(isOn: Binding(get: { auth.faceIDEnabled }, set: { on in Task { await auth.setFaceID(on) } })) {
                Label("Lock with \(auth.biometryName)", systemImage: auth.biometryIcon)
            }
            if auth.faceIDEnabled {
                Picker("Lock after", selection: Binding(get: { auth.autoLockSeconds }, set: { auth.autoLockSeconds = $0 })) {
                    Text("Immediately").tag(0); Text("1 minute").tag(60); Text("5 minutes").tag(300); Text("15 minutes").tag(900)
                }
            }
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            HStack {
                Label("Automatic backup", systemImage: "externaldrive.badge.checkmark")
                Spacer()
                Text(Persistence.lastBackup.map { $0.formatted(.relative(presentation: .named)) } ?? "not yet")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button { exporting = true } label: { Label("Export a backup", systemImage: "square.and.arrow.up") }
            Button { importing = true } label: { Label("Restore from a backup", systemImage: "square.and.arrow.down") }
            if store.cards.isEmpty {
                Button { store.replaceAll(with: DemoData.make()) } label: { Label("Load sample data", systemImage: "wand.and.stars") }
            }
            HStack {
                Label("Home Screen widget", systemImage: "square.text.square")
                Spacer()
                Text(AppGroup.containerURL != nil ? "Ready" : "Needs App Groups")
                    .font(.caption).foregroundStyle(AppGroup.containerURL != nil ? Theme.good : Theme.warn)
            }
            Button(role: .destructive) { confirmWipe = true } label: { Label("Delete all data", systemImage: "trash") }
        } header: {
            Text("Your data")
        } footer: {
            Text("Everything stays on this iPhone. A copy is saved to Files → On My iPhone → Perk Keeper after every change, and it's part of your iCloud Backup.")
        }
    }

    private func readImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingImport = try Persistence.decode(try Data(contentsOf: url))
        } catch {
            importError = "That doesn't look like a Perk Keeper backup."
        }
    }

    // MARK: Appearance / about

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearance) {
                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
            }
            Toggle("Haptics", isOn: $haptics)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                           + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") + ")")
            LabeledContent("Card benefits checked", value: Templates.asOf)
            NavigationLink("How Perk Keeper works") { HowItWorksView() }
        } header: {
            Text("About")
        }
    }
}

enum AmexTerms {
    static let warning = "American Express's Amex Offers terms prohibit adding offers with automated tools, scripts or bots, and say offers added that way may not be honored. Auto-add and Add all click each Add to Card button for you, so using them on Amex is your call. You can keep auto-add on for other banks and turn it off for Amex."
    static let footer = "Auto-add and Add all press each offer's own Add button for you, at a human pace, on the card you're signed in to. They never add one offer to several cards. American Express's offer terms ban automated adding, so they may void Amex offers added this way; other banks can change their rules too."
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: AppData

    init(data: AppData) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let raw = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = try Persistence.decode(raw)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Persistence.encode(data))
    }
}

struct HowItWorksView: View {
    var body: some View {
        List {
            Section("Credits") {
                Text("Each credit knows how often it resets: monthly, quarterly, every six months, each calendar year or card year, or every few years. Mark it used when you use it and Perk Keeper shows what's left and reminds you before it resets.")
            }
            Section("Offers") {
                Text("Banks don't offer an API for card-linked offers. Perk Keeper opens your bank's own offers page in its built-in browser, where you sign in normally. A small script reads the offer tiles on the page (merchant, reward, expiration and status) and, if you ask, presses each Add button for you, one at a time.")
                Text("Each sync compares what's on the page with what Perk Keeper saw last time, so new offers are marked New, added offers that disappear are flagged so you can confirm you used them, and offers your bank shows as redeemed move to Used.")
            }
            Section("Privacy") {
                Text("The script runs in its own isolated space, ignores every form field and never sees your password. Your data is saved only on this iPhone. The only thing Perk Keeper downloads is an updated list of bank page rules from its GitHub repo.")
            }
            Section("When a bank changes its website") {
                Text("Open the sync browser's menu and choose Page diagnostics. It makes a masked outline of the page (account numbers and emails hidden) that can be used to update the bank page rules, which the app downloads automatically.")
            }
        }
        .navigationTitle("How it works")
    }
}
