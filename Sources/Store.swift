import Foundation
import Observation
import SwiftUI
import WidgetKit

/// What the offer engine returns from a scan.
struct ScanTile: Decodable, Hashable {
    var key: String
    var merchant: String
    var reward: String
    var details: String?
    var expires: String?
    var status: String
    var value: Double?
    var minSpend: Double?
    var percent: Double?
    var points: Double?
}

struct ScanResult: Decodable {
    var ok: Bool?
    var url: String?
    var complete: Bool?
    var login: Bool?
    var hints: [String]?
    var tiles: [ScanTile]
}

struct ScanSummary {
    var found = 0
    var new = 0
    var toAdd = 0
    var added = 0
    var used = 0
}

/// All of the app's data, saved as one JSON file on the iPhone.
@MainActor
@Observable
final class AppStore {
    static let shared = AppStore()

    private(set) var data: AppData
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored var isDemo = false

    init() {
        data = Persistence.load() ?? AppData()
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: Saving

    func update(_ body: (inout AppData) -> Void) {
        body(&data)
        scheduleSave()
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        if !isDemo { Persistence.save(data) }
        widgetSnapshot().save()
        WidgetCenter.shared.reloadAllTimelines()
        Task { await Notifier.shared.reschedule(store: self) }
    }

    func replaceAll(with newData: AppData) {
        data = newData
        scheduleSave()
    }

    func loadDemo() {
        isDemo = true
        data = DemoData.make()
        widgetSnapshot().save()
    }

    // MARK: Cards

    var cards: [Card] { data.cards.sorted { $0.createdAt < $1.createdAt } }

    func card(_ id: UUID?) -> Card? {
        guard let id else { return nil }
        return data.cards.first { $0.id == id }
    }

    @discardableResult
    func addCard(template: CardTemplate?, name: String, issuer: Issuer, last4: String, anniversaryMonth: Int?,
                 annualFee: Double?, colors: (String, String), keepCredits: Set<Int>? = nil) -> Card {
        let card = Card(name: name, issuer: issuer, last4: last4, colorHex: colors.0, colorHex2: colors.1,
                        annualFee: annualFee, anniversaryMonth: anniversaryMonth, templateID: template?.id)
        update { d in
            d.cards.append(card)
            for (i, t) in (template?.credits ?? []).enumerated() {
                var c = t.makeCredit(cardID: card.id)
                if let keep = keepCredits, !keep.contains(i) { c.hidden = true }
                d.credits.append(c)
            }
        }
        return card
    }

    func save(card: Card) {
        update { d in
            if let i = d.cards.firstIndex(where: { $0.id == card.id }) { d.cards[i] = card } else { d.cards.append(card) }
        }
    }

    func deleteCard(_ id: UUID) {
        update { d in
            d.cards.removeAll { $0.id == id }
            d.credits.removeAll { $0.cardID == id }
            d.offers.removeAll { $0.cardID == id }
            for i in d.deadlines.indices where d.deadlines[i].cardID == id { d.deadlines[i].cardID = nil }
        }
    }

    // MARK: Credits

    func credits(for cardID: UUID, includeHidden: Bool = true) -> [Credit] {
        data.credits.filter { $0.cardID == cardID && (includeHidden || !$0.hidden) }
    }

    func credit(_ id: UUID) -> Credit? { data.credits.first { $0.id == id } }

    func status(of credit: Credit, at date: Date = .now) -> CreditStatus {
        let card = self.card(credit.cardID)
        let p = credit.period(containing: date, card: card)
        return CreditStatus(credit: credit, card: card, period: p, periodAmount: credit.periodAmount(for: p), used: credit.used(in: p))
    }

    /// Current standing of every active credit, soonest reset first.
    func creditStatuses(at date: Date = .now, includeHidden: Bool = false) -> [CreditStatus] {
        data.credits
            .filter { (includeHidden || !$0.hidden) && $0.isActive(on: date) && card($0.cardID) != nil }
            .map { status(of: $0, at: date) }
            .sorted { ($0.resetsOn ?? .distantFuture, $0.credit.name) < ($1.resetsOn ?? .distantFuture, $1.credit.name) }
    }

    func save(credit: Credit) {
        update { d in
            if let i = d.credits.firstIndex(where: { $0.id == credit.id }) { d.credits[i] = credit } else { d.credits.append(credit) }
        }
    }

    func deleteCredit(_ id: UUID) { update { $0.credits.removeAll { $0.id == id } } }

    func logUse(_ creditID: UUID, amount: Double, date: Date = .now, note: String = "") {
        update { d in
            guard let i = d.credits.firstIndex(where: { $0.id == creditID }) else { return }
            d.credits[i].uses.append(CreditUse(date: date, amount: amount, note: note))
            if d.credits[i].needsEnrollment { d.credits[i].enrolled = true }
        }
    }

    /// Marks the rest of this period as used (or ticks a checklist item).
    func useRemaining(_ s: CreditStatus) {
        logUse(s.credit.id, amount: s.credit.isChecklist ? 0 : s.remaining)
    }

    func removeUse(creditID: UUID, useID: UUID) {
        update { d in
            guard let i = d.credits.firstIndex(where: { $0.id == creditID }) else { return }
            d.credits[i].uses.removeAll { $0.id == useID }
        }
    }

    func undoLastUse(_ s: CreditStatus) {
        guard let last = s.credit.uses.filter({ s.period.contains($0.date) }).max(by: { $0.date < $1.date }) else { return }
        removeUse(creditID: s.credit.id, useID: last.id)
    }

    // MARK: Credit totals

    var visibleStatuses: [CreditStatus] { creditStatuses() }

    var unusedNow: Double { visibleStatuses.filter { $0.resetsOn != nil }.reduce(0) { $0 + $1.remaining } }

    var usedThisYear: Double {
        let y = Calendar.current.component(.year, from: .now)
        return data.credits.filter { !$0.hidden && card($0.cardID) != nil }.reduce(0) { sum, c in
            sum + c.uses.filter { Calendar.current.component(.year, from: $0.date) == y }.reduce(0) { $0 + $1.amount }
        }
    }

    var yearValue: Double {
        data.credits.filter { !$0.hidden && $0.isActive() && card($0.cardID) != nil }.reduce(0) { $0 + $1.yearValue }
    }

    var annualFees: Double { data.cards.reduce(0) { $0 + ($1.annualFee ?? 0) } }

    var needsEnrollment: [Credit] {
        data.credits.filter { $0.needsEnrollment && !$0.enrolled && !$0.hidden && $0.isActive() && card($0.cardID) != nil }
    }

    // MARK: Offers

    func offers(for cardID: UUID) -> [Offer] { data.offers.filter { $0.cardID == cardID } }

    var visibleOffers: [Offer] { data.offers.filter { !$0.hidden } }

    func isNew(_ o: Offer) -> Bool { o.status == .available && o.firstSeen > data.offersViewedAt && !o.hidden }

    var newOffers: [Offer] { visibleOffers.filter { isNew($0) } }

    var addedOffers: [Offer] {
        visibleOffers.filter { $0.status == .added && !$0.isExpired }
            .sorted { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }
    }

    var missingOffers: [Offer] { addedOffers.filter { $0.missingSince != nil } }

    var addedValue: Double { addedOffers.reduce(0) { $0 + ($1.value ?? 0) } }

    func markOffersViewed() {
        guard !newOffers.isEmpty else { return }
        update { $0.offersViewedAt = Date() }
    }

    func setStatus(_ status: OfferStatus, offerID: String) {
        update { d in
            guard let i = d.offers.firstIndex(where: { $0.id == offerID }) else { return }
            d.offers[i].status = status
            d.offers[i].missingSince = nil
            switch status {
            case .used: d.offers[i].usedAt = Date()
            case .added: d.offers[i].addedAt = d.offers[i].addedAt ?? Date(); d.offers[i].usedAt = nil
            case .available: d.offers[i].usedAt = nil
            case .expired: break
            }
        }
    }

    func setHidden(_ hidden: Bool, offerID: String) {
        update { d in
            if let i = d.offers.firstIndex(where: { $0.id == offerID }) { d.offers[i].hidden = hidden }
        }
    }

    func save(offer: Offer) {
        update { d in
            if let i = d.offers.firstIndex(where: { $0.id == offer.id }) { d.offers[i] = offer } else { d.offers.append(offer) }
        }
    }

    func deleteOffer(_ id: String) { update { $0.offers.removeAll { $0.id == id } } }

    /// Folds a scan of a bank's offers page into the saved offers.
    @discardableResult
    func applyScan(_ r: ScanResult, issuer: Issuer, cardID: UUID?, now: Date = .now) -> ScanSummary {
        var summary = ScanSummary()
        let prefix = (cardID?.uuidString ?? issuer.rawValue) + "|"
        var seen = Set<String>()
        var kinds = Set<String>()
        update { d in
            for t in r.tiles {
                let id = prefix + t.key
                guard !seen.contains(id) else { continue }
                seen.insert(id)
                kinds.insert(t.status)
                let scanned: OfferStatus = t.status == "added" ? .added : t.status == "used" ? .used : .available
                let exp = t.expires.flatMap { Self.dayFormatter.date(from: $0) }
                summary.found += 1
                switch scanned {
                case .available: summary.toAdd += 1
                case .added: summary.added += 1
                case .used: summary.used += 1
                case .expired: break
                }
                if let i = d.offers.firstIndex(where: { $0.id == id }) {
                    var o = d.offers[i]
                    o.merchant = t.merchant
                    if !t.reward.isEmpty { o.reward = t.reward }
                    if let det = t.details, !det.isEmpty { o.details = det }
                    if let exp { o.expires = exp }
                    o.value = t.value ?? o.value
                    o.minSpend = t.minSpend ?? o.minSpend
                    o.percent = t.percent ?? o.percent
                    o.points = t.points ?? o.points
                    o.lastSeen = now
                    o.missingSince = nil
                    switch scanned {
                    case .used:
                        if o.status != .used { o.status = .used; o.usedAt = o.usedAt ?? now }
                    case .added:
                        if o.status != .used {
                            if o.status != .added { o.addedAt = o.addedAt ?? now }
                            o.status = .added
                        }
                    case .available:
                        if o.status == .expired || o.status == .added { o.status = .available; o.addedAt = nil }
                    case .expired:
                        break
                    }
                    d.offers[i] = o
                } else {
                    var o = Offer(id: id, key: t.key, cardID: cardID, issuer: issuer, merchant: t.merchant, reward: t.reward,
                                  details: t.details ?? "", expires: exp, status: scanned, firstSeen: now, lastSeen: now)
                    o.value = t.value
                    o.minSpend = t.minSpend
                    o.percent = t.percent
                    o.points = t.points
                    if scanned == .added { o.addedAt = now }
                    if scanned == .used { o.usedAt = now }
                    d.offers.append(o)
                    if scanned == .available { summary.new += 1 }
                }
            }
            // Offers that were on this list before but aren't anymore.
            guard !r.tiles.isEmpty else { return }
            for i in d.offers.indices where d.offers[i].id.hasPrefix(prefix) && !seen.contains(d.offers[i].id) && !d.offers[i].manual {
                let o = d.offers[i]
                if o.status == .added && kinds.contains("added") {
                    if o.isExpired { d.offers[i].status = .expired } else if o.missingSince == nil { d.offers[i].missingSince = now }
                } else if o.status == .available && kinds.contains("available") && r.complete == true {
                    d.offers[i].status = .expired
                }
            }
        }
        return summary
    }

    func markAdded(keys: [String], issuer: Issuer, cardID: UUID?) {
        guard !keys.isEmpty else { return }
        let prefix = (cardID?.uuidString ?? issuer.rawValue) + "|"
        let ids = Set(keys.map { prefix + $0 })
        update { d in
            for i in d.offers.indices where ids.contains(d.offers[i].id) && d.offers[i].status != .used {
                d.offers[i].status = .added
                d.offers[i].addedAt = d.offers[i].addedAt ?? Date()
                d.offers[i].addedByApp = true
                d.offers[i].missingSince = nil
            }
        }
    }

    func recordSync(issuer: Issuer, cardID: UUID?, found: Int, new: Int, added: Int) {
        update { d in
            d.syncs.append(SyncRecord(issuer: issuer, cardID: cardID, found: found, new: new, added: added))
            if d.syncs.count > 200 { d.syncs.removeFirst(d.syncs.count - 200) }
        }
    }

    func lastSync(issuer: Issuer, cardID: UUID?) -> SyncRecord? {
        data.syncs.filter { $0.issuer == issuer && ($0.cardID == cardID || cardID == nil) }.max { $0.date < $1.date }
    }

    var lastAnySync: Date? { data.syncs.map(\.date).max() }

    var syncableCards: [Card] { cards.filter { $0.issuer.supportsSync } }

    /// Daily tidy-up: expire old offers and drop long-gone ones.
    func housekeeping(now: Date = .now) {
        var changed = false
        var d = data
        for i in d.offers.indices where (d.offers[i].status == .available || d.offers[i].status == .added) && d.offers[i].isExpired {
            d.offers[i].status = .expired
            changed = true
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -45, to: now) ?? now
        let before = d.offers.count
        d.offers.removeAll { $0.status == .expired && !$0.manual && $0.lastSeen < cutoff && ($0.expires ?? $0.lastSeen) < cutoff }
        if d.offers.count != before { changed = true }
        if changed { update { $0 = d } }
    }

    // MARK: Deadlines

    var openDeadlines: [Deadline] { data.deadlines.filter { !$0.done }.sorted { $0.due < $1.due } }

    func save(deadline: Deadline) {
        update { d in
            if let i = d.deadlines.firstIndex(where: { $0.id == deadline.id }) { d.deadlines[i] = deadline } else { d.deadlines.append(deadline) }
        }
    }

    func deleteDeadline(_ id: UUID) { update { $0.deadlines.removeAll { $0.id == id } } }

    // MARK: Widget

    func widgetSnapshot(now: Date = .now) -> WidgetSnapshot {
        let open = creditStatuses(at: now).filter { !$0.isDone && $0.resetsOn != nil }
        let creditItems = open.prefix(8).map { s in
            WidgetSnapshot.Item(
                id: s.id.uuidString, title: s.credit.name,
                detail: s.credit.isChecklist ? "To do" : "\(s.remaining.shortMoney) left",
                amount: s.credit.isChecklist ? nil : s.remaining, ends: s.lastDay, kind: "credit",
                colorHex: s.card?.colorHex ?? "#8E8E93", symbol: s.credit.symbol
            )
        }
        let offerItems = addedOffers.filter { ($0.daysLeft ?? 99) <= 14 }.prefix(6).map { o in
            WidgetSnapshot.Item(
                id: o.id, title: o.merchant, detail: o.valueText ?? "Added offer", amount: o.value, ends: o.expires,
                kind: "offer", colorHex: o.issuer.colorHex, symbol: "tag.fill"
            )
        }
        let items = (Array(creditItems) + Array(offerItems)).sorted { ($0.ends ?? .distantFuture) < ($1.ends ?? .distantFuture) }
        let cal = Calendar.current
        let thisMonth = open.filter { s in s.lastDay.map { cal.isDate($0, equalTo: now, toGranularity: .month) } ?? false }
        return WidgetSnapshot(
            generatedAt: now,
            unusedNow: open.reduce(0) { $0 + $1.remaining },
            unusedThisMonth: thisMonth.reduce(0) { $0 + $1.remaining },
            newOffers: newOffers.count,
            addedOffers: addedOffers.count,
            items: Array(items.prefix(8))
        )
    }
}

/// Reads and writes the data file. A copy also goes to Documents (shown in Files → On My iPhone →
/// Perk Keeper and included in iCloud Backup), which is used if the main file is ever missing.
enum Persistence {
    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerkKeeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    static var backupURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Perk Keeper Backup.json")
    }

    static var lastBackup: Date? {
        (try? FileManager.default.attributesOfItem(atPath: backupURL.path))?[.modificationDate] as? Date
    }

    static func encode(_ data: AppData) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(data)
    }

    static func decode(_ raw: Data) throws -> AppData {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(AppData.self, from: raw)
    }

    static func load() -> AppData? {
        for url in [fileURL, backupURL] {
            if let raw = try? Data(contentsOf: url), let data = try? decode(raw) { return data }
        }
        return nil
    }

    static func save(_ data: AppData) {
        guard let raw = try? encode(data) else { return }
        try? raw.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Never replace a backup that has cards with an empty one (e.g. right after a reinstall).
        if data.cards.isEmpty, let old = try? Data(contentsOf: backupURL), let prev = try? decode(old), !prev.cards.isEmpty { return }
        try? raw.write(to: backupURL, options: .atomic)
    }
}
