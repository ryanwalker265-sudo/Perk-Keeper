import SwiftUI

struct CreditsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("credits.showHidden") private var showHidden = false
    @AppStorage("credits.group") private var group = "card"

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if store.data.credits.isEmpty {
                    ContentUnavailableView {
                        Label("No credits yet", systemImage: "dollarsign.arrow.circlepath")
                    } description: {
                        Text("Add a card on the Cards tab. Cards from the list come with their credits filled in, and you can add your own to any card.")
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            if group == "reset" { byReset } else { byCard }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Credits")
            .navigationDestination(for: CreditRoute.self) { r in CreditDetailView(creditID: r.id) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Group by", selection: $group) {
                            Label("Card", systemImage: "creditcard").tag("card")
                            Label("Reset date", systemImage: "calendar").tag("reset")
                        }
                        Toggle("Show credits I don't use", isOn: $showHidden)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var byCard: some View {
        ForEach(store.cards) { card in
            let statuses = store.credits(for: card.id, includeHidden: showHidden)
                .filter { $0.isActive() }
                .map { store.status(of: $0) }
                .sorted { ($0.isDone ? 1 : 0, $0.resetsOn ?? .distantFuture) < ($1.isDone ? 1 : 0, $1.resetsOn ?? .distantFuture) }
            if !statuses.isEmpty {
                CardCreditsSection(card: card, statuses: statuses)
            }
        }
    }

    @ViewBuilder
    private var byReset: some View {
        let all = store.creditStatuses(includeHidden: showHidden)
        let open = all.filter { !$0.isDone }
        let done = all.filter { $0.isDone }
        if !open.isEmpty { creditList("Still to use", open) }
        if !done.isEmpty { creditList("Used this period", done) }
    }

    private func creditList(_ title: String, _ list: [CreditStatus]) -> some View {
        VStack(spacing: 0) {
            SectionTitle(title: title).padding(.bottom, 6)
            VStack(spacing: 0) {
                ForEach(list) { s in
                    NavigationLink(value: CreditRoute(id: s.credit.id)) {
                        CreditRow(status: s).padding(.vertical, 10).padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                    if s.id != list.last?.id { Divider().padding(.leading, 64) }
                }
            }
            .glassCard()
        }
    }
}

private struct CardCreditsSection: View {
    let card: Card
    let statuses: [CreditStatus]

    var body: some View {
        let yearValue = statuses.filter { !$0.credit.hidden }.reduce(0) { $0 + $1.credit.yearValue }
        let y = Calendar.current.component(.year, from: .now)
        let usedYear = statuses.filter { !$0.credit.hidden }.reduce(0) { sum, s in
            sum + s.credit.uses.filter { Calendar.current.component(.year, from: $0.date) == y }.reduce(0) { $0 + $1.amount }
        }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CardArt(card: card, width: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.displayName).font(.subheadline.weight(.semibold))
                    Text("\(usedYear.shortMoney) of \(yearValue.shortMoney) used this year")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(statuses) { s in
                    NavigationLink(value: CreditRoute(id: s.credit.id)) {
                        CreditRow(status: s, showCard: false)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .opacity(s.credit.hidden ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    if s.id != statuses.last?.id { Divider().padding(.leading, 64) }
                }
            }
            .glassCard()
        }
        .padding(.top, 6)
    }
}

// MARK: - Detail

struct CreditDetailView: View {
    let creditID: UUID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var using = false
    @State private var editing = false

    var body: some View {
        if let credit = store.credit(creditID) {
            let s = store.status(of: credit)
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        header(s)
                        actions(s)
                        if credit.needsEnrollment { enrollment(credit) }
                        if !credit.note.isEmpty {
                            Text(credit.note)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .glassCard()
                        }
                        history(credit)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(credit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
            }
            .sheet(isPresented: $using) { UseCreditSheet(status: s) }
            .sheet(isPresented: $editing) { CreditEditor(credit: credit) }
        } else {
            ContentUnavailableView("Credit removed", systemImage: "trash")
        }
    }

    private func header(_ s: CreditStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Pill(text: s.credit.cadence.badge, color: Theme.accent)
                if let card = s.card {
                    Text(card.displayName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let card = s.card { CardArt(card: card, width: 44) }
            }
            if s.credit.isChecklist {
                Label(s.isDone ? "Done for this period" : "Still to do", systemImage: s.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(s.isDone ? Theme.good : .primary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(s.remaining.shortMoney).font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    Text("left of \(s.periodAmount.shortMoney)").foregroundStyle(.secondary)
                }
                ProgressBar(value: s.progress, color: s.isDone ? Theme.good : Theme.accent, height: 8)
            }
            HStack {
                if let last = s.lastDay {
                    Text("Use by \(last.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    Spacer()
                    Text(s.isDone ? "Resets \(s.resetsOn?.monthDay ?? "")" : "\(DayMath.shortDays(s.daysLeft ?? 0)) left")
                        .foregroundStyle(s.isDone ? .secondary : Theme.urgency(s.daysLeft))
                } else {
                    Text(s.credit.cadence == .multiYear ? "Renews \(s.credit.everyYears) years after you use it" : "No reset date")
                    Spacer()
                }
            }
            .font(.footnote)
            Text("Worth \(s.credit.yearValue.shortMoney) a year").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16)
        .glassCard()
    }

    private func actions(_ s: CreditStatus) -> some View {
        HStack(spacing: 10) {
            Button {
                store.useRemaining(s)
                Haptics.success()
            } label: {
                Label(s.credit.isChecklist ? "Mark done" : "Used all \(s.remaining.shortMoney)", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .glassButton(prominent: true)
            .disabled(s.isDone)
            if !s.credit.isChecklist {
                Button { using = true } label: {
                    Label("Used some", systemImage: "pencil").frame(maxWidth: .infinity)
                }
                .glassButton()
                .disabled(s.isDone)
            }
        }
    }

    private func enrollment(_ credit: Credit) -> some View {
        Toggle(isOn: Binding(get: { credit.enrolled }, set: { v in
            var c = credit
            c.enrolled = v
            store.save(credit: c)
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enrolled").font(.subheadline.weight(.semibold))
                Text("This credit only works after you enroll in your bank's app or website.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassCard(tint: credit.enrolled ? nil : Theme.warn)
    }

    private func history(_ credit: Credit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(title: "History").padding(.bottom, 6)
            if credit.uses.isEmpty {
                Text("Nothing logged yet.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14).glassCard()
            } else {
                VStack(spacing: 0) {
                    let sorted = credit.uses.sorted { $0.date > $1.date }
                    ForEach(sorted) { u in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
                                if !u.note.isEmpty { Text(u.note).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(credit.isChecklist ? "Done" : u.amount.shortMoney).font(.subheadline.monospacedDigit())
                            Button(role: .destructive) {
                                store.removeUse(creditID: credit.id, useID: u.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        if u.id != sorted.last?.id { Divider().padding(.leading, 14) }
                    }
                }
                .glassCard()
            }
        }
    }
}

// MARK: - Log a use

struct UseCreditSheet: View {
    let status: CreditStatus
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var date = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$")
                        TextField("Amount", text: $amount).keyboardType(.decimalPad)
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("\(status.remaining.shortMoney) of \(status.periodAmount.shortMoney) left this period.")
                }
            }
            .navigationTitle(status.credit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        store.logUse(status.credit.id, amount: value, date: date, note: note)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(value <= 0)
                }
            }
            .onAppear { amount = status.remaining > 0 ? status.remaining.clean2 : "" }
        }
        .presentationDetents([.medium])
    }

    private var value: Double { Double(amount.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "$", with: "")) ?? 0 }
}

extension Double {
    /// "15" or "12.95", for text fields.
    var clean2: String { abs(self - rounded()) < 0.005 ? String(Int(rounded())) : String(format: "%.2f", self) }
}

// MARK: - Edit / add a credit

struct CreditEditor: View {
    @State var credit: Credit
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var decemberText = ""
    @State private var hasEnd = false
    @State private var endDate = Date()
    @State private var confirmDelete = false

    private var isNew: Bool { store.credit(credit.id) == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $credit.name)
                    HStack {
                        Text("Amount $")
                        TextField("0 = checklist item", text: $amountText).keyboardType(.decimalPad)
                    }
                    Picker("Resets", selection: $credit.cadence) {
                        ForEach(Cadence.allCases) { c in Text(c.label).tag(c) }
                    }
                    if credit.cadence == .multiYear {
                        Stepper("Every \(credit.everyYears) years", value: $credit.everyYears, in: 1...10)
                    }
                    if credit.cadence == .monthly {
                        HStack {
                            Text("December $")
                            TextField("Same as other months", text: $decemberText).keyboardType(.decimalPad)
                        }
                    }
                    Picker("Icon", selection: $credit.symbol) {
                        ForEach(Self.symbols, id: \.self) { s in Label(s, systemImage: s).labelStyle(.iconOnly).tag(s) }
                    }
                } footer: {
                    Text(credit.cadence == .cardYear ? "Card-year credits reset in the card's anniversary month (set it on the card)." : "Set the amount to 0 for things to tick off, like activating 5% categories.")
                }
                Section {
                    Toggle("Needs enrolling", isOn: $credit.needsEnrollment)
                    if credit.needsEnrollment { Toggle("Enrolled", isOn: $credit.enrolled) }
                    Toggle("Remind me before it resets", isOn: $credit.reminders)
                    Toggle("I don't use this one", isOn: $credit.hidden)
                    Toggle("Benefit ends on a date", isOn: $hasEnd)
                    if hasEnd { DatePicker("Ends", selection: $endDate, displayedComponents: .date) }
                }
                Section("Notes") {
                    TextField("Where it works, how to trigger it…", text: $credit.note, axis: .vertical).lineLimit(2...6)
                }
                if !isNew {
                    Section {
                        Button("Delete credit", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New credit" : "Edit credit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commit() }.disabled(credit.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(credit.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.deleteCredit(credit.id); dismiss() }
            }
            .onAppear {
                amountText = credit.amount.clean2
                decemberText = credit.monthAmounts[12].map { $0.clean2 } ?? ""
                hasEnd = credit.endsOn != nil
                endDate = credit.endsOn ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
            }
        }
    }

    static let symbols = [
        "dollarsign.circle", "creditcard.fill", "airplane", "bed.double.fill", "fork.knife", "car.fill", "cart.fill", "tv.fill",
        "music.note", "bag.fill", "tshirt.fill", "cup.and.saucer.fill", "ticket.fill", "figure.run", "heart.circle.fill",
        "bolt.circle.fill", "gift.fill", "person.text.rectangle", "takeoutbag.and.cup.and.straw.fill", "building.2.fill",
    ]

    private func commit() {
        credit.amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        if credit.cadence == .monthly, let dec = Double(decemberText.replacingOccurrences(of: ",", with: ".")), dec != credit.amount {
            credit.monthAmounts[12] = dec
        } else {
            credit.monthAmounts[12] = nil
        }
        credit.endsOn = hasEnd ? endDate : nil
        store.save(credit: credit)
        dismiss()
    }
}
