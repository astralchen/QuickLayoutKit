import QuickLayout
import QuickLayoutKit
import SwiftUI
import Testing
import UIKit

/// 两侧直接使用默认布局，不给 Kit 补安全区 padding，也不关闭 SwiftUI 的容器安全区。
@MainActor
@Suite(.serialized)
struct DefaultSafeAreaParityTests {
    /// 使用系统软件键盘同时驱动两侧，验证默认避让与按区域忽略的最终几何。
    @Test func keyboardRegionsMatchSwiftUIWithSystemKeyboard() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let field = UITextField(frame: CGRect(x: 20, y: 100, width: 120, height: 44))
        field.borderStyle = .roundedRect
        controller.view.addSubview(field)
        defer { field.resignFirstResponder(); window.isHidden = true }
        for mode in 0..<8 {
            let reference = UIView()
            let actual: UIView = mode >= 6 ? UITableView() : UIView()
            let leaf = Color.blue.background(DefaultSafeAreaCapture(view: reference))
            let native: AnyView
            let content: any QuickLayout.Layout
            switch mode {
            case 1:
                native = AnyView(leaf.ignoresSafeArea(.container))
                content = actual.resizable().ignoresSafeArea(.container)
            case 2:
                native = AnyView(leaf.ignoresSafeArea(.keyboard))
                content = actual.resizable().ignoresSafeArea(.keyboard)
            case 3:
                native = AnyView(leaf.ignoresSafeArea())
                content = actual.resizable().ignoresSafeArea()
            case 4:
                // 嵌套宿主继承默认键盘区域，不再独立扣减同一高度。
                native = AnyView(leaf)
                content = QuickLayoutView { actual.resizable() }.resizable()
            case 6, 7:
                let scroll = actual as! UITableView
                scroll.contentInsetAdjustmentBehavior = mode == 6 ? .never : .always
                native = AnyView(leaf)
                content = QuickLayoutKit.List(scroll)
            case 5:
                native = AnyView(leaf.ignoresSafeArea(.keyboard))
                content = QuickLayoutView { actual.resizable().ignoresSafeArea(.keyboard) }.resizable()
            default:
                native = AnyView(leaf)
                content = actual.resizable()
            }
            let nativeHost = UIHostingController(rootView: native)
            let kitHost = QuickLayoutView { content }
            controller.addChild(nativeHost)
            controller.view.insertSubview(nativeHost.view, belowSubview: field)
            nativeHost.didMove(toParent: controller)
            controller.view.insertSubview(kitHost, belowSubview: field)
            // Duo 横屏的系统栏只在一侧，两种实现必须处于同一块物理窗口区域。
            nativeHost.view.frame = controller.view.bounds
            kitHost.frame = controller.view.bounds
            controller.view.layoutIfNeeded()
            #expect(field.becomeFirstResponder())
            try await Task.sleep(for: .milliseconds(500))
            #expect(controller.view.keyboardLayoutGuide.layoutFrame.height > 100)
            for _ in 0..<12 {
                nativeHost.view.setNeedsLayout()
                kitHost.setNeedsLayout()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(30))
            }
            let expected = reference.convert(reference.bounds, to: nativeHost.view)
            var result = actual.convert(actual.bounds, to: kitHost)
            if let scroll = actual as? UIScrollView {
                // 原生列表比较实际安全内容区域，视口本身仍应延伸到键盘后方。
                result = result.inset(by: scroll.adjustedContentInset)
                #expect(abs(scroll.frame.height - kitHost.bounds.height) < 1)
            }
            #expect(abs(expected.minY - result.minY) < 1 && abs(expected.height - result.height) < 1,
                    "mode=\(mode), SwiftUI=\(expected), Kit=\(result), keyboard=\(kitHost.quickLayoutKeyboardSafeAreaInsets)")
            field.resignFirstResponder()
            try await Task.sleep(for: .milliseconds(300))
            nativeHost.willMove(toParent: nil)
            nativeHost.view.removeFromSuperview()
            nativeHost.removeFromParent()
            kitHost.removeFromSuperview()
        }
    }

    @Test func defaultLayoutAndModifiersMatchSwiftUI() async {
        for mode in Array(0..<8) + [21, 22, 24, 25] {
            for rtl in [false, true] {
                await compare(mode: mode, rtl: rtl)
            }
        }
    }

    @Test func fixedSizeIgnoringEdgesMatchesSwiftUI() async {
        for mode in 11..<17 {
            for rtl in [false, true] { await compare(mode: mode, rtl: rtl) }
        }
    }

    @Test func scrollViewportAndContentMatchSwiftUI() async {
        for mode in [8, 9, 10, 17, 18, 19, 20] {
            for rtl in [false, true] {
                await compare(mode: mode, rtl: rtl)
            }
        }
    }

    private func compare(mode: Int, rtl: Bool) async {
        let reference = UIView(), actual = UIView()
        var nativeSafeTop: CGFloat = -1
        var kitSafeTop: CGFloat = -1
        let nativeLeaf = Color.blue.background(DefaultSafeAreaCapture(view: reference))
        let nested = QuickLayoutView {
            if mode == 14 || mode == 15 {
                actual.resizable().ignoresSafeArea(.container)
            } else {
                actual.resizable()
            }
        }
        let outer = QuickLayoutView { nested.resizable() }
        let wrapper = DefaultSafeAreaUIKitWrapper(content: nested)
        let scroll = QuickLayoutScrollView(.vertical)
        var native = AnyView(nativeLeaf)
        var content: any QuickLayout.Layout = actual.resizable()
        switch mode {
        case 21, 22:
            native = AnyView(SwiftUI.GeometryReader { proxy in
                let _ = { nativeSafeTop = proxy.safeAreaInsets.top }()
                nativeLeaf
            })
            content = QuickLayoutKit.GeometryReader { proxy in
                let _ = { kitSafeTop = proxy.safeAreaInsets.top }()
                actual.resizable()
            }
            if mode == 22 {
                native = AnyView(native.safeAreaPadding(.top, 20))
                content = content.safeAreaPadding(.top, 20)
            }
        case 1:
            native = AnyView(nativeLeaf.ignoresSafeArea(.container))
            content = actual.resizable().ignoresSafeArea(.container)
        case 2:
            native = AnyView(nativeLeaf.ignoresSafeArea(.container, edges: .top))
            content = actual.resizable().ignoresSafeArea(.container, edges: .top)
        case 3:
            native = AnyView(nativeLeaf.safeAreaPadding(0))
            content = actual.resizable().safeAreaPadding()
        case 4:
            native = AnyView(nativeLeaf.safeAreaPadding(.horizontal, 20))
            content = actual.resizable().safeAreaPadding(.horizontal, 20)
        case 5:
            native = AnyView(nativeLeaf.safeAreaPadding(.leading, 8).safeAreaPadding(.leading, 12))
            content = actual.resizable().safeAreaPadding(.leading, 8).safeAreaPadding(.leading, 12)
        case 6:
            native = AnyView(SwiftUI.VStack(spacing: 0) { nativeLeaf })
            content = QuickLayoutKit.VStack { nested.resizable() }
        case 7:
            native = AnyView(SwiftUI.VStack(spacing: 0) { nativeLeaf }.ignoresSafeArea(.container))
            content = QuickLayoutKit.VStack { nested.resizable() }.ignoresSafeArea(.container)
        case 24:
            native = AnyView(SwiftUI.VStack(spacing: 0) { nativeLeaf })
            content = wrapper.resizable()
        case 25:
            native = AnyView(SwiftUI.VStack(spacing: 0) { nativeLeaf }.ignoresSafeArea(.container))
            content = wrapper.resizable().ignoresSafeArea(.container)
        case 11:
            native = AnyView(nativeLeaf.frame(width: 100, height: 80).ignoresSafeArea(.container))
            content = actual.resizable().frame(width: 100, height: 80).ignoresSafeArea(.container)
        case 12:
            native = AnyView(nativeLeaf.frame(width: 100, height: 80).ignoresSafeArea(.container, edges: .bottom))
            content = actual.resizable().frame(width: 100, height: 80).ignoresSafeArea(.container, edges: .bottom)
        case 13:
            native = AnyView(nativeLeaf.frame(width: 100, height: 80).ignoresSafeArea(.container, edges: .leading))
            content = actual.resizable().frame(width: 100, height: 80).ignoresSafeArea(.container, edges: .leading)
        case 14, 15:
            native = AnyView(SwiftUI.VStack(spacing: 0) { nativeLeaf.ignoresSafeArea(.container) })
            content = mode == 14 ? nested.resizable() : outer.resizable()
        case 16:
            native = AnyView(nativeLeaf.ignoresSafeArea(.container).frame(width: 100, height: 80))
            content = actual.resizable().ignoresSafeArea(.container).frame(width: 100, height: 80)
        case 8, 9, 10, 17, 18, 19, 20:
            let nativeScroll = SwiftUI.ScrollView { nativeLeaf.frame(height: 900) }
            let kitScroll = QuickLayoutKit.ScrollView(scroll) { actual.resizable(axis: .horizontal).frame(height: 900) }
            if mode == 19 || mode == 20 {
                native = AnyView(nativeScroll)
                content = kitScroll.resizable(axis: mode == 19 ? [.horizontal, .vertical] : .horizontal)
            } else if mode == 17 || mode == 18 {
                native = AnyView(nativeScroll.ignoresSafeArea(.container, edges: mode == 17 ? .all : .bottom))
                content = kitScroll.ignoresSafeArea(.container, edges: mode == 17 ? .all : .bottom)
            } else if mode == 9 {
                native = AnyView(nativeScroll.safeAreaPadding(.horizontal, 20))
                content = kitScroll.safeAreaPadding(.horizontal, 20)
            } else if mode == 10 {
                native = AnyView(nativeScroll.safeAreaInset(edge: .bottom, spacing: 8) { Color.red.frame(height: 40) })
                content = kitScroll.safeAreaInset(edge: .bottom, spacing: 8) { UIView().resizable().frame(height: 40) }
            } else {
                native = AnyView(nativeScroll)
                content = kitScroll
            }
        default: break
        }
        let nativeHost = UIHostingController(rootView: native
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
        nativeHost.safeAreaRegions = [.container]
        let kitHost = DefaultSafeAreaTestHost { content }
        kitHost.quickLayoutKeyboardSafeAreaBehavior = .disabled
        kitHost.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        nested.quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        scroll.quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 800))
        window.rootViewController = controller
        window.isHidden = false
        controller.addChild(nativeHost)
        controller.view.addSubview(nativeHost.view)
        nativeHost.didMove(toParent: controller)
        controller.view.addSubview(kitHost)
        defer { window.isHidden = true }
        for width: CGFloat in [360, 300] {
            nativeHost.additionalSafeAreaInsets = UIEdgeInsets(top: 13, left: 21, bottom: 17, right: 33)
            nativeHost.view.frame = CGRect(x: 0, y: 80, width: width, height: 480)
            kitHost.frame = CGRect(x: 400, y: 80, width: width, height: 480)
            for _ in 0..<8 {
                nativeHost.view.setNeedsLayout()
                window.layoutIfNeeded()
                nativeHost.view.layoutIfNeeded()
                kitHost.testInsets = nativeHost.view.safeAreaInsets
                kitHost.setNeedsLayout()
                kitHost.layoutIfNeeded()
                // 单独重排子宿主，验证离开父级临时作用域后仍保持相同的布局。
                if mode == 6 || mode == 7 || mode == 14 || mode == 15 {
                    if mode == 15 { outer.setNeedsLayout(); outer.layoutIfNeeded() }
                    nested.setNeedsLayout()
                    nested.layoutIfNeeded()
                }
                if mode == 24 || mode == 25 {
                    wrapper.setNeedsLayout()
                    wrapper.layoutIfNeeded()
                    nested.setNeedsLayout()
                    nested.layoutIfNeeded()
                }
                if [8, 9, 10, 17, 18, 19, 20].contains(mode) {
                    scroll.setNeedsLayout()
                    scroll.layoutIfNeeded()
                }
                try? await Task.sleep(for: .milliseconds(15))
            }
            let expected = reference.convert(reference.bounds, to: nativeHost.view)
            let result = actual.convert(actual.bounds, to: kitHost)
            let message = "mode=\(mode), rtl=\(rtl), width=\(width), expected=\(expected), actual=\(result), scroll=\(scroll.frame), offset=\(scroll.contentOffset), inset=\(scroll.adjustedContentInset)"
            #expect(abs(expected.minX - result.minX) < 1, Comment(rawValue: message))
            #expect(abs(expected.minY - result.minY) < 1, Comment(rawValue: message))
            #expect(abs(expected.width - result.width) < 1, Comment(rawValue: message))
            #expect(abs(expected.height - result.height) < 1, Comment(rawValue: message))
            if mode == 21 || mode == 22 {
                #expect(abs(nativeSafeTop - kitSafeTop) < 1,
                        "SwiftUI safeTop=\(nativeSafeTop), Kit safeTop=\(kitSafeTop)")
            }
            if [8, 9, 10, 17, 18, 19, 20].contains(mode) {
                #expect(scroll.contentSize.height == 900)
                #expect(abs(scroll.frame.minY) < 1)
                #expect(abs(scroll.frame.maxY - kitHost.bounds.maxY) < 1)
            }
        }
    }
}

private struct DefaultSafeAreaCapture: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class DefaultSafeAreaTestHost: QuickLayoutView {
    var testInsets = UIEdgeInsets.zero
    override var safeAreaInsets: UIEdgeInsets { testInsets }
}

/// 模拟业务层的普通 UIKit 包装，验证安全区继承不依赖连续的 Kit 宿主。
private final class DefaultSafeAreaUIKitWrapper: UIView {
    let content: UIView
    init(content: UIView) {
        self.content = content
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        if content.superview !== self { addSubview(content) }
        content.frame = bounds
    }
}
