import Foundation

/// Ready-made cards with their recurring credits. Checked against issuer pages and card reviews in
/// November 2026. Everything can be edited after adding, since issuers change benefits often.
struct CardTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let issuer: Issuer
    let colors: (String, String)
    let annualFee: Double?
    let credits: [CreditTemplate]
    var note: String = ""

    static func == (a: CardTemplate, b: CardTemplate) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var yearValue: Double {
        credits.reduce(0) { $0 + $1.makeCredit(cardID: UUID()).yearValue }
    }
}

struct CreditTemplate: Hashable {
    let name: String
    let amount: Double
    let cadence: Cadence
    var monthAmounts: [Int: Double] = [:]
    var everyYears: Int = 4
    var symbol: String = "dollarsign.circle"
    var note: String = ""
    var enroll: Bool = false
    var endsOn: DateComponents? = nil

    func makeCredit(cardID: UUID) -> Credit {
        Credit(
            cardID: cardID, name: name, amount: amount, cadence: cadence, monthAmounts: monthAmounts,
            everyYears: everyYears, symbol: symbol, note: note, needsEnrollment: enroll,
            enrolled: false, endsOn: endsOn.flatMap { Calendar.current.date(from: $0) }
        )
    }
}

enum Templates {
    static let asOf = "November 2026"

    private static func ends(_ y: Int, _ m: Int, _ d: Int) -> DateComponents { DateComponents(year: y, month: m, day: d) }

    private static let globalEntry = CreditTemplate(
        name: "Global Entry / TSA PreCheck", amount: 120, cadence: .multiYear, everyYears: 4,
        symbol: "person.text.rectangle", note: "Application fee credit: up to $120 for Global Entry or $85 for TSA PreCheck."
    )

    static let all: [CardTemplate] = [
        CardTemplate(
            id: "amex-platinum", name: "Platinum Card", issuer: .amex, colors: ("#C9CDD3", "#7D838C"), annualFee: 895,
            credits: [
                CreditTemplate(name: "Hotel credit", amount: 300, cadence: .semiannual, symbol: "bed.double.fill",
                               note: "Prepaid Fine Hotels + Resorts or The Hotel Collection (2-night minimum) booked through Amex Travel. Amex added Airbnb Luxe stays in October 2026."),
                CreditTemplate(name: "Resy", amount: 100, cadence: .quarterly, symbol: "fork.knife",
                               note: "Pay with the card at U.S. Resy restaurants.", enroll: true),
                CreditTemplate(name: "Digital entertainment", amount: 25, cadence: .monthly, symbol: "tv.fill",
                               note: "Disney+, Hulu, ESPN+, Peacock, Paramount+, YouTube Premium/TV, NYT, WSJ. Pay the service directly, not through an app store.", enroll: true),
                CreditTemplate(name: "Uber Cash", amount: 15, cadence: .monthly, monthAmounts: [12: 35], symbol: "car.fill",
                               note: "$15 each month and $35 in December. Add the card to your Uber account; unused Uber Cash expires at month end."),
                CreditTemplate(name: "Uber One", amount: 120, cadence: .annual, symbol: "car.circle",
                               note: "Auto-renewing Uber One membership paid with the card.", enroll: true),
                CreditTemplate(name: "Walmart+", amount: 12.95, cadence: .monthly, symbol: "cart.fill",
                               note: "Monthly Walmart+ membership (plus tax) paid with the card.", enroll: true),
                CreditTemplate(name: "lululemon", amount: 75, cadence: .quarterly, symbol: "tshirt.fill",
                               note: "U.S. lululemon stores and lululemon.com.", enroll: true),
                CreditTemplate(name: "Airline fee", amount: 200, cadence: .annual, symbol: "airplane",
                               note: "Incidental fees on the one airline you select in your Amex account.", enroll: true),
                CreditTemplate(name: "CLEAR+", amount: 219, cadence: .annual, symbol: "person.badge.shield.checkmark.fill",
                               note: "CLEAR+ membership paid with the card."),
                CreditTemplate(name: "Oura Ring", amount: 200, cadence: .annual, symbol: "circle.circle",
                               note: "Oura Ring hardware bought at ouraring.com.", enroll: true),
                CreditTemplate(name: "Equinox", amount: 300, cadence: .annual, symbol: "figure.run",
                               note: "Equinox+ or Equinox club membership.", enroll: true),
                globalEntry,
            ],
            note: "Saks credit ended July 1, 2026."
        ),
        CardTemplate(
            id: "amex-gold", name: "Gold Card", issuer: .amex, colors: ("#E2C275", "#A97C2A"), annualFee: 325,
            credits: [
                CreditTemplate(name: "Dining credit", amount: 10, cadence: .monthly, symbol: "takeoutbag.and.cup.and.straw.fill",
                               note: "Grubhub/Seamless, Buffalo Wild Wings, Five Guys, The Cheesecake Factory and Wonder.", enroll: true),
                CreditTemplate(name: "Uber Cash", amount: 10, cadence: .monthly, symbol: "car.fill",
                               note: "Add the card to your Uber account. U.S. rides and Uber Eats."),
                CreditTemplate(name: "Resy", amount: 50, cadence: .semiannual, symbol: "fork.knife",
                               note: "U.S. Resy restaurants.", enroll: true),
                CreditTemplate(name: "Dunkin'", amount: 7, cadence: .monthly, symbol: "cup.and.saucer.fill",
                               note: "U.S. Dunkin' locations.", enroll: true),
            ]
        ),
        CardTemplate(
            id: "chase-sapphire-reserve", name: "Sapphire Reserve", issuer: .chase, colors: ("#2C3E5C", "#111A2B"), annualFee: 795,
            credits: [
                CreditTemplate(name: "Travel credit", amount: 300, cadence: .cardYear, symbol: "airplane",
                               note: "Applies automatically to most travel purchases each card year."),
                CreditTemplate(name: "The Edit hotel credit", amount: 500, cadence: .annual, symbol: "bed.double.fill",
                               note: "Two $250 credits a year, one per prepaid 2+ night stay booked through The Edit."),
                CreditTemplate(name: "Exclusive Tables dining", amount: 150, cadence: .semiannual, symbol: "fork.knife",
                               note: "Sapphire Reserve Exclusive Tables restaurants on OpenTable."),
                CreditTemplate(name: "StubHub & viagogo", amount: 150, cadence: .semiannual, symbol: "ticket.fill",
                               note: "Activate once in the Chase app.", enroll: true, endsOn: ends(2027, 12, 31)),
                CreditTemplate(name: "DoorDash promos", amount: 35, cadence: .monthly, symbol: "bag.fill",
                               note: "One $15 restaurant promo and two $10 grocery/retail promos each month with DashPass.", enroll: true),
                CreditTemplate(name: "Lyft", amount: 10, cadence: .monthly, symbol: "car.fill",
                               note: "In-app credit posts on the 1st.", endsOn: ends(2027, 9, 30)),
                CreditTemplate(name: "Peloton", amount: 10, cadence: .monthly, symbol: "bicycle",
                               note: "Peloton membership paid with the card.", enroll: true, endsOn: ends(2027, 12, 31)),
                CreditTemplate(name: "Select Chase Travel hotels", amount: 250, cadence: .oneTime, symbol: "building.2.fill",
                               note: "One-time 2026 credit for a 2+ night stay at select hotels (IHG, Omni, Virgin and others).", endsOn: ends(2026, 12, 31)),
                CreditTemplate(name: "Apple TV+ & Apple Music", amount: 0, cadence: .oneTime, symbol: "music.note.tv.fill",
                               note: "Activate each subscription once in the Chase app. Free through June 22, 2027.", enroll: true, endsOn: ends(2027, 6, 22)),
                globalEntry,
            ]
        ),
        CardTemplate(
            id: "chase-sapphire-preferred", name: "Sapphire Preferred", issuer: .chase, colors: ("#3B5B8C", "#1D2F4F"), annualFee: 95,
            credits: [
                CreditTemplate(name: "Chase Travel hotel credit", amount: 50, cadence: .cardYear, symbol: "bed.double.fill",
                               note: "Hotel stays booked through Chase Travel."),
            ]
        ),
        CardTemplate(
            id: "capital-one-venture-x", name: "Venture X", issuer: .capitalOne, colors: ("#3A3A3C", "#0E0E10"), annualFee: 395,
            credits: [
                CreditTemplate(name: "Capital One Travel credit", amount: 300, cadence: .cardYear, symbol: "airplane",
                               note: "Bookings made through Capital One Travel."),
                CreditTemplate(name: "10,000 anniversary miles", amount: 0, cadence: .cardYear, symbol: "gift.fill",
                               note: "Posts each account anniversary. Check that it arrived."),
                globalEntry,
            ]
        ),
        CardTemplate(
            id: "delta-reserve", name: "Delta SkyMiles Reserve", issuer: .amex, colors: ("#3B3F48", "#16181D"), annualFee: 650,
            credits: [
                CreditTemplate(name: "Resy", amount: 20, cadence: .monthly, symbol: "fork.knife", note: "U.S. Resy restaurants.", enroll: true),
                CreditTemplate(name: "Rideshare", amount: 10, cadence: .monthly, symbol: "car.fill", note: "Uber, Lyft, Curb, Revel and Alto in the U.S.", enroll: true),
                CreditTemplate(name: "Delta Stays", amount: 200, cadence: .annual, symbol: "bed.double.fill", note: "Prepaid hotels booked on delta.com/stays."),
                CreditTemplate(name: "Companion certificate", amount: 0, cadence: .cardYear, symbol: "person.2.fill",
                               note: "Arrives after each card anniversary. Book before it expires."),
                globalEntry,
            ]
        ),
        CardTemplate(
            id: "delta-platinum", name: "Delta SkyMiles Platinum", issuer: .amex, colors: ("#B7BDC6", "#6E747D"), annualFee: 350,
            credits: [
                CreditTemplate(name: "Resy", amount: 10, cadence: .monthly, symbol: "fork.knife", note: "U.S. Resy restaurants.", enroll: true),
                CreditTemplate(name: "Rideshare", amount: 10, cadence: .monthly, symbol: "car.fill", note: "U.S. rideshare.", enroll: true),
                CreditTemplate(name: "Delta Stays", amount: 150, cadence: .annual, symbol: "bed.double.fill", note: "Prepaid hotels booked on delta.com/stays."),
                CreditTemplate(name: "Companion certificate", amount: 0, cadence: .cardYear, symbol: "person.2.fill",
                               note: "Arrives after each card anniversary."),
            ]
        ),
        CardTemplate(
            id: "delta-gold", name: "Delta SkyMiles Gold", issuer: .amex, colors: ("#D9B864", "#A07F2C"), annualFee: 150,
            credits: [
                CreditTemplate(name: "Delta Stays", amount: 100, cadence: .annual, symbol: "bed.double.fill", note: "Prepaid hotels booked on delta.com/stays."),
            ]
        ),
        CardTemplate(
            id: "hilton-aspire", name: "Hilton Honors Aspire", issuer: .amex, colors: ("#26344F", "#0F1626"), annualFee: 550,
            credits: [
                CreditTemplate(name: "Hilton resort credit", amount: 200, cadence: .semiannual, symbol: "beach.umbrella.fill", note: "Participating Hilton Resorts."),
                CreditTemplate(name: "Flight credit", amount: 50, cadence: .quarterly, symbol: "airplane", note: "Flights bought directly from an airline or amextravel.com."),
                CreditTemplate(name: "CLEAR+", amount: 199, cadence: .annual, symbol: "person.badge.shield.checkmark.fill", note: "CLEAR+ membership.", enroll: true),
                CreditTemplate(name: "Free night reward", amount: 0, cadence: .cardYear, symbol: "moon.stars.fill", note: "Earned each card anniversary."),
            ]
        ),
        CardTemplate(
            id: "marriott-brilliant", name: "Marriott Bonvoy Brilliant", issuer: .amex, colors: ("#3A302B", "#15110F"), annualFee: 650,
            credits: [
                CreditTemplate(name: "Dining credit", amount: 25, cadence: .monthly, symbol: "fork.knife", note: "Restaurants worldwide."),
                CreditTemplate(name: "Free night award", amount: 0, cadence: .cardYear, symbol: "moon.stars.fill", note: "Earned each card anniversary."),
            ]
        ),
        CardTemplate(
            id: "robinhood-gold", name: "Robinhood Gold Card", issuer: .robinhood, colors: ("#E5C55E", "#B08A24"), annualFee: 0,
            credits: [],
            note: "3% cash back on everything and no statement credits. Track offers and deadlines for it here."
        ),
        CardTemplate(
            id: "robinhood-platinum", name: "Robinhood Platinum Card", issuer: .robinhood, colors: ("#C4CAD2", "#7B828B"), annualFee: 695,
            credits: [
                CreditTemplate(name: "Travel credit", amount: 150, cadence: .semiannual, symbol: "airplane"),
                CreditTemplate(name: "Hotel credit", amount: 250, cadence: .semiannual, symbol: "bed.double.fill", note: "Luxury hotels booked through Robinhood, 2-night minimum."),
                CreditTemplate(name: "Dining credit", amount: 20, cadence: .monthly, monthAmounts: [12: 30], symbol: "fork.knife", note: "Participating restaurants."),
                CreditTemplate(name: "Autonomous rides", amount: 20, cadence: .monthly, monthAmounts: [12: 30], symbol: "car.side.fill"),
                CreditTemplate(name: "DoorDash", amount: 20, cadence: .monthly, monthAmounts: [1: 30], symbol: "bag.fill", note: "$10 twice a month on $50+ orders."),
                CreditTemplate(name: "Health wearable", amount: 200, cadence: .annual, symbol: "heart.circle.fill"),
                globalEntry,
            ],
            note: "Terms were still settling when this list was made. Check Robinhood's terms."
        ),
        CardTemplate(
            id: "chase-freedom-flex", name: "Freedom Flex", issuer: .chase, colors: ("#4A90C8", "#1F5E91"), annualFee: 0,
            credits: [
                CreditTemplate(name: "Activate 5% categories", amount: 0, cadence: .quarterly, symbol: "bolt.circle.fill",
                               note: "Activate each quarter to earn 5% on up to $1,500 in the bonus categories."),
            ]
        ),
        CardTemplate(
            id: "discover-it", name: "Discover it Cash Back", issuer: .discover, colors: ("#F7A23B", "#D3611A"), annualFee: 0,
            credits: [
                CreditTemplate(name: "Activate 5% categories", amount: 0, cadence: .quarterly, symbol: "bolt.circle.fill",
                               note: "Activate each quarter for 5% on up to $1,500 in the calendar categories."),
            ]
        ),
    ]

    static func template(id: String?) -> CardTemplate? { all.first { $0.id == id } }
}
