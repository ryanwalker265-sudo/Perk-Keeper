import SwiftUI

enum Theme {
    static let accent = Color("AccentColor")
    static let gold = Color(red: 0.83, green: 0.62, blue: 0.18)
    static let good = Color(red: 0.10, green: 0.62, blue: 0.40)
    static let warn = Color(red: 0.93, green: 0.52, blue: 0.10)
    static let urgent = Color(red: 0.86, green: 0.22, blue: 0.20)

    /// Red within 2 days, orange within a week, otherwise quiet.
    static func urgency(_ days: Int?) -> Color {
        guard let days else { return .secondary }
        if days <= 2 { return urgent }
        if days <= 7 { return warn }
        return .secondary
    }
}

/// A miniature of the physical card, in its colors.
struct CardArt: View {
    let card: Card
    var width: CGFloat = 54
    var showText = false

    var body: some View {
        let h = width / 1.586
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: card.colorHex), Color(hex: card.colorHex2)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.6)
            if showText {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.issuer.shortName.uppercased())
                        .font(.system(size: width * 0.055, weight: .heavy))
                        .opacity(0.8)
                    Spacer()
                    HStack {
                        Text(card.name).font(.system(size: width * 0.07, weight: .semibold))
                        Spacer()
                        if !card.last4.isEmpty {
                            Text("•• " + String(card.last4.suffix(4))).font(.system(size: width * 0.06, weight: .medium).monospacedDigit())
                        }
                    }
                }
                .foregroundStyle(textColor)
                .padding(width * 0.07)
            } else {
                Capsule().fill(.white.opacity(0.55)).frame(width: width * 0.22, height: max(2, width * 0.04))
                    .padding(width * 0.1)
            }
        }
        .frame(width: width, height: h)
        .shadow(color: .black.opacity(0.18), radius: width * 0.04, y: width * 0.02)
        .accessibilityLabel(card.displayName)
    }

    private var textColor: Color {
        // Light cards (platinum, gold) get dark text.
        let light = ["#C9CDD3", "#E2C275", "#B7BDC6", "#D9B864", "#E5C55E", "#C4CAD2", "#F7A23B"]
        return light.contains(card.colorHex.uppercased()) ? Color.black.opacity(0.75) : .white
    }
}

struct Pill: View {
    let text: String
    var color: Color = .secondary
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.13), in: Capsule())
    }
}

struct IssuerBadge: View {
    let issuer: Issuer
    var body: some View {
        Text(issuer.shortName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(issuer.color, in: Capsule())
    }
}

struct ProgressBar: View {
    let value: Double
    var color: Color = Theme.good
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule().fill(color.gradient).frame(width: max(height, g.size.width * min(max(value, 0), 1)))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}

struct Stat: View {
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
