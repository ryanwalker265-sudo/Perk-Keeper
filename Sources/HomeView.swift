import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var showAddCard = false
    @State private var editingDeadline: Deadline?
    @State private var usingCredit: CreditStatus?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        if store.cards.isEmpty {
                            WelcomeCard(showAddCard: $showAddCard)
                        } else {
                            SummaryCard()
                            if !store.needsEnrollment.isEmpty { EnrollCard() }
                            resettingSoon
                            OffersGlance()
                            deadlines
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.showSync = true } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .accessibilityLabel("Sync offers")
                }
            }
            .sheet(isPresented: $showAddCard) { AddCardSheet() }
            .sheet(item: $editingDeadline) { d in DeadlineEditor(deadline: d) }
            .sheet(item: $usingCredit) { s in UseCreditSheet(status: s) }
            .navigationDestination(for: CreditRoute.self) { r in CreditDetailView(creditID: r.id) }
        }
    }

    @ViewBuilder
    private var resettingSoon: some View {
        let open = store.creditStatuses().filter { !$0.isDone && $0.resetsOn != nil }
        if !open.isEmpty {
            VStack(spacing: 0) {
                SectionTitle(title: "Use before they reset", icon: "hourglass", color: Theme.warn)
                    .padding(.bottom, 6)
                VStack(spacing: 0) {
                    ForEach(Array(open.prefix(6))) { s in
                        NavigationLink(value: CreditRoute(id: s.credit.id)) {
                            CreditRow(status: s)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { usingCredit = s } label: { Label("Used part of it…", systemImage: "pencil") }
                        }
                        if s.id != open.prefix(6).last?.id { Divider().padding(.leading, 64) }
                    }
                }
                .glassCard()
                if open.count > 6 {
                    Button("See all \(open.count)") { router.tab = .credits }
                        .font(.footnote.weight(.semibold))
                        .padding(.top, 8)
                }
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(Theme.good)
                VStack(alignment: .leading) {
                    Text("Everything's used").font(.subheadline.weight(.semibold))
                    Text("No credits are waiting this period.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .glassCard()
        }
    }

    @ViewBuilder
    private var deadlines: some View {
        VStack(spacing: 0) {
            HStack {
                SectionTitle(title: "Deadlines", icon: "calendar.badge.clock")
                Button { editingDeadline = Deadline(title: "", due: Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now) } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .padding(.top, 8)
                .accessibilityLabel("Add deadline")
            }
            .padding(.bottom, 6)
            if store.openDeadlines.isEmpty {
                Text("Track sign-up bonuses, bank bonuses or anything with a due date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(store.openDeadlines) { d in
                        DeadlineRow(deadline: d)
                            .padding(12)
                            .contentShape(Rectangle())
                            .onTapGesture { editingDeadline = d }
                        if d.id != store.openDeadlines.last?.id { Divider().padding(.leading, 14) }
                    }
                }
                .glassCard()
            }
        }
    }
}

private struct WelcomeCard: View {
    @Binding var showAddCard: Bool
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text("Never waste a card perk").font(.title2.weight(.bold))
            Text("Add your cards to track every statement credit and when it resets. Then sync your bank's offers page: Perk Keeper finds new offers, adds them for you and tells you which ones you've used.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showAddCard = true
            } label: {
                Label("Add your first card", systemImage: "plus")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .glassButton(prominent: true)
            Button("Try it with sample data") { store.replaceAll(with: DemoData.make()) }
                .font(.footnote)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .glassCard()
        .padding(.top, 8)
    }
}

private struct SummaryCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let unused = store.unusedNow
        let used = store.usedThisYear
        let value = store.yearValue
        VStack(alignment: .leading, spacing: 12) {
            Text("Left to use right now").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(unused.shortMoney)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Spacer()
                if let next = store.creditStatuses().first(where: { !$0.isDone && $0.lastDay != nil }), let last = next.lastDay {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Next reset").font(.caption2).foregroundStyle(.secondary)
                        Text(last.relativeDay).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.urgency(next.daysLeft))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ProgressBar(value: value > 0 ? used / value : 0, color: Theme.gold, height: 7)
                Text("Used \(used.shortMoney) of \(value.shortMoney) in credits this year")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: 0) {
                Stat(value: store.annualFees.shortMoney, label: "annual fees")
                Divider().frame(height: 28)
                Stat(value: "\(store.addedOffers.count)", label: "offers added")
                Divider().frame(height: 28)
                Stat(value: store.addedValue > 0 ? store.addedValue.shortMoney : "—", label: "offer value", color: Theme.good)
            }
        }
        .padding(16)
        .glassCard(tint: Theme.gold)
        .padding(.top, 6)
    }
}

private struct EnrollCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let list = store.needsEnrollment
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill").font(.title3).foregroundStyle(Theme.warn)
            VStack(alignment: .leading, spacing: 4) {
                Text(list.count == 1 ? "1 credit needs enrolling" : "\(list.count) credits need enrolling")
                    .font(.subheadline.weight(.semibold))
                Text(list.prefix(4).map(\.name).joined(separator: ", ") + (list.count > 4 ? "…" : ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text("Enroll in your bank's app, then mark it enrolled on the credit.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard(tint: Theme.warn)
    }
}

private struct OffersGlance: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        let newCount = store.newOffers.count
        let expiring = store.addedOffers.filter { ($0.daysLeft ?? 99) <= 7 }
        let missing = store.missingOffers
        VStack(spacing: 0) {
            SectionTitle(title: "Card offers", icon: "tag.fill", color: Theme.accent)
                .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        router.offerFilter = .new
                        router.tab = .offers
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(newCount)").font(.title2.weight(.bold).monospacedDigit())
                            Text(newCount == 1 ? "new offer" : "new offers").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button {
                        router.offerFilter = .added
                        router.tab = .offers
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(store.addedOffers.count)").font(.title2.weight(.bold).monospacedDigit())
                            Text("added, not used").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button { router.showSync = true } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath").font(.subheadline.weight(.semibold))
                    }
                    .glassButton(prominent: true)
                }
                if let last = store.lastAnySync {
                    Text("Last synced \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else if store.syncableCards.isEmpty {
                    Text("Add an Amex, Chase, Citi, BofA, Wells Fargo or U.S. Bank card to sync its offers. You can add offers from any other card by hand.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Sync once to pull in your offers. Perk Keeper can add them all for you.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if !missing.isEmpty {
                    Divider()
                    MissingOffersPrompt(offers: missing)
                }
                if !expiring.isEmpty {
                    Divider()
                    Text("Added offers expiring this week").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(expiring.prefix(4)) { o in OfferLine(offer: o) }
                }
            }
            .padding(14)
            .glassCard()
        }
    }
}

/// Compact one-line offer used on Today.
struct OfferLine: View {
    let offer: Offer
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(offer.issuer.color).frame(width: 8, height: 8)
            Text(offer.merchant).font(.subheadline.weight(.medium)).lineLimit(1)
            if let v = offer.valueText { Text(v).font(.caption).foregroundStyle(Theme.good) }
            Spacer()
            if let d = offer.daysLeft {
                Text(DayMath.shortDays(d) + (d >= 0 ? " left" : "")).font(.caption.monospacedDigit()).foregroundStyle(Theme.urgency(d))
            }
        }
    }
}

/// "These offers disappeared from your added list. Did you use them?"
struct MissingOffersPrompt: View {
    let offers: [Offer]
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Gone from your added list. Did you use these?", systemImage: "questionmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.warn)
            ForEach(offers.prefix(5)) { o in
                HStack {
                    Text(o.merchant).font(.subheadline).lineLimit(1)
                    Spacer()
                    Button("Used") { store.setStatus(.used, offerID: o.id); Haptics.success() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(Theme.good)
                    Button("No") { store.setStatus(.expired, offerID: o.id) }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct DeadlineRow: View {
    let deadline: Deadline
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                var d = deadline
                d.done = true
                store.save(deadline: d)
                Haptics.success()
            } label: {
                Image(systemName: "circle").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark done")
            VStack(alignment: .leading, spacing: 4) {
                Text(deadline.title).font(.subheadline.weight(.semibold))
                if let t = deadline.target, t > 0 {
                    let p = deadline.progress ?? 0
                    ProgressBar(value: p / t, color: Theme.gold, height: 5)
                    Text("\(p.shortMoney) of \(t.shortMoney)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                if !deadline.detail.isEmpty {
                    Text(deadline.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(deadline.due.monthDay).font(.caption.weight(.semibold))
                Text(DayMath.shortDays(deadline.daysLeft) + (deadline.daysLeft >= 0 ? " left" : ""))
                    .font(.caption2).foregroundStyle(Theme.urgency(deadline.daysLeft))
            }
        }
    }
}

struct DeadlineEditor: View {
    @State var deadline: Deadline
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var targetText = ""
    @State private var progressText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is it? (e.g. Sapphire bonus)", text: $deadline.title)
                    TextField("Notes (e.g. spend $5,000)", text: $deadline.detail, axis: .vertical)
                    DatePicker("Due", selection: $deadline.due, displayedComponents: .date)
                    Picker("Card", selection: $deadline.cardID) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.cards) { c in Text(c.displayName).tag(Optional(c.id)) }
                    }
                }
                Section {
                    HStack { Text("Goal $"); TextField("Optional", text: $targetText).keyboardType(.decimalPad) }
                    HStack { Text("So far $"); TextField("Optional", text: $progressText).keyboardType(.decimalPad) }
                } header: {
                    Text("Spending goal")
                } footer: {
                    Text("You'll get reminders a week and a day before it's due.")
                }
                if store.data.deadlines.contains(where: { $0.id == deadline.id }) {
                    Section {
                        Button("Mark done") { deadline.done = true; commit() }
                        Button("Delete", role: .destructive) { store.deleteDeadline(deadline.id); dismiss() }
                    }
                }
            }
            .navigationTitle(deadline.title.isEmpty ? "New deadline" : "Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commit() }.disabled(deadline.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                targetText = deadline.target.map { $0.clean } ?? ""
                progressText = deadline.progress.map { $0.clean } ?? ""
            }
        }
    }

    private func commit() {
        deadline.target = Double(targetText.replacingOccurrences(of: ",", with: ""))
        deadline.progress = Double(progressText.replacingOccurrences(of: ",", with: ""))
        store.save(deadline: deadline)
        dismiss()
    }
}
