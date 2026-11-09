import Foundation
import CoreML

/// アプリに入っている Core ML モデル（Resources/Models）を探して使える形にする。
/// Swift Playgrounds 版・IPA 版のどちらも、モデルは加工せずにアプリへ入れ、
/// 初めて使うときに端末でコンパイルして保存する（2 回目からはすぐ読み込める）。
enum ModelStore {
    enum StoreError: LocalizedError {
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let name): return "モデル「\(name)」がアプリの中に見つかりません。"
            }
        }
    }

    private static let extensions = ["mlmodelc", "mlpackage", "mlmodel"]

    /// アプリの中のモデルの場所
    static func bundledURL(named name: String) -> URL? {
        var bundles: [Bundle] = [Bundle.main]
        bundles += Bundle.allBundles
        if let res = Bundle.main.resourceURL,
           let items = try? FileManager.default.contentsOfDirectory(at: res, includingPropertiesForKeys: nil) {
            for item in items where item.pathExtension == "bundle" {
                if let b = Bundle(url: item) { bundles.append(b) }
            }
        }
        for b in bundles {
            for ext in extensions {
                if let u = b.url(forResource: name, withExtension: ext) { return u }
                if let u = b.url(forResource: name, withExtension: ext, subdirectory: "Models") { return u }
                if let u = b.url(forResource: name, withExtension: ext, subdirectory: "Resources/Models") { return u }
            }
        }
        // 最後の手段：アプリの中を全部探す
        if let res = Bundle.main.resourceURL,
           let e = FileManager.default.enumerator(at: res, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in e where extensions.contains(url.pathExtension) {
                if url.deletingPathExtension().lastPathComponent == name { return url }
                if url.pathExtension == "mlpackage" || url.pathExtension == "mlmodelc" { e.skipDescendants() }
            }
        }
        return nil
    }

    static func isBundled(_ name: String) -> Bool { bundledURL(named: name) != nil }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HUDNavigator/Models/Compiled", isDirectory: true)
    }

    /// 使える状態のモデル。初回はコンパイル（数秒〜数十秒）。
    static func load(named name: String, computeUnits: MLComputeUnits = .all) async throws -> MLModel {
        guard let source = bundledURL(named: name) else { throw StoreError.notFound(name) }
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        if source.pathExtension == "mlmodelc" {
            return try MLModel(contentsOf: source, configuration: config)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let cached = cacheDirectory.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
        let stampURL = cacheDirectory.appendingPathComponent("\(name).stamp")
        let stamp = signature(of: source)
        if fm.fileExists(atPath: cached.path), (try? String(contentsOf: stampURL, encoding: .utf8)) == stamp,
           let model = try? MLModel(contentsOf: cached, configuration: config) {
            return model
        }
        let compiled = try await MLModel.compileModel(at: source)
        try? fm.removeItem(at: cached)
        try fm.moveItem(at: compiled, to: cached)
        try? stamp.write(to: stampURL, atomically: true, encoding: .utf8)
        return try MLModel(contentsOf: cached, configuration: config)
    }

    /// 中身が変わったか（アプリの更新）を見分けるための目印：合計サイズ
    private static func signature(of url: URL) -> String {
        let fm = FileManager.default
        var total: UInt64 = 0
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
           let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e {
                total += UInt64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        } else {
            total = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return "\(url.lastPathComponent)-\(total)"
    }
}
