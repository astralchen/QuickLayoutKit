import QuickLayout
import QuickLayoutKit
import SwiftUI
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct ContainerRelativeFrameParityTests {
    @Test func nearestContainersAndNestedScrollsMatchSwiftUI() async {
        await compareModes(0..<8)
        await compareModes(29..<31)
    }

    @Test func safeAreaModifiersAndPhysicalInsetsMatchSwiftUI() async {
        await compareModes(8..<24)
    }

    @Test func axesCountSpanLengthAndAlignmentMatchSwiftUI() async {
        await compareModes(24..<29)
    }

    private func compareModes(_ modes: Range<Int>) async {
        for mode in modes {
            for rtl in [false, true] {
                await compare(mode: mode, rtl: rtl)
            }
        }
    }

    private let scenarioNames = [
        "fixed wrapper", "stack and padding", "ordinary nested host", "horizontal viewport",
        "vertical viewport", "vertical then horizontal scroll", "horizontal then vertical scroll",
        "ordinary host inside scroll", "safe padding inside fixed frame", "safe padding",
        "leading safe inset", "ignore inside safe padding", "safe padding inside ignore",
        "asymmetric safe padding", "ignore vertical padding", "ignore leading safe inset",
        "repeated ignores", "keyboard ignore preserves container padding", "nested safe padding",
        "flexible content ignores padding", "physical safe area", "ignore physical safe area",
        "physical area and added padding", "scroll inside physical safe area",
        "horizontal axis", "vertical axis", "count and span default zero spacing",
        "axis dependent length", "bottom trailing content alignment",
        "vertical scroll content margins", "horizontal scroll content margins"
    ]

    private func compare(mode: Int, rtl: Bool) async {
        let reference = UIView()
        let actual = UIView()
        var nativeLeaf = mode == 19 ? AnyView(Color.blue.background(RelativeFrameProbe(view: reference)))
            : AnyView(Color.blue.containerRelativeFrame([.horizontal, .vertical])
                .background(RelativeFrameProbe(view: reference)))
        var actualLeaf: any QuickLayout.Layout = mode == 19 ? actual.resizable()
            : actual.resizable().containerRelativeFrame([.horizontal, .vertical])
        switch mode {
        case 24:
            nativeLeaf = AnyView(Color.blue.frame(height: 29).containerRelativeFrame(.horizontal)
                .background(RelativeFrameProbe(view: reference)))
            actualLeaf = actual.resizable().frame(height: 29).containerRelativeFrame(.horizontal)
        case 25:
            nativeLeaf = AnyView(Color.blue.frame(width: 37).containerRelativeFrame(.vertical)
                .background(RelativeFrameProbe(view: reference)))
            actualLeaf = actual.resizable().frame(width: 37).containerRelativeFrame(.vertical)
        case 26:
            nativeLeaf = AnyView(Color.blue.containerRelativeFrame([.horizontal, .vertical], count: 3, span: 2, spacing: 0)
                .background(RelativeFrameProbe(view: reference)))
            actualLeaf = actual.resizable().containerRelativeFrame([.horizontal, .vertical], count: 3, span: 2)
        case 27:
            nativeLeaf = AnyView(Color.blue.containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                axis == .horizontal ? length / 2 : length - 40
            }.background(RelativeFrameProbe(view: reference)))
            actualLeaf = actual.resizable().containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                axis == .horizontal ? length / 2 : length - 40
            }
        case 28:
            nativeLeaf = AnyView(Color.blue.frame(width: 53, height: 31)
                .background(RelativeFrameProbe(view: reference))
                .containerRelativeFrame([.horizontal, .vertical], alignment: .bottomTrailing))
            actualLeaf = actual.frame(width: 53, height: 31)
                .containerRelativeFrame([.horizontal, .vertical], alignment: .bottomTrailing)
        default: break
        }
        let native: AnyView
        let content: any QuickLayout.Layout
        switch mode {
        case 1:
            native = AnyView(SwiftUI.VStack(spacing: 0) { nativeLeaf }.padding(13).frame(width: 120, height: 100, alignment: .topLeading))
            content = QuickLayoutKit.VStack { actualLeaf }.padding(13).frame(width: 120, height: 100, alignment: .topLeading)
        case 2:
            native = AnyView(nativeLeaf.frame(width: 120, height: 100, alignment: .topLeading))
            content = QuickLayoutView { actualLeaf }.frame(width: 120, height: 100, alignment: .topLeading)
        case 3, 7:
            // 固定非滚动轴，避免双轴相对尺寸反过来参与自然视口尺寸求解。
            native = AnyView(SwiftUI.ScrollView(.horizontal) { nativeLeaf.frame(height: 180) }.frame(width: 240, height: 180))
            if mode == 7 {
                let child = QuickLayoutView { actualLeaf }
                content = RelativeFrameScroll(.horizontal) { child.frame(height: 180) }.frame(width: 240, height: 180)
            } else {
                content = RelativeFrameScroll(.horizontal) { actualLeaf.frame(height: 180) }.frame(width: 240, height: 180)
            }
        case 4:
            native = AnyView(SwiftUI.ScrollView(.vertical) { nativeLeaf.frame(width: 240) }.frame(width: 240, height: 180))
            content = RelativeFrameScroll(.vertical) { actualLeaf.frame(width: 240) }.frame(width: 240, height: 180)
        case 5:
            native = AnyView(SwiftUI.ScrollView(.vertical) {
                SwiftUI.ScrollView(.horizontal) { nativeLeaf.frame(height: 110) }.frame(width: 160, height: 110)
            }.frame(width: 240, height: 180))
            let inner = RelativeFrameScroll(.horizontal) { actualLeaf.frame(height: 110) }
            content = RelativeFrameScroll(.vertical) { inner.frame(width: 160, height: 110) }.frame(width: 240, height: 180)
        case 6:
            native = AnyView(SwiftUI.ScrollView(.horizontal) {
                SwiftUI.ScrollView(.vertical) { nativeLeaf.frame(width: 160) }.frame(width: 160, height: 110)
            }.frame(width: 240, height: 180))
            let inner = RelativeFrameScroll(.vertical) { actualLeaf.frame(width: 160) }
            content = RelativeFrameScroll(.horizontal) { inner.frame(width: 160, height: 110) }.frame(width: 240, height: 180)
        case 8:
            native = AnyView(nativeLeaf.safeAreaPadding(.horizontal, 20).frame(width: 120, height: 100, alignment: .topLeading))
            content = actualLeaf.safeAreaPadding(.horizontal, 20).frame(width: 120, height: 100, alignment: .topLeading)
        case 9:
            native = AnyView(nativeLeaf.safeAreaPadding(.horizontal, 20))
            content = actualLeaf.safeAreaPadding(.horizontal, 20)
        case 10:
            native = AnyView(nativeLeaf.safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: 30) })
            content = actualLeaf.safeAreaInset(edge: .leading, spacing: 0) { UIView().resizable().frame(width: 30) }
        case 11:
            native = AnyView(nativeLeaf.ignoresSafeArea(.container, edges: .horizontal).safeAreaPadding(.horizontal, 20))
            content = actualLeaf.ignoresSafeArea(.container, edges: .horizontal).safeAreaPadding(.horizontal, 20)
        case 12:
            native = AnyView(nativeLeaf.safeAreaPadding(.horizontal, 20).ignoresSafeArea(.container, edges: .horizontal))
            content = actualLeaf.safeAreaPadding(.horizontal, 20).ignoresSafeArea(.container, edges: .horizontal)
        case 13:
            native = AnyView(nativeLeaf.ignoresSafeArea(.container, edges: .leading)
                .safeAreaPadding(SwiftUI.EdgeInsets(top: 9, leading: 21, bottom: 17, trailing: 33)))
            content = actualLeaf.ignoresSafeArea(.container, edges: .leading)
                .safeAreaPadding(.init(top: 9, leading: 21, bottom: 17, trailing: 33))
        case 14:
            native = AnyView(nativeLeaf.ignoresSafeArea(.container, edges: .vertical).safeAreaPadding(.vertical, 20))
            content = actualLeaf.ignoresSafeArea(.container, edges: .vertical).safeAreaPadding(.vertical, 20)
        case 15:
            native = AnyView(nativeLeaf.ignoresSafeArea(.container, edges: .leading)
                .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: 30) })
            content = actualLeaf.ignoresSafeArea(.container, edges: .leading)
                .safeAreaInset(edge: .leading, spacing: 0) { UIView().resizable().frame(width: 30) }
        case 16:
            native = AnyView(nativeLeaf.ignoresSafeArea(.container, edges: .horizontal)
                .ignoresSafeArea(.container, edges: .horizontal).safeAreaPadding(.horizontal, 20))
            content = actualLeaf.ignoresSafeArea(.container, edges: .horizontal)
                .ignoresSafeArea(.container, edges: .horizontal).safeAreaPadding(.horizontal, 20)
        case 17:
            native = AnyView(nativeLeaf.ignoresSafeArea(.keyboard, edges: .horizontal).safeAreaPadding(.horizontal, 20))
            content = actualLeaf.ignoresSafeArea(.keyboard, edges: .horizontal).safeAreaPadding(.horizontal, 20)
        case 18:
            native = AnyView(nativeLeaf.ignoresSafeArea(.container, edges: .horizontal)
                .safeAreaPadding(.horizontal, 10).safeAreaPadding(.horizontal, 20))
            content = actualLeaf.ignoresSafeArea(.container, edges: .horizontal)
                .safeAreaPadding(.horizontal, 10).safeAreaPadding(.horizontal, 20)
        case 19:
            native = AnyView(nativeLeaf.ignoresSafeArea(.container, edges: .horizontal).safeAreaPadding(.horizontal, 20))
            content = actualLeaf.ignoresSafeArea(.container, edges: .horizontal).safeAreaPadding(.horizontal, 20)
        case 20:
            native = nativeLeaf
            content = actualLeaf
        case 21:
            native = AnyView(nativeLeaf.ignoresSafeArea(.container))
            content = actualLeaf.ignoresSafeArea(.container)
        case 22:
            native = AnyView(nativeLeaf.safeAreaPadding(.horizontal, 12))
            content = actualLeaf.safeAreaPadding(.horizontal, 12)
        case 23:
            native = AnyView(SwiftUI.ScrollView(.vertical) { nativeLeaf.frame(width: 160) }.frame(width: 160, height: 110))
            content = RelativeFrameScroll(.vertical) { actualLeaf.frame(width: 160) }.frame(width: 160, height: 110)
        case 29:
            native = AnyView(SwiftUI.ScrollView(.vertical) { nativeLeaf.frame(width: 200) }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .contentMargins(.vertical, 12, for: .scrollContent)
                .frame(width: 240, height: 180))
            content = RelativeFrameScroll(.vertical) { actualLeaf.frame(width: 200) }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .contentMargins(.vertical, 12, for: .scrollContent)
                .frame(width: 240, height: 180)
        case 30:
            native = AnyView(SwiftUI.ScrollView(.horizontal) { nativeLeaf.frame(height: 156) }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .contentMargins(.vertical, 12, for: .scrollContent)
                .frame(width: 240, height: 180))
            content = RelativeFrameScroll(.horizontal) { actualLeaf.frame(height: 156) }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .contentMargins(.vertical, 12, for: .scrollContent)
                .frame(width: 240, height: 180)
        default:
            native = AnyView(nativeLeaf.frame(width: 120, height: 100, alignment: .topLeading))
            content = actualLeaf.frame(width: 120, height: 100, alignment: .topLeading)
        }
        let host = UIHostingController(rootView: native.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
        host.safeAreaRegions = (20...23).contains(mode) ? [.container] : []
        if (20...23).contains(mode) { host.additionalSafeAreaInsets = UIEdgeInsets(top: 9, left: 21, bottom: 17, right: 33) }
        let actualRoot: any QuickLayout.Layout = (20...23).contains(mode) ? content.safeAreaPadding(0) : content
        let actualHost = RelativeFrameHost {
            actualRoot.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        actualHost.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 800))
        window.rootViewController = controller
        window.isHidden = false
        controller.addChild(host)
        controller.view.addSubview(host.view)
        host.didMove(toParent: controller)
        controller.view.addSubview(actualHost)
        defer { window.isHidden = true }
        for size in [CGSize(width: 360, height: 480), CGSize(width: 300, height: 400)] {
            if (20...23).contains(mode) {
                host.additionalSafeAreaInsets = size.width == 360
                    ? UIEdgeInsets(top: 9, left: 21, bottom: 17, right: 33)
                    : UIEdgeInsets(top: 15, left: 31, bottom: 11, right: 19)
            }
            host.view.frame = CGRect(origin: CGPoint(x: 0, y: 80), size: size)
            actualHost.frame = CGRect(origin: CGPoint(x: 400, y: 80), size: size)
            actualHost.setNeedsQuickLayout()
            for _ in 0..<15 {
                host.view.setNeedsLayout()
                window.layoutIfNeeded()
                host.view.layoutIfNeeded()
                if (20...23).contains(mode) {
                    actualHost.testInsets = host.view.safeAreaInsets
                    actualHost.setNeedsQuickLayout()
                }
                actualHost.layoutIfNeeded()
                try? await Task.sleep(for: .milliseconds(20))
            }
            #expect(reference.superview != nil && actual.superview != nil)
            var ancestor = actual.superview
            while let view = ancestor, view !== actualHost {
                if view is RelativeFrameScroll {
                    #expect(view.effectiveUserInterfaceLayoutDirection == (rtl ? .rightToLeft : .leftToRight))
                }
                ancestor = view.superview
            }
            let expected = reference.convert(reference.bounds, to: host.view)
            let result = actual.convert(actual.bounds, to: actualHost)
            #expect(abs(result.minX - expected.minX) < 0.6 && abs(result.minY - expected.minY) < 0.6
                    && abs(result.width - expected.width) < 0.6 && abs(result.height - expected.height) < 0.6,
                    "\(scenarioNames[mode]), RTL=\(rtl), size=\(size): \(result) vs \(expected)")
        }
    }
}

private final class RelativeFrameHost: QuickLayoutView {
    var testInsets = UIEdgeInsets.zero
    override var safeAreaInsets: UIEdgeInsets { testInsets }
}

private struct RelativeFrameProbe: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension ContainerRelativeFrameParityTests {
    @Test func ordinaryHostKeepsReferenceDuringIndependentLayoutAndReparenting() {
        let leaf = UIView()
        let nested = RelativeFrameHost {
            leaf.resizable().containerRelativeFrame([.horizontal, .vertical])
        }
        var usesFirst = true
        let first = RelativeFrameHost {
            if usesFirst { nested.frame(width: 120, height: 100) }
        }
        let second = RelativeFrameHost { nested.frame(width: 120, height: 100) }
        first.frame.size = CGSize(width: 360, height: 480)
        first.setNeedsQuickLayout()
        first.layoutIfNeeded()
        #expect(leaf.bounds.size == first.bounds.size)
        nested.setNeedsQuickLayout()
        nested.layoutIfNeeded()
        #expect(leaf.bounds.size == first.bounds.size)

        usesFirst = false
        first.setNeedsQuickLayout()
        first.layoutIfNeeded()
        second.frame.size = CGSize(width: 300, height: 400)
        second.setNeedsQuickLayout()
        second.layoutIfNeeded()
        #expect(leaf.bounds.size == second.bounds.size)
        nested.setNeedsQuickLayout()
        nested.layoutIfNeeded()
        #expect(leaf.bounds.size == second.bounds.size)
    }

    @Test func shortHorizontalScrollKeepsContentSizeAndMirrorsOnlyPlacement() {
        let child = UIView()
        let scroll = RelativeFrameScroll(.horizontal) {
            child.frame(width: 120, height: 40)
        }
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset = UIEdgeInsets(top: 0, left: 11, bottom: 0, right: 23)
        scroll.frame.size = CGSize(width: 300, height: 100)
        for rtl in [false, true, false] {
            scroll.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            scroll.setNeedsQuickLayout()
            scroll.layoutIfNeeded()
            #expect(scroll.contentSize.width == 120)
            #expect(child.frame.minX == (rtl ? 146 : 0))
            #expect(scroll.contentOffset.x == -11)
        }
    }
}

/// 对应 SwiftUI 的环境方向传播；UIKit 宿主默认 preserve，不隐式覆盖局部语义。
private final class RelativeFrameScroll: QuickLayoutScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
