import Foundation

public struct HUDPanel: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var widget: WidgetKind
    public var config: WidgetConfig
    public var frame: NormalizedRect
    public var zIndex: Int
    public var isVisible: Bool
    public var opacity: Double
    public var style: PanelStyleOverride

    public init(
        id: UUID = UUID(),
        widget: WidgetKind,
        config: WidgetConfig = WidgetConfig(),
        frame: NormalizedRect,
        zIndex: Int = 0,
        isVisible: Bool = true,
        opacity: Double = 1,
        style: PanelStyleOverride = PanelStyleOverride()
    ) {
        self.id = id
        self.widget = widget
        self.config = config
        self.frame = frame
        self.zIndex = zIndex
        self.isVisible = isVisible
        self.opacity = opacity
        self.style = style
    }

    enum CodingKeys: String, CodingKey {
        case id, widget, config, frame, zIndex, isVisible, opacity, style
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        widget = try c.decode(WidgetKind.self, forKey: .widget)
        config = c.value(.config, default: WidgetConfig())
        frame = c.value(.frame, default: NormalizedRect(x: 0.4, y: 0.4, width: 0.2, height: 0.1))
        zIndex = c.value(.zIndex, default: 0)
        isVisible = c.value(.isVisible, default: true)
        opacity = c.value(.opacity, default: 1)
        style = c.value(.style, default: PanelStyleOverride())
    }

    /// ウィジェットの既定サイズで中央付近に作る。
    public static func make(_ widget: WidgetKind, at origin: HUDPoint? = nil, zIndex: Int = 0) -> HUDPanel {
        let size = widget.defaultSize
        let x = origin?.x ?? (0.5 - size.width / 2)
        let y = origin?.y ?? (0.5 - size.height / 2)
        return HUDPanel(widget: widget, frame: NormalizedRect(x: x, y: y, width: size.width, height: size.height).clamped(), zIndex: zIndex)
    }
}

/// HUDキャンバス全体の設定（グラスの見え方の調整）。
public struct CanvasSettings: Codable, Hashable, Sendable {
    /// 表示位置のずらし（キャンバス幅・高さに対する割合、-0.3〜0.3）。
    public var offsetX: Double
    public var offsetY: Double
    /// 全体の拡大率（0.5〜1.2）。グラスの視野の端が見えにくい場合に縮める。
    public var scale: Double
    /// 画面端の余白（割合）。
    public var safeMargin: Double
    /// グリッドの分割数（スナップ用）。
    public var gridDivisions: Int
    public var snapToGrid: Bool
    public var preventOverlap: Bool
    /// 1080p 換算の最小文字サイズ（px）。これより小さい文字は描画時に引き上げる。
    public var minimumFontPixels: Double
    /// 全パネルの文字の倍率（音声「文字を大きく」などで変える）
    public var textScale: Double

    public init(
        offsetX: Double = 0,
        offsetY: Double = 0,
        scale: Double = 1,
        safeMargin: Double = 0.03,
        gridDivisions: Int = 48,
        snapToGrid: Bool = true,
        preventOverlap: Bool = true,
        minimumFontPixels: Double = 22,
        textScale: Double = 1
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
        self.safeMargin = safeMargin
        self.gridDivisions = gridDivisions
        self.snapToGrid = snapToGrid
        self.preventOverlap = preventOverlap
        self.minimumFontPixels = minimumFontPixels
        self.textScale = textScale
    }

    enum CodingKeys: String, CodingKey {
        case offsetX, offsetY, scale, safeMargin, gridDivisions, snapToGrid, preventOverlap, minimumFontPixels, textScale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CanvasSettings()
        offsetX = c.value(.offsetX, default: d.offsetX)
        offsetY = c.value(.offsetY, default: d.offsetY)
        scale = c.value(.scale, default: d.scale)
        safeMargin = c.value(.safeMargin, default: d.safeMargin)
        gridDivisions = c.value(.gridDivisions, default: d.gridDivisions)
        snapToGrid = c.value(.snapToGrid, default: d.snapToGrid)
        preventOverlap = c.value(.preventOverlap, default: d.preventOverlap)
        minimumFontPixels = c.value(.minimumFontPixels, default: d.minimumFontPixels)
        textScale = c.value(.textScale, default: d.textScale)
    }

    /// 値を安全な範囲に収める。
    public func sanitized() -> CanvasSettings {
        var s = self
        s.offsetX = offsetX.clamped(to: -0.3...0.3)
        s.offsetY = offsetY.clamped(to: -0.3...0.3)
        s.scale = scale.clamped(to: 0.5...1.2)
        s.safeMargin = safeMargin.clamped(to: 0...0.2)
        s.gridDivisions = gridDivisions.clamped(to: 4...96)
        s.minimumFontPixels = minimumFontPixels.clamped(to: 10...60)
        s.textScale = textScale.clamped(to: 0.6...1.8)
        return s
    }
}

public struct HUDLayout: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var panels: [HUDPanel]
    public var canvas: CanvasSettings

    public init(id: UUID = UUID(), name: String, panels: [HUDPanel], canvas: CanvasSettings = CanvasSettings()) {
        self.id = id
        self.name = name
        self.panels = panels
        self.canvas = canvas
    }

    enum CodingKeys: String, CodingKey {
        case id, name, panels, canvas
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "レイアウト")
        panels = c.value(.panels, default: [])
        canvas = c.value(.canvas, default: CanvasSettings())
    }

    /// 描画順（zIndex 昇順）。
    public var panelsInDrawingOrder: [HUDPanel] {
        panels.sorted { $0.zIndex == $1.zIndex ? $0.id.uuidString < $1.id.uuidString : $0.zIndex < $1.zIndex }
    }

    public var visiblePanels: [HUDPanel] { panelsInDrawingOrder.filter(\.isVisible) }

    /// 表示中のウィジェットが必要とするサービス。
    public var activeRequirements: Set<WidgetRequirement> {
        visiblePanels.reduce(into: Set<WidgetRequirement>()) { $0.formUnion($1.widget.requirements) }
    }

    public func panel(id: UUID) -> HUDPanel? { panels.first { $0.id == id } }

    public mutating func update(_ panel: HUDPanel) {
        if let index = panels.firstIndex(where: { $0.id == panel.id }) {
            panels[index] = panel
        }
    }

    public var maxZIndex: Int { panels.map(\.zIndex).max() ?? 0 }
    public var minZIndex: Int { panels.map(\.zIndex).min() ?? 0 }

    public func contains(widget: WidgetKind) -> Bool {
        panels.contains { $0.widget == widget && $0.isVisible }
    }
}
