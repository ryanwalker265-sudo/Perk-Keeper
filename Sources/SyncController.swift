import Foundation
import Observation
import UIKit
import WebKit

/// One trip to a bank's offers page.
struct SyncSession: Identifiable {
    let id = UUID()
    let adapter: OfferAdapter
    var cardID: UUID?
    var autoAdd: Bool
    var demo = false
    var startURL: URL? = nil
}

/// What the engine reports about the page it's on.
struct PageState: Decodable, Equatable {
    var url = ""
    var host = ""
    var main = true
    var login = false
    var onDomain = true
    var tiles = 0
    var toAdd = 0
    var added = 0
    var used = 0
    var hints: [String] = []
    var title = ""

    enum CodingKeys: String, CodingKey { case url, host, main, login, onDomain, tiles, toAdd, added, used, hints, title }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = c.value(.url, "")
        host = c.value(.host, "")
        main = c.value(.main, true)
        login = c.value(.login, false)
        onDomain = c.value(.onDomain, true)
        tiles = c.value(.tiles, 0)
        toAdd = c.value(.toAdd, 0)
        added = c.value(.added, 0)
        used = c.value(.used, 0)
        hints = c.value(.hints, [])
        title = c.value(.title, "")
    }
}

struct AddResult: Decodable {
    var clicked: Bool
    var key: String?
    var merchant: String?
    var reward: String?
    var skipped: Int?
    var remaining: Int?
}

/// A JavaScript alert or confirm from the bank's page, answered exactly once.
final class JSDialog {
    let message: String
    let isConfirm: Bool
    private var handler: ((Bool) -> Void)?

    init(message: String, isConfirm: Bool, handler: @escaping (Bool) -> Void) {
        self.message = message
        self.isConfirm = isConfirm
        self.handler = handler
    }

    func complete(_ ok: Bool) {
        handler?(ok)
        handler = nil
    }
}

/// Drives the in-app browser: loads the bank's offers page, lets the engine read it, adds offers
/// one at a time when asked, and saves what it finds.
///
/// Your bank login happens in this browser exactly as in Safari. Perk Keeper never reads the
/// login form (the engine runs in its own isolated script world and ignores form fields), and
/// the site data stays in this iPhone's web storage, which you can clear in Settings.
@MainActor
@Observable
final class SyncController: NSObject {
    enum Phase: Equatable {
        case opening, login, looking, scanning, ready, adding, finished
        case failed(String)
    }

    struct Progress: Equatable {
        var done = 0
        var total = 0
        var current = ""
    }

    let session: SyncSession
    var adapter: OfferAdapter { session.adapter }
    var cardID: UUID?
    var phase: Phase = .opening
    var page = PageState()
    var stepIndex = 0
    var lastScan = ScanSummary()
    var totalNew = 0
    var addedCount = 0
    var failedCount = 0
    var skippedCount = 0
    var progress = Progress()
    var notice: String?
    var dialog: JSDialog?
    var autoAdd: Bool
    var canGoBack = false

    @ObservationIgnored private(set) var webView: WKWebView?
    private let store: AppStore
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var pipeline = false
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private var scannedSteps = Set<Int>()
    @ObservationIgnored private var activeFrame: WKFrameInfo?
    @ObservationIgnored private var addedKeys: [String] = []
    @ObservationIgnored private var closed = false

    static let world = WKContentWorld.world(name: "PerkKeeper")

    init(session: SyncSession, store: AppStore) {
        self.session = session
        self.store = store
        self.cardID = session.cardID
        self.autoAdd = session.autoAdd
        super.init()
    }

    var card: Card? { store.card(cardID) }

    var cardsForIssuer: [Card] { store.cards.filter { $0.issuer == adapter.issuer } }

    private var savesResults: Bool { !session.demo || store.isDemo }

    // MARK: Web view

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.applicationNameForUserAgent = "Version/26.0 Mobile/15E148 Safari/604.1"
        cfg.defaultWebpagePreferences.preferredContentMode = .mobile
        cfg.allowsInlineMediaPlayback = true
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: "window.__PK_CONFIG = \(adapter.json);", injectionTime: .atDocumentStart,
                                       forMainFrameOnly: false, in: Self.world))
        ucc.addUserScript(WKUserScript(source: Engine.source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: Self.world))
        ucc.add(MessageProxy(owner: self), contentWorld: Self.world, name: "pk")
        cfg.userContentController = ucc
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        #if DEBUG
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        #endif
        webView = wv
        return wv
    }

    func start() {
        let wv = makeWebView()
        guard wv.url == nil else { return }
        if session.demo, let url = adapter.steps.first?.url, url.isFileURL {
            wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if let url = session.startURL ?? adapter.steps.first?.url {
            wv.load(URLRequest(url: url))
        }
    }

    func goToStep(_ i: Int) {
        guard adapter.steps.indices.contains(i) else { return }
        stepIndex = i
        let url = adapter.steps[i].url
        if url.isFileURL { webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        else { webView?.load(URLRequest(url: url)) }
    }

    func reload() { webView?.reload() }
    func goBack() { webView?.goBack() }

    // MARK: Messages from the engine

    fileprivate func receive(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "state",
              let data = try? JSONSerialization.data(withJSONObject: body),
              let s = try? JSONDecoder().decode(PageState.self, from: data) else { return }
        if s.tiles > 0 { activeFrame = message.frameInfo.isMainFrame ? nil : message.frameInfo }
        if !s.main && s.tiles == 0 && !s.login { return }
        if !s.main && s.tiles == 0 && page.tiles > 0 { return }
        page = s
        guard !busy, !pipeline, phase != .finished else { return }
        if s.login && s.tiles == 0 {
            phase = .login
        } else if s.tiles > 0 {
            if case .failed = phase { phase = .ready }
            if phase != .ready { phase = .ready }
            if !scannedSteps.contains(stepIndex) { Task { await runPipeline() } }
        } else if phase == .opening || phase == .login || phase == .ready {
            phase = .looking
        }
    }

    // MARK: Scan and add

    /// First look at a page with offers: read everything; with auto-add on, add them and move on.
    private func runPipeline() async {
        guard !pipeline else { return }
        pipeline = true
        defer { pipeline = false }
        scannedSteps.insert(stepIndex)
        await performScan(expand: true)
        if autoAdd, lastScan.toAdd > 0, !cancelRequested { await performAddAll() }
        guard autoAdd, !cancelRequested else { return }
        if stepIndex + 1 < adapter.steps.count {
            goToStep(stepIndex + 1)
        } else {
            phase = .finished
            await Notifier.shared.notifySyncResult(issuer: adapter.issuer, new: totalNew, added: addedCount)
        }
    }

    func scan() async {
        guard !busy, !pipeline else { return }
        await performScan(expand: true)
    }

    func addAll() async {
        guard !busy, !pipeline else { return }
        pipeline = true
        defer { pipeline = false }
        await performAddAll()
    }

    func cancel() { cancelRequested = true }

    private func performScan(expand: Bool) async {
        busy = true
        defer { busy = false }
        phase = .scanning
        notice = nil
        let opts: [String: Any] = ["expand": expand, "loadMoreDelay": 1100, "scrollDelay": 700]
        guard let raw = await call("return await window.__PK.scan(o);", ["o": opts]) as? String,
              let r = decode(ScanResult.self, raw) else {
            phase = page.tiles > 0 ? .ready : .looking
            notice = "Couldn't read this page yet. Tap Scan when your offers are showing."
            return
        }
        if r.ok == false {
            phase = .looking
            notice = "This page isn't on \(adapter.name)'s website."
            return
        }
        let target = resolveCard(hints: r.hints ?? [])
        if savesResults {
            lastScan = store.applyScan(r, issuer: adapter.issuer, cardID: target)
        } else {
            var s = ScanSummary()
            s.found = r.tiles.count
            s.toAdd = r.tiles.filter { $0.status == "available" }.count
            s.added = r.tiles.filter { $0.status == "added" }.count
            s.new = scannedSteps.count <= 1 && totalNew == 0 ? s.toAdd : 0
            lastScan = s
        }
        totalNew += lastScan.new
        phase = r.tiles.isEmpty ? .looking : .ready
    }

    private func performAddAll() async {
        busy = true
        cancelRequested = false
        phase = .adding
        let skip = Prefs.skipWords
        var tried: [String] = []
        var strikes = 0
        progress = Progress(done: 0, total: max(lastScan.toAdd, page.toAdd), current: "")
        let delay = Prefs.careful ? 1800...3200 : 900...1700

        loop: for _ in 0..<300 {
            if cancelRequested { break }
            guard await waitForOffers(timeout: 12) else {
                notice = "The offers list didn't come back. Tap Scan to check where things stand."
                break
            }
            let before = webView?.url
            let o: [String: Any] = ["tried": tried, "skip": skip, "preClickMs": 250]
            guard let raw = await call("return await window.__PK.addNext(o);", ["o": o]) as? String,
                  let r = decode(AddResult.self, raw) else { break }
            skippedCount = r.skipped ?? 0
            guard r.clicked, let key = r.key else { break }
            tried.append(key)
            progress.current = r.merchant ?? ""
            progress.total = max(progress.total, progress.done + 1 + (r.remaining ?? 0))
            try? await Task.sleep(for: .milliseconds(Int.random(in: delay)))

            if let err = await call("return window.__PK.errorText() || '';") as? String, !err.isEmpty {
                notice = "\(adapter.issuer.shortName) says: \(err)"
                failedCount += 1
                break loop
            }
            if adapter.goesBackAfterAdding, webView?.url != before {
                _ = await call("return await window.__PK.goBack();")
                try? await Task.sleep(for: .milliseconds(900))
                _ = await waitForOffers(timeout: 12)
            }
            let st = await call("return window.__PK.statusOf(k);", ["k": key]) as? String ?? "gone"
            if st == "available" {
                failedCount += 1
                strikes += 1
                if strikes >= 4 {
                    notice = "Several offers didn't stick. \(adapter.issuer.shortName) may be slowing down adds; try again later or turn on Careful pace."
                    break
                }
            } else {
                strikes = 0
                addedKeys.append(key)
                addedCount += 1
                progress.done += 1
            }
        }
        if savesResults { store.markAdded(keys: addedKeys, issuer: adapter.issuer, cardID: cardID) }
        busy = false
        if !closed { await performScan(expand: false) }
        Haptics.success()
    }

    private func waitForOffers(timeout: Double) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cancelRequested { return false }
            if let n = await call("return window.__PK ? window.__PK.state().tiles : 0;") as? Int, n > 0 { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    // MARK: Cards

    func choose(card id: UUID?) {
        guard id != cardID else { return }
        cardID = id
        notice = nil
    }

    /// If the page names exactly one of the user's cards from this bank, save offers to that card.
    private func resolveCard(hints: [String]) -> UUID? {
        let tails = Set(hints.map { String($0.suffix(4)) })
        let matches = cardsForIssuer.filter { $0.last4.count >= 4 && tails.contains(String($0.last4.suffix(4))) }
        if matches.count == 1, let m = matches.first, m.id != cardID {
            cardID = m.id
            notice = "Saving to \(m.displayName), the card shown on the page."
        }
        return cardID
    }

    // MARK: Diagnostics

    func diagnostics() async -> String {
        let outline = await call("return window.__PK ? window.__PK.outline() : 'engine not on this page';") as? String ?? "no response"
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return """
        Perk Keeper \(v) diagnostics · \(adapter.name) · adapters v\(AdapterStore.shared.version) · \(Date().formatted(date: .abbreviated, time: .shortened))
        Account numbers and emails are masked. Share this to get selectors fixed.

        \(outline)
        """
    }

    // MARK: Closing

    func close() {
        guard !closed else { return }
        closed = true
        cancelRequested = true
        if let d = dialog { d.complete(false); dialog = nil }
        if savesResults, lastScan.found > 0 || addedCount > 0 {
            store.recordSync(issuer: adapter.issuer, cardID: cardID, found: lastScan.found, new: totalNew, added: addedCount)
        }
        store.saveNow()
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    // MARK: Helpers

    private func decode<T: Decodable>(_ type: T.Type, _ raw: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(raw.utf8))
    }

    /// Calls into the engine in its isolated world, in the frame that holds the offers.
    private func call(_ js: String, _ args: [String: Any] = [:]) async -> Any? {
        guard let webView else { return nil }
        let frame = activeFrame
        let first = await Self.run(webView, js, args, frame)
        if case .success(let v) = first { return v }
        guard frame != nil else { return nil }
        activeFrame = nil
        if case .success(let v) = await Self.run(webView, js, args, nil) { return v }
        return nil
    }

    private static func run(_ webView: WKWebView, _ js: String, _ args: [String: Any], _ frame: WKFrameInfo?) async -> Result<Any, Error> {
        await withCheckedContinuation { cont in
            webView.callAsyncJavaScript(js, arguments: args, in: frame, in: world) { result in
                cont.resume(returning: result)
            }
        }
    }
}

// MARK: - WebKit delegates

extension SyncController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        canGoBack = webView.canGoBack
        if !busy && !pipeline && phase != .finished { phase = .opening }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        canGoBack = webView.canGoBack
        if phase == .opening { phase = .looking }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    private func handle(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
        if !busy && !pipeline { phase = .failed(ns.localizedDescription) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            // Phone numbers, mail links and app links open outside the browser.
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Links that open a new window load here instead.
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        if closed { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            dialog?.complete(false)
            dialog = JSDialog(message: message, isConfirm: false) { _ in cont.resume() }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        if closed { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            dialog?.complete(false)
            dialog = JSDialog(message: message, isConfirm: true) { cont.resume(returning: $0) }
        }
    }
}

/// Keeps WebKit from holding the controller strongly.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: SyncController?
    init(owner: SyncController) { self.owner = owner }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { owner?.receive(message) }
    }
}
