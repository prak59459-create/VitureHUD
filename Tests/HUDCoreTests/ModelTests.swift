import XCTest
@testable import HUDCore

final class GeometryTests: XCTestCase {
    func testDenormalizeIsResolutionIndependent() {
        let r = NormalizedRect(x: 0.25, y: 0.5, width: 0.2, height: 0.1)
        let hd = r.denormalized(in: .fullHD)
        XCTAssertEqual(hd.x, 480, accuracy: 0.001)
        XCTAssertEqual(hd.y, 540, accuracy: 0.001)
        let ipad = r.denormalized(in: HUDSize(width: 1180, height: 820))
        XCTAssertEqual(ipad.x / 1180, 0.25, accuracy: 1e-9)
        XCTAssertEqual(ipad.y / 820, 0.5, accuracy: 1e-9)
        let back = NormalizedRect.fromPixels(hd, in: .fullHD)
        XCTAssertEqual(back, r)
    }

    func testClampKeepsInsideCanvas() {
        let r = NormalizedRect(x: 0.95, y: -0.2, width: 0.3, height: 0.001).clamped(minSize: 0.02)
        XCTAssertGreaterThanOrEqual(r.minX, 0)
        XCTAssertLessThanOrEqual(r.maxX, 1 + 1e-9)
        XCTAssertGreaterThanOrEqual(r.minY, 0)
        XCTAssertEqual(r.height, 0.02, accuracy: 1e-9)
    }

    func testIoU() {
        let a = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let b = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        XCTAssertEqual(a.iou(a), 1, accuracy: 1e-9)
        XCTAssertEqual(a.iou(b), 0.0625 / (0.25 + 0.25 - 0.0625), accuracy: 1e-9)
        XCTAssertEqual(a.iou(NormalizedRect(x: 0.6, y: 0.6, width: 0.1, height: 0.1)), 0)
    }
}

final class ColorTests: XCTestCase {
    func testHexRoundTrip() throws {
        let c = try XCTUnwrap(ColorToken(hex: "#5AE4FF"))
        XCTAssertEqual(c.hexString, "#5AE4FF")
        let withAlpha = try XCTUnwrap(ColorToken(hex: "#11223380"))
        XCTAssertEqual(withAlpha.alpha, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(withAlpha.hexString, "#11223380")
        XCTAssertEqual(ColorToken(hex: "fff")?.hexString, "#FFFFFF")
        XCTAssertNil(ColorToken(hex: "#12"))
        XCTAssertNil(ColorToken(hex: "zzzzzz"))
    }

    func testCodableAsString() throws {
        let data = try HUDJSON.encode(["c": ColorToken.red], pretty: false)
        XCTAssertEqual(String(data: data, encoding: .utf8), "{\"c\":\"#FF4D4D\"}")
        let back = try HUDJSON.decode([String: ColorToken].self, from: data)
        XCTAssertEqual(back["c"], .red)
    }

    func testContrastAndGlassVisibility() {
        XCTAssertEqual(ColorToken.white.contrastRatio(with: .black), 21, accuracy: 0.01)
        XCTAssertLessThan(ColorToken(hex: "#202020")!.glassVisibility, 0.2)
        XCTAssertGreaterThan(ColorToken.cyan.glassVisibility, 0.9)
    }
}

final class CodableCompatibilityTests: XCTestCase {
    func testLayoutRoundTrip() throws {
        let preset = try XCTUnwrap(BuiltInContent.makePresets().first)
        let data = try HUDJSON.encode(preset.layout)
        let back = try HUDJSON.decode(HUDLayout.self, from: data)
        XCTAssertEqual(back, preset.layout)
    }

    func testPanelDecodesWithMissingKeys() throws {
        let json = #"{"widget":"clock","frame":{"x":0.1,"y":0.1,"width":0.2,"height":0.1}}"#
        let panel = try HUDJSON.decode(HUDPanel.self, from: Data(json.utf8))
        XCTAssertEqual(panel.widget, .clock)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.opacity, 1)
        XCTAssertEqual(panel.config, WidgetConfig())
    }

    func testThemeDecodesOldFileWithoutNewStyleKeys() throws {
        let json = ##"{"id":"00000000-0000-0000-0000-0000000000F1","name":"古いテーマ","style":{"textColor":"#FF0000"}}"##
        let theme = try HUDJSON.decode(Theme.self, from: Data(json.utf8))
        XCTAssertEqual(theme.name, "古いテーマ")
        XCTAssertEqual(theme.style.textColor, ColorToken(hex: "#FF0000"))
        XCTAssertEqual(theme.style.cornerRadius, PanelStyle().cornerRadius)
    }

    func testSettingsMergeDefaultsForMissingNestedKeys() throws {
        // 古い設定ファイル：voice に rate が無い、detection 自体が無い
        let json = #"{"displayOutput":"mirrorOnly","voice":{"guidanceEnabled":false}}"#
        let s = try AppSettings.decodeMergingDefaults(from: Data(json.utf8))
        XCTAssertEqual(s.displayOutput, .mirrorOnly)
        XCTAssertFalse(s.voice.guidanceEnabled)
        XCTAssertEqual(s.voice.rate, VoiceSettings().rate)
        XCTAssertEqual(s.detection, DetectionSettings())
        XCTAssertFalse(s.history.enabled, "履歴は既定 OFF")
    }

    func testNotificationSettingsRoundTrip() throws {
        var s = NotificationSettings()
        s.channels[.weather] = AlertChannelSettings(showsBanner: false, speaks: true, playsSound: true)
        let data = try HUDJSON.encode(s)
        let back = try HUDJSON.decode(NotificationSettings.self, from: data)
        XCTAssertEqual(back.channel(for: .weather), AlertChannelSettings(showsBanner: false, speaks: true, playsSound: true))
        XCTAssertEqual(back.channel(for: .hazard), NotificationSettings().channel(for: .hazard))
    }

    func testSettingsBundleRejectsNewerVersion() throws {
        let bundle = SettingsBundle(version: 99, exportedAt: Date(), deviceName: "x", settings: nil, themes: [], presets: [], favorites: [])
        let data = try bundle.encoded()
        XCTAssertThrowsError(try SettingsBundle.decode(data)) { error in
            XCTAssertEqual(error as? SettingsBundleError, .newerVersion(99))
        }
    }

    func testSettingsBundleMergeKeepsBuiltIns() {
        let builtIns = BuiltInContent.themes
        var user = Theme(name: "自分", style: PanelStyle())
        let existing = builtIns + [user]
        user.name = "自分（更新）"
        let newer = Theme(name: "新規", style: PanelStyle())
        let merged = SettingsBundle.merged(existing, incoming: [user, newer], strategy: .merge, isBuiltIn: { $0.isBuiltIn })
        XCTAssertEqual(merged.count, builtIns.count + 2)
        XCTAssertEqual(merged.first { $0.id == user.id }?.name, "自分（更新）")
        let replaced = SettingsBundle.merged(existing, incoming: [newer], strategy: .replace, isBuiltIn: { $0.isBuiltIn })
        XCTAssertEqual(replaced.count, builtIns.count + 1)
    }
}

final class BuiltInContentTests: XCTestCase {
    func testSevenThemesAndPresets() {
        XCTAssertEqual(BuiltInContent.themes.count, 7)
        XCTAssertEqual(BuiltInContent.makePresets().count, 12)
        XCTAssertEqual(Set(BuiltInContent.makePresets().map(\.id)).count, 12)
        XCTAssertEqual(Set(BuiltInContent.makePresets().compactMap(\.key)), Set(BuiltInContent.presetAliases.keys))
        XCTAssertEqual(Set(BuiltInContent.themes.map(\.id)).count, 7)
    }

    func testPresetsReferToExistingThemes() {
        for preset in BuiltInContent.makePresets() {
            XCTAssertNotNil(BuiltInContent.theme(key: preset.themeRef), preset.name)
        }
    }

    func testPresetPanelsAreInsideCanvas() {
        for preset in BuiltInContent.makePresets() {
            for panel in preset.layout.panels {
                XCTAssertGreaterThanOrEqual(panel.frame.minX, 0, "\(preset.name) \(panel.widget)")
                XCTAssertLessThanOrEqual(panel.frame.maxX, 1.0001, "\(preset.name) \(panel.widget)")
                XCTAssertGreaterThanOrEqual(panel.frame.minY, 0, "\(preset.name) \(panel.widget)")
                XCTAssertLessThanOrEqual(panel.frame.maxY, 1.0001, "\(preset.name) \(panel.widget)")
            }
        }
    }

    func testWalkingPresetsKeepTheViewClear() {
        // 歩行中プリセットは画面の 15% 以下、中央の視界を塞がない
        for key in ["walkNav", "minimal"] {
            let preset = BuiltInContent.makePresets().first { $0.key == key }!
            let coverage = LayoutEngine.coverageRatio(preset.layout.panels)
            XCTAssertLessThanOrEqual(coverage, 0.20, "\(key) coverage \(coverage)")
            XCTAssertTrue(LayoutEngine.panelsBlockingCenter(preset.layout.panels).isEmpty, key)
        }
    }

    func testPresetPanelsDoNotOverlap() {
        for preset in BuiltInContent.makePresets() {
            let panels = preset.layout.panels
            for i in panels.indices {
                for j in panels.indices where j > i {
                    XCTAssertFalse(panels[i].frame.intersects(panels[j].frame), "\(preset.name): \(panels[i].widget) と \(panels[j].widget) が重なっている")
                }
            }
        }
    }

    func testBuiltInThemesAreVisibleOnGlasses() {
        for theme in BuiltInContent.themes {
            XCTAssertGreaterThanOrEqual(theme.style.textColor.glassVisibility, 0.55, theme.name)
            XCTAssertTrue(theme.visibilityWarnings.isEmpty, "\(theme.name): \(theme.visibilityWarnings)")
        }
    }

    func testPresetDuplicateGetsNewIDs() {
        let p = BuiltInContent.makePresets()[0]
        let copy = p.duplicated()
        XCTAssertNotEqual(copy.id, p.id)
        XCTAssertFalse(copy.isBuiltIn)
        XCTAssertNil(copy.key)
        XCTAssertTrue(Set(copy.layout.panels.map(\.id)).isDisjoint(with: Set(p.layout.panels.map(\.id))))
    }

    func testLayoutRequirements() {
        let layout = HUDLayout(name: "t", panels: [
            HUDPanel.make(.clock),
            HUDPanel.make(.miniMap),
            HUDPanel(widget: .detections, frame: NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1), isVisible: false),
        ])
        XCTAssertEqual(layout.activeRequirements, [.location, .heading])
    }
}
