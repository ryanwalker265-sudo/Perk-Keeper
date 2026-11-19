import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var demoSync: SyncSession?

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("Today", systemImage: "sparkles") }
                .tag(AppRouter.Tab.home)
            CreditsView()
                .tabItem { Label("Credits", systemImage: "dollarsign.arrow.circlepath") }
                .tag(AppRouter.Tab.credits)
            OffersView()
                .tabItem { Label("Offers", systemImage: "tag") }
                .tag(AppRouter.Tab.offers)
                .badge(store.newOffers.count)
            CardsView()
                .tabItem { Label("Cards", systemImage: "creditcard") }
                .tag(AppRouter.Tab.cards)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
        .minimizingTabBar()
        .sheet(isPresented: $router.showSync) { SyncHubView() }
        .fullScreenCover(item: $demoSync) { s in SyncBrowserView(session: s) }
        .onAppear {
            if LaunchOptions.demoSync, demoSync == nil {
                demoSync = SyncSession(adapter: AdapterStore.shared.demoAdapter, cardID: store.cards.first?.id, autoAdd: true, demo: true)
            }
        }
    }
}

/// Small "Used it" style button used in lists.
struct UseButton: View {
    let status: CreditStatus
    @Environment(AppStore.self) private var store

    var body: some View {
        Button {
            if status.isDone { store.undoLastUse(status) } else { store.useRemaining(status); Haptics.success() }
        } label: {
            Image(systemName: status.isDone ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(status.isDone ? Theme.good : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status.isDone ? "Mark not used" : "Mark \(status.credit.name) used")
    }
}

struct CreditRow: View {
    let status: CreditStatus
    var showCard = true
    var showUseButton = true

    private var tint: Color { status.card.map { Color(hex: $0.colorHex2) } ?? Theme.accent }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.13))
                Image(systemName: status.credit.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(status.credit.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if status.credit.needsEnrollment && !status.credit.enrolled {
                        Pill(text: "Enroll", color: Theme.warn)
                    }
                    Spacer(minLength: 0)
                    if showCard, let card = status.card { CardArt(card: card, width: 30) }
                }
                if !status.credit.isChecklist {
                    ProgressBar(value: status.progress, color: status.isDone ? Theme.good : Theme.accent, height: 5)
                }
                HStack {
                    Text(amountText).foregroundStyle(.secondary)
                    Spacer()
                    Text(timeText).foregroundStyle(status.isDone ? .secondary : Theme.urgency(status.daysLeft))
                }
                .font(.caption.monospacedDigit())
            }
            if showUseButton { UseButton(status: status) }
        }
        .contentShape(Rectangle())
    }

    private var amountText: String {
        if status.credit.isChecklist { return status.isDone ? "Done" : "To do" }
        if status.isDone { return "All \(status.periodAmount.shortMoney) used" }
        if status.used > 0 { return "\(status.remaining.shortMoney) left of \(status.periodAmount.shortMoney)" }
        return "\(status.periodAmount.shortMoney) \(status.credit.cadence == .monthly ? "this month" : "to use")"
    }

    private var timeText: String {
        guard let resets = status.resetsOn else {
            return status.credit.cadence == .multiYear ? (status.isDone ? "Used" : "Available") : "No end date"
        }
        if status.isDone { return "Resets \(resets.monthDay)" }
        if let ends = status.credit.endsOn, status.credit.cadence == .oneTime { return "Ends \(ends.monthDay)" }
        return "\(DayMath.shortDays(status.daysLeft ?? 0)) left"
    }
}
