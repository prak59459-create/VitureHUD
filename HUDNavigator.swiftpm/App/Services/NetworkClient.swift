import Foundation
import Network
import Observation
import Security

/// 外部通信の記録（プライバシー画面で確認できる）。アプリの外部通信は全てここを通す。
@MainActor
@Observable
final class NetworkLog {
    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let date: Date
        let host: String
        let purpose: String
        let bytesSent: Int
        let bytesReceived: Int
        let status: Int?
        let error: String?
    }

    private(set) var entries: [Entry] = []
    private(set) var isOnline = true
    private(set) var isExpensive = false

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                self?.isOnline = online
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "hudnavigator.network.monitor"))
    }

    func record(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
    }

    func clear() { entries.removeAll() }

    /// 目的を付けて通信する。送受信サイズと結果を記録する。
    func send(_ request: URLRequest, purpose: String) async throws -> (Data, HTTPURLResponse) {
        let host = request.url?.host ?? "?"
        let sent = request.httpBody?.count ?? 0
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            record(Entry(date: Date(), host: host, purpose: purpose, bytesSent: sent, bytesReceived: data.count, status: http?.statusCode, error: nil))
            guard let http else { throw URLError(.badServerResponse) }
            return (data, http)
        } catch {
            record(Entry(date: Date(), host: host, purpose: purpose, bytesSent: sent, bytesReceived: 0, status: nil, error: error.localizedDescription))
            throw error
        }
    }
}

/// API キーの保存（端末の Keychain。外部には送らない・ログに出さない）。
enum KeychainStore {
    private static let service = "io.github.prak59459.hudnavigator.apikeys"

    static func save(_ value: String, account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) { save("", account: account) }

    static func deleteAll() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
    }
}

/// 天気（Open-Meteo、非商用は無料・APIキー不要）。取得できない値は表示しない。
@MainActor
@Observable
final class WeatherModel {
    private(set) var snapshot: WeatherSnapshot?
    private(set) var isLoading = false
    private(set) var lastError: String?

    @ObservationIgnored private var lastFetchCoordinate: GeoCoordinate?
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored weak var network: NetworkLog?

    /// 必要なら取得（15分経過 or 2km 以上移動）
    func refreshIfNeeded(at coordinate: GeoCoordinate, enabled: Bool) {
        guard enabled, !isLoading else { return }
        let now = Date()
        if let last = lastAttempt, now.timeIntervalSince(last) < 60 { return }
        if let snap = snapshot, let lastC = lastFetchCoordinate, !snap.isStale(at: now, maxAge: 15 * 60), Geo.distance(lastC, coordinate) < 2000 {
            return
        }
        Task { await refresh(at: coordinate) }
    }

    func refresh(at coordinate: GeoCoordinate) async {
        guard let network else { return }
        isLoading = true
        lastAttempt = Date()
        defer { isLoading = false }
        do {
            guard let url = OpenMeteo.forecastURL(for: coordinate) else { return }
            let (data, response) = try await network.send(URLRequest(url: url, timeoutInterval: 15), purpose: "天気の取得（丸めた現在地）")
            guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
            var snap = try OpenMeteo.parseForecast(data, fetchedAt: Date())
            if let airURL = OpenMeteo.airQualityURL(for: coordinate),
               let air = try? await network.send(URLRequest(url: airURL, timeoutInterval: 15), purpose: "空気質の取得（丸めた現在地）"),
               air.1.statusCode == 200 {
                snap = (try? OpenMeteo.mergeAirQuality(air.0, into: snap)) ?? snap
            }
            snapshot = snap
            lastFetchCoordinate = coordinate
            lastError = nil
        } catch {
            lastError = network.isOnline ? "天気を取得できませんでした" : "オフラインのため天気を取得できません"
        }
    }

    func clear() {
        snapshot = nil
        lastFetchCoordinate = nil
    }
}
