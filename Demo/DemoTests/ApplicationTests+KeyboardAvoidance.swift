import QuickLayout
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
import Testing
import UIKit

extension ApplicationTests {
    @Test func keyboardAvoiderIgnoresForeignAndRemovedInputs() {
        let center = NotificationCenter()
        let root = UIView()
        let scroll = keyboardTestScroll()
        root.addSubview(scroll)
        let other = UITextField(frame: CGRect(x: 10, y: 700, width: 100, height: 44))
        root.addSubview(other)
        let avoider = QuickLayoutKeyboardAvoider(scrollView: scroll, notificationCenter: center)
        center.post(name: UITextField.textDidBeginEditingNotification, object: other)
        avoider.apply(keyboardTestContext(y: 360))
        avoider.scrollActiveViewIntoVisibleArea(animated: false)
        #expect(scroll.contentOffset.y == 0)

        scroll.addSubview(other)
        avoider.setActiveView(other)
        root.addSubview(other)
        avoider.scrollActiveViewIntoVisibleArea(animated: false)
        #expect(scroll.contentOffset.y == 0)
    }

    @Test func keyboardAvoiderUsesActualObstructionForFloatingAndDockedKeyboards() {
        let scroll = keyboardTestScroll(height: 600)
        let avoider = QuickLayoutKeyboardAvoider(scrollView: scroll, notificationCenter: NotificationCenter())
        let field = UITextField(frame: CGRect(x: 110, y: 220, width: 100, height: 40))
        scroll.addSubview(field)
        avoider.setActiveView(field)
        let floating = CGRect(x: 90, y: 200, width: 160, height: 130)
        avoider.apply(keyboardTestContext(frame: floating))
        #expect(scroll.contentOffset.y > 0)
        #expect(!field.frame.offsetBy(dx: 0, dy: -scroll.contentOffset.y).intersects(floating))

        scroll.contentOffset = .zero
        field.frame.origin.x = 260
        avoider.scrollActiveViewIntoVisibleArea(animated: false)
        #expect(scroll.contentOffset.y == 0)

        field.frame = CGRect(x: 10, y: 390, width: 200, height: 12)
        avoider.safeAreaStrategy = .subtractExisting
        avoider.apply(keyboardTestContext(frame: CGRect(x: 0, y: 380, width: 320, height: 220)))
        #expect(abs(scroll.contentInset.bottom - 196) < 0.01)
        #expect(field.frame.maxY - scroll.contentOffset.y <= 380)
    }

    @Test func keyboardAvoiderRecapturesAndRestoresOnlyItsOwnInsets() {
        let scroll = keyboardTestScroll()
        scroll.verticalScrollIndicatorInsets.bottom = 8
        scroll.horizontalScrollIndicatorInsets.bottom = 6
        let first = QuickLayoutKeyboardAvoider(scrollView: scroll, notificationCenter: NotificationCenter())
        let show = keyboardTestContext(y: 360)
        first.apply(show)
        scroll.contentInset.top = 17
        scroll.horizontalScrollIndicatorInsets.bottom = 22  // 调用方替换了业务基线。
        first.captureCurrentInsetsAsBase()
        first.apply(show)
        #expect(scroll.contentInset.bottom == 130)
        #expect(scroll.verticalScrollIndicatorInsets.bottom == 128)
        #expect(scroll.horizontalScrollIndicatorInsets.bottom == 142)

        var second: QuickLayoutKeyboardAvoider? = QuickLayoutKeyboardAvoider(scrollView: scroll, notificationCenter: NotificationCenter())
        #expect(scroll.contentInset.bottom == 10)
        second?.apply(show)
        first.stop()
        first.apply(.hidden)
        #expect(scroll.contentInset.bottom == 130)
        second = nil
        #expect(scroll.contentInset.top == 17)
        #expect(scroll.contentInset.bottom == 10)
        #expect(scroll.verticalScrollIndicatorInsets.bottom == 8)
        #expect(scroll.horizontalScrollIndicatorInsets.bottom == 22)
    }

    @Test func keyboardAnimationDoesNotUndoSubsequentScrolling() async throws {
        let scroll = keyboardTestScroll()
        let controller = UIViewController()
        controller.view.addSubview(scroll)
        let window = try makeVisibleTestWindow(rootViewController: controller)
        defer { window.isHidden = true }
        let field = UITextField(frame: CGRect(x: 10, y: 700, width: 100, height: 44))
        scroll.addSubview(field)
        let avoider = QuickLayoutKeyboardAvoider(scrollView: scroll, notificationCenter: NotificationCenter())
        avoider.setActiveView(field)
        let frame = window.screen.coordinateSpace.convert(CGRect(x: 0, y: 360, width: 320, height: 120), from: scroll)
        avoider.apply(keyboardTestContext(frame: frame, duration: 0.35))
        try await Task.sleep(for: .milliseconds(60))
        scroll.contentOffset = .zero
        try await Task.sleep(for: .milliseconds(650))
        #expect(scroll.contentOffset.y == 0)
        withExtendedLifetime(avoider) {}
    }

    @Test func keyboardScrollContentRetainsContainerSafeAreaWhileIgnoringKeyboard() {
        let scroll = RegionScroll(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scroll.contentInsetAdjustmentBehavior = .never
        let avoider = QuickLayoutKeyboardAvoider(scrollView: scroll, notificationCenter: NotificationCenter())
        for context in [QuickLayoutKeyboardContext.hidden, keyboardTestContext(y: 360), .hidden] {
            avoider.apply(context)
            scroll.setNeedsLayout()
            scroll.layoutIfNeeded()
            // 键盘出现时，滚动 inset 已包含容器安全区；内容不能再增加 34 点。
            // 隐藏后 .never 没有自动 inset，默认内容布局负责保留容器安全区。
            #expect(scroll.contentSize.height == (context.isVisible ? 20 : 54))
        }
    }

    @Test func keyboardHostAnimatesWhenGuideLagsAndRecoversOnReenable() async throws {
        let host = GuideHost()
        let controller = UIViewController()
        controller.view = host
        let window = try makeVisibleTestWindow(rootViewController: controller)
        defer { window.isHidden = true }
        let center = NotificationCenter()
        host.configureQuickLayoutKeyboardSafeAreaForTesting(notificationCenter: center) { _, view in
            view.keyboardLayoutGuide.layoutFrame.height > view.safeAreaInsets.bottom
        }
        host.quickLayoutKeyboardSafeAreaBehavior = .followsDockedKeyboard(usesBottomSafeArea: false)
        window.layoutIfNeeded()
        let start = host.marker.layer.position.y
        let frame = CGRect(x: 0, y: host.bounds.height - 220, width: host.bounds.width, height: 220)
        center.post(name: UIResponder.keyboardWillChangeFrameNotification, object: window.screen, userInfo: [
            UIResponder.keyboardFrameEndUserInfoKey: window.screen.coordinateSpace.convert(frame, from: host),
            UIResponder.keyboardAnimationDurationUserInfoKey: 0.5,
            UIResponder.keyboardAnimationCurveUserInfoKey: UIView.AnimationCurve.linear.rawValue,
        ])
        try await Task.sleep(for: .milliseconds(30))
        host.guide.reportedFrame = frame
        host.setNeedsLayout()
        host.layoutIfNeeded()
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 220)
        try await Task.sleep(for: .milliseconds(100))
        let mid = try #require(host.marker.layer.presentation()).position.y
        #expect(mid < start - 1 && mid > host.marker.layer.position.y + 1)
        try await Task.sleep(for: .milliseconds(500))
        host.quickLayoutKeyboardSafeAreaBehavior = .disabled
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 0)
        host.quickLayoutKeyboardSafeAreaBehavior = .followsDockedKeyboard(usesBottomSafeArea: false)
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 220)
    }
    @Test func keyboardRapidReversalStaysBetweenLayoutEndpoints() async throws {
        let host = GuideHost()
        let controller = UIViewController()
        controller.view = host
        let window = try makeVisibleTestWindow(rootViewController: controller)
        defer { window.isHidden = true }
        let center = NotificationCenter()
        host.configureQuickLayoutKeyboardSafeAreaForTesting(notificationCenter: center) { _, view in
            view.keyboardLayoutGuide.layoutFrame.height > view.safeAreaInsets.bottom
        }
        host.quickLayoutKeyboardSafeAreaBehavior = .followsDockedKeyboard(usesBottomSafeArea: false)
        host.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        func post(show: Bool) {
            let frame = CGRect(x: 0, y: host.bounds.height - (show ? 220 : 0), width: host.bounds.width, height: 220)
            host.guide.reportedFrame = show ? frame : .zero
            center.post(name: show ? UIResponder.keyboardWillShowNotification : UIResponder.keyboardWillHideNotification,
                        object: window.screen, userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: window.screen.coordinateSpace.convert(frame, from: host),
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.4,
                UIResponder.keyboardAnimationCurveUserInfoKey: 7,
            ])
        }
        let hiddenY = host.marker.layer.position.y
        post(show: true)
        let shownY = host.marker.layer.position.y
        #expect(hiddenY - shownY > 100)
        var samples: [CGFloat] = []
        for frame in 0..<55 {
            if frame == 5 { post(show: false) }
            if frame == 10 { post(show: true) }
            try await Task.sleep(for: .milliseconds(12))
            samples.append(try #require(host.marker.layer.presentation()).position.y)
        }
        let minimum = try #require(samples.min())
        let maximum = try #require(samples.max())
        #expect(minimum >= shownY - 1)
        #expect(maximum <= hiddenY + 1)
        #expect(samples.contains { $0 > shownY + 1 && $0 < hiddenY - 1 })
        #expect(abs((samples.last ?? hiddenY) - shownY) < 1)
    }

    @Test func keyboardHostAndScrollAvoidOnlyTheRemainingIntersection() {
        let host = CombinedHost(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let center = NotificationCenter()
        host.configureQuickLayoutKeyboardSafeAreaForTesting(notificationCenter: center) { _, _ in true }
        host.quickLayoutKeyboardSafeAreaBehavior = .followsDockedKeyboard(usesBottomSafeArea: false)
        let avoider = QuickLayoutKeyboardAvoider(scrollView: host.scroll, notificationCenter: center)
        host.layoutIfNeeded()
        for show in [true, false] {
            center.post(name: show ? UIResponder.keyboardWillShowNotification : UIResponder.keyboardWillHideNotification,
                        object: nil, userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: show ? 360 : 480, width: 320, height: 120),
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ])
            host.layoutIfNeeded()
            #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == (show ? 120 : 0))
            #expect(host.scroll.frame.height == (show ? 360 : 480))
            #expect(host.scroll.contentInset.bottom == 0)
        }
        withExtendedLifetime(avoider) {}
    }

}

@MainActor private func keyboardTestScroll(height: CGFloat = 480) -> UIScrollView {
    let scroll = SafeScroll(frame: CGRect(x: 0, y: 0, width: 320, height: height))
    scroll.contentSize = CGSize(width: 320, height: 1600)
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.contentInset.bottom = 10
    return scroll
}

private func keyboardTestContext(y: CGFloat) -> QuickLayoutKeyboardContext {
    keyboardTestContext(frame: CGRect(x: 0, y: y, width: 320, height: 120))
}

private func keyboardTestContext(frame: CGRect, duration: TimeInterval = 0) -> QuickLayoutKeyboardContext {
    QuickLayoutKeyboardContext(endFrame: frame, animationDuration: duration, animationOptions: .curveLinear, isVisible: true)
}

private final class SafeScroll: UIScrollView {
    override var safeAreaInsets: UIEdgeInsets { UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0) }
}

private final class RegionScroll: QuickLayoutScrollView {
    let marker = UIView()
    override var safeAreaInsets: UIEdgeInsets { UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0) }
    override var body: Layout {
        marker.frame(width: 20, height: 20).safeAreaPadding(.bottom, 0).ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private final class TestKeyboardGuide: UIKeyboardLayoutGuide {
    var reportedFrame: CGRect = .zero
    override var layoutFrame: CGRect { reportedFrame }
}

private final class GuideHost: QuickLayoutView {
    let guide = TestKeyboardGuide()
    let marker = UIView()
    let fill = UIView()
    override var keyboardLayoutGuide: UIKeyboardLayoutGuide { guide }
    override var body: Layout {
        ZStack(alignment: .bottom) {
            fill.resizable()
            marker.frame(width: 40, height: 40).safeAreaPadding(.bottom, 0).ignoresSafeArea(.container, edges: .bottom)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private final class CombinedHost: QuickLayoutView {
    let scroll = QuickLayoutScrollView()
    override var body: Layout {
        scroll.resizable().frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.bottom, 0).ignoresSafeArea(.container, edges: .bottom)
    }
}
