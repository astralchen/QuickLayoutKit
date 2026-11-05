import Testing
import UIKit
import QuickLayoutKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct GeometryAdaptiveGridTests {
    @Test func columnBreakpointsUseAvailableWidth() {
        for (width, columns) in [(0.0, 1), (103, 1), (219, 1), (220, 2), (335, 2),
                                 (336, 3), (451, 3), (452, 4), (1200, 4)] {
            let metrics = GeometryAdaptiveGridMetrics(size: CGSize(width: width, height: 328))
            #expect(metrics.columns == columns)
            #expect(metrics.rows == (6 + columns - 1) / columns)
            #expect(metrics.cellSize.width >= 0)
        }
    }

    @Test func resizingKeepsCardIdentityAndIncompleteRowColumnWidths() async throws {
        let grid = GeometryAdaptiveGridView()
        let window = mount(grid)
        defer { window.isHidden = true }
        var original: [UILabel] = []
        for (width, columns) in [(180.0, 1), (280, 2), (400, 3), (600, 4)] {
            grid.frame.size = CGSize(width: width, height: 360)
            grid.setNeedsQuickLayout()
            await settle(grid)
            let cards = cardViews(grid)
            #expect(cards.count == 6)
            if original.isEmpty { original = cards }
            #expect(cards.map(ObjectIdentifier.init) == original.map(ObjectIdentifier.init))
            let metrics = try #require(grid.metrics)
            #expect(metrics.columns == columns)
            for (index, card) in cards.enumerated() {
                #expect(card.superview === grid)
                #expect(abs(card.frame.width - metrics.cellSize.width) < 0.5)
                #expect(abs(card.frame.height - metrics.cellSize.height) < 0.5)
                #expect(abs(card.frame.minX - (16 + CGFloat(index % columns) * (metrics.cellSize.width + 12))) < 0.5)
                #expect(abs(card.frame.minY - (16 + CGFloat(index / columns) * (metrics.cellSize.height + 12))) < 0.5)
                #expect(grid.bounds.contains(card.frame))
            }
        }
    }

    @Test func paddingChangesColumnsAndRTLReversesEachRow() async throws {
        let grid = GeometryAdaptiveGridView()
        let window = mount(grid)
        defer { window.isHidden = true }
        grid.frame.size = CGSize(width: 400, height: 360)
        await settle(grid)
        #expect(grid.metrics?.columns == 3)
        grid.contentInset = 48
        grid.semanticContentAttribute = .forceRightToLeft
        grid.setNeedsQuickLayout()
        await settle(grid)
        let metrics = try #require(grid.metrics)
        #expect(metrics.columns == 2)
        let cards = cardViews(grid)
        #expect(cards.count == 6)
        for (index, card) in cards.enumerated() {
            let trailing = 400 - 48 - CGFloat(index % 2) * (metrics.cellSize.width + 12)
            #expect(abs(card.frame.maxX - trailing) < 0.5)
            #expect(grid.bounds.contains(card.frame))
        }
    }

    private func cardViews(_ grid: UIView) -> [UILabel] {
        grid.subviews.compactMap { $0 as? UILabel }.sorted { ($0.accessibilityIdentifier ?? "") < ($1.accessibilityIdentifier ?? "") }
    }

    private func mount(_ view: UIView) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        }
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        controller.view.addSubview(view)
        view.frame = CGRect(x: 0, y: 100, width: 400, height: 360)
        return window
    }

    private func settle(_ view: UIView) async {
        for _ in 0..<8 {
            view.window?.layoutIfNeeded()
            view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
