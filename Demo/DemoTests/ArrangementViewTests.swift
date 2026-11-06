#if compiler(>=6.4)
import QuickLayoutKit
@testable import QuickLayoutKitUIKit
import SwiftUI
import Testing
import UIKit
@testable import Demo

@MainActor
struct ArrangementViewTests {
    @Test func placementHonorsDivisionEdgesAndAxisRestrictions() {
        let panes = QuickLayoutKit.ArrangementViewStyleConfiguration(
            primary: UIView().resizable().overlayArrangementEdge(QuickLayoutKit.HorizontalEdge.trailing),
            secondary: UIView().resizable()
        )
        let rect = CGRect(x: 10, y: 20, width: 600, height: 480)
        let gap = CGRect(x: 250, y: 0, width: 10, height: 900)
        func resolve(_ kind: ArrangementKind, _ axes: QuickLayoutKit.AxisSet, rtl: Bool = false) -> ArrangementPlacement {
            ArrangementPlacement.resolve(panes: panes, style: kind, axes: axes, rect: rect, divisions: [gap],
                                         horizontal: .regular, vertical: .regular, rtl: rtl)
        }
        let split = resolve(.split, .horizontal)
        #expect(split.axis == .horizontal && split.primary.maxX == gap.minX && split.secondary?.minX == gap.maxX)
        #expect(resolve(.overlay, .horizontal).primary == split.secondary)
        #expect(resolve(.overlay, .horizontal, rtl: true).primary == split.primary)
        let restricted = resolve(.split, .vertical)
        #expect(restricted.axis == .horizontal && restricted.secondary == nil)
        let fractional = ArrangementPlacement.resolve(
            panes: panes, style: .split, axes: .horizontal, rect: rect,
            divisions: [gap.offsetBy(dx: 0.5, dy: 0)], horizontal: .regular, vertical: .regular, rtl: false, scale: 3)
        #expect(abs(fractional.primary.maxX - 752.0 / 3) < 0.001)
        #expect(abs((fractional.secondary?.minX ?? 0) - 782.0 / 3) < 0.001)
        #expect(resolve(.overlay, .vertical).primary == rect && resolve(.overlay, .vertical).secondary == rect)

        // 同一条竖向分隔带穿过较高的容器时，split 仍沿垂直轴上下排列。
        let tall = CGRect(x: 10, y: 20, width: 600, height: 800)
        let column = ArrangementPlacement.resolve(panes: panes, style: .split, axes: [.horizontal, .vertical],
            rect: tall, divisions: [gap], horizontal: .regular, vertical: .regular, rtl: false)
        #expect(column.axis == .vertical && column.primary.width == tall.width)
        #expect(column.primary.maxY == column.secondary?.minY)
    }

    @Test func divisionMustSpanThePartOfThePreviewInsideTheWindow() {
        let panes = QuickLayoutKit.ArrangementViewStyleConfiguration(
            primary: UIView().resizable(), secondary: UIView().resizable()
        )
        let rect = CGRect(x: 0, y: 0, width: 540, height: 490)
        let window = CGRect(x: -287, y: -215, width: 951, height: 669)
        let fold = CGRect(x: 169, y: window.minY, width: 40, height: window.height)
        func placement(_ region: CGRect) -> ArrangementPlacement {
            ArrangementPlacement.resolve(panes: panes, style: .split, axes: [.horizontal, .vertical],
                rect: rect, divisions: [region], windowBounds: window,
                horizontal: .regular, vertical: .regular, rtl: false)
        }
        let crossing = placement(fold)
        #expect(crossing.primary == CGRect(x: 0, y: 0, width: 169, height: 490))
        #expect(crossing.secondary == CGRect(x: 209, y: 0, width: 331, height: 490))
        // 短于可见范围的分隔带不能把两个区域推开。
        #expect(placement(fold.insetBy(dx: 0, dy: 20)).primary.width == 270)
    }

    @Test func divisionRespectsPaneRangesAndKeepsAxisWhenSecondaryDoesNotFit() {
        let panes = QuickLayoutKit.ArrangementViewStyleConfiguration(
            primary: UIView().resizable().splitArrangementLayoutRatio(
                minHorizontal: 0.4, idealHorizontal: 0.6, maxHorizontal: 0.8),
            secondary: UIView().resizable()
        )
        let rect = CGRect(x: 0, y: 0, width: 540, height: 340)
        func resolve(at x: CGFloat) -> ArrangementPlacement {
            ArrangementPlacement.resolve(panes: panes, style: .split, axes: .horizontal, rect: rect,
                divisions: [CGRect(x: x, y: 0, width: 40, height: 340)],
                horizontal: .regular, vertical: .regular, rtl: false)
        }
        let narrow = resolve(at: 169)
        #expect(narrow.primary == CGRect(x: 40, y: 0, width: 324, height: 340))
        #expect(narrow.secondary == CGRect(x: 364, y: 0, width: 7, height: 340))
        let single = resolve(at: 195)
        #expect(single.primary == CGRect(x: 40, y: 0, width: 305, height: 340))
        #expect(single.secondary == nil && single.axis == .horizontal)
        let wide = resolve(at: 450)
        #expect(wide.primary.width == 324 && wide.secondary?.width == 126)
    }

    @available(iOS 27.1, *)
    @Test func splitMatchesNativePaneFramesThroughWindowChanges() async throws {
        let first = UIView(), second = UIView()
        let nativeFirst = UIView(), nativeSecond = UIView()
        let kit = QuickLayoutView {
            QuickLayoutKit.ArrangementView {
                first.resizable().splitArrangementLayoutRatio(0.54)
            } secondary: {
                second.resizable()
            }.arrangementViewStyle(.split)
        }
        let reference = UIHostingConfiguration {
            SwiftUI.ArrangementView {
                ReferencePane(view: nativeFirst).splitArrangementLayoutRatio(0.54)
            } secondary: {
                ReferencePane(view: nativeSecond)
            }.arrangementViewStyle(.split)
        }.margins(.all, 0).makeContentView()
        let root = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: root)
        defer { window.isHidden = true }
        root.view.addSubview(reference)
        root.view.addSubview(kit)
        for size in [CGSize(width: 390, height: 750), CGSize(width: 669, height: 830),
                     CGSize(width: 669, height: 720), CGSize(width: 844, height: 300),
                     CGSize(width: 1024, height: 680),
                     CGSize(width: 390, height: 750)] {
            reference.frame = CGRect(origin: .zero, size: size)
            kit.frame = reference.frame
            try await settle(kit, reference)
            let a = first.convert(first.bounds, to: kit)
            let b = second.convert(second.bounds, to: kit)
            let nativeA = nativeFirst.convert(nativeFirst.bounds, to: reference)
            let nativeB = nativeSecond.convert(nativeSecond.bounds, to: reference)
            #expect(a.width > 0 && a.height > 0)
            expectEqual(a, nativeA)
            expectEqual(b, nativeB)
            #expect(first.splitArrangementAxis == (nativeA.maxX <= nativeB.minX + 1 ? .horizontal : .vertical))
            print("Arrangement parity: proposal=\(size), primary=\(a), secondary=\(b)")
        }
    }

    @available(iOS 27.1, *)
    @Test func styleCanForwardItsConfigurationAndPaneConstraints() async throws {
        let first = UIView(), second = UIView()
        let nativeFirst = UIView(), nativeSecond = UIView()
        let kit = QuickLayoutView {
            QuickLayoutKit.ArrangementView {
                first.resizable().splitArrangementLayoutSize(minWidth: 100, idealWidth: 180, maxWidth: 230)
                    .splitArrangementLayoutRatio(minHorizontal: 0.2, maxHorizontal: 0.6)
            } secondary: {
                second.resizable()
            }.arrangementViewStyle(ForwardingStyle())
        }
        let native = UIHostingConfiguration {
            SwiftUI.ArrangementView {
                ReferencePane(view: nativeFirst).splitArrangementLayoutSize(minWidth: 100, idealWidth: 180, maxWidth: 230)
                    .splitArrangementLayoutRatio(minHorizontal: 0.2, maxHorizontal: 0.6)
            } secondary: { ReferencePane(view: nativeSecond) }.arrangementViewStyle(.split)
        }.margins(.all, 0).makeContentView()
        let root = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: root)
        defer { window.isHidden = true }
        root.view.addSubview(kit)
        root.view.addSubview(native)
        kit.frame = CGRect(x: 0, y: 0, width: 700, height: 350)
        native.frame = kit.frame
        try await settle(kit, native)
        expectEqual(first.convert(first.bounds, to: kit), nativeFirst.convert(nativeFirst.bounds, to: native))
        expectEqual(second.convert(second.bounds, to: kit), nativeSecond.convert(nativeSecond.bounds, to: native))
    }

    @available(iOS 27.1, *)
    @Test func automaticMatchesNativeForCompetingPreferences() async throws {
        let root = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: root)
        defer { window.isHidden = true }
        for (ratio, priority) in [(0.7 as CGFloat?, -1.0), (0.7, 0.0), (0.7, 1.0), (nil, 0.0)] {
            let p = UIView(), s = UIView(), nativeP = UIView(), nativeS = UIView()
            let kit = QuickLayoutView {
                QuickLayoutKit.ArrangementView {
                    p.resizable().layoutPriority(priority).splitArrangementLayoutRatio(ratio)
                } secondary: { s.resizable().splitArrangementLayoutRatio(0.6) }
            }
            let native = UIHostingConfiguration {
                SwiftUI.ArrangementView {
                    ReferencePane(view: nativeP).layoutPriority(priority).splitArrangementLayoutRatio(ratio)
                } secondary: { ReferencePane(view: nativeS).splitArrangementLayoutRatio(0.6) }
            }.margins(.all, 0).makeContentView()
            root.view.addSubview(native)
            root.view.addSubview(kit)
            kit.frame = CGRect(x: 0, y: 0, width: 390, height: 750)
            native.frame = kit.frame
            try await settle(kit, native)
            expectEqual(p.convert(p.bounds, to: kit), nativeP.convert(nativeP.bounds, to: native))
            expectEqual(s.convert(s.bounds, to: kit), nativeS.convert(nativeS.bounds, to: native))
            kit.removeFromSuperview()
            native.removeFromSuperview()
        }
    }

    @Test func customStyleCanReuseConfigurationThroughAnAncestor() async throws {
        let first = UIView(), second = UIView()
        let host = QuickLayoutView {
            QuickLayoutKit.ZStack {
                QuickLayoutKit.ArrangementView { first.resizable() } secondary: { second.resizable() }
            }.arrangementViewStyle(LeadingBadgeStyle())
        }
        let root = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: root)
        defer { window.isHidden = true }
        root.view.addSubview(host)
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        try await settle(host)
        #expect(first.frame.width == 80 && second.frame.width == 40)
        #expect(second.frame.minX - first.frame.maxX == 8)
    }

    @available(iOS 27.1, *)
    @Test func restrictedSplitAndOverlayMatchNative() async throws {
        for overlay in [false, true] {
            let first = UIView(), second = UIView()
            let nativeFirst = UIView(), nativeSecond = UIView()
            let kit = QuickLayoutView {
                let panes = QuickLayoutKit.ArrangementView {
                    first.resizable().overlayArrangementEdge(QuickLayoutKit.HorizontalEdge.trailing)
                } secondary: { second.resizable() }
                if overlay { panes.arrangementViewStyle(.overlay.axes([])) }
                else { panes.arrangementViewStyle(.split.axes(.horizontal)) }
            }
            let native = UIHostingConfiguration {
                let panes = SwiftUI.ArrangementView {
                    ReferencePane(view: nativeFirst).overlayArrangementEdge(SwiftUI.HorizontalEdge.trailing)
                } secondary: { ReferencePane(view: nativeSecond) }
                if overlay { panes.arrangementViewStyle(.overlay.axes([])) }
                else { panes.arrangementViewStyle(.split.axes(.horizontal)) }
            }.margins(.all, 0).makeContentView()
            let root = UIViewController()
            let window = try makeVisibleTestWindow(rootViewController: root)
            defer { window.isHidden = true }
            root.view.addSubview(native)
            root.view.addSubview(kit)
            kit.frame = CGRect(x: 0, y: 0, width: 390, height: 750)
            native.frame = kit.frame
            try await settle(kit, native)
            expectEqual(first.convert(first.bounds, to: kit), nativeFirst.convert(nativeFirst.bounds, to: native))
            #expect(second.isDescendant(of: kit) == nativeSecond.isDescendant(of: native))
            if overlay { #expect(first.overlayArrangementZIndex > second.overlayArrangementZIndex) }
            if second.isDescendant(of: kit) {
                expectEqual(second.convert(second.bounds, to: kit), nativeSecond.convert(nativeSecond.bounds, to: native))
            }
        }
    }

    private func settle(_ views: UIView...) async throws {
        for _ in 0..<3 {
            for view in views { view.setNeedsLayout(); view.layoutIfNeeded() }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    private func expectEqual(_ actual: CGRect, _ expected: CGRect, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(actual.minX - expected.minX) <= 1 && abs(actual.minY - expected.minY) <= 1 &&
                abs(actual.width - expected.width) <= 1 && abs(actual.height - expected.height) <= 1,
                "actual=\(actual), SwiftUI=\(expected)", sourceLocation: sourceLocation)
    }
}

@available(iOS 27.1, *)
private struct ReferencePane: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 10, height: proposal.height ?? 10)
    }
}

private struct LeadingBadgeStyle: QuickLayoutKit.ArrangementViewStyle {
    func makeBody(configuration: Configuration) -> some QuickLayoutKit.Layout {
        QuickLayoutKit.HStack(spacing: 8) {
            configuration.primary.frame(width: 80)
            configuration.secondary.frame(width: 40)
        }
    }
}

private struct ForwardingStyle: QuickLayoutKit.ArrangementViewStyle {
    func makeBody(configuration: Configuration) -> some QuickLayoutKit.Layout {
        QuickLayoutKit.ArrangementView(configuration).arrangementViewStyle(.split)
    }
}
#endif
