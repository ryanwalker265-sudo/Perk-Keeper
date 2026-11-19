import Foundation

/// Sample wallet for trying the app (and for the screenshots in CI). Dates are relative to today.
enum DemoData {
    static func make(now: Date = .now) -> AppData {
        let cal = Calendar.current
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: now) ?? now }
        func month(_ n: Int) -> Date { cal.date(byAdding: .month, value: n, to: now) ?? now }
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now

        var d = AppData()
        let plat = Card(name: "Platinum Card", issuer: .amex, last4: "41009", colorHex: "#C9CDD3", colorHex2: "#7D838C",
                        annualFee: 895, anniversaryMonth: 3, templateID: "amex-platinum", createdAt: day(-300))
        let gold = Card(name: "Gold Card", issuer: .amex, last4: "12006", colorHex: "#E2C275", colorHex2: "#A97C2A",
                        annualFee: 325, anniversaryMonth: 8, templateID: "amex-gold", createdAt: day(-299))
        let csr = Card(name: "Sapphire Reserve", issuer: .chase, last4: "4422", colorHex: "#2C3E5C", colorHex2: "#111A2B",
                       annualFee: 795, anniversaryMonth: 6, templateID: "chase-sapphire-reserve", createdAt: day(-298))
        let rh = Card(name: "Robinhood Gold Card", issuer: .robinhood, last4: "8810", colorHex: "#E5C55E", colorHex2: "#B08A24",
                      annualFee: 0, templateID: "robinhood-gold", createdAt: day(-297))
        d.cards = [plat, gold, csr, rh]

        func credits(_ card: Card, hide: Set<String> = []) -> [Credit] {
            (Templates.template(id: card.templateID)?.credits ?? []).map {
                var c = $0.makeCredit(cardID: card.id)
                c.hidden = hide.contains(c.name)
                c.enrolled = c.needsEnrollment && !["Resy", "Dunkin'"].contains(c.name)
                return c
            }
        }
        var all = credits(plat, hide: ["lululemon", "Oura Ring", "Equinox"]) + credits(gold) + credits(csr)

        func use(_ name: String, on card: Card, _ amount: Double, _ date: Date) {
            if let i = all.firstIndex(where: { $0.name == name && $0.cardID == card.id }) {
                all[i].uses.append(CreditUse(date: date, amount: amount))
            }
        }
        let thisMonth = max(startOfMonth, day(-3))
        use("Uber Cash", on: plat, 15, thisMonth)
        use("Digital entertainment", on: plat, 13.99, thisMonth)
        use("Hotel credit", on: plat, 300, month(-2))
        use("Airline fee", on: plat, 200, month(-6))
        use("CLEAR+", on: plat, 219, month(-8))
        use("Global Entry / TSA PreCheck", on: plat, 120, month(-20))
        use("Dining credit", on: gold, 10, thisMonth)
        use("Dunkin'", on: gold, 7, thisMonth)
        use("Travel credit", on: csr, 300, month(-4))
        use("DoorDash promos", on: csr, 15, thisMonth)
        d.credits = all

        func offer(_ card: Card, _ merchant: String, _ reward: String, exp: Int, _ status: OfferStatus,
                   value: Double? = nil, minSpend: Double? = nil, percent: Double? = nil, seen: Int = -20, missing: Bool = false) -> Offer {
            let key = merchant.lowercased().filter { $0.isLetter || $0.isNumber } + "|" + reward.lowercased().filter { $0.isLetter || $0.isNumber }
            var o = Offer(id: card.id.uuidString + "|" + key, key: key, cardID: card.id, issuer: card.issuer, merchant: merchant,
                          reward: reward, expires: day(exp), status: status, firstSeen: day(seen), lastSeen: day(0))
            o.value = value
            o.minSpend = minSpend
            o.percent = percent
            if status == .added || status == .used { o.addedAt = day(seen + 1); o.addedByApp = true }
            if status == .used { o.usedAt = day(-4) }
            if missing { o.missingSince = day(-1) }
            return o
        }
        let newSeen = 0
        d.offers = [
            offer(plat, "Hilton", "Spend $250 or more, earn $50 back. Up to 2 times (total of $100).", exp: 42, .available, value: 100, minSpend: 250, seen: newSeen),
            offer(plat, "Dell Technologies", "Earn 10% back on purchases, up to a total of $40", exp: 57, .available, value: 40, percent: 10, seen: newSeen),
            offer(plat, "Instacart", "Earn 20% back, up to $15", exp: 24, .available, value: 15, percent: 20, seen: newSeen),
            offer(plat, "Lowe's", "Spend $100+, earn $20 back", exp: 31, .available, value: 20, minSpend: 100, seen: newSeen),
            offer(plat, "Walgreens", "Spend $20 or more, earn $5 back", exp: 2, .added, value: 5, minSpend: 20),
            offer(plat, "FedEx", "Spend $30+, earn $10 back", exp: 5, .added, value: 10, minSpend: 30),
            offer(plat, "Disney+", "Spend $10.99 or more, earn $10.99 back", exp: 40, .added, value: 10.99, minSpend: 10.99),
            offer(plat, "Hulu", "Spend $7.99 or more, earn $7.99 back", exp: 20, .added, value: 7.99, minSpend: 7.99, missing: true),
            offer(plat, "Best Buy", "Spend $200 or more, earn $30 back", exp: 16, .used, value: 30, minSpend: 200),
            offer(gold, "Uber Eats", "Get $5 back on a single purchase of $25+", exp: 9, .used, value: 5, minSpend: 25),
            offer(gold, "Whole Foods Market", "Spend $60+, earn $10 back", exp: 13, .added, value: 10, minSpend: 60),
            offer(csr, "Starbucks", "5% cash back", exp: 12, .available, percent: 5, seen: newSeen),
            offer(csr, "Wayfair", "10% cash back", exp: 30, .available, percent: 10, seen: -9),
            offer(csr, "Lyft", "$10 cash back", exp: 5, .added, value: 10),
            offer(csr, "Peloton", "$50 cash back", exp: 9, .added, value: 50),
        ]
        d.offersViewedAt = day(-2)
        d.deadlines = [
            Deadline(title: "Sapphire Reserve bonus", detail: "Spend $6,000 for 125,000 points", due: day(52), cardID: csr.id, target: 6000, progress: 3850),
            Deadline(title: "Checking bonus: keep $2,500 in", detail: "Leave it until the bonus posts", due: day(18)),
        ]
        d.syncs = [
            SyncRecord(issuer: .amex, cardID: plat.id, date: day(-2), found: 38, new: 6, added: 6),
            SyncRecord(issuer: .chase, cardID: csr.id, date: day(-3), found: 21, new: 2, added: 2),
        ]
        return d
    }
}
