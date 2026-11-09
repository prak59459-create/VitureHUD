import Foundation

public enum AlignmentEdge: String, CaseIterable, Sendable {
    case left, right, top, bottom, centerHorizontal, centerVertical

    public var displayName: String {
        switch self {
        case .left: return "左揃え"
        case .right: return "右揃え"
        case .top: return "上揃え"
        case .bottom: return "下揃え"
        case .centerHorizontal: return "左右中央"
        case .centerVertical: return "上下中央"
        }
    }
}

/// HUDパネルの配置計算（純粋関数）。
public enum LayoutEngine {
    /// グリッドにスナップする。
    public static func snap(_ rect: NormalizedRect, gridDivisions: Int) -> NormalizedRect {
        guard gridDivisions > 0 else { return rect }
        let g = 1.0 / Double(gridDivisions)
        func s(_ v: Double) -> Double { (v / g).rounded() * g }
        var r = NormalizedRect(x: s(rect.x), y: s(rect.y), width: max(g, s(rect.width)), height: max(g, s(rect.height)))
        r = r.clamped(minSize: g)
        return r
    }

    /// 余白を考慮した範囲内に収める。
    public static func clamp(_ rect: NormalizedRect, margin: Double) -> NormalizedRect {
        let m = margin.clamped(to: 0...0.2)
        let w = min(rect.width, 1 - 2 * m)
        let h = min(rect.height, 1 - 2 * m)
        let x = rect.x.clamped(to: m...(1 - m - w))
        let y = rect.y.clamped(to: m...(1 - m - h))
        return NormalizedRect(x: x, y: y, width: w, height: h)
    }

    /// ドラッグ移動後の位置（スナップ・余白・画面端への吸着）。
    public static func moved(_ rect: NormalizedRect, by delta: HUDPoint, canvas: CanvasSettings, edgeSnapDistance: Double = 0.015) -> NormalizedRect {
        var r = rect.offsetBy(dx: delta.x, dy: delta.y)
        if canvas.snapToGrid { r = snap(r, gridDivisions: canvas.gridDivisions) }
        r = clamp(r, margin: canvas.safeMargin)
        // 余白の端に近ければ吸着
        let m = canvas.safeMargin
        if abs(r.minX - m) < edgeSnapDistance { r.x = m }
        if abs(r.maxX - (1 - m)) < edgeSnapDistance { r.x = 1 - m - r.width }
        if abs(r.minY - m) < edgeSnapDistance { r.y = m }
        if abs(r.maxY - (1 - m)) < edgeSnapDistance { r.y = 1 - m - r.height }
        return r
    }

    /// 右下ハンドルでのサイズ変更。
    public static func resized(_ rect: NormalizedRect, by delta: HUDPoint, canvas: CanvasSettings, minSize: Double = 0.04) -> NormalizedRect {
        var r = rect
        r.width = max(minSize, rect.width + delta.x)
        r.height = max(minSize, rect.height + delta.y)
        if canvas.snapToGrid {
            let g = 1.0 / Double(max(1, canvas.gridDivisions))
            r.width = max(minSize, (r.width / g).rounded() * g)
            r.height = max(minSize, (r.height / g).rounded() * g)
        }
        let m = canvas.safeMargin
        r.width = min(r.width, 1 - m - r.x)
        r.height = min(r.height, 1 - m - r.y)
        return r
    }

    /// 選択したパネルを揃える。基準は最初のパネル。
    public static func align(_ panels: [HUDPanel], edge: AlignmentEdge) -> [HUDPanel] {
        guard let reference = panels.first?.frame else { return panels }
        return panels.map { panel in
            var p = panel
            switch edge {
            case .left: p.frame.x = reference.minX
            case .right: p.frame.x = reference.maxX - p.frame.width
            case .top: p.frame.y = reference.minY
            case .bottom: p.frame.y = reference.maxY - p.frame.height
            case .centerHorizontal: p.frame.x = reference.midX - p.frame.width / 2
            case .centerVertical: p.frame.y = reference.midY - p.frame.height / 2
            }
            p.frame = p.frame.clamped()
            return p
        }
    }

    /// 重なっているパネルを、動かす量が小さい方向へ押し出して解消する。
    /// `pinned` のパネル（今ドラッグしているもの）は動かさない。
    public static func resolveOverlaps(_ panels: [HUDPanel], pinned: UUID? = nil, margin: Double = 0.03, gap: Double = 0.01, maxIterations: Int = 40) -> [HUDPanel] {
        var result = panels
        let visibleIndices = result.indices.filter { result[$0].isVisible }
        for _ in 0..<maxIterations {
            var moved = false
            for a in visibleIndices {
                for b in visibleIndices where b != a {
                    guard result[a].frame.intersects(result[b].frame) else { continue }
                    // 動かす方を決める（pinned は動かさない、それ以外は後ろの方）
                    let moverIndex: Int
                    let anchorIndex: Int
                    if result[a].id == pinned {
                        moverIndex = b; anchorIndex = a
                    } else if result[b].id == pinned {
                        moverIndex = a; anchorIndex = b
                    } else {
                        moverIndex = max(a, b); anchorIndex = min(a, b)
                    }
                    let anchor = result[anchorIndex].frame
                    var m = result[moverIndex].frame
                    // 4方向の押し出し量
                    let pushRight = anchor.maxX + gap - m.minX
                    let pushLeft = m.maxX - (anchor.minX - gap)
                    let pushDown = anchor.maxY + gap - m.minY
                    let pushUp = m.maxY - (anchor.minY - gap)
                    var options: [(Double, Double, Double)] = [
                        (pushRight, pushRight, 0),
                        (pushLeft, -pushLeft, 0),
                        (pushDown, 0, pushDown),
                        (pushUp, 0, -pushUp),
                    ]
                    // 画面外に出てしまう方向は後回し
                    options.sort { lhs, rhs in
                        let lFits = fits(m.offsetBy(dx: lhs.1, dy: lhs.2), margin: margin)
                        let rFits = fits(m.offsetBy(dx: rhs.1, dy: rhs.2), margin: margin)
                        if lFits != rFits { return lFits }
                        return lhs.0 < rhs.0
                    }
                    let choice = options[0]
                    m = clamp(m.offsetBy(dx: choice.1, dy: choice.2), margin: margin)
                    if m != result[moverIndex].frame {
                        result[moverIndex].frame = m
                        moved = true
                    }
                }
            }
            if !moved { break }
        }
        return result
    }

    static func fits(_ r: NormalizedRect, margin: Double) -> Bool {
        r.minX >= margin - 1e-9 && r.minY >= margin - 1e-9 && r.maxX <= 1 - margin + 1e-9 && r.maxY <= 1 - margin + 1e-9
    }

    /// 自動整列：画面の左右の端に沿って上から並べる（中央の視界を空ける）。
    public static func autoArrange(_ panels: [HUDPanel], margin: Double = 0.03, gap: Double = 0.015) -> [HUDPanel] {
        var result = panels
        let order = result.indices
            .filter { result[$0].isVisible }
            .sorted { result[$0].frame.area > result[$1].frame.area }
        var leftY = margin
        var rightY = margin
        var useLeft = true
        for i in order {
            var f = result[i].frame
            f.width = min(f.width, 0.3)
            f.height = min(f.height, 1 - 2 * margin)
            let goLeft: Bool
            if leftY + f.height > 1 - margin && rightY + f.height <= 1 - margin {
                goLeft = false
            } else if rightY + f.height > 1 - margin && leftY + f.height <= 1 - margin {
                goLeft = true
            } else {
                goLeft = useLeft
            }
            if goLeft {
                f.x = margin
                f.y = leftY
                leftY += f.height + gap
            } else {
                f.x = 1 - margin - f.width
                f.y = rightY
                rightY += f.height + gap
            }
            useLeft.toggle()
            result[i].frame = clamp(f, margin: margin)
        }
        return result
    }

    /// 前面へ／背面へ
    public static func bringToFront(_ id: UUID, in layout: HUDLayout) -> HUDLayout {
        var l = layout
        if let i = l.panels.firstIndex(where: { $0.id == id }) { l.panels[i].zIndex = layout.maxZIndex + 1 }
        return l
    }

    public static func sendToBack(_ id: UUID, in layout: HUDLayout) -> HUDLayout {
        var l = layout
        if let i = l.panels.firstIndex(where: { $0.id == id }) { l.panels[i].zIndex = layout.minZIndex - 1 }
        return l
    }

    /// パネルを複製（少しずらして新しいIDで追加）。
    public static func duplicate(_ id: UUID, in layout: HUDLayout, offset: Double = 0.03) -> (HUDLayout, UUID?) {
        guard let original = layout.panel(id: id) else { return (layout, nil) }
        var copy = original
        copy.id = UUID()
        copy.frame = original.frame.offsetBy(dx: offset, dy: offset).clamped()
        copy.zIndex = layout.maxZIndex + 1
        var l = layout
        l.panels.append(copy)
        return (l, copy.id)
    }

    /// パネルが画面を覆う割合（重なりは1回だけ数える）。歩行中プリセットの視界確保チェックに使う。
    public static func coverageRatio(_ panels: [HUDPanel], resolution: Int = 100) -> Double {
        let visible = panels.filter(\.isVisible)
        guard !visible.isEmpty else { return 0 }
        var covered = 0
        let n = resolution
        for yi in 0..<n {
            let y = (Double(yi) + 0.5) / Double(n)
            for xi in 0..<n {
                let x = (Double(xi) + 0.5) / Double(n)
                let p = HUDPoint(x: x, y: y)
                if visible.contains(where: { $0.frame.contains(p) }) { covered += 1 }
            }
        }
        return Double(covered) / Double(n * n)
    }

    /// 中央の視界（前方）を塞いでいるパネル。
    public static func panelsBlockingCenter(_ panels: [HUDPanel], centerRegion: NormalizedRect = NormalizedRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5)) -> [HUDPanel] {
        panels.filter { $0.isVisible && ($0.frame.intersection(centerRegion)?.area ?? 0) > centerRegion.area * 0.15 }
    }

    /// 新しいパネルを置く空き場所を探す（重ならない最初の場所）。
    public static func freeSpot(for size: (width: Double, height: Double), avoiding panels: [HUDPanel], margin: Double = 0.03, step: Double = 0.02) -> NormalizedRect {
        var y = margin
        while y + size.height <= 1 - margin + 1e-9 {
            var x = margin
            while x + size.width <= 1 - margin + 1e-9 {
                let candidate = NormalizedRect(x: x, y: y, width: size.width, height: size.height)
                if !panels.contains(where: { $0.isVisible && $0.frame.intersects(candidate) }) {
                    return candidate
                }
                x += step
            }
            y += step
        }
        return NormalizedRect(x: 0.5 - size.width / 2, y: 0.5 - size.height / 2, width: size.width, height: size.height)
    }
}
