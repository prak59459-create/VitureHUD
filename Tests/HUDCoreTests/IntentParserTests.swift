import XCTest
@testable import HUDCore

final class IntentParserTests: XCTestCase {
    let parser = IntentParser(userPresetNames: ["通勤": "user-1"])

    func check(_ text: String, _ expected: AppCommand, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(parser.parse(text), expected, "「\(text)」", file: file, line: line)
    }

    func testPlanExamples() {
        // 計画書 8-2 の例
        check("目的地を検索して", .open(.navigation).fallbackSearch)
        check("地図を大きくして", .mapZoom(.zoomIn))
        check("黒背景に変更して", .setBackground(.black))
        check("速度を表示して", .showWidget(.speed))
        check("ナビを開始して", .startNavigation)
        check("HUDをミニマルモードにして", .applyPreset(key: "minimal"))
    }

    func testBackground() {
        check("背景を黒にして", .setBackground(.black))
        check("カメラにして", .setBackground(.camera))
        check("背景をカメラに切り替えて", .setBackground(.camera))
        check("背景を切り替えて", .toggleBackground)
    }

    func testPresetsAndThemes() {
        check("徒歩ナビモードにして", .applyPreset(key: "walkNav"))
        check("旅行モード", .applyPreset(key: "travel"))
        check("通勤モードにして", .applyPreset(key: "user-1"))
        check("サイバーパンクテーマにして", .applyTheme(key: "cyberpunk"))
        check("ネオンのテーマ", .applyTheme(key: "neon"))
    }

    func testNavigation() {
        check("東京駅までナビして", .navigate(to: "東京駅"))
        check("東京タワーに行きたい", .navigate(to: "東京タワー"))
        check("ここから渋谷駅までの案内", .navigate(to: "渋谷駅"))
        check("ナビを終了して", .stopNavigation)
        check("案内をやめて", .stopNavigation)
        check("近くのコンビニを探して", .searchNearby(.convenienceStore))
        check("この辺のトイレはどこ", .searchNearby(.restroom))
        check("新宿御苑を検索して", .search("新宿御苑"))
    }

    func testToggles() {
        check("音声案内をオフにして", .setVoiceGuidance(false))
        check("ミュート", .setVoiceGuidance(false))
        check("音声案内をオンにして", .setVoiceGuidance(true))
        check("物体認識をオンにして", .setDetection(true))
        check("物体認識を止めて", .setDetection(false))
        check("危険検知をオフ", .setHazardAlerts(false))
        check("時計を消して", .hideWidget(.clock))
        check("コンパスを表示", .showWidget(.compass))
        check("地図を3Dにして", .setMap3D(true))
        check("地図を縮小", .mapZoom(.zoomOut))
        check("カメラを明るくして", .cameraExposure(.up))
    }

    func testStatusQuestions() {
        check("今何時？", .status(.time))
        check("バッテリーは？", .status(.battery))
        check("バッテリー", .status(.battery))
        check("あと何分？", .status(.eta))
        check("今日の天気は", .status(.weather))
        check("ここはどこ", .status(.location))
    }

    func testHUD() {
        check("HUDを開始して", .startHUD)
        check("ＨＵＤを終了", .stopHUD)
        check("HUDを編集", .open(.hudEditor))
        check("パネルを並べて", .autoArrange)
    }

    func testFallsBackToAssistant() {
        check("おすすめのラーメン屋は？", .ask("おすすめのラーメン屋は？"))
        check("", .cancel)
    }

    func testNormalize() {
        XCTAssertEqual(IntentParser.normalize("ＨＵＤ を　開始！"), "hudを開始")
        XCTAssertEqual(IntentParser.normalize("バッテリー"), "バッテリー")
    }
}

private extension AppCommand {
    /// 「目的地を検索して」は検索語がないので、ナビ画面を開くのが妥当。
    var fallbackSearch: AppCommand { .open(.navigation) }
}
