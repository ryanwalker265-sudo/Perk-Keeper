import Foundation
import UserNotifications
import UIKit

/// Preferences stored on this iPhone.
enum Prefs {
    static let d = UserDefaults.standard

    static var notificationsOn: Bool {
        get { d.object(forKey: "notify.on") as? Bool ?? false }
        set { d.set(newValue, forKey: "notify.on") }
    }
    static var creditDays: Int { d.object(forKey: "notify.creditDays") as? Int ?? 3 }
    static var offerDays: Int { d.object(forKey: "notify.offerDays") as? Int ?? 3 }
    static var hour: Int { d.object(forKey: "notify.hour") as? Int ?? 9 }
    static var syncEvery: Int { d.object(forKey: "notify.syncEvery") as? Int ?? 3 }
    static var syncHour: Int { d.object(forKey: "notify.syncHour") as? Int ?? 19 }
    static var feeReminders: Bool { d.object(forKey: "notify.fees") as? Bool ?? true }

    static var autoAdd: Bool { d.object(forKey: "sync.autoAdd") as? Bool ?? true }
    /// Issuers the user has turned auto-add off for.
    static var autoAddOff: Set<String> { Set(d.stringArray(forKey: "sync.autoAddOff") ?? []) }
    static func autoAdd(for issuer: Issuer) -> Bool {
        guard autoAdd, !autoAddOff.contains(issuer.rawValue) else { return false }
        // Amex's offer terms ban automated adding: only after the user has read that.
        return issuer != .amex || d.bool(forKey: "amexTermsAcknowledged")
    }
    static var careful: Bool { d.object(forKey: "sync.careful") as? Bool ?? false }
    static var skipWords: [String] {
        (d.string(forKey: "sync.skip") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }
}

/// Perk Keeper's reminders. Everything is a local notification scheduled on the iPhone, so no
/// server or account is involved. The schedule is rebuilt whenever data changes or the app opens.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    weak var router: AppRouter?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let s = await center.notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    var permissionDenied: Bool {
        get async { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied }
    }

    private struct Planned {
        var id: String
        var date: Date
        var title: String
        var body: String
        var route: String
        var thread: String
    }

    private func at(_ day: Date, hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    private func days(_ n: Int, from d: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: d) ?? d
    }

    func reschedule(store: AppStore) async {
        let center = UNUserNotificationCenter.current()
        guard Prefs.notificationsOn, !store.isDemo else {
            center.removeAllPendingNotificationRequests()
            return
        }
        let now = Date()
        var plan: [Planned] = []

        // Credits with value left, grouped by reminder day.
        var creditGroups: [Date: [CreditStatus]] = [:]
        for s in store.creditStatuses(at: now) where !s.isDone && s.credit.reminders {
            guard let lastDay = s.lastDay else { continue }
            var fire = at(days(-max(Prefs.creditDays - 1, 0), from: lastDay), hour: Prefs.hour)
            if fire <= now { fire = at(lastDay, hour: Prefs.hour) }
            guard fire > now else { continue }
            creditGroups[fire, default: []].append(s)
        }
        for (fire, items) in creditGroups {
            let total = items.reduce(0) { $0 + $1.remaining }
            let last = items.compactMap(\.lastDay).min() ?? fire
            let when = DayMath.daysUntil(last, from: fire) == 0 ? "today" : "by \(last.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))"
            let title: String
            if items.count == 1, let s = items.first {
                title = s.credit.isChecklist ? "\(s.credit.name): still to do" : "\(s.remaining.shortMoney) \(s.credit.name) left"
            } else {
                title = total > 0 ? "\(total.shortMoney) in credits to use" : "\(items.count) perks to use"
            }
            let list = items.prefix(4).map { s in
                s.credit.isChecklist ? s.credit.name : "\(s.credit.name) \(s.remaining.shortMoney)"
            }.joined(separator: " · ")
            plan.append(Planned(id: "credit-\(Int(fire.timeIntervalSince1970))", date: fire, title: title,
                                body: "Use \(when) before it resets. \(list)", route: "credits", thread: "credits"))
        }

        // Added offers that expire soon, grouped by day.
        var offerGroups: [Date: [Offer]] = [:]
        for o in store.addedOffers {
            guard let exp = o.expires else { continue }
            var fire = at(days(-Prefs.offerDays, from: exp), hour: Prefs.hour + 1)
            if fire <= now { fire = at(exp, hour: Prefs.hour + 1) }
            guard fire > now else { continue }
            offerGroups[fire, default: []].append(o)
        }
        for (fire, offers) in offerGroups {
            let title = offers.count == 1 ? "\(offers[0].merchant) offer expires soon" : "\(offers.count) added offers expire soon"
            let list = offers.prefix(4).map { o in o.valueText.map { "\(o.merchant) (\($0))" } ?? o.merchant }.joined(separator: ", ")
            let exp = offers.compactMap(\.expires).min() ?? fire
            plan.append(Planned(id: "offer-\(Int(fire.timeIntervalSince1970))", date: fire, title: title,
                                body: "\(list). Last day \(exp.monthDay).", route: "offers.added", thread: "offers"))
        }

        // "Check for new offers" nudges.
        if Prefs.syncEvery > 0, !store.syncableCards.isEmpty {
            let base = store.lastAnySync ?? now
            var next = at(days(Prefs.syncEvery, from: base), hour: Prefs.syncHour)
            if next <= now.addingTimeInterval(3600) { next = at(days(next <= now ? 1 : 0, from: now), hour: Prefs.syncHour) }
            if next <= now { next = at(days(1, from: now), hour: Prefs.syncHour) }
            let names = Array(Set(store.syncableCards.map(\.issuer.shortName))).sorted().joined(separator: ", ")
            for k in 0..<3 {
                let fire = days(k * Prefs.syncEvery, from: next)
                plan.append(Planned(id: "sync-\(k)", date: fire, title: "New card offers are probably waiting",
                                    body: "Tap to check \(names) and add new offers in one go.", route: "sync", thread: "sync"))
            }
        }

        // Deadlines.
        for dl in store.openDeadlines {
            for before in [7, 1] {
                let fire = at(days(-before, from: dl.due), hour: Prefs.hour)
                guard fire > now else { continue }
                plan.append(Planned(id: "deadline-\(dl.id.uuidString)-\(before)", date: fire,
                                    title: before == 1 ? "Due tomorrow: \(dl.title)" : "Due in a week: \(dl.title)",
                                    body: dl.detail.isEmpty ? "Due \(dl.due.monthDay)." : dl.detail, route: "home", thread: "deadlines"))
            }
        }

        // Annual fees.
        if Prefs.feeReminders {
            let cal = Calendar.current
            for card in store.cards {
                guard let fee = card.annualFee, fee > 0, let m = card.anniversaryMonth else { continue }
                let y = cal.component(.year, from: now)
                var anniv = cal.date(from: DateComponents(year: y, month: m, day: 1)) ?? now
                if anniv <= now { anniv = cal.date(byAdding: .year, value: 1, to: anniv) ?? anniv }
                let fire = at(days(-30, from: anniv), hour: Prefs.hour)
                guard fire > now else { continue }
                plan.append(Planned(id: "fee-\(card.id.uuidString)", date: fire, title: "\(card.name) annual fee next month",
                                    body: "\(fee.shortMoney) posts around \(anniv.formatted(.dateTime.month(.wide))). Check what you used this year before it renews.",
                                    route: "cards", thread: "fees"))
            }
        }

        center.removeAllPendingNotificationRequests()
        for p in plan.sorted(by: { $0.date < $1.date }).prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            content.threadIdentifier = p.thread
            content.userInfo = ["route": p.route]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.date)
            let req = UNNotificationRequest(identifier: "pk.\(p.id)", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
    }

    func sendTest() async -> Bool {
        guard await requestPermission() else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Perk Keeper reminders are on"
        content.body = "You'll hear about credits before they reset and offers before they expire."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "pk.test.\(UUID().uuidString)", content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
        return (try? await UNUserNotificationCenter.current().add(req)) != nil
    }

    func notifySyncResult(issuer: Issuer, new: Int, added: Int) async {
        guard Prefs.notificationsOn, new > 0 || added > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = added > 0 ? "Added \(added) \(issuer.shortName) offers" : "\(new) new \(issuer.shortName) offers"
        content.body = "Open Perk Keeper to see what's new and what's about to expire."
        content.userInfo = ["route": "offers.new"]
        let req = UNNotificationRequest(identifier: "pk.result.\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo["route"] as? String ?? "home"
        await MainActor.run { Notifier.shared.router?.open(route: route) }
    }
}
