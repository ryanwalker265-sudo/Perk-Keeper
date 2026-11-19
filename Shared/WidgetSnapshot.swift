import Foundation
import SwiftUI

/// Shared between the app and the widget. The app writes a small summary into the App Group
/// container after every change; the widget only ever reads it.
enum AppGroup {
    static let id = "group.com.perkkeeper.app"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}

struct WidgetSnapshot: Codable {
    struct Item: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var detail: String
        var amount: Double?
        var ends: Date?
        var kind: String          // "credit" or "offer"
        var colorHex: String
        var symbol: String
    }

    var generatedAt: Date
    var unusedNow: Double
    var unusedThisMonth: Double
    var newOffers: Int
    var addedOffers: Int
    var items: [Item]

    static let fileName = "widget-snapshot.json"

    static var url: URL? { AppGroup.containerURL?.appendingPathComponent(fileName) }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    /// Returns false when there's no App Group (some sideloading tools don't keep it).
    @discardableResult
    func save() -> Bool {
        guard let url = Self.url else { return false }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(self) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static let placeholder = WidgetSnapshot(
        generatedAt: .now, unusedNow: 207, unusedThisMonth: 52.95, newOffers: 6, addedOffers: 9,
        items: [
            Item(id: "1", title: "Digital entertainment", detail: "$25 left", amount: 25, ends: Calendar.current.date(byAdding: .day, value: 3, to: .now), kind: "credit", colorHex: "#9EA4AD", symbol: "tv"),
            Item(id: "2", title: "Uber Cash", detail: "$15 left", amount: 15, ends: Calendar.current.date(byAdding: .day, value: 3, to: .now), kind: "credit", colorHex: "#9EA4AD", symbol: "car.fill"),
            Item(id: "3", title: "Hilton", detail: "$50 back", amount: 50, ends: Calendar.current.date(byAdding: .day, value: 6, to: .now), kind: "offer", colorHex: "#006FCF", symbol: "tag.fill"),
        ]
    )

    static let empty = WidgetSnapshot(generatedAt: .now, unusedNow: 0, unusedThisMonth: 0, newOffers: 0, addedOffers: 0, items: [])
}

extension Color {
    /// "#RRGGBB" → Color. Falls back to gray.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&v) else {
            self = .gray
            return
        }
        self = Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

enum DayMath {
    /// Whole days from today to the given day (0 = today, negative = past).
    static func daysUntil(_ date: Date, from now: Date = .now) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    }

    static func shortDays(_ days: Int) -> String {
        switch days {
        case ..<0: return "ended"
        case 0: return "today"
        case 1: return "1 day"
        default: return "\(days) days"
        }
    }
}
