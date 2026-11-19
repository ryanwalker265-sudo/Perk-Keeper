import Foundation
import Observation

/// One bank's entry from adapters.json: where its offers live and how the engine should read them.
struct OfferAdapter: Identifiable, Hashable {
    struct Step: Hashable {
        let id: String
        let label: String
        let url: URL
    }

    let issuer: Issuer
    let name: String
    let steps: [Step]
    let afterClick: String
    let tips: String
    let domains: [String]
    /// The raw JSON object, handed to the engine as window.__PK_CONFIG.
    let json: String

    var id: String { issuer.rawValue }
    var goesBackAfterAdding: Bool { afterClick == "back" }
}

/// Bank page details ship with the app and are refreshed from the GitHub repo, so a bank changing
/// its website can be fixed without a new build. The file is data only (addresses, CSS selectors
/// and text patterns); the engine's code itself never comes from the network.
@MainActor
@Observable
final class AdapterStore {
    static let shared = AdapterStore()

    static let remoteURL = URL(string: "https://raw.githubusercontent.com/ryanwalker265-sudo/Perk-Keeper/main/Resources/adapters.json")!

    private(set) var version = 0
    private(set) var updated = ""
    private(set) var adapters: [OfferAdapter] = []
    private(set) var source = "built in"
    var lastChecked: Date? {
        get { UserDefaults.standard.object(forKey: "adapters.checked") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "adapters.checked") }
    }

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerkKeeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("adapters.json")
    }

    init() {
        let bundled = Bundle.main.url(forResource: "adapters", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        let cached = try? Data(contentsOf: Self.cacheURL)
        let b = bundled.flatMap(Self.parse)
        let c = cached.flatMap(Self.parse)
        if let c, c.version > (b?.version ?? 0) {
            apply(c, source: "updated")
        } else if let b {
            apply(b, source: "built in")
        }
    }

    private func apply(_ p: Parsed, source: String) {
        version = p.version
        updated = p.updated
        adapters = p.adapters
        self.source = source
    }

    func adapter(for issuer: Issuer) -> OfferAdapter {
        adapters.first { $0.issuer == issuer }
            ?? adapters.first { $0.issuer == .other }
            ?? OfferAdapter(issuer: issuer, name: issuer.name, steps: [], afterClick: "stay", tips: "", domains: [], json: "{}")
    }

    /// A copy of the Amex adapter pointed at a page bundled with the app, for trying sync safely.
    var demoAdapter: OfferAdapter {
        let base = adapter(for: .amex)
        var obj = (try? JSONSerialization.jsonObject(with: Data(base.json.utf8))) as? [String: Any] ?? [:]
        obj["demo"] = true
        obj["pageStatus"] = []
        let json = (try? JSONSerialization.data(withJSONObject: obj)).flatMap { String(data: $0, encoding: .utf8) } ?? base.json
        let page = Bundle.main.url(forResource: "demo-offers", withExtension: "html") ?? URL(string: "about:blank")!
        return OfferAdapter(issuer: .amex, name: "Demo bank", steps: [.init(id: "available", label: "Demo offers", url: page)],
                            afterClick: "stay", tips: "This is a practice page bundled with the app. Nothing here touches a real account.",
                            domains: [], json: json)
    }

    func refreshIfNeeded(force: Bool = false) async {
        if !force, let last = lastChecked, Date().timeIntervalSince(last) < 12 * 3600 { return }
        var req = URLRequest(url: Self.remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        req.setValue("PerkKeeper", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let p = Self.parse(data) else { return }
        lastChecked = Date()
        if p.version > version {
            try? data.write(to: Self.cacheURL, options: .atomic)
            apply(p, source: "updated")
        }
    }

    struct Parsed {
        let version: Int
        let updated: String
        let adapters: [OfferAdapter]
    }

    nonisolated static func parse(_ data: Data) -> Parsed? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = root["adapters"] as? [[String: Any]] else { return nil }
        var out: [OfferAdapter] = []
        for obj in list {
            guard let raw = obj["issuer"] as? String, let issuer = Issuer(rawValue: raw),
                  let json = (try? JSONSerialization.data(withJSONObject: obj)).flatMap({ String(data: $0, encoding: .utf8) }) else { continue }
            let steps: [OfferAdapter.Step] = (obj["steps"] as? [[String: Any]] ?? []).compactMap { s in
                guard let id = s["id"] as? String, let label = s["label"] as? String,
                      let u = (s["url"] as? String).flatMap(URL.init(string:)), u.scheme == "https" else { return nil }
                return .init(id: id, label: label, url: u)
            }
            out.append(OfferAdapter(
                issuer: issuer, name: obj["name"] as? String ?? issuer.name, steps: steps,
                afterClick: obj["afterClick"] as? String ?? "stay", tips: obj["tips"] as? String ?? "",
                domains: obj["domains"] as? [String] ?? [], json: json
            ))
        }
        guard !out.isEmpty else { return nil }
        return Parsed(version: root["version"] as? Int ?? 0, updated: root["updated"] as? String ?? "", adapters: out)
    }
}

enum Engine {
    static let source: String = {
        guard let url = Bundle.main.url(forResource: "offer-engine", withExtension: "js"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }()
}
