import QuickLayout
import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

extension AppNavigationTests {
    /// 使用 Demo 的应用宿主运行真实 UIScrollView 动画，不以静态 offset 断言代替动画完成。
    @Test(arguments: [false, true])
    func crossAxisInsetChangePreservesRunningScrollAnimation(horizontal: Bool) async throws {
        let host = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        let scroll = SplitScrollAnimationProbe(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = scroll
        _ = ScrollView(scroll, horizontal ? .horizontal : .vertical) {
            UIView().frame(width: horizontal ? 1200 : 300, height: horizontal ? 300 : 1200)
        }
        host.view.addSubview(scroll)
        scroll.layoutIfNeeded()
        scroll.scrollTo(horizontal ? .trailing : .bottom, animated: true)
        func position() -> CGFloat { horizontal ? scroll.contentOffset.x : scroll.contentOffset.y }
        try #require(await waitForCondition { position() > 20 && position() < 880 })
        let before = position()
        scroll.testInsets = horizontal
            ? UIEdgeInsets(top: 80, left: 0, bottom: 10, right: 0)
            : UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 10)
        scroll.safeAreaInsetsDidChange()
        scroll.layoutIfNeeded()
        #expect(scroll.restoredStaleCrossAxisCount > 0)
        #expect(await waitForCondition { position() > before + 10 })
        #expect(await waitForCondition { scroll.completedAnimations == 1 && abs(position() - 900) < 1 })
        scroll.layoutIfNeeded()
        #expect(abs((horizontal ? scroll.contentOffset.y : scroll.contentOffset.x) + 80) < 1)
    }

    @Test(arguments: [false, true])
    func crossAxisAlignmentPrecedesPendingScrollAnimation(horizontal: Bool) async throws {
        let host = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        let scroll = SplitScrollAnimationProbe(frame: .zero)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = scroll
        _ = ScrollView(scroll, horizontal ? .horizontal : .vertical) {
            UIView().frame(width: horizontal ? 1200 : 300, height: horizontal ? 300 : 1200)
        }
        // 零尺寸时请求滚动，等待首次有效布局，同时引入非滚动轴 inset。
        scroll.scrollTo(horizontal ? .trailing : .bottom, animated: true)
        host.view.addSubview(scroll)
        scroll.testInsets = horizontal
            ? UIEdgeInsets(top: 80, left: 0, bottom: 10, right: 0)
            : UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 10)
        scroll.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        scroll.layoutIfNeeded()
        #expect(scroll.restoredStaleCrossAxisCount > 0)
        #expect(await waitForCondition {
            scroll.completedAnimations == 1
                && abs((horizontal ? scroll.contentOffset.x : scroll.contentOffset.y) - 900) < 1
        })
        #expect(abs((horizontal ? scroll.contentOffset.y : scroll.contentOffset.x) + 80) < 1)
    }

    @Test(.enabled("Expanded split-view layout requires iPad") {
        await MainActor.run { UIDevice.current.userInterfaceIdiom == .pad }
    })
    func splitSafeAreaScenariosPreserveModifierContrast() async throws {
        let split = ExampleSplitViewController()
        let window = try makeVisibleTestWindow(rootViewController: split, size: CGSize(width: 1133, height: 744))
        defer { window.isHidden = true }
        split.select(.safeAreaPadding)
        let page = try #require(split.detailNavigationController.viewControllers.first as? SafeAreaPaddingViewController)
        try #require(await waitForCondition { !split.isCollapsed && page.view.window === window })
        for width in [260.0, 360.0, 280.0] {
            split.preferredPrimaryColumnWidth = width
            window.setNeedsLayout()
            window.layoutIfNeeded()
            // 默认布局与显式零间距具有相同安全边界，滚动外框始终保留完整视口。
            // 来回切换不能累积内容 inset。
            for scenario in [SafeAreaPaddingViewController.Scenario.baseline, .zeroAll, .baseline] {
                page.selectScenario(at: scenario.rawValue)
                #expect(await waitForCondition {
                    page.view.layoutIfNeeded()
                    let expected = page.view.bounds
                    let actual = page.pageScrollView.convert(page.pageScrollView.bounds, to: page.view)
                    return actual.width > 0
                        && abs(actual.minX - expected.minX) < 1
                        && abs(actual.minY - expected.minY) < 1
                        && abs(actual.maxX - expected.maxX) < 1
                        && abs(actual.maxY - expected.maxY) < 1
                })
                let actualInsets = page.pageScrollView.adjustedContentInset
                let safe = page.view.safeAreaInsets
                #expect(abs(actualInsets.left - safe.left) < 1)
                #expect(abs(actualInsets.right - safe.right) < 1)
                #expect(abs(actualInsets.top - safe.top) < 1)
                #expect(abs(actualInsets.bottom - safe.bottom) < 1)
                #expect(page.pageScrollView.contentInsetAdjustmentBehavior == .automatic)
            }
        }
    }

    /// 容器级几何回归；真实系统窗口/分隔线手势另由 UI 测试覆盖。
    @Test(.enabled("Expanded split-view layout requires iPad") {
        await MainActor.run { UIDevice.current.userInterfaceIdiom == .pad }
    })
    func splitDetailRespectsAsymmetricSafeAreaAcrossColumnWidths() async throws {
        let split = ExampleSplitViewController()
        let window = try makeVisibleTestWindow(rootViewController: split, size: CGSize(width: 1133, height: 744))
        defer { window.isHidden = true }
        split.select(.counter)
        let detail = try #require(split.detailNavigationController.viewControllers.first as? CounterViewController)
        try #require(await waitForCondition { !split.isCollapsed && detail.view.window === window })
        for width in [260.0, 360.0, 280.0] {
            split.preferredPrimaryColumnWidth = width
            for insets in [UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 12),
                           UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 64)] {
                detail.additionalSafeAreaInsets = insets
                window.setNeedsLayout()
                window.layoutIfNeeded()
                #expect(await waitForCondition {
                    detail.view.layoutIfNeeded()
                    let safe = detail.view.safeAreaLayoutGuide.layoutFrame
                    let button = detail.incrementButton.convert(detail.incrementButton.bounds, to: detail.view)
                    return button.width > 0 && button.minX >= safe.minX - 1 && button.maxX <= safe.maxX + 1
                }, "Counter content must remain inside the actual asymmetric safe area at column width \(width), insets \(insets)")
                let scroll = try #require(detail.view.allSubviews(of: QuickLayoutScrollView.self).first)
                let safe = detail.view.safeAreaLayoutGuide.layoutFrame
                let controls = try #require(detail.incrementButton.superview)
                let frame = controls.convert(controls.bounds, to: detail.view)
                #expect(frame.minX >= safe.minX - 1 && frame.maxX <= safe.maxX + 1,
                        "controls \(frame), safe \(safe), adjusted \(scroll.adjustedContentInset)")
            }
        }
    }
}

@MainActor
private final class SplitScrollAnimationProbe: QuickLayoutScrollView, UIScrollViewDelegate {
    // 重现修复针对的 UIKit 状态：内容尺寸已更新，非滚动轴仍保留旧偏移。
    // 单纯改变 inset 可能被 UIKit 在 super.layoutSubviews 中自动校正，漏测修正分支。
    var testInsets = UIEdgeInsets.zero {
        willSet {
            staleCrossAxisOffset = axis == .vertical ? bounds.origin.x : bounds.origin.y
        }
    }
    var completedAnimations = 0
    var restoredStaleCrossAxisCount = 0
    private var staleCrossAxisOffset: CGFloat?

    // 本探针只模拟交叉轴 inset，排除窗口顶部安全区改变内容长度的影响。
    override var safeAreaInsets: UIEdgeInsets { .zero }
    override var adjustedContentInset: UIEdgeInsets { testInsets }

    override var contentSize: CGSize {
        didSet {
            guard let staleCrossAxisOffset else { return }
            self.staleCrossAxisOffset = nil
            var staleBounds = bounds
            if axis == .vertical {
                staleBounds.origin.x = staleCrossAxisOffset
            } else {
                staleBounds.origin.y = staleCrossAxisOffset
            }
            bounds = staleBounds
            restoredStaleCrossAxisCount += 1
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        completedAnimations += 1
    }
}
