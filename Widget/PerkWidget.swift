import SwiftUI
import WidgetKit

struct PerkEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let hasData: Bool
}

struct PerkProvider: TimelineProvider {
    func placeholder(in context: Context) -> PerkEntry {
        PerkEntry(date: .now, snapshot: .placeholder, hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PerkEntry) -> Void) {
        if let s = WidgetSnapshot.load() {
            completion(PerkEntry(date: .now, snapshot: s, hasData: true))
        } else {
            completion(PerkEntry(date: .now, snapshot: .placeholder, hasData: context.isPreview))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PerkEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        let now = Date()
        let cal = Calendar.current
        // One entry now and one at each of the next few midnights so "days left" stays right.
        var entries: [PerkEntry] = [PerkEntry(date: now, snapshot: snap ?? .empty, hasData: snap != nil)]
        for i in 1...3 {
            if let d = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: now)) {
                entries.append(PerkEntry(date: d.addingTimeInterval(60), snapshot: snap ?? .empty, hasData: snap != nil))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct PerkWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PerkEntry

    private var items: [WidgetSnapshot.Item] {
        entry.snapshot.items.filter { item in
            guard let ends = item.ends else { return true }
            return DayMath.daysUntil(ends, from: entry.date) >= 0
        }
    }

    var body: some View {
        if !entry.hasData {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "creditcard.and.123").font(.title2).foregroundStyle(.green)
                Text("Open Perk Keeper to fill this in.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            switch family {
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Use it or lose it").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(entry.snapshot.unusedNow.widgetMoney)
                .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.6)
            Spacer(minLength: 2)
            if let first = items.first {
                row(first, compact: true)
            }
            if entry.snapshot.newOffers > 0 {
                Label("\(entry.snapshot.newOffers) new offers", systemImage: "tag.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Left to use").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(entry.snapshot.unusedNow.widgetMoney)
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if entry.snapshot.newOffers > 0 {
                    Label("\(entry.snapshot.newOffers) new", systemImage: "tag.fill").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                }
                Label("\(entry.snapshot.addedOffers) added", systemImage: "checkmark.circle").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if items.isEmpty {
                    Text("Nothing expiring soon.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(items.prefix(4)) { item in row(item, compact: false) }
                Spacer(minLength: 0)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.snapshot.unusedNow.widgetMoney) to use").font(.headline)
            if let first = items.first {
                Text("\(first.title) · \(daysText(first))").font(.caption).lineLimit(1)
            }
            if entry.snapshot.newOffers > 0 {
                Text("\(entry.snapshot.newOffers) new offers").font(.caption2)
            }
        }
    }

    private func row(_ item: WidgetSnapshot.Item, compact: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.symbol)
                .font(.caption2)
                .foregroundStyle(Color(hex: item.colorHex))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.caption.weight(.semibold)).lineLimit(1)
                if !compact { Text(item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 2)
            Text(daysText(item))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(urgency(item))
        }
    }

    private func daysText(_ item: WidgetSnapshot.Item) -> String {
        guard let ends = item.ends else { return "" }
        let d = DayMath.daysUntil(ends, from: entry.date)
        return d == 0 ? "today" : "\(d)d"
    }

    private func urgency(_ item: WidgetSnapshot.Item) -> Color {
        guard let ends = item.ends else { return .secondary }
        let d = DayMath.daysUntil(ends, from: entry.date)
        return d <= 2 ? .red : d <= 7 ? .orange : .secondary
    }
}

private extension Double {
    var widgetMoney: String {
        abs(self - rounded()) < 0.005 ? "$" + Int(rounded()).formatted() : String(format: "$%.2f", self)
    }
}

struct PerkWidget: Widget {
    let kind = "PerkKeeperWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PerkProvider()) { entry in
            PerkWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.05, green: 0.20, blue: 0.15).opacity(0.18), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .widgetURL(URL(string: "perkkeeper://credits"))
        }
        .configurationDisplayName("Use it or lose it")
        .description("Credits about to reset and added offers about to expire.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct PerkWidgetBundle: WidgetBundle {
    var body: some Widget {
        PerkWidget()
    }
}
