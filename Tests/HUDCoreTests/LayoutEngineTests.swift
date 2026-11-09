import XCTest
@testable import HUDCore

final class LayoutEngineTests: XCTestCase {
    func testSnapToGrid() {
        let r = LayoutEngine.snap(NormalizedRect(x: 0.123, y: 0.456, width: 0.21, height: 0.09), gridDivisions: 10)
        XCTAssertEqual(r.x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(r.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.2, accuracy: 1e-9)
        XCTAssertEqual(r.height, 0.1, accuracy: 1e-9)
    }

    func testMoveRespectsMarginAndEdgeSnap() {
        var canvas = CanvasSettings()
        canvas.snapToGrid = false
        canvas.safeMargin = 0.05
        let r = NormalizedRect(x: 0.5, y: 0.5, width: 0.2, height: 0.1)
        let moved = LayoutEngine.moved(r, by: HUDPoint(x: 0.9, y: -0.9), canvas: canvas)
        XCTAssertEqual(moved.maxX, 0.95, accuracy: 1e-9)
        XCTAssertEqual(moved.minY, 0.05, accuracy: 1e-9)
        let nearEdge = LayoutEngine.moved(r, by: HUDPoint(x: -0.44, y: 0), canvas: canvas)
        XCTAssertEqual(nearEdge.minX, 0.05, accuracy: 1e-9, "余白の近くで吸着")
    }

    func testResizeHasMinimumAndStaysInside() {
        var canvas = CanvasSettings()
        canvas.snapToGrid = false
        let r = NormalizedRect(x: 0.8, y: 0.8, width: 0.1, height: 0.1)
        let bigger = LayoutEngine.resized(r, by: HUDPoint(x: 0.5, y: 0.5), canvas: canvas)
        XCTAssertLessThanOrEqual(bigger.maxX, 1 - canvas.safeMargin + 1e-9)
        let smaller = LayoutEngine.resized(r, by: HUDPoint(x: -0.5, y: -0.5), canvas: canvas)
        XCTAssertEqual(smaller.width, 0.04, accuracy: 1e-9)
    }

    func testResolveOverlapsSeparatesPanels() {
        let a = HUDPanel(widget: .clock, frame: NormalizedRect(x: 0.4, y: 0.4, width: 0.2, height: 0.1))
        let b = HUDPanel(widget: .battery, frame: NormalizedRect(x: 0.45, y: 0.42, width: 0.2, height: 0.1))
        let c = HUDPanel(widget: .date, frame: NormalizedRect(x: 0.42, y: 0.45, width: 0.2, height: 0.1))
        let result = LayoutEngine.resolveOverlaps([a, b, c], pinned: a.id)
        XCTAssertEqual(result[0].frame, a.frame, "固定したパネルは動かない")
        for i in result.indices {
            for j in result.indices where j > i {
                XCTAssertFalse(result[i].frame.intersects(result[j].frame), "\(i) と \(j) が重なっている")
            }
            XCTAssertTrue(LayoutEngine.fits(result[i].frame, margin: 0.03))
        }
    }

    func testAutoArrangeKeepsCenterClear() {
        let panels = (0..<6).map { i in
            HUDPanel(widget: WidgetKind.allCases[i], frame: NormalizedRect(x: 0.4, y: 0.4, width: 0.15, height: 0.1))
        }
        let arranged = LayoutEngine.autoArrange(panels)
        XCTAssertTrue(LayoutEngine.panelsBlockingCenter(arranged).isEmpty)
        for i in arranged.indices {
            for j in arranged.indices where j > i {
                XCTAssertFalse(arranged[i].frame.intersects(arranged[j].frame))
            }
        }
    }

    func testAlign() {
        let a = HUDPanel(widget: .clock, frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1))
        let b = HUDPanel(widget: .date, frame: NormalizedRect(x: 0.5, y: 0.3, width: 0.1, height: 0.1))
        let left = LayoutEngine.align([a, b], edge: .left)
        XCTAssertEqual(left[1].frame.x, 0.1, accuracy: 1e-9)
        let right = LayoutEngine.align([a, b], edge: .right)
        XCTAssertEqual(right[1].frame.maxX, 0.3, accuracy: 1e-9)
        let center = LayoutEngine.align([a, b], edge: .centerHorizontal)
        XCTAssertEqual(center[1].frame.midX, 0.2, accuracy: 1e-9)
    }

    func testZOrderAndDuplicate() {
        let a = HUDPanel(widget: .clock, frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), zIndex: 0)
        let b = HUDPanel(widget: .date, frame: NormalizedRect(x: 0.5, y: 0.3, width: 0.1, height: 0.1), zIndex: 1)
        var layout = HUDLayout(name: "t", panels: [a, b])
        layout = LayoutEngine.bringToFront(a.id, in: layout)
        XCTAssertEqual(layout.panelsInDrawingOrder.last?.id, a.id)
        layout = LayoutEngine.sendToBack(a.id, in: layout)
        XCTAssertEqual(layout.panelsInDrawingOrder.first?.id, a.id)
        let (dup, newID) = LayoutEngine.duplicate(b.id, in: layout)
        XCTAssertEqual(dup.panels.count, 3)
        XCTAssertNotNil(newID)
        XCTAssertEqual(dup.panel(id: newID!)?.widget, .date)
    }

    func testCoverage() {
        let full = HUDPanel(widget: .clock, frame: .full)
        XCTAssertEqual(LayoutEngine.coverageRatio([full]), 1, accuracy: 1e-9)
        let quarter = HUDPanel(widget: .clock, frame: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(LayoutEngine.coverageRatio([quarter, quarter]), 0.25, accuracy: 0.01, "重なりは1回だけ数える")
    }

    func testFreeSpotAvoidsExisting() {
        let existing = [HUDPanel(widget: .clock, frame: NormalizedRect(x: 0.03, y: 0.03, width: 0.3, height: 0.2))]
        let spot = LayoutEngine.freeSpot(for: (0.2, 0.1), avoiding: existing)
        XCTAssertFalse(spot.intersects(existing[0].frame))
    }
}
