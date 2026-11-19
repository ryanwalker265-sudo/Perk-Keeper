import SwiftUI
import BackgroundTasks
import LocalAuthentication
import Observation

@main
struct PerkKeeperApp: App {
    @State private var store = AppStore.shared
    @State private var router = AppRouter()
    @State private var auth = AuthModel()
    @Environment(\.scenePhase) private var scenePhase

    static let refreshTaskID = "com.perkkeeper.app.refresh"

    init() {
        Notifier.shared.install()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            BackgroundRefresh.handle(task)
        }
        LaunchOptions.apply()
    }

    var body: some Scene {
        WindowGroup {
            AppGate()
                .environment(store)
                .environment(router)
                .environment(auth)
                .tint(Theme.accent)
                .onAppear { Notifier.shared.router = router }
                .onOpenURL { url in
                    guard url.scheme == "perkkeeper" else { return }
                    router.open(route: url.host ?? "home")
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                auth.didEnterBackground()
                store.saveNow()
                BackgroundRefresh.schedule()
            case .active:
                store.housekeeping()
                Task {
                    await auth.willEnterForeground()
                    await Notifier.shared.reschedule(store: store)
                    await AdapterStore.shared.refreshIfNeeded()
                }
            default: break
            }
        }
    }
}

/// Where the app is showing, so notifications and links can jump to the right place.
@MainActor
@Observable
final class AppRouter {
    enum Tab: String, Hashable { case home, credits, offers, cards, settings }

    var tab: Tab = .home
    var offerFilter: OfferFilter = .new
    var showSync = false

    func open(route: String) {
        switch route {
        case "credits": tab = .credits
        case "offers", "offers.new": tab = .offers; offerFilter = .new
        case "offers.added": tab = .offers; offerFilter = .added
        case "sync": tab = .offers; showSync = true
        case "cards": tab = .cards
        case "settings": tab = .settings
        default: tab = .home
        }
    }
}

/// Launch arguments used by the screenshot run in CI: -demo, -tab <name>, -demoSync.
enum LaunchOptions {
    static var args: [String] { ProcessInfo.processInfo.arguments }
    static var demo: Bool { args.contains("-demo") }
    static var demoSync: Bool { args.contains("-demoSync") }
    static var tab: String? {
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func apply() {
        if demo { AppStore.shared.loadDemo() }
    }
}

struct AppGate: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(AuthModel.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        ZStack {
            switch auth.state {
            case .starting:
                ZStack { AppBackground(); ProgressView() }
            case .locked:
                LockView().transition(.opacity)
            case .open:
                RootView().transition(.opacity)
            }
            if auth.faceIDEnabled && auth.state == .open && scenePhase != .active {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
                }
                .ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.state)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .task {
            if auth.state == .starting {
                if LaunchOptions.demo { auth.state = .open } else { await auth.start() }
                if let t = LaunchOptions.tab { router.open(route: t) }
                store.housekeeping()
            }
        }
    }
}

struct LockView: View {
    @Environment(AuthModel.self) private var auth

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: auth.biometryIcon)
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("Perk Keeper is locked").font(.title2.weight(.bold))
                Button {
                    Task { await auth.unlock() }
                } label: {
                    Label("Unlock with \(auth.biometryName)", systemImage: auth.biometryIcon)
                        .fontWeight(.semibold)
                        .frame(maxWidth: 280)
                        .padding(.vertical, 6)
                }
                .glassButton(prominent: true)
                .disabled(auth.unlocking)
                Spacer()
            }
            .padding()
        }
    }
}

/// Optional Face ID lock.
@MainActor
@Observable
final class AuthModel {
    enum State: Equatable { case starting, locked, open }

    var state: State = .starting
    var unlocking = false

    var faceIDEnabled: Bool = UserDefaults.standard.bool(forKey: "faceIDEnabled") {
        didSet { UserDefaults.standard.set(faceIDEnabled, forKey: "faceIDEnabled") }
    }
    var autoLockSeconds: Int = UserDefaults.standard.object(forKey: "autoLockSeconds") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(autoLockSeconds, forKey: "autoLockSeconds") }
    }

    @ObservationIgnored private var backgroundedAt: Date?

    func start() async {
        if faceIDEnabled && canAuthenticate {
            state = .locked
            await unlock()
        } else {
            state = .open
        }
    }

    private var canAuthenticate: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Face ID"
        }
    }

    var biometryIcon: String { biometryName == "Touch ID" ? "touchid" : biometryName == "Optic ID" ? "opticid" : "faceid" }

    func unlock() async {
        guard !unlocking else { return }
        unlocking = true
        defer { unlocking = false }
        if await authenticate(reason: "Unlock Perk Keeper") { state = .open }
    }

    func setFaceID(_ on: Bool) async {
        if on { guard await authenticate(reason: "Use \(biometryName) to unlock Perk Keeper") else { return } }
        faceIDEnabled = on
    }

    private func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    func didEnterBackground() { backgroundedAt = Date() }

    func willEnterForeground() async {
        defer { backgroundedAt = nil }
        guard state == .open, faceIDEnabled, let at = backgroundedAt, Date().timeIntervalSince(at) >= Double(autoLockSeconds) else { return }
        state = .locked
        await unlock()
    }
}

/// iOS wakes the app now and then to refresh the widget and reminders after periods roll over.
enum BackgroundRefresh {
    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: PerkKeeperApp.refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task { @MainActor in
            let store = AppStore.shared
            store.housekeeping()
            store.saveNow()
            await Notifier.shared.reschedule(store: store)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
