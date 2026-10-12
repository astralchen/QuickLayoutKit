import Testing
import UIKit
import SwiftUI
import QuickLayout
@testable import QuickLayoutKitCore
import QuickLayoutKitUIKit

@MainActor
@Suite(.serialized)
struct GeometryProxyTests {
    @Test func layoutBatchFreezesSiblingSnapshotsBeforeActions() async {
        let registry = QuickLayoutGeometryObservationRegistry()
        let firstView = UIView(), secondView = UIView()
        var secondWidths: [CGFloat] = []
        let second = secondView.resizable().onGeometryChange(for: CGFloat.self) { $0.size.width } action: { secondWidths.append($0) }
        let first = firstView.resizable().onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
            second.applyFrame(CGRect(x: 0, y: 0, width: 60, height: 20))
        }
        QuickLayoutGeometryObservationContext.withRegistry(registry) {
            first.applyFrame(CGRect(x: 0, y: 0, width: 40, height: 20))
            second.applyFrame(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        #expect(secondWidths == [40])
        for _ in 0..<10 where secondWidths.count < 2 { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(secondWidths == [40, 60])
    }

    @Test func scopesAndAnchorsSurviveBodyRebuilds() async {
        let anchor = QuickLayoutKitCore.Anchor<CGRect>(.bounds)
        let target = UIView()
        let registry = QuickLayoutGeometryObservationRegistry()
        func element() -> any QuickLayoutBridge.Layout {
            target.resizable().geometryAnchor(anchor).coordinateSpace(.named("stable"))
                .geometryContainer(.init(contentMargins: .init(top: 1, leading: 2, bottom: 3, trailing: 4)))
        }
        let first = QuickLayoutGeometryObservationContext.withRegistry(registry) { element() }
        let rebuilt = QuickLayoutGeometryObservationContext.withRegistry(registry) { element() }
        #expect(first.views().map(ObjectIdentifier.init) == rebuilt.views().map(ObjectIdentifier.init))

        var callbacks = 0
        var host: QuickLayoutView!
        host = QuickLayoutView {
            target.resizable().geometryAnchor(anchor)
                .onGeometryChange(for: CGRect?.self) { $0.resolve(anchor) } action: { _ in
                    callbacks += 1
                    host.setNeedsQuickLayout()
                }
                .coordinateSpace(.named("stable"))
        }
        let window = mount(host)
        defer { window.isHidden = true }
        for _ in 0..<3 { host.layoutIfNeeded(); GeometryWindowMonitor.forWindow(window).refresh() }
        let settled = callbacks
        for _ in 0..<5 {
            host.setNeedsQuickLayout(); host.layoutIfNeeded()
            GeometryWindowMonitor.forWindow(window).refresh()
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(callbacks == settled)
        host = nil
    }

    @Test func swiftUIReferenceReportsSameLocalSize() async {
        var swiftUISize: CGSize?
        let content = SwiftUI.Color.clear.frame(width: 80, height: 40)
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { swiftUISize = $0 }
        let controller = SwiftUI.UIHostingController(rootView: content)
        let window = makeWindow()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded(); controller.view.layoutIfNeeded()
        for _ in 0..<10 where swiftUISize == nil { try? await Task.sleep(for: .milliseconds(20)) }
        let native = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 40))
        let proxy = QuickLayoutKitCore.GeometryProxy(observing: native, layoutDirection: .leftToRight)
        #expect(swiftUISize == proxy.size)
    }

    @Test func nativeReservedRegionsMatchUIKitAndKeepIdentifiers() {
        guard #available(iOS 27.1, *) else { return }
        let view = UIView()
        let window = mount(view)
        defer { window.isHidden = true }
        let a = QuickLayoutKitCore.GeometryProxy(observing: view, layoutDirection: .leftToRight)
        let b = QuickLayoutKitCore.GeometryProxy(observing: view, layoutDirection: .leftToRight)
        for kind in [QuickLayoutKitCore.ReservedRegion.Kind.occlusion, .division] {
            let native = view.reservedRegions(kind: kind == .division ? .division : .occlusion, options: .includeInactive)
            let regions = a.reservedRegions(kind: kind, options: .includeInactive, layoutDirectionBehavior: .fixed)
            print("Geometry UIKit \(kind): \(native.count) regions, \(native.filter(\.isActive).count) active")
            #expect(regions.map(\.frame) == native.map(\.frame))
            #expect(regions.map(\.isActive) == native.map(\.isActive))
            #expect(regions.map(\.id) == b.reservedRegions(kind: kind, options: .includeInactive).map(\.id))
        }
    }

    @Test func namedSpaceCrossesNestedUIKitHosts() {
        let child = UIView()
        var result: CGRect?
        let nested = QuickLayoutView {
            child.resizable().onGeometryChange(for: CGRect?.self) { $0.bounds(of: .named("outer")) } action: { result = $0 }
        }
        let host = QuickLayoutView {
            nested.resizable().frame(width: 100, height: 80).padding(10).coordinateSpace(.named("outer"))
        }
        let window = mount(host)
        defer { window.isHidden = true }
        nested.layoutIfNeeded()
        GeometryWindowMonitor.forWindow(window).refresh()
        #expect(result?.size == CGSize(width: 120, height: 100))
        #expect(result?.origin == CGPoint(x: -10, y: -10))
    }

    @Test func pureLayoutAnchorAndWindowIsolation() {
        let anchor = QuickLayoutKitCore.Anchor<CGRect>(.bounds)
        var result: CGRect?
        let host = QuickLayoutView {
            HStack {
                Spacer().frame(width: 30, height: 40).geometryAnchor(anchor)
            }.onGeometryChange(for: CGRect?.self) { $0.resolve(anchor) } action: { result = $0 }
        }
        let window = mount(host)
        defer { window.isHidden = true }
        GeometryWindowMonitor.forWindow(window).refresh()
        #expect(result?.size == CGSize(width: 30, height: 40))
        let other = UIView()
        let otherWindow = mount(other)
        defer { otherWindow.isHidden = true }
        #expect(QuickLayoutKitCore.GeometryProxy(observing: other, layoutDirection: .leftToRight).resolve(anchor) == nil)
    }

    @Test func recursiveActionCoalescesWithoutLosingLatestValue() async {
        let view = UIView()
        var widths: [CGFloat] = []
        var depth = 0
        var maximumDepth = 0
        var element: (any QuickLayoutBridge.Layout)?
        element = view.resizable().onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            depth += 1; maximumDepth = max(maximumDepth, depth)
            widths.append(width)
            if width == 40 { element?.applyFrame(CGRect(x: 0, y: 0, width: 60, height: 20)) }
            depth -= 1
        }
        element?.applyFrame(CGRect(x: 0, y: 0, width: 40, height: 20))
        for _ in 0..<10 where widths.count < 2 { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(maximumDepth == 1)
        #expect(widths == [40, 60])
        element = nil
    }

    @Test func namedSpaceBoundsAndShadowing() {
        let target = UIView()
        var snapshots: [QuickLayoutKitCore.GeometryProxy] = []
        let host = QuickLayoutView {
            target.resizable()
                .onGeometryChange(for: QuickLayoutKitCore.GeometryProxy.self, of: { $0 }) { snapshots.append($0) }
                .frame(width: 60, height: 30)
                .coordinateSpace(.named("container"))
                .padding(20)
                .coordinateSpace(.named("container"))
        }
        let window = mount(host)
        defer { window.isHidden = true }
        host.layoutIfNeeded()
        let value = snapshots.last
        #expect(value?.frame(in: .named("container")).size == CGSize(width: 60, height: 30))
        #expect(value?.bounds(of: .named("container")) == CGRect(x: 0, y: 0, width: 60, height: 30))
        #expect(value?.bounds(of: .named("missing")) == nil)
    }

    @Test func anchorConversionIsFrozenAndRejectsDetachedSources() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let source = UIView(frame: CGRect(x: 70, y: 80, width: 60, height: 40))
        let target = UIView(frame: CGRect(x: 10, y: 20, width: 200, height: 150))
        root.addSubview(source); root.addSubview(target)
        let anchor = source.geometryAnchor(QuickLayoutKitCore.Anchor<CGRect>.Source.bounds)
        let center = source.geometryAnchor(QuickLayoutKitCore.Anchor<CGPoint>.Source.center)
        let snapshot = QuickLayoutKitCore.GeometryProxy(observing: target, layoutDirection: .leftToRight)
        #expect(snapshot[anchor] == CGRect(x: 60, y: 60, width: 60, height: 40))
        #expect(snapshot[center] == CGPoint(x: 90, y: 80))
        source.removeFromSuperview()
        #expect(snapshot[anchor].width == 60)
        #expect(QuickLayoutKitCore.GeometryProxy(observing: target, layoutDirection: .leftToRight).resolve(anchor) == nil)
    }

    @Test func anchorRotationsAndCompositeSources() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let source = UIView(frame: CGRect(x: 30, y: 40, width: 50, height: 60))
        let target = UIView(frame: root.bounds)
        root.addSubview(source); root.addSubview(target)
        source.bounds.origin = CGPoint(x: 4, y: 7)
        source.transform = CGAffineTransform(rotationAngle: .pi / 4).scaledBy(x: 1.2, y: 0.8)
        let points = source.geometryAnchor(QuickLayoutKitCore.Anchor<[CGPoint]>.Source([.topLeading, .bottomTrailing]))
        let optional = source.geometryAnchor(QuickLayoutKitCore.Anchor<CGRect?>.Source(.bounds))
        let proxy = QuickLayoutKitCore.GeometryProxy(observing: target, layoutDirection: .leftToRight)
        let expected = source.convert(CGPoint(x: source.bounds.minX, y: source.bounds.minY), to: target)
        #expect(abs(proxy[points][0].x - expected.x) < 0.001)
        #expect(abs(proxy[points][0].y - expected.y) < 0.001)
        #expect(proxy[optional] != nil)
    }

    @Test func scrollAxesAndBoundsUseViewportCoordinates() {
        let outer = QuickLayoutScrollView(.vertical)
        outer.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        let inner = QuickLayoutScrollView(.horizontal)
        inner.frame = CGRect(x: 10, y: 20, width: 200, height: 100)
        let target = UIView(frame: CGRect(x: 70, y: 30, width: 20, height: 20))
        outer.addSubview(inner); inner.addSubview(target)
        inner.bounds.origin.x = 40
        let proxy = QuickLayoutKitCore.GeometryProxy(observing: target, layoutDirection: .leftToRight)
        #expect(proxy.frame(in: .scrollView(axis: .horizontal)).origin == CGPoint(x: 70, y: 30))
        #expect(proxy.bounds(of: .scrollView(axis: .horizontal))?.origin == CGPoint(x: -30, y: -30))
        #expect(proxy.frame(in: .scrollView(axis: .vertical)).origin == CGPoint(x: 40, y: 50))
        let legacy: GeometryCoordinateSpace = .scrollView
        #expect(proxy.frame(in: legacy) == proxy.frame(in: .scrollView))
    }

    @Test func explicitContainerGeometryAndRTL() {
        let target = UIView()
        let scope = GeometryScope(container: GeometryContainerValues(
            contentMargins: .init(top: 10, leading: 20, bottom: 30, trailing: 40),
            cornerInsets: .init(topLeading: CGSize(width: 30, height: 40)),
            cornerRadii: .init(topLeading: 40, bottomLeading: 30, bottomTrailing: 20, topTrailing: 10)))
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        root.addSubview(scope.view); scope.view.frame = root.bounds
        root.addSubview(target); target.frame = CGRect(x: 5, y: 5, width: 190, height: 190)
        let proxy = QuickLayoutKitCore.GeometryProxy(observing: target, layoutDirection: .leftToRight, scopes: [scope])
        if #available(iOS 26.0, *) {
            #expect(proxy.containerCornerInsets.topLeading == CGSize(width: 25, height: 35))
        }
        if #available(iOS 27.0, *) {
            #expect(proxy.concentricCornerRadii?.topLeading == 35)
            #expect(proxy.concentricCornerRadii(in: CGRect(x: 20, y: 20, width: 50, height: 50))?.topLeading == 15)
        }
        if #available(iOS 27.1, *) {
            #expect(proxy.contentMargins(for: .container, edges: .horizontal).leading == 15)
            let rtl = QuickLayoutKitCore.GeometryProxy(observing: target, layoutDirection: .rightToLeft, scopes: [scope])
            #expect(rtl.contentMargins(for: .container).leading == 35)
        }
    }

    @Test func reservedRegionFilteringAndMirroringDoNotDoubleMargins() {
        guard #available(iOS 27.1, *) else { return }
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        var proxy = QuickLayoutKitCore.GeometryProxy(observing: view, layoutDirection: .rightToLeft)
        let id = UUID()
        proxy.regionSnapshots = [
            GeometryReservedSnapshot(id: id, division: false, frame: CGRect(x: 10, y: 20, width: 30, height: 40),
                                     margins: .init(top: 1, leading: 2, bottom: 3, trailing: 4), active: true),
            GeometryReservedSnapshot(id: UUID(), division: true, frame: .zero, margins: .zero, active: false),
        ]
        let value = proxy.reservedRegions(kind: .occlusion)[0]
        #expect(value.frame == CGRect(x: 160, y: 20, width: 30, height: 40))
        #expect(value.margins.leading == 4)
        #expect(value.id == proxy.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed)[0].id)
        #expect(proxy.reservedRegions(kind: .division).isEmpty)
        #expect(proxy.reservedRegions(kind: .division, options: .includeInactive).count == 1)
    }

    @Test func windowMonitorTracksAncestorMovementWithoutRelayout() {
        let child = UIView()
        var origins: [CGPoint] = []
        let host = QuickLayoutView {
            child.resizable().onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origins.append($0) }
        }
        let window = mount(host)
        defer { window.isHidden = true }
        let count = origins.count
        host.center.x += 37
        GeometryWindowMonitor.forWindow(window).refresh()
        #expect(origins.count == count + 1)
        GeometryWindowMonitor.forWindow(window).refresh()
        #expect(origins.count == count + 1)
    }

    @Test func marginChangesMeasurementAndUnmountLifecycle() async {
        let child = UIView()
        var snapshots: [QuickLayoutKitCore.GeometryProxy] = []
        let host = QuickLayoutView {
            child.resizable().onGeometryChange(for: QuickLayoutKitCore.GeometryProxy.self, of: { $0 }) { snapshots.append($0) }
        }
        let window = mount(host)
        defer { window.isHidden = true }
        let settled = snapshots.count
        _ = host.sizeThatFits(CGSize(width: 70, height: 60))
        GeometryWindowMonitor.forWindow(window).refresh()
        #expect(snapshots.count == settled)
        host.layoutMargins = UIEdgeInsets(top: 11, left: 12, bottom: 13, right: 14)
        GeometryWindowMonitor.forWindow(window).refresh()
        #expect(snapshots.count > settled)
        #expect(snapshots.last?.size == snapshots.first?.size)
        let observers = host.subviews.compactMap { $0 as? GeometryObserverView }
        #expect(observers.count == 1)
        for observer in observers { observer.removeFromSuperview() }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(observers.allSatisfy { !$0.hasAppliedGeometry })
        let detachedCount = snapshots.count
        GeometryWindowMonitor.forWindow(window).refresh()
        #expect(snapshots.count == detachedCount)
    }

    private func mount(_ view: UIView) -> UIWindow {
        let controller = UIViewController()
        controller.view = view
        let window = makeWindow()
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded(); view.layoutIfNeeded()
        GeometryWindowMonitor.forWindow(window).refresh()
        return window
    }

    private func makeWindow() -> UIWindow {
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) {
            return UIWindow(windowScene: scene)
        }
        return UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
    }
}
