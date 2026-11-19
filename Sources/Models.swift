import Foundation
import SwiftUI

// MARK: - Issuers

enum Issuer: String, Codable, CaseIterable, Identifiable {
    case amex, chase, citi, capitalOne, bankOfAmerica, wellsFargo, usBank, discover, robinhood, apple, barclays, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .amex: "American Express"
        case .chase: "Chase"
        case .citi: "Citi"
        case .capitalOne: "Capital One"
        case .bankOfAmerica: "Bank of America"
        case .wellsFargo: "Wells Fargo"
        case .usBank: "U.S. Bank"
        case .discover: "Discover"
        case .robinhood: "Robinhood"
        case .apple: "Apple"
        case .barclays: "Barclays"
        case .other: "Other"
        }
    }

    var shortName: String {
        switch self {
        case .amex: "Amex"
        case .bankOfAmerica: "BofA"
        case .wellsFargo: "Wells Fargo"
        case .capitalOne: "Capital One"
        case .usBank: "U.S. Bank"
        default: name
        }
    }

    var colorHex: String {
        switch self {
        case .amex: "#006FCF"
        case .chase: "#117ACA"
        case .citi: "#056DAE"
        case .capitalOne: "#D03027"
        case .bankOfAmerica: "#E31837"
        case .wellsFargo: "#D71E28"
        case .usBank: "#0C2074"
        case .discover: "#FF6000"
        case .robinhood: "#3AA84F"
        case .apple: "#8E8E93"
        case .barclays: "#00AEEF"
        case .other: "#6E6E73"
        }
    }

    var color: Color { Color(hex: colorHex) }

    /// What the bank calls its card-linked offers.
    var offersName: String {
        switch self {
        case .amex: "Amex Offers"
        case .chase: "Chase Offers"
        case .citi: "Citi Merchant Offers"
        case .bankOfAmerica: "BankAmeriDeals"
        case .wellsFargo: "My Wells Fargo Deals"
        case .usBank: "Cash-back deals"
        default: "Card offers"
        }
    }

    /// Banks whose offers page Perk Keeper can read and add from.
    var supportsSync: Bool {
        switch self {
        case .amex, .chase, .citi, .bankOfAmerica, .wellsFargo, .usBank: true
        default: false
        }
    }
}

// MARK: - Cards

struct Card: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var issuer: Issuer
    var last4: String = ""
    var colorHex: String = "#3A3A3C"
    var colorHex2: String = "#1C1C1E"
    var annualFee: Double? = nil
    /// Month the card was opened (1–12). Card-year credits and the annual fee follow it.
    var anniversaryMonth: Int? = nil
    var templateID: String? = nil
    var notes: String = ""
    var createdAt = Date()

    var displayName: String { last4.isEmpty ? name : "\(name) ••\(last4.suffix(4))" }
}

extension Card {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "Card")
        issuer = c.value(.issuer, .other)
        last4 = c.value(.last4, "")
        colorHex = c.value(.colorHex, "#3A3A3C")
        colorHex2 = c.value(.colorHex2, "#1C1C1E")
        annualFee = c.optional(.annualFee)
        anniversaryMonth = c.optional(.anniversaryMonth)
        templateID = c.optional(.templateID)
        notes = c.value(.notes, "")
        createdAt = c.value(.createdAt, Date())
    }
}

// MARK: - Credits (statement credits and other recurring perks)

enum Cadence: String, Codable, CaseIterable, Identifiable {
    case monthly, quarterly, semiannual, annual, cardYear, multiYear, oneTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .semiannual: "Every 6 months"
        case .annual: "Calendar year"
        case .cardYear: "Card year"
        case .multiYear: "Every few years"
        case .oneTime: "One time"
        }
    }

    var badge: String {
        switch self {
        case .monthly: "MONTHLY"
        case .quarterly: "QUARTERLY"
        case .semiannual: "HALF-YEAR"
        case .annual: "YEARLY"
        case .cardYear: "CARD YEAR"
        case .multiYear: "MULTI-YEAR"
        case .oneTime: "ONE TIME"
        }
    }

    var periodsPerYear: Double {
        switch self {
        case .monthly: 12
        case .quarterly: 4
        case .semiannual: 2
        case .annual, .cardYear, .oneTime: 1
        case .multiYear: 0.25
        }
    }
}

struct CreditUse: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var amount: Double
    var note: String = ""
}

struct Credit: Identifiable, Codable, Hashable {
    var id = UUID()
    var cardID: UUID
    var name: String
    /// Value per period. 0 turns the credit into a checklist item ("Activate 5% categories").
    var amount: Double
    var cadence: Cadence
    /// Monthly credits whose amount differs in some months (Uber Cash: $35 in December).
    var monthAmounts: [Int: Double] = [:]
    var everyYears: Int = 4
    var symbol: String = "dollarsign.circle"
    var note: String = ""
    var needsEnrollment: Bool = false
    var enrolled: Bool = false
    var endsOn: Date? = nil
    var uses: [CreditUse] = []
    /// "I don't use this one": kept, but left out of totals, reminders and the widget.
    var hidden: Bool = false
    var reminders: Bool = true
    var createdAt = Date()

    var isChecklist: Bool { amount <= 0 }
}

extension Credit {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        cardID = c.value(.cardID, UUID())
        name = c.value(.name, "Credit")
        amount = c.value(.amount, 0)
        cadence = c.value(.cadence, .annual)
        monthAmounts = c.value(.monthAmounts, [:])
        everyYears = c.value(.everyYears, 4)
        symbol = c.value(.symbol, "dollarsign.circle")
        note = c.value(.note, "")
        needsEnrollment = c.value(.needsEnrollment, false)
        enrolled = c.value(.enrolled, false)
        endsOn = c.optional(.endsOn)
        uses = c.value(.uses, [])
        hidden = c.value(.hidden, false)
        reminders = c.value(.reminders, true)
        createdAt = c.value(.createdAt, Date())
    }
}

struct Period: Hashable {
    var start: Date
    /// Exclusive: the moment the next period starts.
    var end: Date

    func contains(_ d: Date) -> Bool { d >= start && d < end }
    var isOpenEnded: Bool { end > Date.distantFuture.addingTimeInterval(-86400 * 365) }
}

extension Credit {
    /// The period that contains `date`, using the card's anniversary month for card-year credits.
    func period(containing date: Date, card: Card?, calendar cal: Calendar = .current) -> Period {
        let comps = cal.dateComponents([.year, .month], from: date)
        let y = comps.year ?? 2026, m = comps.month ?? 1
        func first(_ y: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: 1)) ?? date }
        func plus(_ d: Date, months: Int) -> Date { cal.date(byAdding: .month, value: months, to: d) ?? d }

        var p: Period
        switch cadence {
        case .monthly:
            let s = first(y, m); p = Period(start: s, end: plus(s, months: 1))
        case .quarterly:
            let s = first(y, ((m - 1) / 3) * 3 + 1); p = Period(start: s, end: plus(s, months: 3))
        case .semiannual:
            let s = first(y, m <= 6 ? 1 : 7); p = Period(start: s, end: plus(s, months: 6))
        case .annual:
            let s = first(y, 1); p = Period(start: s, end: plus(s, months: 12))
        case .cardYear:
            let am = min(max(card?.anniversaryMonth ?? 1, 1), 12)
            let s = first(m >= am ? y : y - 1, am); p = Period(start: s, end: plus(s, months: 12))
        case .multiYear:
            if let last = uses.map(\.date).max(),
               let end = cal.date(byAdding: .year, value: max(1, everyYears), to: last), end > date {
                p = Period(start: last, end: end)
            } else {
                p = Period(start: .distantPast, end: .distantFuture)
            }
        case .oneTime:
            p = Period(start: .distantPast, end: .distantFuture)
        }
        if let endsOn, let cutoff = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endsOn)), cutoff < p.end {
            p.end = cutoff
        }
        return p
    }

    func periodAmount(for period: Period, calendar cal: Calendar = .current) -> Double {
        if cadence == .monthly, let m = cal.dateComponents([.month], from: period.start).month, let o = monthAmounts[m] { return o }
        return amount
    }

    func used(in period: Period) -> Double {
        uses.filter { period.contains($0.date) }.reduce(0) { $0 + $1.amount }
    }

    func usedCount(in period: Period) -> Int { uses.filter { period.contains($0.date) }.count }

    /// Total value over a calendar year (for "worth $X a year").
    var yearValue: Double {
        switch cadence {
        case .monthly: (1...12).reduce(0) { $0 + (monthAmounts[$1] ?? amount) }
        case .multiYear: amount / Double(max(everyYears, 1))
        default: amount * cadence.periodsPerYear
        }
    }

    func isActive(on date: Date = .now) -> Bool {
        guard let endsOn else { return true }
        return Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: endsOn)
    }
}

/// A credit's standing right now: how much is left and when it resets.
struct CreditStatus: Identifiable, Hashable {
    var credit: Credit
    var card: Card?
    var period: Period
    var periodAmount: Double
    var used: Double

    var id: UUID { credit.id }
    var remaining: Double { credit.isChecklist ? 0 : max(0, periodAmount - used) }
    var isDone: Bool { credit.isChecklist ? credit.usedCount(in: period) > 0 : remaining < 0.005 }
    var progress: Double {
        if credit.isChecklist { return isDone ? 1 : 0 }
        return periodAmount > 0 ? min(1, used / periodAmount) : 0
    }
    /// When the unused part is lost (start of the next period), nil when open-ended.
    var resetsOn: Date? { period.isOpenEnded ? nil : period.end }
    var lastDay: Date? { resetsOn.flatMap { Calendar.current.date(byAdding: .day, value: -1, to: $0) } }
    var daysLeft: Int? { lastDay.map { DayMath.daysUntil($0) } }
    var needsAttention: Bool { !isDone && !credit.hidden }
}

// MARK: - Offers (card-linked merchant offers)

enum OfferStatus: String, Codable, CaseIterable, Identifiable {
    case available, added, used, expired
    var id: String { rawValue }

    var label: String {
        switch self {
        case .available: "To add"
        case .added: "Added"
        case .used: "Used"
        case .expired: "Expired"
        }
    }
}

struct Offer: Identifiable, Codable, Hashable {
    /// Card (or issuer) + the engine's key for merchant and reward, so the same offer keeps its
    /// history across syncs.
    var id: String
    var key: String
    var cardID: UUID?
    var issuer: Issuer
    var merchant: String
    var reward: String
    var details: String = ""
    /// Last day the offer can be used.
    var expires: Date?
    var status: OfferStatus
    var firstSeen = Date()
    var lastSeen = Date()
    var addedAt: Date? = nil
    var usedAt: Date? = nil
    var value: Double? = nil
    var minSpend: Double? = nil
    var percent: Double? = nil
    var points: Double? = nil
    var manual = false
    var addedByApp = false
    /// Set when an added offer disappears from the bank's "added" list before it expires (often
    /// because it was used). The app asks about it.
    var missingSince: Date? = nil
    var hidden = false
    var note = ""

    var daysLeft: Int? { expires.map { DayMath.daysUntil($0) } }
    var isExpired: Bool { (daysLeft ?? 1) < 0 }

    var valueText: String? {
        if let value { return "\(value.shortMoney) back" }
        if let percent { return "\(percent.clean)% back" }
        if let points { return "\(Int(points).formatted()) pts" }
        return nil
    }
}

extension Offer {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID().uuidString)
        key = c.value(.key, id)
        cardID = c.optional(.cardID)
        issuer = c.value(.issuer, .other)
        merchant = c.value(.merchant, "Offer")
        reward = c.value(.reward, "")
        details = c.value(.details, "")
        expires = c.optional(.expires)
        status = c.value(.status, .available)
        firstSeen = c.value(.firstSeen, Date())
        lastSeen = c.value(.lastSeen, Date())
        addedAt = c.optional(.addedAt)
        usedAt = c.optional(.usedAt)
        value = c.optional(.value)
        minSpend = c.optional(.minSpend)
        percent = c.optional(.percent)
        points = c.optional(.points)
        manual = c.value(.manual, false)
        addedByApp = c.value(.addedByApp, false)
        missingSince = c.optional(.missingSince)
        hidden = c.value(.hidden, false)
        note = c.value(.note, "")
    }
}

// MARK: - Deadlines (sign-up bonuses, bank bonuses, anything with a date)

struct Deadline: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var detail: String = ""
    var due: Date
    var cardID: UUID? = nil
    var done = false
    var target: Double? = nil
    var progress: Double? = nil

    var daysLeft: Int { DayMath.daysUntil(due) }
}

extension Deadline {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        title = c.value(.title, "Deadline")
        detail = c.value(.detail, "")
        due = c.value(.due, Date())
        cardID = c.optional(.cardID)
        done = c.value(.done, false)
        target = c.optional(.target)
        progress = c.optional(.progress)
    }
}

// MARK: - Sync history

struct SyncRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var issuer: Issuer
    var cardID: UUID?
    var date = Date()
    var found = 0
    var new = 0
    var added = 0
}

// MARK: - Everything that's saved

struct AppData: Codable {
    var version = 1
    var cards: [Card] = []
    var credits: [Credit] = []
    var offers: [Offer] = []
    var deadlines: [Deadline] = []
    var syncs: [SyncRecord] = []
    /// Offers first seen after this are "new".
    var offersViewedAt = Date.distantPast

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, 1)
        cards = c.value(.cards, [])
        credits = c.value(.credits, [])
        offers = c.value(.offers, [])
        deadlines = c.value(.deadlines, [])
        syncs = c.value(.syncs, [])
        offersViewedAt = c.value(.offersViewedAt, .distantPast)
    }
}

// MARK: - Tolerant decoding (older/newer files never fail to open)

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    func optional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

// MARK: - Formatting

extension Double {
    var money: String { formatted(.currency(code: "USD")) }

    /// "$15" or "$12.95"
    var shortMoney: String {
        let r = (self * 100).rounded() / 100
        if abs(r - r.rounded()) < 0.005 { return "$" + Int(r.rounded()).formatted() }
        return String(format: "$%.2f", r)
    }

    var clean: String {
        abs(self - rounded()) < 0.001 ? String(Int(rounded())) : String(format: "%.1f", self)
    }
}

extension Date {
    /// "today", "tomorrow", "in 5 days", "Dec 1"
    var relativeDay: String {
        let d = DayMath.daysUntil(self)
        switch d {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...13: return "in \(d) days"
        default: return formatted(.dateTime.month(.abbreviated).day())
        }
    }

    var monthDay: String { formatted(.dateTime.month(.abbreviated).day()) }
}
