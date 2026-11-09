import SwiftUI

/// 編集プレビュー上で、パネルの選択・移動・サイズ変更を受け付ける透明なレイヤー。
struct EditorInteractionLayer: View {
    @Environment(AppModel.self) private var model
    let canvasSize: CGSize
    @State private var dragStart: [UUID: NormalizedRect] = [:]
    @State private var resizeStart: [UUID: NormalizedRect] = [:]

    var body: some View {
        let size = HUDSize(width: canvasSize.width, height: canvasSize.height)
        let canvas = model.layout.canvas
        ZStack(alignment: .topLeading) {
            // 余白とグリッドの目安
            SafeMarginGuide(margin: canvas.safeMargin, showsGrid: canvas.snapToGrid, divisions: canvas.gridDivisions)
                .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.selectedPanelIDs = [] }

            ForEach(model.layout.panelsInDrawingOrder) { panel in
                let rect = panel.frame.denormalized(in: size)
                let selected = model.selectedPanelIDs.contains(panel.id)
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selected ? UIStyle.accent : Color.white.opacity(0.35), style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: selected ? [] : [5, 4]))
                    )
                    .overlay(alignment: .topLeading) {
                        if selected {
                            Text(panel.widget.displayName)
                                .font(.caption2.bold())
                                .padding(.horizontal, 4)
                                .background(UIStyle.accent, in: Capsule())
                                .foregroundStyle(.black)
                                .offset(y: -16)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Circle()
                                .fill(UIStyle.accent)
                                .frame(width: 22, height: 22)
                                .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.black))
                                .offset(x: 9, y: 9)
                                .gesture(resizeGesture(panel.id, size: size, canvas: canvas))
                                .accessibilityLabel("サイズ変更")
                        }
                    }
                    .frame(width: max(8, rect.width), height: max(8, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                    .onTapGesture { model.selectedPanelIDs = [panel.id] }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        if selected { model.selectedPanelIDs.remove(panel.id) } else { model.selectedPanelIDs.insert(panel.id) }
                    }
                    .gesture(moveGesture(panel.id, size: size, canvas: canvas))
                    .accessibilityLabel("\(panel.widget.displayName)のパネル")
            }
        }
    }

    private func moveGesture(_ id: UUID, size: HUDSize, canvas: CanvasSettings) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStart[id] == nil {
                    guard let frame = model.layout.panel(id: id)?.frame else { return }
                    dragStart[id] = frame
                    model.pushUndo()
                    if !model.selectedPanelIDs.contains(id) { model.selectedPanelIDs = [id] }
                }
                guard let start = dragStart[id] else { return }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                model.updatePanel(id) { $0.frame = start.offsetBy(dx: dx, dy: dy).clamped() }
            }
            .onEnded { value in
                guard let start = dragStart[id] else { return }
                let delta = HUDPoint(x: value.translation.width / size.width, y: value.translation.height / size.height)
                model.updatePanel(id) { $0.frame = LayoutEngine.moved(start, by: delta, canvas: canvas) }
                if canvas.preventOverlap { model.resolveOverlaps(pinned: id) }
                dragStart[id] = nil
            }
    }

    private func resizeGesture(_ id: UUID, size: HUDSize, canvas: CanvasSettings) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if resizeStart[id] == nil {
                    guard let frame = model.layout.panel(id: id)?.frame else { return }
                    resizeStart[id] = frame
                    model.pushUndo()
                }
                guard let start = resizeStart[id] else { return }
                var noSnap = canvas
                noSnap.snapToGrid = false
                let delta = HUDPoint(x: value.translation.width / size.width, y: value.translation.height / size.height)
                model.updatePanel(id) { $0.frame = LayoutEngine.resized(start, by: delta, canvas: noSnap) }
            }
            .onEnded { value in
                guard let start = resizeStart[id] else { return }
                let delta = HUDPoint(x: value.translation.width / size.width, y: value.translation.height / size.height)
                model.updatePanel(id) { $0.frame = LayoutEngine.resized(start, by: delta, canvas: canvas) }
                if canvas.preventOverlap { model.resolveOverlaps(pinned: id) }
                resizeStart[id] = nil
            }
    }
}

/// 余白（セーフエリア）とグリッドの目安線
struct SafeMarginGuide: View {
    let margin: Double
    let showsGrid: Bool
    let divisions: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                if showsGrid && divisions > 0 {
                    Path { path in
                        let step = max(1, divisions / 8)
                        for i in stride(from: 0, through: divisions, by: step) {
                            let x = w * Double(i) / Double(divisions)
                            let y = h * Double(i) / Double(divisions)
                            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: h))
                            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: w, y: y))
                        }
                    }
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
                Rectangle()
                    .stroke(Color.yellow.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                    .frame(width: w * (1 - 2 * margin), height: h * (1 - 2 * margin))
                    .offset(x: w * margin, y: h * margin)
                // 中央の視界（歩行中はここを空けておく）
                Rectangle()
                    .stroke(Color.green.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
                    .frame(width: w * 0.4, height: h * 0.5)
                    .offset(x: w * 0.3, y: h * 0.25)
            }
        }
    }
}
