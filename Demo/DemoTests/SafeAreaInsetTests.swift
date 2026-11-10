import QuickLayout
import QuickLayoutKit
import SwiftUI
import Testing
import UIKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct SafeAreaInsetTests {
    @Test func scrollKeepsViewportAndReservesBarWithoutChangingContentSize() {
        let scroll = QuickLayoutScrollView(.vertical)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset.bottom = 7
        scroll.verticalScrollIndicatorInsets.bottom = 3
        let bar = UIView()
        let host = InsetTestHost {
            QuickLayoutKit.ScrollView(scroll) { UIView().resizable(axis: .horizontal).frame(height: 900) }
                .contentMargins(.bottom, 11, for: .scrollContent)
                .safeAreaInset(edge: .bottom, spacing: 8) { bar.resizable(axis: .horizontal).frame(height: 50) }
        }
        host.testInsets.bottom = 20
        layout(host)
        #expect(scroll.frame == host.bounds)
        #expect(scroll.contentSize.height == 900)
        #expect(abs(scroll.adjustedContentInset.bottom - 96) < 0.01)
        #expect(abs(scroll.verticalScrollIndicatorInsets.bottom - 81) < 0.01)
        #expect(bar.frame.maxY == host.bounds.maxY - 20)
        scroll.scrollTo(.bottom, animated: false)
        #expect(abs(900 - scroll.contentOffset.y - (bar.frame.minY - 8 - 7 - 11)) < 0.5)
    }

    @Test func nestedInsetsKeepOrderAndDynamicSizeWithoutAccumulation() {
        let scroll = QuickLayoutScrollView(.vertical)
        scroll.contentInsetAdjustmentBehavior = .never
        let inner = UIView(), outer = UIView()
        var height: CGFloat = 30
        let host = InsetTestHost {
            QuickLayoutKit.ScrollView(scroll) { UIView().resizable(axis: .horizontal).frame(height: 900) }
                .safeAreaInset(edge: .bottom, spacing: 4) { inner.frame(width: 100, height: height) }
                .safeAreaInset(edge: .bottom, spacing: 6) { outer.frame(width: 100, height: 20) }
        }
        host.testInsets.bottom = 10
        for value: CGFloat in [30, 60, 30] {
            height = value
            layout(host)
            #expect(outer.frame.maxY == 470)
            #expect(inner.frame.maxY == outer.frame.minY - 6)
            #expect(scroll.adjustedContentInset.bottom == 10 + 20 + 6 + value + 4)
            scroll.setNeedsQuickLayout()
            scroll.layoutIfNeeded()
            #expect(scroll.adjustedContentInset.bottom == 40 + value)
        }
    }

    @Test func resizingInsetKeepsExistingEndPositionAndPreservesMiddle() {
        for horizontal in [false, true] {
            for rtl in [false, true] {
                let scroll = QuickLayoutScrollView(horizontal ? .horizontal : .vertical)
                scroll.contentInsetAdjustmentBehavior = .never
                scroll.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
                var extent: CGFloat = 30
                var enabled = true
                let host = InsetTestHost {
                    let page = QuickLayoutKit.ScrollView(scroll, horizontal ? .horizontal : .vertical) {
                        UIView().frame(width: horizontal ? 900 : 320, height: horizontal ? 480 : 900)
                    }
                    if !enabled { page }
                    else if horizontal {
                        page.safeAreaInset(edge: QuickLayoutKit.HorizontalEdge.trailing, spacing: 8) {
                            UIView().frame(width: extent, height: 100)
                        }
                    } else {
                        page.safeAreaInset(edge: .bottom, spacing: 8) {
                            UIView().frame(width: 100, height: extent)
                        }
                    }
                }
                host.semanticContentAttribute = scroll.semanticContentAttribute
                layout(host)
                scroll.scrollTo(horizontal ? .trailing : .bottom, animated: false)
                func assertAtEnd() {
                    let inset = scroll.adjustedContentInset
                    let expected = horizontal
                        ? (rtl ? -inset.left : scroll.contentSize.width - scroll.bounds.width + inset.right)
                        : scroll.contentSize.height - scroll.bounds.height + inset.bottom
                    #expect(abs((horizontal ? scroll.contentOffset.x : scroll.contentOffset.y) - expected) < 0.5)
                }
                // 已到底 -> 增高 -> 缩小；变化后不再调用 scrollTo。
                for value: CGFloat in [70, 30, 90] {
                    extent = value
                    layout(host)
                    assertAtEnd()
                }
                enabled = false
                layout(host)
                assertAtEnd()
                enabled = true
                layout(host)
                assertAtEnd()
                let middle = CGPoint(x: horizontal ? 200 : 0, y: horizontal ? 0 : 200)
                scroll.setContentOffset(middle, animated: false)
                extent = 50
                layout(host)
                #expect(scroll.contentOffset == middle)
            }
        }
    }

    @Test func removalAndReparentingRestoreOnlyOwnedInsets() {
        let scroll = QuickLayoutScrollView(.vertical)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset.bottom = 9
        var includes = true
        let first = InsetTestHost {
            if includes {
                QuickLayoutKit.ScrollView(scroll) { UIView().resizable(axis: .horizontal).frame(height: 900) }
                    .safeAreaInset(edge: .bottom) { UIView().frame(height: 40) }
            }
        }
        layout(first)
        #expect(scroll.contentInset.bottom == 49)
        includes = false
        layout(first)
        #expect(scroll.contentInset.bottom == 9)
        let second = InsetTestHost {
            QuickLayoutKit.ScrollView(scroll) { UIView().resizable(axis: .horizontal).frame(height: 900) }
                .safeAreaInset(edge: .top) { UIView().frame(height: 25) }
        }
        layout(second)
        layout(first)
        #expect(scroll.contentInset.top == 25)
        #expect(scroll.contentInset.bottom == 9)
    }

    @Test func leadingAndTrailingUsePhysicalEdgesInBothDirections() {
        for rtl in [false, true] {
            let scroll = QuickLayoutScrollView(.vertical)
            scroll.contentInsetAdjustmentBehavior = .never
            let leading = UIView(), trailing = UIView()
            let host = InsetTestHost {
                QuickLayoutKit.ScrollView(scroll) { UIView().resizable(axis: .horizontal).frame(height: 900) }
                    .safeAreaInset(edge: QuickLayoutKit.HorizontalEdge.leading, spacing: 4) { leading.frame(width: 30, height: 80) }
                    .safeAreaInset(edge: QuickLayoutKit.HorizontalEdge.trailing, spacing: 6) { trailing.frame(width: 20, height: 80) }
            }
            host.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            scroll.semanticContentAttribute = host.semanticContentAttribute
            host.testInsets = UIEdgeInsets(top: 0, left: 7, bottom: 0, right: 13)
            layout(host)
            #expect(scroll.frame == host.bounds)
            #expect(abs(scroll.contentInset.left - CGFloat(7 + (rtl ? 26 : 34))) < 0.01)
            #expect(abs(scroll.contentInset.right - CGFloat(13 + (rtl ? 34 : 26))) < 0.01)
            #expect(abs((rtl ? 320 - leading.frame.maxX : leading.frame.minX) - (rtl ? 13 : 7)) < 0.5)
        }
    }

    @Test func keyboardAndBarShareObstructionWithoutDoublingInsets() {
        let scroll = QuickLayoutScrollView(.vertical)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset.bottom = 7
        let host = InsetTestHost {
            QuickLayoutKit.ScrollView(scroll) { UIView().resizable(axis: .horizontal).frame(height: 900) }
                .contentMargins(.bottom, 11)
                .safeAreaInset(edge: .bottom) { UIView().frame(height: 50) }
        }
        // 模拟宿主已经发布 120 点底部遮挡，同时滚动避让器收到相同几何。
        host.testInsets.bottom = 120
        layout(host)
        let avoider = QuickLayoutKeyboardAvoider(scrollView: scroll, notificationCenter: NotificationCenter())
        avoider.apply(QuickLayoutKeyboardContext(endFrame: CGRect(x: 0, y: 360, width: 320, height: 120),
                                                animationDuration: 0, animationOptions: .curveLinear, isVisible: true))
        #expect(abs(scroll.contentInset.bottom - 188) < 0.01)
        layout(host)
        #expect(scroll.contentInset.bottom == 188)
        avoider.apply(.hidden)
        host.testInsets.bottom = 20
        layout(host)
        #expect(scroll.contentInset.bottom == 88)
        avoider.stop()
        #expect(scroll.contentInset.bottom == 88)
    }

    @Test func removingModifierKeepsScrollAndBusinessMargins() {
        let scroll = QuickLayoutScrollView(.vertical)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset.bottom = 7
        var enabled = true
        let host = InsetTestHost {
            let page = QuickLayoutKit.ScrollView(scroll) { UIView().resizable(axis: .horizontal).frame(height: 900) }
                .contentMargins(.bottom, 11)
            if enabled { page.safeAreaInset(edge: .bottom) { UIView().frame(height: 50) } }
            else { page }
        }
        layout(host)
        #expect(scroll.contentInset.bottom == 68)
        enabled = false
        layout(host)
        #expect(scroll.contentInset.bottom == 18)
        #expect(scroll.frame == host.bounds)
    }

    @Test func scrollViewportAndBarMatchSwiftUI() async {
        for rtl in [false, true] {
            let referenceBar = UIView()
            let native = SwiftUI.ScrollView {
                Color.clear.frame(height: 900)
            }.safeAreaInset(edge: .bottom, spacing: 8) {
                Color.blue.frame(height: 50).background(InsetProbe(view: referenceBar))
            }.environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            let hosting = UIHostingController(rootView: native)
            hosting.safeAreaRegions = []
            let scroll = QuickLayoutScrollView(.vertical)
            scroll.contentInsetAdjustmentBehavior = .never
            let bar = UIView()
            let actual = InsetTestHost {
                QuickLayoutKit.ScrollView(scroll) { UIView().resizable(axis: .horizontal).frame(height: 900) }
                    .safeAreaInset(edge: .bottom, spacing: 8) { bar.resizable(axis: .horizontal).frame(height: 50) }
            }
            actual.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            let controller = UIViewController()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 800))
            window.rootViewController = controller
            window.isHidden = false
            defer { window.isHidden = true }
            controller.addChild(hosting)
            controller.view.addSubview(hosting.view)
            hosting.didMove(toParent: controller)
            controller.view.addSubview(actual)
            hosting.view.frame = CGRect(x: 0, y: 100, width: 320, height: 480)
            actual.frame = CGRect(x: 400, y: 100, width: 320, height: 480)
            for _ in 0..<8 {
                hosting.view.setNeedsLayout()
                hosting.view.layoutIfNeeded()
                actual.setNeedsQuickLayout()
                actual.layoutIfNeeded()
                try? await Task.sleep(for: .milliseconds(20))
            }
            let nativeScroll = findScroll(hosting.view)
            #expect(nativeScroll != nil)
            if let nativeScroll {
                #expect(scroll.bounds.size == nativeScroll.bounds.size)
                #expect(abs(scroll.adjustedContentInset.bottom - nativeScroll.adjustedContentInset.bottom) < 0.5)
            }
            #expect(bar.convert(bar.bounds, to: actual) == referenceBar.convert(referenceBar.bounds, to: hosting.view))
        }
    }

    @Test func demoScenariosResizeAndKeepLastRowReachable() {
        let page = SafeAreaInsetViewController()
        page.loadViewIfNeeded()
        for size in [CGSize(width: 390, height: 844), CGSize(width: 669, height: 951), CGSize(width: 768, height: 600)] {
            page.view.frame = CGRect(origin: .zero, size: size)
            for scenario in SafeAreaInsetStageView.Scenario.allCases {
                page.selectScenario(scenario)
                for _ in 0..<4 { page.view.setNeedsLayout(); page.view.layoutIfNeeded() }
                let stage = page.stage
                let scroll = stage.scrollView
                scroll.scrollTo(.bottom, animated: false)
                let last = scroll.subviews.first { $0.accessibilityIdentifier == "safeAreaInset.row.24" }
                #expect(last != nil)
                if let last {
                    let lastRect = last.convert(last.bounds, to: stage)
                    let bottom = [.bottom, .repeated, .mixed, .keyboard].contains(scenario)
                        ? stage.primaryBar.frame.minY : stage.bounds.maxY
                    #expect(lastRect.maxY <= bottom + 0.5,
                            "scenario=\(scenario) size=\(size) last=\(lastRect) bar=\(stage.primaryBar.frame) scroll=\(scroll.frame) inset=\(scroll.adjustedContentInset)")
                }
                #expect(scroll.frame == stage.bounds)
            }
        }
    }

    // 真实键盘及拖动由 UI 测试覆盖；这里注入通知，独立验证嵌套宿主的坐标换算。
    @Test func nestedDemoHostFollowsKeyboardNotifications() throws {
        let page = SafeAreaInsetViewController()
        let stage = page.stage
        let center = NotificationCenter()
        stage.quickLayoutKeyboardSafeAreaBehavior = .disabled
        stage.configureQuickLayoutKeyboardSafeAreaForTesting(notificationCenter: center) { _, _ in true }
        stage.quickLayoutKeyboardSafeAreaBehavior = .followsDockedKeyboard()
        let window = try makeVisibleTestWindow(rootViewController: UINavigationController(rootViewController: page))
        defer { window.isHidden = true }
        page.selectScenario(.keyboard)
        for _ in 0..<4 { window.layoutIfNeeded(); page.view.setNeedsLayout(); page.view.layoutIfNeeded() }
        let original = stage.primaryBar.frame.minY
        for height: CGFloat in [240, 120, 0] {
            let frame = stage.convert(CGRect(x: 0, y: stage.bounds.height - height,
                                            width: stage.bounds.width, height: height), to: nil)
            center.post(name: height > 0 ? UIResponder.keyboardWillShowNotification : UIResponder.keyboardWillHideNotification,
                        object: nil, userInfo: [UIResponder.keyboardFrameEndUserInfoKey: frame,
                                               UIResponder.keyboardAnimationDurationUserInfoKey: 0])
            for _ in 0..<3 { stage.setNeedsLayout(); stage.layoutIfNeeded() }
            if height > 0 {
                #expect(stage.primaryBar.frame.minY < original)
                #expect(abs(stage.primaryBar.frame.maxY - (stage.bounds.height - height)) < 0.5)
            } else {
                #expect(abs(stage.primaryBar.frame.minY - original) < 0.5)
            }
        }
    }

    @Test func demoBackgroundExtendsOnlyBeyondOutermostBottomBar() throws {
        for rtl in [false, true] {
            let stage = SafeAreaInsetStageView()
            stage.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            stage.scrollView.semanticContentAttribute = stage.semanticContentAttribute
            let controller = UIViewController()
            controller.view = stage
            let window = try makeVisibleTestWindow(rootViewController: controller,
                                                  size: CGSize(width: 706, height: 460))
            defer { window.isHidden = true }
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 24, bottom: 24, right: 40)
            for scenario in SafeAreaInsetStageView.Scenario.allCases {
                stage.scenario = scenario
                for expanded in [false, true] {
                    stage.expanded = expanded
                    for _ in 0..<3 { window.layoutIfNeeded(); stage.setNeedsQuickLayout(); stage.layoutIfNeeded() }
                    let outer: SafeAreaInsetBarView?
                    switch scenario {
                    case .bottom, .mixed, .keyboard: outer = stage.primaryBar
                    case .repeated: outer = stage.secondaryBar
                    default: outer = nil
                    }
                    for bar in [stage.primaryBar, stage.secondaryBar] {
                        if bar === outer {
                            #expect(stage.safeAreaInsets.bottom > 0)
                            let background = bar.insetBackground.convert(bar.insetBackground.bounds, to: stage)
                            #expect(abs(background.maxY - stage.bounds.maxY) < 0.5)
                            #expect(abs(bar.frame.maxY - (stage.bounds.maxY - stage.safeAreaInsets.bottom)) < 0.5)
                            #expect(background.minX >= stage.safeAreaInsets.left - 0.5)
                            #expect(background.maxX <= stage.bounds.maxX - stage.safeAreaInsets.right + 0.5)
                            let title = bar.titleLabel.convert(bar.titleLabel.bounds, to: stage)
                            #expect(title.maxY <= bar.frame.maxY)
                            #expect(bar.insetBackground.superview === bar)
                            #expect(bar.subviews.first === bar.insetBackground)
                            #expect(!bar.insetBackground.isUserInteractionEnabled)
                        } else {
                            #expect(bar.insetBackground.frame == bar.bounds)
                        }
                    }
                    if outer != nil {
                        stage.scrollView.scrollTo(.bottom, animated: false)
                        let last = try #require(stage.scrollView.subviews.first {
                            $0.accessibilityIdentifier == "safeAreaInset.row.24"
                        })
                        let lastFrame = last.convert(last.bounds, to: stage)
                        #expect(lastFrame.maxY <= stage.primaryBar.frame.minY - stage.spacing + 0.5)
                    }
                }
            }
        }
    }

    @Test func keyboardBarStaysInsideShortContainerAndSafeCrossAxis() throws {
        for size in [CGSize(width: 706, height: 460), CGSize(width: 402, height: 640)] {
            let stage = SafeAreaInsetStageView()
            let center = NotificationCenter()
            stage.quickLayoutKeyboardSafeAreaBehavior = .disabled
            stage.configureQuickLayoutKeyboardSafeAreaForTesting(notificationCenter: center) { _, _ in true }
            stage.quickLayoutKeyboardSafeAreaBehavior = .followsDockedKeyboard()
            stage.scenario = .keyboard
            let controller = UIViewController()
            controller.view = stage
            let window = try makeVisibleTestWindow(rootViewController: controller, size: size)
            defer { window.isHidden = true }
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 40)
            window.layoutIfNeeded()
            for keyboardHeight: CGFloat in [0, 240, 0] {
                let keyboardFrame = stage.convert(CGRect(x: 0, y: stage.bounds.height - keyboardHeight,
                                                         width: stage.bounds.width, height: keyboardHeight), to: nil)
                center.post(name: keyboardHeight == 0 ? UIResponder.keyboardWillHideNotification : UIResponder.keyboardWillShowNotification,
                            object: nil, userInfo: [UIResponder.keyboardFrameEndUserInfoKey: keyboardFrame,
                                                   UIResponder.keyboardAnimationDurationUserInfoKey: 0])
                for _ in 0..<3 { stage.setNeedsQuickLayout(); stage.layoutIfNeeded() }
                let bar = stage.primaryBar
                let field = bar.field.convert(bar.field.bounds, to: stage)
                let title = bar.titleLabel.convert(bar.titleLabel.bounds, to: stage)
                #expect(bar.frame.minX >= stage.safeAreaInsets.left - 0.5)
                #expect(bar.frame.maxX <= stage.bounds.width - stage.safeAreaInsets.right + 0.5)
                #expect(field.minX >= bar.frame.minX + 15.5)
                #expect(field.maxX <= bar.frame.maxX - 15.5)
                #expect(title.minY >= bar.frame.minY)
                #expect(field.minY >= title.maxY)
                #expect(bar.frame.maxY <= stage.bounds.height - keyboardHeight + 0.5)
                #expect(field.maxY <= bar.frame.maxY)
                let background = bar.insetBackground.convert(bar.insetBackground.bounds, to: stage)
                let expectedBottom = keyboardHeight == 0 ? stage.bounds.maxY : bar.frame.maxY
                #expect(abs(background.maxY - expectedBottom) < 0.5)
                #expect(background.maxY <= stage.bounds.maxY - keyboardHeight + 0.5)
            }
        }
    }

    @Test func keyboardDismissPaddingTracksVisibleInsetAndClearsOnRemoval() {
        let stage = SafeAreaInsetStageView(frame: CGRect(x: 0, y: 0, width: 706, height: 460))
        for (scenario, expanded) in [(SafeAreaInsetStageView.Scenario.keyboard, false), (.keyboard, true), (.none, false)] {
            stage.scenario = scenario
            stage.expanded = expanded
            for _ in 0..<3 { stage.setNeedsQuickLayout(); stage.layoutIfNeeded() }
            if #available(iOS 17.0, *) {
                let expected = scenario == .keyboard ? stage.primaryBar.bounds.height + stage.spacing : 0
                #expect(abs(stage.quickLayoutKeyboardDismissPadding - expected) < 0.5)
            }
            if scenario == .keyboard {
                #expect(stage.primaryBar.field.bounds.height >= 44)
            }
        }
    }

    @Test func insetBarStateChangeRelayoutsWithoutChangingBounds() {
        let bar = SafeAreaInsetBarView(frame: CGRect(x: 0, y: 0, width: 300, height: 160))
        bar.titleLabel.text = "Inset"
        bar.layoutIfNeeded()
        bar.showsInput = true
        bar.layoutIfNeeded()
        #expect(bar.field.superview === bar)
        let compactY = bar.field.frame.minY
        bar.expanded = true
        bar.layoutIfNeeded()
        #expect(bar.field.frame.minY > compactY)
        #expect(bar.field.frame.minX >= 16)
        bar.showsInput = false
        bar.layoutIfNeeded()
        #expect(bar.field.superview == nil)
    }

    private func layout(_ host: UIView) {
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        for _ in 0..<3 { host.setNeedsLayout(); host.layoutIfNeeded() }
    }
    private func findScroll(_ view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { findScroll($0) }.first
    }
}

private final class InsetTestHost: QuickLayoutView {
    var testInsets = UIEdgeInsets.zero
    override var safeAreaInsets: UIEdgeInsets { testInsets }
}
private struct InsetProbe: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
