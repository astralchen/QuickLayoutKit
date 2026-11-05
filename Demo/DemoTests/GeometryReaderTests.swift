import Testing
import SwiftUI
import QuickLayoutKit
import QuickLayout
import QuickLayoutCore
import UIKit

@MainActor
@Suite(.serialized)
struct GeometryReaderTests {
    @Test func proposalAndMeasurementAreIndependentOfContent() {
        var builds = 0
        let child = UIView()
        let reader = QuickLayoutKit.GeometryReader { proxy in
            let _ = { builds += 1 }()
            child.resizable().frame(width: 900, height: proxy.size.height * 2)
        }
        for (proposal, expected) in [
            (CGSize(width: 240, height: 120), CGSize(width: 240, height: 120)),
            (CGSize(width: CGFloat.infinity, height: 120), CGSize(width: 10, height: 120)),
            (CGSize(width: 240, height: CGFloat.infinity), CGSize(width: 240, height: 10)),
            (CGSize(width: CGFloat.infinity, height: CGFloat.infinity), CGSize(width: 10, height: 10)),
            (.zero, .zero),
            (CGSize(width: -2, height: CGFloat.nan), .zero),
            (CGSize(width: CGFloat.greatestFiniteMagnitude, height: 80), CGSize(width: 10, height: 80))
        ] {
            #expect(reader.layoutThatFits(proposal).size == expected)
        }
        #expect(builds == 7)
        #expect(child.superview == nil)
        #expect(reader.quick_flexibility(for: .horizontal) == .fullyFlexible)
        #expect(reader.quick_flexibility(for: .vertical) == .fullyFlexible)
        #expect(reader.fixedSize().layoutThatFits(CGSize(width: 300, height: 200)).size == CGSize(width: 10, height: 10))
    }

    @Test func relativeContentResizesAndDirectChildrenOverlap() async {
        let a = UIView(), b = UIView()
        var size = CGSize.zero
        let host = QuickLayoutView {
            QuickLayoutKit.GeometryReader { proxy in
                let _ = { size = proxy.size }()
                a.resizable().frame(width: proxy.size.width / 2, height: 40)
                b.resizable().frame(width: 30, height: 20)
            }
        }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        #expect(size == host.bounds.size)
        #expect(a.frame == CGRect(x: 0, y: 0, width: 120, height: 40))
        #expect(b.frame == CGRect(x: 0, y: 0, width: 30, height: 20))
        let readerHost = a.superview
        host.frame.size.width = 360
        host.setNeedsQuickLayout()
        await settle(host)
        #expect(a.frame.width == 180)
        #expect(a.superview === readerHost)
    }

    @Test func rtlAndAlignmentGuidesDoNotDisplaceLeadingOrigin() async {
        let child = UIView()
        let host = QuickLayoutView {
            QuickLayoutKit.GeometryReader { _ in
                child.resizable().frame(width: 40, height: 20)
                    .alignmentGuide(QuickLayoutCore.HorizontalAlignment.leading) { _ in 99 }
                    .alignmentGuide(QuickLayoutCore.VerticalAlignment.top) { _ in 77 }
            }.layoutDirection(.rightToLeft)
        }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        #expect(child.frame == CGRect(x: 200, y: 0, width: 40, height: 20))
    }

    @Test func conditionalChildrenAreRemovedAndClosureIsReplaced() async {
        let wide = UIView(), narrow = UIView()
        var useWide = true
        let host = QuickLayoutView {
            let selected = useWide
            QuickLayoutKit.GeometryReader { proxy in
                if selected && proxy.size.width > 150 {
                    wide.resizable().frame(height: 30)
                } else {
                    narrow.resizable().frame(height: 20)
                }
            }
        }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        let reader = wide.superview
        #expect(reader != nil)
        useWide = false
        host.setNeedsQuickLayout()
        await settle(host)
        #expect(wide.superview == nil)
        #expect(narrow.superview === reader)
    }

    @Test func sameCallSiteReadersHaveSeparateIdentityAndNestedReadersWork() async {
        let children = [UIView(), UIView()]
        let host = QuickLayoutView {
            HStack(spacing: 0) {
                for child in children {
                    QuickLayoutKit.GeometryReader { outer in
                        QuickLayoutKit.GeometryReader { inner in
                            child.resizable().frame(width: inner.size.width, height: outer.size.height)
                        }
                    }
                }
            }
        }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        #expect(children.allSatisfy { $0.superview === host })
        #expect(children.allSatisfy { $0.frame.size == CGSize(width: 120, height: 120) })
        let parents = children.map(\.superview)
        host.setNeedsQuickLayout()
        await settle(host)
        #expect(children[0].superview === parents[0])
        #expect(children[1].superview === parents[1])
    }

    @Test func overflowDoesNotChangeContainerOrClipContent() async {
        let child = UIView()
        var size = CGSize.zero
        let host = QuickLayoutView {
            QuickLayoutKit.GeometryReader { proxy in
                let _ = { size = proxy.size }()
                child.resizable().frame(width: 400, height: 200)
            }.frame(width: 100, height: 60)
        }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        #expect(size == CGSize(width: 100, height: 60))
        #expect(child.frame == CGRect(x: 70, y: 30, width: 400, height: 200))
        #expect(child.superview?.clipsToBounds == false)
    }

    @Test func namedGlobalAndSafeAreaGeometryTracksAncestorMovement() async {
        var proxy: QuickLayoutKitCore.GeometryProxy?
        let child = UIView()
        let host = QuickLayoutView {
            QuickLayoutKit.GeometryReader { value in
                let _ = { proxy = value }()
                child.resizable()
            }.padding(12).coordinateSpace(.named("stage"))
        }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        #expect(proxy?.frame(in: .named("stage")) == CGRect(x: 12, y: 12, width: 216, height: 96))
        #expect(proxy?.bounds(of: .named("stage")) == CGRect(x: -12, y: -12, width: 240, height: 120))
        let old = proxy?.frame(in: .global)
        host.center.y += 37
        await settle(host)
        #expect(proxy?.frame(in: .global).minY == (old?.minY ?? 0) + 37)
        #expect(proxy?.safeAreaInsets.top == child.superview?.safeAreaInsets.top)
    }

    @Test func scrollAxisUsesIdealTenAndExplicitFrameOverridesIt() async {
        let scroll = QuickLayoutScrollView(.vertical)
        let child = UIView()
        var size = CGSize.zero
        var explicit = false
        let host = QuickLayoutView {
            ScrollView(scroll) {
                QuickLayoutKit.GeometryReader { proxy in
                    let _ = { size = proxy.size }()
                    child.resizable()
                }.frame(height: explicit ? 90 : nil)
            }
        }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        #expect(size == CGSize(width: 240, height: 10))
        explicit = true
        host.setNeedsQuickLayout()
        await settle(host)
        #expect(size == CGSize(width: 240, height: 90))
    }

    @Test func horizontalScrollUpdatesGlobalFrameWithoutResizingReader() async {
        let scroll = QuickLayoutScrollView(.horizontal)
        var proxy: QuickLayoutKitCore.GeometryProxy?
        let child = UIView()
        let host = QuickLayoutView {
            ScrollView(scroll, .horizontal) {
                QuickLayoutKit.GeometryReader { value in
                    let _ = { proxy = value }()
                    child.resizable()
                }.frame(width: 600)
            }
        }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        #expect(proxy?.size == CGSize(width: 600, height: 120))
        let old = proxy?.frame(in: .global)
        scroll.setContentOffset(CGPoint(x: 70, y: 0), animated: false)
        await settle(host)
        #expect(proxy?.frame(in: .global).minX == (old?.minX ?? 0) - 70)
        #expect(proxy?.size == CGSize(width: 600, height: 120))
    }

    @Test func safeAreaChangesReachReaderContent() async {
        var top: CGFloat = -1
        let child = UIView()
        let host = QuickLayoutView {
            QuickLayoutKit.GeometryReader { proxy in
                let _ = { top = proxy.safeAreaInsets.top }()
                child.resizable()
            }
        }
        let window = mount(host, size: CGSize(width: 240, height: 240))
        defer { window.isHidden = true }
        host.frame.origin.y = 0
        await settle(host)
        let initial = top
        window.rootViewController?.additionalSafeAreaInsets.top += 40
        await settle(host)
        #expect(top >= initial + 39)
        #expect(top == child.superview?.safeAreaInsets.top)
    }

    @Test func backgroundReaderDoesNotExpandPrimaryContent() async {
        let primary = UIView(), overlay = UIView()
        var size = CGSize.zero
        let host = QuickLayoutView {
            primary.resizable().frame(width: 80, height: 40)
                .background {
                    QuickLayoutKit.GeometryReader { proxy in
                        let _ = { size = proxy.size }()
                        overlay.resizable()
                    }
                }
        }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        #expect(size == CGSize(width: 80, height: 40))
        #expect(primary.frame.size == size)
        #expect(overlay.frame.size == size)
    }

    @Test func swiftUIReferenceMatchesIdealSizeAndRelativePlacement() async {
        var ideal: CGSize?, relative: CGSize?, childFrame: CGRect?
        let reference = SwiftUI.VStack(spacing: 0) {
            SwiftUI.GeometryReader { proxy in
                SwiftUI.Color.clear.onAppear { ideal = proxy.size }
            }.fixedSize()
            SwiftUI.GeometryReader { proxy in
                SwiftUI.Color.clear
                    .frame(width: proxy.size.width / 2, height: 40)
                    .background {
                        SwiftUI.GeometryReader { child in
                            SwiftUI.Color.clear.onAppear {
                                relative = proxy.size
                                childFrame = child.frame(in: .named("reference"))
                            }
                        }
                    }
            }.frame(width: 240, height: 120).coordinateSpace(name: "reference")
        }
        let controller = UIHostingController(rootView: reference)
        let window = makeWindow()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        await settle(controller.view)
        #expect(ideal == CGSize(width: 10, height: 10))
        #expect(relative == CGSize(width: 240, height: 120))
        expectReferenceFrame(childFrame, CGRect(x: 0, y: 0, width: 120, height: 40), in: window)
    }

    @Test func swiftUIReferenceMatchesScrollAndRTL() async {
        var scrollSize: CGSize?, rtlFrame: CGRect?
        let reference = SwiftUI.VStack {
            SwiftUI.ScrollView(.vertical) {
                SwiftUI.GeometryReader { proxy in
                    SwiftUI.Color.clear.onAppear { scrollSize = proxy.size }
                }
            }.frame(width: 240, height: 120)
            SwiftUI.GeometryReader { _ in
                SwiftUI.Color.clear.frame(width: 40, height: 20)
                    .background {
                        SwiftUI.GeometryReader { proxy in
                            SwiftUI.Color.clear.onAppear { rtlFrame = proxy.frame(in: .named("rtl")) }
                        }
                    }
            }.frame(width: 240, height: 120)
                .coordinateSpace(name: "rtl").environment(\.layoutDirection, .rightToLeft)
        }
        let controller = UIHostingController(rootView: reference)
        let window = makeWindow()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        await settle(controller.view)
        #expect(scrollSize == CGSize(width: 240, height: 10))
        expectReferenceFrame(rtlFrame, CGRect(x: 200, y: 0, width: 40, height: 20), in: window)
    }

    @Test func unchangedGeometryDoesNotKeepRebuildingContent() async {
        let child = UIView()
        var builds = 0
        let host = QuickLayoutView {
            QuickLayoutKit.GeometryReader { proxy in
                let _ = { builds += 1 }()
                child.resizable().frame(width: proxy.size.width / 2, height: 40)
            }
        }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        let settled = builds
        #expect(settled > 0)
        await settle(host)
        #expect(builds == settled)
    }

    @Test func removedReaderReleasesCapturedContent() async {
        var visible = true
        weak var weakChild: UIView?
        let host = QuickLayoutView {
            if visible {
                let child = UIView()
                let _ = { weakChild = child }()
                QuickLayoutKit.GeometryReader { _ in child.resizable() }
            }
        }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        #expect(weakChild != nil)
        visible = false
        host.setNeedsQuickLayout()
        await settle(host)
        #expect(weakChild == nil)
    }

    /// SwiftUI 的命名空间转换可能跨越半像素原点；位置允许一个物理像素，尺寸保持精确比较。
    @Test func oneMeasurementProducesCompleteTreeWithoutMountingOrApplying() {
        let child = ReaderMeasurementProbe()
        var builds = 0
        let reader = QuickLayoutKit.GeometryReader { proxy in
            let _ = { builds += 1 }()
            child.frame(width: proxy.size.width / 2, height: 30)
        }
        _ = reader.views()
        #expect(builds == 0)
        let node = reader.layoutThatFits(CGSize(width: 200, height: 100))
        #expect(builds == 1)
        #expect(child.measurements == [CGSize(width: 100, height: 30)])
        #expect(nodeViews(node).contains { $0 === child })
        #expect(child.superview == nil)
        #expect(child.frame == .zero)
        let stage = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        reader.views().forEach(stage.addSubview)
        reader._applyFrame(stage.bounds, alignment: .topLeading, layoutDirection: .leftToRight, cachedLayout: node)
        #expect(builds == 1)
        #expect(child.measurements.count == 1)
        #expect(child.superview === stage)
        #expect(child.frame == CGRect(x: 0, y: 0, width: 100, height: 30))
        #expect(stage.subviews.allSatisfy { !($0 is QuickLayoutView) })
    }

    @Test func speculativeMeasurementDoesNotChangeAppliedTreeAndOldCacheRestoresItsBranch() {
        let small = ReaderMeasurementProbe(), large = ReaderMeasurementProbe()
        var builds = 0
        let reader = QuickLayoutKit.GeometryReader { proxy in
            let _ = { builds += 1 }()
            if proxy.size.width < 150 {
                small.frame(width: 40, height: 20)
            } else {
                large.frame(width: 60, height: 30)
            }
        }
        let stage = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 100))
        reader.views().forEach(stage.addSubview)
        let a = reader.layoutThatFits(CGSize(width: 100, height: 80), layoutDirection: .rightToLeft)
        reader._applyFrame(CGRect(x: 10, y: 5, width: 100, height: 80), alignment: .topLeading,
                           layoutDirection: .leftToRight, cachedLayout: a)
        #expect(small.frame == CGRect(x: 70, y: 5, width: 40, height: 20))
        let b = reader.layoutThatFits(CGSize(width: 200, height: 80), layoutDirection: .leftToRight)
        #expect(small.superview === stage)
        #expect(large.superview == nil)
        #expect(small.frame == CGRect(x: 70, y: 5, width: 40, height: 20))
        reader._applyFrame(CGRect(x: 10, y: 5, width: 200, height: 80), alignment: .topLeading,
                           layoutDirection: .rightToLeft, cachedLayout: b)
        #expect(small.superview == nil)
        #expect(large.frame == CGRect(x: 10, y: 5, width: 60, height: 30))
        reader._applyFrame(CGRect(x: 20, y: 15, width: 100, height: 80), alignment: .topLeading,
                           layoutDirection: .leftToRight, cachedLayout: a)
        #expect(large.superview == nil)
        #expect(small.superview === stage)
        #expect(small.frame == CGRect(x: 80, y: 15, width: 40, height: 20))
        #expect(builds == 2)
        #expect(small.measurements.count == 1)
        #expect(large.measurements.count == 1)
    }

    @Test func cacheRestoresGeometryCallbackCapturedByThatMeasurement() {
        let child = UIView()
        var reported: [CGFloat] = []
        let reader = QuickLayoutKit.GeometryReader { proxy in
            child.resizable()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { _ in
                    reported.append(proxy.size.width)
                }
        }
        let stage = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        reader.views().forEach(stage.addSubview)
        let a = reader.layoutThatFits(CGSize(width: 100, height: 80), layoutDirection: .rightToLeft)
        let b = reader.layoutThatFits(CGSize(width: 200, height: 80), layoutDirection: .leftToRight)
        #expect(reported.isEmpty)
        reader._applyFrame(CGRect(x: 0, y: 0, width: 100, height: 80), alignment: .topLeading,
                           layoutDirection: .leftToRight, cachedLayout: a)
        reader._applyFrame(stage.bounds, alignment: .topLeading, layoutDirection: .leftToRight, cachedLayout: b)
        reader._applyFrame(CGRect(x: 0, y: 0, width: 100, height: 80), alignment: .topLeading,
                           layoutDirection: .leftToRight, cachedLayout: a)
        #expect(reported == [100, 200, 100])
    }

    @Test func cachedReaderRestoresNamedSpaceAfterAnotherBranchWasMeasured() {
        let child = UIView()
        var sizes: [CGSize?] = []
        let reader = QuickLayoutKit.GeometryReader { proxy in
            child.resizable()
                .onGeometryChange(for: CGSize?.self, of: { $0.bounds(of: .named("small"))?.size }) {
                    sizes.append($0)
                }
                .coordinateSpace(.named(proxy.size.width < 150 ? "small" : "large"))
        }
        let stage = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        reader.views().forEach(stage.addSubview)
        let a = reader.layoutThatFits(CGSize(width: 100, height: 80))
        reader._applyFrame(CGRect(x: 0, y: 0, width: 100, height: 80), alignment: .topLeading,
                           layoutDirection: .leftToRight, cachedLayout: a)
        let b = reader.layoutThatFits(CGSize(width: 200, height: 80))
        #expect(sizes == [CGSize(width: 100, height: 80)])
        reader._applyFrame(stage.bounds, alignment: .topLeading, layoutDirection: .leftToRight, cachedLayout: b)
        reader._applyFrame(CGRect(x: 0, y: 0, width: 100, height: 80), alignment: .topLeading,
                           layoutDirection: .leftToRight, cachedLayout: a)
        #expect(sizes == [CGSize(width: 100, height: 80), nil, CGSize(width: 100, height: 80)])
    }

    @Test func gridProducesCompleteReaderCellsAndReusesTheirMeasuredNodes() async {
        let cells = (0..<4).map { _ in UIView() }
        let host = QuickLayoutView {
            QuickLayoutBridge.Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                for row in 0..<2 {
                    QuickLayoutBridge.GridRow {
                        for column in 0..<2 {
                            QuickLayoutKit.GeometryReader { proxy in
                                cells[row * 2 + column].resizable()
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                            }
                        }
                    }
                }
            }
        }
        let window = mount(host, size: CGSize(width: 210, height: 130))
        defer { window.isHidden = true }
        await settle(host)
        #expect(cells.allSatisfy { $0.superview === host })
        #expect(cells.map(\.frame) == [CGRect(x: 0, y: 0, width: 100, height: 60),
                                       CGRect(x: 110, y: 0, width: 100, height: 60),
                                       CGRect(x: 0, y: 70, width: 100, height: 60),
                                       CGRect(x: 110, y: 70, width: 100, height: 60)])
        host.semanticContentAttribute = .forceRightToLeft
        host.frame.size.width = 310
        host.setNeedsQuickLayout()
        await settle(host)
        #expect(cells[0].frame == CGRect(x: 160, y: 0, width: 150, height: 60))
        #expect(cells[1].frame == CGRect(x: 0, y: 0, width: 150, height: 60))
        #expect(cells.allSatisfy { $0.superview === host })
    }

    @Test func readerHonorsStackAndGridLayoutPriority() {
        for useGrid in [false, true] {
            let a = UIView(), b = UIView(), fixed = UIView()
            let readerA = QuickLayoutKit.GeometryReader { proxy in a.resizable().frame(width: proxy.size.width, height: 40) }
            let readerB = QuickLayoutKit.GeometryReader { proxy in b.resizable().frame(width: proxy.size.width, height: 40) }
            let layout: any QuickLayoutBridge.Layout
            if useGrid {
                layout = QuickLayoutBridge.Grid(horizontalSpacing: 10) {
                    QuickLayoutBridge.GridRow {
                        fixed.frame(width: 40, height: 40)
                        readerA.layoutPriority(1)
                        readerB
                    }
                }
            } else {
                layout = HStack(spacing: 10) {
                    fixed.frame(width: 40, height: 40)
                    readerA.layoutPriority(1)
                    readerB
                }
            }
            let stage = UIView(frame: CGRect(x: 0, y: 0, width: 260, height: 40))
            layout.views().forEach(stage.addSubview)
            let node = layout.layoutThatFits(stage.bounds.size)
            layout._applyFrame(stage.bounds, alignment: .topLeading, layoutDirection: .leftToRight, cachedLayout: node)
            #expect(a.frame.width == 200)
            #expect(b.frame.width == 0)
            #expect(fixed.frame.width == 40)
            #expect(a.superview === stage && b.superview === stage)
        }
    }

    @Test func cachedHostKeepsReadersFlatAndUpdatesSizeAndDirection() async {
        let child = UIView()
        let nested = QuickLayoutView {
            QuickLayoutKit.GeometryReader { proxy in
                child.resizable().frame(width: proxy.size.width / 2, height: 30)
            }
        }
        let host = ReaderCachingHost { nested.resizable() }
        let window = mount(host, size: CGSize(width: 240, height: 120))
        defer { window.isHidden = true }
        await settle(host)
        #expect(child.superview === nested)
        #expect(child.frame == CGRect(x: 0, y: 0, width: 120, height: 30))
        host.frame.size.width = 320
        host.semanticContentAttribute = .forceRightToLeft
        nested.semanticContentAttribute = .forceRightToLeft
        host.setNeedsQuickLayout()
        await settle(host)
        #expect(child.frame == CGRect(x: 160, y: 0, width: 160, height: 30))
        #expect(child.superview === nested)
    }

    private func nodeViews(_ node: LayoutNode) -> [UIView] {
        (node.view.map { [$0] } ?? []) + node.children.flatMap { nodeViews($0.layout) }
    }

    private func expectReferenceFrame(_ actual: CGRect?, _ expected: CGRect, in window: UIWindow) {
        guard let actual else { Issue.record("SwiftUI did not deliver geometry"); return }
        let pixel = 1 / max(1, window.traitCollection.displayScale)
        #expect(abs(actual.minX - expected.minX) <= pixel)
        #expect(abs(actual.minY - expected.minY) <= pixel)
        #expect(actual.size == expected.size)
    }

    private func makeWindow() -> UIWindow {
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            return UIWindow(windowScene: scene)
        }
        return UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    private func mount(_ host: UIView, size: CGSize) -> UIWindow {
        let window = makeWindow()
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        controller.view.addSubview(host)
        host.frame = CGRect(origin: CGPoint(x: 20, y: 150), size: size)
        return window
    }

    private func settle(_ view: UIView) async {
        for _ in 0..<12 {
            view.window?.layoutIfNeeded()
            view.layoutIfNeeded()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

@MainActor
private final class ReaderMeasurementProbe: UIView {
    var measurements: [CGSize] = []
    override func sizeThatFits(_ size: CGSize) -> CGSize { measurements.append(size); return size }
}

@MainActor
private final class ReaderCachingHost: QuickLayoutView {
    override var isCachingEnabled: Bool { true }
}
