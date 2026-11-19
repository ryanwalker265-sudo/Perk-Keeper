import SwiftUI

enum OfferFilter: String, CaseIterable, Identifiable {
    case new, toAdd, added, used, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .new: "New"
        case .toAdd: "To add"
        case .added: "Added"
        case .used: "Used"
        case .all: "All"
        }
    }
}

struct OffersView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var search = ""
    @State private var cardFilter: UUID?
    @AppStorage("offers.sort") private var sort = "expiring"
    @State private var showManual = false

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(spacing: 12) {
                        Picker("Show", selection: $router.offerFilter) {
                            ForEach(OfferFilter.allCases) { f in Text(label(for: f)).tag(f) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 4)

                        if router.offerFilter == .added && !store.missingOffers.isEmpty {
                            MissingOffersPrompt(offers: store.missingOffers).padding(14).glassCard(tint: Theme.warn)
                        }
                        if shown.isEmpty {
                            emptyState.padding(.top, 40)
                        } else {
                            summaryLine
                            VStack(spacing: 0) {
                                ForEach(shown) { o in
                                    NavigationLink(value: OfferRoute(id: o.id)) { OfferRow(offer: o, isNew: store.isNew(o)) }
                                        .buttonStyle(.plain)
                                        .contextMenu { OfferActions(offer: o) }
                                    if o.id != shown.last?.id { Divider().padding(.leading, 16) }
                                }
                            }
                            .glassCard()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .searchable(text: $search, prompt: "Merchant or reward")
            }
            .navigationTitle("Offers")
            .navigationDestination(for: OfferRoute.self) { r in OfferDetailView(offerID: r.id) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            Label("Expiring soonest", systemImage: "hourglass").tag("expiring")
                            Label("Biggest value", systemImage: "dollarsign").tag("value")
                            Label("Merchant", systemImage: "textformat").tag("merchant")
                            Label("Newest", systemImage: "sparkles").tag("newest")
                        }
                        Picker("Card", selection: $cardFilter) {
                            Text("All cards").tag(UUID?.none)
                            ForEach(store.cards) { c in Text(c.displayName).tag(Optional(c.id)) }
                        }
                    } label: {
                        Image(systemName: cardFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showManual = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add an offer by hand")
                    Button { router.showSync = true } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .accessibilityLabel("Sync offers")
                }
            }
            .sheet(isPresented: $showManual) { ManualOfferSheet() }
            .onDisappear { store.markOffersViewed() }
        }
    }

    private func label(for f: OfferFilter) -> String {
        let n = count(f)
        return n > 0 && f != .all ? "\(f.label) \(n)" : f.label
    }

    private func count(_ f: OfferFilter) -> Int { base.filter { matches($0, f) }.count }

    private var base: [Offer] {
        store.visibleOffers.filter { cardFilter == nil || $0.cardID == cardFilter }
    }

    private func matches(_ o: Offer, _ f: OfferFilter) -> Bool {
        switch f {
        case .new: return store.isNew(o) && !o.isExpired
        case .toAdd: return o.status == .available && !o.isExpired
        case .added: return o.status == .added && !o.isExpired
        case .used: return o.status == .used
        case .all: return true
        }
    }

    private var shown: [Offer] {
        var list = base.filter { matches($0, router.offerFilter) }
        if !search.isEmpty {
            list = list.filter { $0.merchant.localizedCaseInsensitiveContains(search) || $0.reward.localizedCaseInsensitiveContains(search) }
        }
        switch sort {
        case "value": list.sort { ($0.value ?? 0) > ($1.value ?? 0) }
        case "merchant": list.sort { $0.merchant.localizedCaseInsensitiveCompare($1.merchant) == .orderedAscending }
        case "newest": list.sort { $0.firstSeen > $1.firstSeen }
        default:
            if router.offerFilter == .used { list.sort { ($0.usedAt ?? .distantPast) > ($1.usedAt ?? .distantPast) } }
            else { list.sort { ($0.expires ?? .distantFuture, $0.merchant) < ($1.expires ?? .distantFuture, $1.merchant) } }
        }
        return list
    }

    @ViewBuilder
    private var summaryLine: some View {
        let value = shown.reduce(0) { $0 + ($1.value ?? 0) }
        HStack {
            Text("\(shown.count) offer\(shown.count == 1 ? "" : "s")")
            if value > 0 { Text("· up to \(value.shortMoney) back").foregroundStyle(Theme.good) }
            Spacer()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch router.offerFilter {
        case .new:
            ContentUnavailableView {
                Label("No new offers", systemImage: "sparkles")
            } description: {
                Text(store.syncableCards.isEmpty
                     ? "Add an Amex, Chase, Citi, Bank of America, Wells Fargo or U.S. Bank card, then sync to pull in its offers."
                     : "Sync to check your banks for new offers. Perk Keeper can add them for you while it looks.")
            } actions: {
                if !store.syncableCards.isEmpty {
                    Button("Sync offers") { router.showSync = true }.glassButton(prominent: true)
                }
            }
        case .added:
            ContentUnavailableView("Nothing added and unused", systemImage: "checkmark.seal",
                                   description: Text("Offers you've added to a card show here until you use them or they expire."))
        case .used:
            ContentUnavailableView("No used offers yet", systemImage: "tag",
                                   description: Text("Offers move here when your bank shows them as redeemed, or when you mark them used."))
        default:
            ContentUnavailableView("No offers", systemImage: "tag",
                                   description: Text("Sync a bank or add an offer by hand with +."))
        }
    }
}

struct OfferRow: View {
    let offer: Offer
    var isNew = false
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(offer.issuer.color.opacity(0.14))
                Text(String(offer.merchant.prefix(1)).uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(offer.issuer.color)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(offer.merchant).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if isNew { Pill(text: "NEW", color: Theme.accent) }
                    Spacer(minLength: 0)
                    if let v = offer.valueText { Text(v).font(.caption.weight(.semibold)).foregroundStyle(Theme.good) }
                }
                Text(offer.reward).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    statusPill
                    if let card = store.card(offer.cardID) {
                        Text(card.displayName).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    } else {
                        IssuerBadge(issuer: offer.issuer)
                    }
                    Spacer(minLength: 0)
                    if let d = offer.daysLeft, offer.status != .used {
                        Text(d < 0 ? "Expired" : "\(DayMath.shortDays(d)) left")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(Theme.urgency(d))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusPill: some View {
        switch offer.status {
        case .available: Pill(text: "Not added", color: .secondary, icon: "plus.circle")
        case .added: Pill(text: offer.missingSince != nil ? "Used?" : "Added", color: offer.missingSince != nil ? Theme.warn : Theme.accent, icon: "checkmark.circle")
        case .used: Pill(text: "Used", color: Theme.good, icon: "checkmark.seal.fill")
        case .expired: Pill(text: "Expired", color: .secondary, icon: "clock")
        }
    }
}

struct OfferActions: View {
    let offer: Offer
    @Environment(AppStore.self) private var store

    var body: some View {
        if offer.status != .used {
            Button { store.setStatus(.used, offerID: offer.id) } label: { Label("Mark used", systemImage: "checkmark.seal") }
        }
        if offer.status == .available {
            Button { store.setStatus(.added, offerID: offer.id) } label: { Label("I added it myself", systemImage: "plus.circle") }
        }
        if offer.status == .used {
            Button { store.setStatus(.added, offerID: offer.id) } label: { Label("Not used yet", systemImage: "arrow.uturn.backward") }
        }
        Button { store.setHidden(true, offerID: offer.id) } label: { Label("Hide", systemImage: "eye.slash") }
    }
}

struct OfferDetailView: View {
    let offerID: String
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let o = store.data.offers.first(where: { $0.id == offerID }) {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                IssuerBadge(issuer: o.issuer)
                                Text(o.issuer.offersName).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if let card = store.card(o.cardID) { CardArt(card: card, width: 44) }
                            }
                            Text(o.merchant).font(.title.weight(.bold))
                            Text(o.reward).font(.body)
                            if !o.details.isEmpty { Text(o.details).font(.footnote).foregroundStyle(.secondary) }
                            HStack(spacing: 8) {
                                if let v = o.value { Pill(text: "Up to \(v.shortMoney)", color: Theme.good, icon: "dollarsign") }
                                if let m = o.minSpend { Pill(text: "Spend \(m.shortMoney)+", color: .secondary) }
                                if let p = o.points { Pill(text: "\(Int(p).formatted()) pts", color: Theme.gold) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .glassCard()

                        VStack(spacing: 0) {
                            row("Status", value: o.status.label)
                            Divider()
                            row("Expires", value: o.expires.map { "\($0.formatted(date: .abbreviated, time: .omitted)) (\($0.relativeDay))" } ?? "Not shown")
                            Divider()
                            row("First seen", value: o.firstSeen.formatted(date: .abbreviated, time: .omitted))
                            if let a = o.addedAt {
                                Divider()
                                row("Added", value: a.formatted(date: .abbreviated, time: .omitted) + (o.addedByApp ? " by Perk Keeper" : ""))
                            }
                            if let u = o.usedAt {
                                Divider()
                                row("Used", value: u.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                        .glassCard()

                        actions(o)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(o.merchant)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Offer removed", systemImage: "trash")
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func actions(_ o: Offer) -> some View {
        VStack(spacing: 10) {
            switch o.status {
            case .available:
                Button { router.showSync = true } label: {
                    Label("Add it with a sync", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                }
                .glassButton(prominent: true)
                Button { store.setStatus(.added, offerID: o.id) } label: {
                    Label("I added it myself", systemImage: "plus.circle").frame(maxWidth: .infinity)
                }
                .glassButton()
            case .added:
                Button { store.setStatus(.used, offerID: o.id); Haptics.success() } label: {
                    Label("I used it", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                }
                .glassButton(prominent: true)
            case .used:
                Button { store.setStatus(.added, offerID: o.id) } label: {
                    Label("Not used yet", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .glassButton()
            case .expired:
                EmptyView()
            }
            Button(role: .destructive) {
                if o.manual { store.deleteOffer(o.id) } else { store.setHidden(true, offerID: o.id) }
                dismiss()
            } label: {
                Text(o.manual ? "Delete offer" : "Hide offer").frame(maxWidth: .infinity)
            }
            .glassButton()
        }
    }
}

/// For cards whose bank Perk Keeper can't read (or offers seen in an app): add by hand.
struct ManualOfferSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var merchant = ""
    @State private var reward = ""
    @State private var cardID: UUID?
    @State private var hasExpiry = true
    @State private var expires = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var added = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Merchant", text: $merchant)
                    TextField("Reward (e.g. Spend $50, get $10 back)", text: $reward, axis: .vertical)
                    Picker("Card", selection: $cardID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(store.cards) { c in Text(c.displayName).tag(Optional(c.id)) }
                    }
                    Toggle("Already added to the card", isOn: $added)
                    Toggle("Has an expiration date", isOn: $hasExpiry)
                    if hasExpiry { DatePicker("Expires", selection: $expires, displayedComponents: .date) }
                } footer: {
                    Text("You'll be reminded before added offers expire.")
                }
            }
            .navigationTitle("Add an offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(merchant.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let card = store.card(cardID)
        let key = "manual-" + UUID().uuidString
        var o = Offer(id: (cardID?.uuidString ?? "manual") + "|" + key, key: key, cardID: cardID, issuer: card?.issuer ?? .other,
                      merchant: merchant.trimmingCharacters(in: .whitespaces), reward: reward, expires: hasExpiry ? expires : nil,
                      status: added ? .added : .available)
        o.manual = true
        o.addedAt = added ? Date() : nil
        o.firstSeen = .distantPast // not "new"
        let parsed = RewardParser.parse(reward)
        o.value = parsed.value
        o.minSpend = parsed.minSpend
        o.percent = parsed.percent
        store.save(offer: o)
        dismiss()
    }
}

/// Same rules as the engine's parseReward, for offers typed in by hand.
enum RewardParser {
    static func parse(_ text: String) -> (value: Double?, minSpend: Double?, percent: Double?) {
        func num(_ pattern: String) -> Double? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
            return Double(text[r].replacingOccurrences(of: ",", with: ""))
        }
        let percent = num(#"(\d+(?:\.\d+)?)\s?%"#)
        let value = num(#"up to (?:a total of )?\$\s?([\d,]+(?:\.\d{1,2})?)"#)
            ?? num(#"(?:earn|get|receive)\s+(?:a\s+)?\$\s?([\d,]+(?:\.\d{1,2})?)"#)
            ?? num(#"\$\s?([\d,]+(?:\.\d{1,2})?)\s+(?:back|cash ?back|statement credit|credit|off)"#)
        let minSpend = num(#"spend\s+(?:at least\s+)?\$\s?([\d,]+(?:\.\d{1,2})?)"#) ?? num(#"\$\s?([\d,]+(?:\.\d{1,2})?)\s?\+"#)
        return (value, minSpend, percent)
    }
}
