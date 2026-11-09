import Foundation

extension PlaceResult {
    init(google p: GooglePlace, from origin: GeoCoordinate?) {
        self.init(
            name: p.name,
            address: p.address,
            coordinate: p.coordinate,
            category: p.category,
            phone: p.phone,
            url: p.mapsURL.flatMap(URL.init(string:)),
            distance: origin.map { Geo.distance($0, p.coordinate) }
        )
        rating = p.rating
        ratingCount = p.ratingCount
        openNow = p.openNow
        openingHours = p.openingHours
        source = "Google"
    }
}

/// Google Maps Platform（Places API・Routes API）を REST で使う。
/// APIキー（ユーザーが用意）と送信への同意がある場合のみ動く。従量課金（無料枠あり）。
enum GoogleMapsService {
    static let keyAccount = "googleMaps"

    enum ServiceError: LocalizedError {
        case notConfigured
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Google Maps の APIキーが設定されていないか、送信に同意していません（設定 → 地図・ナビ）。"
            case .http(let code, let body):
                if code == 403 { return "Google Maps API が使えません（APIキー・有効化した API・請求先の設定を確認してください）。" }
                return "Google Maps API のエラー（\(code)）：\(body.prefix(120))"
            }
        }
    }

    static var hasKey: Bool { (KeychainStore.load(account: keyAccount) ?? "").isEmpty == false }

    static func isReady(_ s: GoogleMapsSettings) -> Bool { s.consentGiven && hasKey }

    private static func post(_ url: URL, body: [String: Any], fieldMask: String, purpose: String, network: NetworkLog) async throws -> Data {
        guard let key = KeychainStore.load(account: keyAccount), !key.isEmpty else { throw ServiceError.notConfigured }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await network.send(request, purpose: purpose)
        guard response.statusCode == 200 else { throw ServiceError.http(response.statusCode, String(data: data, encoding: .utf8) ?? "") }
        return data
    }

    static func search(_ query: String, near: GeoCoordinate?, network: NetworkLog) async throws -> [PlaceResult] {
        let data = try await post(GoogleMapsAPI.placesTextURL, body: GoogleMapsAPI.textSearchBody(query: query, near: near?.rounded()), fieldMask: GoogleMapsAPI.placesFieldMask, purpose: "場所の検索（Google・検索語と丸めた現在地）", network: network)
        return try GoogleMapsAPI.parsePlaces(data).map { PlaceResult(google: $0, from: near) }
            .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    static func nearby(_ category: NearbyCategory, near: GeoCoordinate, network: NetworkLog) async throws -> [PlaceResult] {
        let data = try await post(GoogleMapsAPI.placesNearbyURL, body: GoogleMapsAPI.nearbyBody(category: category, near: near.rounded()), fieldMask: GoogleMapsAPI.placesFieldMask, purpose: "周辺施設の検索（Google・丸めた現在地）", network: network)
        return try GoogleMapsAPI.parsePlaces(data).map { PlaceResult(google: $0, from: near) }
    }

    static func routes(from: GeoCoordinate, to place: PlaceResult, transport: TransportMode, network: NetworkLog) async throws -> [NavRoute] {
        let body = GoogleMapsAPI.routesBody(from: from, to: place.coordinate, transport: transport, departure: transport == .transit ? Date() : nil)
        let data = try await post(GoogleMapsAPI.routesURL, body: body, fieldMask: GoogleMapsAPI.routesFieldMask, purpose: "経路の検索（Google・出発地と目的地）", network: network)
        let routes = try GoogleMapsAPI.parseRoutes(data, transport: transport, destinationName: place.name)
        guard !routes.isEmpty else { throw RoutePlanner.PlannerError.noRoute }
        return routes
    }
}

/// iCloud Drive のフォルダを使った自動同期（CloudKit を使わない方法）。
/// ユーザーがフォルダを選ぶと、そこに設定ファイルを自動で書き出し・取り込みする。
@MainActor
@Observable
final class SyncFolderService {
    private(set) var folderName: String?
    private(set) var lastMessage: String?
    private(set) var isWorking = false

    static let fileName = "HUDNavigator-同期.json"
    private let bookmarkKey = "hudnavigator.syncFolderBookmark"

    init() {
        if let url = resolveFolder() { folderName = url.lastPathComponent }
    }

    var isConfigured: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// フォルダを選んだとき
    func setFolder(_ url: URL) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            folderName = url.lastPathComponent
            lastMessage = "同期フォルダ：\(url.lastPathComponent)"
            return true
        } catch {
            lastMessage = "フォルダを記録できませんでした：\(error.localizedDescription)"
            return false
        }
    }

    func clearFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderName = nil
        lastMessage = "同期フォルダの設定を解除しました"
    }

    private func resolveFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    /// 書き出し
    func write(_ data: Data) -> Bool {
        guard let folder = resolveFolder() else { return false }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let target = folder.appendingPathComponent(Self.fileName)
        var coordError: NSError?
        var success = false
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordError) { url in
            success = (try? data.write(to: url, options: .atomic)) != nil
        }
        lastMessage = success ? "同期フォルダに書き出しました（\(HUDFormat.clock(Date()))）" : "同期フォルダに書き出せませんでした"
        return success
    }

    /// 読み込み（iCloud にあってまだ端末にない場合はダウンロードを頼む）
    /// iCloud のダウンロード待ちで画面が止まらないよう、読み込みは別スレッドで行う
    func read() async -> Data? {
        guard let folder = resolveFolder() else { return nil }
        let name = Self.fileName
        return await Task.detached(priority: .utility) {
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            let target = folder.appendingPathComponent(name)
            try? FileManager.default.startDownloadingUbiquitousItem(at: target)
            var coordError: NSError?
            var result: Data?
            NSFileCoordinator().coordinate(readingItemAt: target, options: [], error: &coordError) { url in
                result = try? Data(contentsOf: url)
            }
            return result
        }.value
    }

    func setMessage(_ text: String) { lastMessage = text }
    func setWorking(_ v: Bool) { isWorking = v }
}
