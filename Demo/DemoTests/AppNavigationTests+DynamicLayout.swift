import QuickLayout
import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

extension AppNavigationTests {
    @Test func keyboardControlsRemainReachableInShortContainer() {
        let view = AnimatedKeyboardResponsiveView()
        for height in [700.0, 180.0, 320.0, 700.0] {
            view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            view.contentScrollView.layoutIfNeeded()
            view.contentScrollView.scrollTo(.bottom, animated: false)
            let button = view.submitButton.convert(view.submitButton.bounds, to: view)
            #expect(button.minY >= 20)
            #expect(button.maxY <= height)
            #expect(button.height == 50)
            #expect(view.textField.bounds.height == 44)
            #expect(view.contentScrollView.bounds.height <= height - 40)
            if height == 180 {
                #expect(view.contentScrollView.contentSize.height > view.contentScrollView.bounds.height)
            }
        }
    }

    /// 同一宿主往返缩放，验证滚动视口采用当前提议，且内容不会被压缩到不可读。
    @Test func fittingScrollReflowsAcrossContinuousContainerChanges() {
        let label = UILabel()
        label.numberOfLines = 0
        label.text = String(repeating: "Content follows its container. ", count: 45)
        let scroll = QuickLayoutScrollView()
        let host = QuickLayoutView {
            ContentFittingScroll(scroll) {
                label.resizable(axis: .horizontal).padding(16)
            }.frame(maxWidth: 620)
        }
        var expandedHeight: CGFloat = 0
        for size in [CGSize(width: 900, height: 900), CGSize(width: 320, height: 240),
                     CGSize(width: 500, height: 180), CGSize(width: 900, height: 900)] {
            host.frame.size = size
            host.setNeedsLayout()
            host.layoutIfNeeded()
            scroll.layoutIfNeeded()
            #expect(scroll.bounds.width <= min(620, size.width) + 1)
            #expect(scroll.bounds.height > 0 && scroll.bounds.height <= size.height + 1)
            #expect(label.bounds.width > 0 && label.bounds.width <= scroll.bounds.width - 32 + 1)
            #expect(label.bounds.height >= label.sizeThatFits(CGSize(width: label.bounds.width, height: .infinity)).height - 1)
            if size.height == 900 {
                if expandedHeight > 0 { #expect(abs(scroll.bounds.height - expandedHeight) < 1) }
                expandedHeight = scroll.bounds.height
                #expect(scroll.bounds.height < size.height)
            } else {
                #expect(scroll.contentSize.height > scroll.bounds.height)
            }
        }
    }

    /// 不重建控制器：扩展、缩小、加入侧栏安全区，再恢复原尺寸。
    @Test func dashboardReflowsWithinChangingSafeViewport() throws {
        let controller = DashboardViewController()
        let window = try makeVisibleTestWindow(rootViewController: controller, size: CGSize(width: 1200, height: 900))
        defer { window.isHidden = true }
        for (width, inset) in [(1200.0, 0.0), (1200.0, 360.0), (390.0, 0.0), (1200.0, 0.0)] {
            window.frame.size.width = width
            controller.view.frame = window.bounds
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: 0)
            window.layoutIfNeeded()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            controller.scrollView.layoutIfNeeded()
            let profile = controller.profileCardView.convert(controller.profileCardView.bounds, to: controller.view)
            let weekly = controller.weeklyGoalCardView.convert(controller.weeklyGoalCardView.bounds, to: controller.view)
            let safe = controller.view.safeAreaLayoutGuide.layoutFrame
            #expect(profile.minX >= safe.minX && profile.maxX <= safe.maxX)
            #expect(weekly.minX >= safe.minX && weekly.maxX <= safe.maxX)
            #expect(profile.width > 0 && weekly.width > 0)
            if width - inset >= 1000 {
                #expect(weekly.minX >= profile.maxX)
            } else {
                #expect(weekly.minY >= profile.maxY)
            }
        }
    }

    @Test func frameLabKeepsControlsInsideResizedViewport() throws {
        let controller = FrameLabViewController()
        let window = try makeVisibleTestWindow(rootViewController: controller, size: CGSize(width: 1200, height: 900))
        defer { window.isHidden = true }
        controller.selectPresentation(.guided)
        let page = controller.contentView
        page.selectScenario(.alignment)
        page.selectAlignment(8)
        for width in [1200.0, 744.0, 390.0, 320.0, 1200.0] {
            window.frame.size.width = width
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            page.layoutIfNeeded()
            page.pageScrollView.layoutIfNeeded()
            let scroll = page.pageScrollView
            let visible = scroll.bounds.inset(by: scroll.adjustedContentInset)
            for control in page.allSubviews(of: UIControl.self) where control.bounds.width > 0 {
                let frame = control.convert(control.bounds, to: scroll)
                #expect(frame.minX >= visible.minX - 1)
                #expect(frame.maxX <= visible.maxX + 1)
            }
            #expect(page.state.alignmentIndex == 8)
            #expect(controller.contentView === page)
        }
    }
}
