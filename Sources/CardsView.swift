import SwiftUI

struct CardsView: View {
    @Environment(AppStore.self) private var store
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if store.cards.isEmpty {
                    ContentUnavailableView {
                        Label("No cards yet", systemImage: "creditcard")
                    } description: {
                        Text("Pick your card from the list to get its credits filled in, or add any card yourself.")
                    } actions: {
                        Button("Add a card") { showAdd = true }.glassButton(prominent: true)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(store.cards) { card in
                                NavigationLink(value: CardRoute(id: card.id)) { CardTile(card: card) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Cards")
            .navigationDestination(for: CardRoute.self) { r in CardDetailView(cardID: r.id) }
            .navigationDestination(for: CreditRoute.self) { r in CreditDetailView(creditID: r.id) }
            .navigationDestination(for: OfferRoute.self) { r in OfferDetailView(offerID: r.id) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add card")
                }
            }
            .sheet(isPresented: $showAdd) { AddCardSheet() }
        }
    }
}

private struct CardTile: View {
    let card: Card
    @Environment(AppStore.self) private var store

    var body: some View {
        let credits = store.credits(for: card.id, includeHidden: false).filter { $0.isActive() }
        let statuses = credits.map { store.status(of: $0) }
        let left = statuses.filter { $0.resetsOn != nil }.reduce(0) { $0 + $1.remaining }
        let yearValue = credits.reduce(0) { $0 + $1.yearValue }
        let added = store.offers(for: card.id).filter { $0.status == .added && !$0.isExpired }.count
        HStack(spacing: 14) {
            CardArt(card: card, width: 104, showText: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(card.issuer.name).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if left > 0 { Pill(text: "\(left.shortMoney) to use", color: Theme.warn) }
                    if added > 0 { Pill(text: "\(added) offers", color: Theme.accent) }
                }
                if yearValue > 0 || (card.annualFee ?? 0) > 0 {
                    Text("Credits \(yearValue.shortMoney)/yr · fee \((card.annualFee ?? 0).shortMoney)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassCard(interactive: true)
    }
}

struct CardDetailView: View {
    let cardID: UUID
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var newCredit: Credit?
    @State private var syncing: SyncSession?
    @State private var confirmDelete = false

    var body: some View {
        if let card = store.card(cardID) {
            let statuses = store.credits(for: card.id).filter { $0.isActive() }.map { store.status(of: $0) }
            let offers = store.offers(for: card.id).filter { !$0.hidden && ($0.status == .added || $0.status == .available) && !$0.isExpired }
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        CardArt(card: card, width: 300, showText: true).padding(.top, 8)
                        facts(card)
                        if card.issuer.supportsSync {
                            Button {
                                syncing = SyncSession(adapter: AdapterStore.shared.adapter(for: card.issuer), cardID: card.id, autoAdd: Prefs.autoAdd(for: card.issuer))
                            } label: {
                                Label("Sync \(card.issuer.offersName)", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                            }
                            .glassButton(prominent: true)
                        }
                        creditsSection(card, statuses)
                        if !offers.isEmpty {
                            VStack(spacing: 0) {
                                SectionTitle(title: "Offers on this card", trailing: "\(offers.count)").padding(.bottom, 6)
                                VStack(spacing: 0) {
                                    ForEach(offers.sorted { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }.prefix(12)) { o in
                                        NavigationLink(value: OfferRoute(id: o.id)) { OfferRow(offer: o, isNew: store.isNew(o)) }
                                            .buttonStyle(.plain)
                                        Divider().padding(.leading, 16)
                                    }
                                }
                                .glassCard()
                            }
                        }
                        Button("Remove card", role: .destructive) { confirmDelete = true }
                            .font(.footnote)
                            .padding(.top, 6)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(card.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
            }
            .sheet(isPresented: $editing) { CardEditor(card: card) }
            .sheet(item: $newCredit) { c in CreditEditor(credit: c) }
            .fullScreenCover(item: $syncing) { s in SyncBrowserView(session: s) }
            .confirmationDialog("Remove \(card.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove card and its credits and offers", role: .destructive) {
                    store.deleteCard(card.id)
                    dismiss()
                }
            }
        } else {
            ContentUnavailableView("Card removed", systemImage: "creditcard")
        }
    }

    private func facts(_ card: Card) -> some View {
        HStack(spacing: 0) {
            Stat(value: (card.annualFee ?? 0).shortMoney, label: "annual fee")
            Divider().frame(height: 28)
            Stat(value: card.anniversaryMonth.map { Calendar.current.shortMonthSymbols[$0 - 1] } ?? "—", label: "renews")
            Divider().frame(height: 28)
            let value = store.credits(for: card.id, includeHidden: false).filter { $0.isActive() }.reduce(0) { $0 + $1.yearValue }
            Stat(value: value.shortMoney, label: "credits / yr", color: Theme.good)
        }
        .padding(.vertical, 12)
        .glassCard()
    }

    private func creditsSection(_ card: Card, _ statuses: [CreditStatus]) -> some View {
        VStack(spacing: 0) {
            HStack {
                SectionTitle(title: "Credits & perks")
                Button { newCredit = Credit(cardID: card.id, name: "", amount: 0, cadence: .monthly) } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .padding(.top, 8)
                .accessibilityLabel("Add a credit")
            }
            .padding(.bottom, 6)
            if statuses.isEmpty {
                Text("No credits on this card. Tap + to add one, like a monthly streaming credit or a yearly travel credit.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14).glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(statuses) { s in
                        NavigationLink(value: CreditRoute(id: s.credit.id)) {
                            CreditRow(status: s, showCard: false)
                                .padding(.vertical, 10).padding(.horizontal, 14)
                                .opacity(s.credit.hidden ? 0.5 : 1)
                        }
                        .buttonStyle(.plain)
                        if s.id != statuses.last?.id { Divider().padding(.leading, 64) }
                    }
                }
                .glassCard()
            }
        }
    }
}

// MARK: - Adding a card

struct AddCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var groups: [(Issuer, [CardTemplate])] {
        let list = Templates.all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.issuer.name.localizedCaseInsensitiveContains(search) }
        let order = Issuer.allCases
        return order.compactMap { i in
            let t = list.filter { $0.issuer == i }
            return t.isEmpty ? nil : (i, t)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CardSetupView(template: nil, onDone: { dismiss() })
                    } label: {
                        Label("Any other card", systemImage: "plus.rectangle.on.rectangle")
                    }
                } footer: {
                    Text("Credits and fees as of \(Templates.asOf). You can change anything after adding.")
                }
                ForEach(groups, id: \.0) { issuer, templates in
                    Section(issuer.name) {
                        ForEach(templates) { t in
                            NavigationLink {
                                CardSetupView(template: t, onDone: { dismiss() })
                            } label: {
                                TemplateRow(template: t)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Find your card")
            .navigationTitle("Add a card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct TemplateRow: View {
    let template: CardTemplate
    var body: some View {
        HStack(spacing: 12) {
            CardArt(card: Card(name: template.name, issuer: template.issuer, colorHex: template.colors.0, colorHex2: template.colors.1), width: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.subheadline.weight(.semibold))
                Text(template.credits.isEmpty ? "No statement credits" : "\(template.credits.count) perks · \(template.yearValue.shortMoney)/yr in credits")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Last 4, anniversary month and which credits to track, then add.
struct CardSetupView: View {
    let template: CardTemplate?
    var onDone: () -> Void
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var issuer: Issuer = .amex
    @State private var last4 = ""
    @State private var fee = ""
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var knowsMonth = false
    @State private var keep: Set<Int> = []
    @State private var colorIndex = 0

    static let palette: [(String, String)] = [
        ("#3A3A3C", "#0E0E10"), ("#C9CDD3", "#7D838C"), ("#E2C275", "#A97C2A"), ("#2C3E5C", "#111A2B"),
        ("#0F7A5A", "#073D2E"), ("#8E2C48", "#3E0F1E"), ("#3F51B5", "#1A237E"), ("#F7A23B", "#D3611A"),
    ]

    var body: some View {
        Form {
            Section {
                TextField("Card name", text: $name)
                if template == nil {
                    Picker("Bank", selection: $issuer) {
                        ForEach(Issuer.allCases) { i in Text(i.name).tag(i) }
                    }
                }
                TextField("Last 4 or 5 digits (optional)", text: $last4)
                    .keyboardType(.numberPad)
                    .onChange(of: last4) { _, v in last4 = String(v.filter(\.isNumber).prefix(5)) }
                HStack { Text("Annual fee $"); TextField("0", text: $fee).keyboardType(.decimalPad) }
                Toggle("I know when it renews", isOn: $knowsMonth)
                if knowsMonth {
                    Picker("Renewal month", selection: $month) {
                        ForEach(1...12, id: \.self) { m in Text(Calendar.current.monthSymbols[m - 1]).tag(m) }
                    }
                }
                if template == nil {
                    Picker("Color", selection: $colorIndex) {
                        ForEach(Self.palette.indices, id: \.self) { i in
                            Text(["Black", "Platinum", "Gold", "Navy", "Green", "Burgundy", "Blue", "Orange"][i]).tag(i)
                        }
                    }
                }
            } header: {
                CardArt(card: preview, width: 220, showText: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .textCase(nil)
            } footer: {
                Text("The digits help Perk Keeper tell your cards apart when it syncs offers. The renewal month sets card-year credits and a reminder before the annual fee.")
            }

            if let template, !template.credits.isEmpty {
                Section {
                    ForEach(template.credits.indices, id: \.self) { i in
                        let c = template.credits[i]
                        Toggle(isOn: Binding(get: { keep.contains(i) }, set: { on in if on { keep.insert(i) } else { keep.remove(i) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(c.name, systemImage: c.symbol).font(.subheadline.weight(.medium))
                                Text(c.amount > 0 ? "\(c.amount.shortMoney) · \(c.cadence.label.lowercased())" : c.cadence.label)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Track these credits")
                } footer: {
                    Text(template.note.isEmpty ? "Turn off any you won't use. They stay on the card, hidden from totals and reminders." : template.note)
                }
            } else if let template, !template.note.isEmpty {
                Section { Text(template.note).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(template?.name ?? "New card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { add() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard name.isEmpty else { return }
            if let t = template {
                name = t.name
                issuer = t.issuer
                fee = t.annualFee.map { $0.clean2 } ?? ""
                keep = Set(t.credits.indices)
            }
        }
    }

    private var preview: Card {
        let colors = template?.colors ?? Self.palette[colorIndex]
        return Card(name: name.isEmpty ? "Card" : name, issuer: template?.issuer ?? issuer, last4: last4, colorHex: colors.0, colorHex2: colors.1)
    }

    private func add() {
        let colors = template?.colors ?? Self.palette[colorIndex]
        store.addCard(template: template, name: name.trimmingCharacters(in: .whitespaces), issuer: template?.issuer ?? issuer,
                      last4: last4, anniversaryMonth: knowsMonth ? month : nil, annualFee: Double(fee),
                      colors: colors, keepCredits: template == nil ? nil : keep)
        Haptics.success()
        onDone()
    }
}

struct CardEditor: View {
    @State var card: Card
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var fee = ""
    @State private var knowsMonth = false
    @State private var month = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Card name", text: $card.name)
                    Picker("Bank", selection: $card.issuer) {
                        ForEach(Issuer.allCases) { i in Text(i.name).tag(i) }
                    }
                    TextField("Last 4 or 5 digits", text: $card.last4).keyboardType(.numberPad)
                    HStack { Text("Annual fee $"); TextField("0", text: $fee).keyboardType(.decimalPad) }
                    Toggle("I know when it renews", isOn: $knowsMonth)
                    if knowsMonth {
                        Picker("Renewal month", selection: $month) {
                            ForEach(1...12, id: \.self) { m in Text(Calendar.current.monthSymbols[m - 1]).tag(m) }
                        }
                    }
                } header: {
                    CardArt(card: card, width: 220, showText: true).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                Section("Notes") {
                    TextField("Anything to remember", text: $card.notes, axis: .vertical).lineLimit(2...6)
                }
            }
            .navigationTitle("Edit card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        card.annualFee = Double(fee)
                        card.anniversaryMonth = knowsMonth ? month : nil
                        card.last4 = String(card.last4.filter(\.isNumber).prefix(5))
                        store.save(card: card)
                        dismiss()
                    }
                }
            }
            .onAppear {
                fee = card.annualFee.map { $0.clean2 } ?? ""
                knowsMonth = card.anniversaryMonth != nil
                month = card.anniversaryMonth ?? Calendar.current.component(.month, from: .now)
            }
        }
    }
}
