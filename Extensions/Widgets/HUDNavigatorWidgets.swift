import WidgetKit
import SwiftUI
import AppIntents

// ホーム画面・ロック画面のウィジェットと、コントロールセンターのボタン。
// どれも hudnavigator:// の URL でアプリを開いて操作する（アプリのデータは読まない）。
// 正式アプリの「ウィジェット付き」IPA にだけ含まれる（Swift Playgrounds 版にはない）。

struct QuickAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let url: URL

    init(_ id: String, _ title: String, _ symbol: String, _ path: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.url = URL(string: "hudnavigator://" + path)!
    }

    static let hud = QuickAction("hud", "HUD", "eyeglasses", "hud/start")
    static let background = QuickAction("background", "背景", "circle.lefthalf.filled", "background/toggle")
    static let voice = QuickAction("voice", "話しかける", "mic.fill", "voice")
    static let preset = QuickAction("preset", "次の表示", "square.stack", "preset/next")
    static let walk = QuickAction("walk", "徒歩ナビ", "figure.walk", "preset/walkNav")
    static let guidance = QuickAction("guidance", "もう一度", "arrow.counterclockwise", "guidance")

    static let nearby: [QuickAction] = [
        QuickAction("conv", "コンビニ", "bag", "nearby/convenienceStore"),
        QuickAction("cafe", "カフェ", "cup.and.saucer", "nearby/cafe"),
        QuickAction("restroom", "トイレ", "toilet", "nearby/restroom"),
        QuickAction("station", "駅", "tram", "nearby/station"),
    ]
}

struct StaticEntry: TimelineEntry {
    let date: Date
}

struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticEntry { StaticEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (StaticEntry) -> Void) {
        completion(StaticEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        completion(Timeline(entries: [StaticEntry(date: Date())], policy: .never))
    }
}

private let accent = Color(red: 0.0, green: 0.9, blue: 1.0)

struct ActionTile: View {
    let action: QuickAction
    var body: some View {
        Link(destination: action.url) {
            VStack(spacing: 4) {
                Image(systemName: action.symbol)
                    .font(.title3.weight(.semibold))
                Text(action.title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct LauncherView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "eyeglasses").font(.title2.weight(.semibold))
            }
            .widgetURL(QuickAction.hud.url)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("HUD Navigator", systemImage: "eyeglasses").font(.headline)
                Text("タップで HUD を開始").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(QuickAction.hud.url)
        case .accessoryInline:
            Label("HUD を開始", systemImage: "eyeglasses")
                .widgetURL(QuickAction.hud.url)
        case .systemSmall:
            VStack(spacing: 6) {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(accent)
                Text("HUD を開始")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("グラスをつないでタップ")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .widgetURL(QuickAction.hud.url)
        default:
            let actions: [QuickAction] = family == .systemLarge
                ? [.hud, .background, .voice, .preset, .walk, .guidance]
                : [.hud, .background, .voice, .preset]
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: family == .systemLarge ? 3 : 4)
            VStack(alignment: .leading, spacing: 8) {
                Label("HUD Navigator", systemImage: "eyeglasses")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(actions) { ActionTile(action: $0).frame(height: family == .systemLarge ? 90 : 64) }
                }
                if family == .systemLarge {
                    Text("近くを探す")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(QuickAction.nearby) { ActionTile(action: $0).frame(height: 64) }
                    }
                }
            }
        }
    }
}

struct NearbyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("近くを探す", systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 8) {
                ForEach(QuickAction.nearby) { ActionTile(action: $0) }
            }
        }
    }
}

struct LauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HUDNavigatorLauncher", provider: StaticProvider()) { _ in
            LauncherView()
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("HUD Navigator")
        .description("HUD の開始・背景の切り替え・音声操作をワンタップで。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NearbyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HUDNavigatorNearby", provider: StaticProvider()) { _ in
            NearbyView()
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("近くを探す")
        .description("近くのコンビニ・カフェ・トイレ・駅を探して HUD に表示します。")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - コントロールセンター（iOS 18）

/// コントロールのボタンから URL でアプリを開く
struct OpenHUDActionIntent: AppIntent {
    static var title: LocalizedStringResource = "HUD Navigator の操作"
    static var isDiscoverable: Bool = false

    @Parameter(title: "操作")
    var path: String

    init() { path = "hud/start" }
    init(path: String) { self.path = path }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "hudnavigator://" + path)!))
    }
}

struct HUDStartControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.prak59459.hudnavigator.control.hud") {
            ControlWidgetButton(action: OpenHUDActionIntent(path: "hud/start")) {
                Label("HUD を開始", systemImage: "eyeglasses")
            }
        }
        .displayName("HUD を開始")
        .description("HUD Navigator を開いて HUD を表示します。")
    }
}

struct VoiceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.prak59459.hudnavigator.control.voice") {
            ControlWidgetButton(action: OpenHUDActionIntent(path: "voice")) {
                Label("HUD に話しかける", systemImage: "mic.fill")
            }
        }
        .displayName("HUD に話しかける")
        .description("HUD Navigator のアシスタントを開きます。")
    }
}

@main
struct HUDNavigatorWidgetBundle: WidgetBundle {
    var body: some Widget {
        LauncherWidget()
        NearbyWidget()
        HUDStartControl()
        VoiceControl()
    }
}
