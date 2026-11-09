// swift-tools-version: 5.9

// Swift Playgrounds（iPad）で開くための定義。
// ソースは Core/（純粋ロジック）と App/（iOS アプリ）。
// 同じソースを GitHub Actions でも XcodeGen（../project.yml）経由でビルドし、IPA を作る。
// Swift Playgrounds がこのファイルを書き換えることがあるため、手で大きく変更しないこと。

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "HUD Navigator",
    platforms: [
        .iOS("18.0")
    ],
    products: [
        .iOSApplication(
            name: "HUD Navigator",
            targets: ["AppModule"],
            bundleIdentifier: "io.github.prak59459.hudnavigator.playgrounds",
            teamIdentifier: "",
            displayVersion: "0.1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .map),
            accentColor: .presetColor(.cyan),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .camera(purposeString: "HUDの背景にカメラ映像を表示し、物体認識（実験機能）を行うために使います。映像は端末内でのみ処理し、保存・送信しません。"),
                .locationWhenInUse(purposeString: "現在地の表示、ナビゲーション、速度、天気の取得に使います。位置情報は端末内で処理します。"),
                .microphone(purposeString: "音声コマンド（AIアシスタント）で話しかけるために使います。"),
                .speechRecognition(purposeString: "話した言葉を文字にして、アプリの操作に変換するために使います。"),
                .motion(purposeString: "歩行・停止などの移動状態の推定と、センサー情報の表示に使います。"),
                .bluetoothAlways(purposeString: "Bluetooth の心拍計から心拍数を受け取り、HUD に表示するために使います。")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            resources: [
                // 物体検出モデル（YOLOv3・パブリックドメイン）。初回起動時に端末でコンパイルして使う
                .copy("Resources/Models")
            ]
        )
    ]
)
