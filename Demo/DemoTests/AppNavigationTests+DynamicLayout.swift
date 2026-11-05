import QuickLayout
import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

extension AppNavigationTests {
    @Test func nestedSafeAreaChangeInvalidatesNaturalScrollViewport() {
        let child = MutableSafeAreaLayoutView {
            UILabel().frame(height: 40).safeAreaPadding(.bottom, 0)
        }
        let scroll = QuickLayoutScrollView()
        let host = QuickLayoutView {
            ContentFittingScroll(scroll) {
                child.resizable(axis: .horizontal).fixedSize(axis: .vertical)
            }
        }
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
        host.layoutIfNeeded()
        for bottom in [34.0, 58.0, 0.0, 34.0] {
            child.testInsets.bottom = bottom
            child.safeAreaInsetsDidChange()
            // 只消费已发布的失效，不手动将外层标记为需要布局。
            for _ in 0..<4 { host.layoutIfNeeded() }
            #expect(abs(scroll.bounds.height - (40 + bottom)) < 1)
            #expect(abs(child.bounds.height - scroll.bounds.height) < 1)
        }
    }

    /// 遍历目录中的真实页面；同一控制器连续缩放，检查页面滚动视口的交叉轴范围。
    @Test func catalogPagesKeepVerticalScrollContentWithinResizedViewport() throws {
        let router = MainRouter()
        for route in MainRoute.allCases where AppTab(route: route) == nil && route.isAvailable {
            let controller = try #require(router.makeViewController(for: route))
            let window = try makeVisibleTestWindow(rootViewController: controller, size: CGSize(width: 1024, height: 900))
            defer { window.isHidden = true }
            (controller as? ViewThatFitsViewController)?.setProposedSize(CGSize(width: 320, height: 160))
            for width in [1024.0, 768.0, 600.0, 375.0, 320.0, 1366.0, 1024.0] {
                window.frame.size.width = width
                controller.view.frame = window.bounds
                window.layoutIfNeeded()
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                for scroll in controller.view.allSubviews(of: QuickLayoutScrollView.self) where scroll.axis == .vertical {
                    scroll.layoutIfNeeded()
                    guard scroll.bounds.width > 0 else { continue }
                    let available = max(0, scroll.bounds.width - scroll.adjustedContentInset.left - scroll.adjustedContentInset.right)
                    #expect(scroll.contentSize.width <= available + 1,
                            "\(route) at \(width): content \(scroll.contentSize.width), viewport \(available)")
                    #expect(scroll.contentSize.height.isFinite)
                    var contentViews: [UIView] = []
                    scroll.body.quick_extractViewsIntoArray(&contentViews)
                    for child in contentViews where child.bounds.width > 0 && !child.isHidden {
                        let frame = child.convert(child.bounds, to: scroll)
                        #expect(frame.minX >= -1 && frame.maxX <= available + 1,
                                "\(route) at \(width): \(type(of: child)) \(frame), viewport \(available)")
                    }
                }
            }
        }
    }

    @Test func fittingScrollMeasuresInsideItsOwnContainerContext() {
        let label = UILabel()
        label.numberOfLines = 0
        label.text = String(repeating: "Content follows its scroll viewport. ", count: 20)
        let scroll = QuickLayoutScrollView()
        scroll.contentInset = UIEdgeInsets(top: 10, left: 16, bottom: 20, right: 16)
        let host = QuickLayoutView {
            ContentFittingScroll(scroll) {
                label.resizable(axis: .horizontal).containerRelativeFrame(.horizontal)
            }.frame(maxWidth: 620)
        }
        for width in [1000.0, 320.0, 600.0, 1000.0] {
            host.frame = CGRect(x: 0, y: 0, width: width, height: 1800)
            host.setNeedsLayout()
            host.layoutIfNeeded()
            scroll.layoutIfNeeded()
            #expect(abs(scroll.bounds.height - scroll.contentSize.height - 30) < 1)
            #expect(abs(label.bounds.width - (min(width, 620) - 32)) < 1)
        }
    }

    @Test func roomHeaderMeasurementDoesNotDependOnPreviousBounds() {
        let header = RoomHeaderView()
        header.configure(roomTitle: "Room", roomSubtitle: "Music", audience: "12 online",
                         audienceAccessibilityHint: "Audience", avatarAccessibilityLabel: "Room",
                         avatarAccessibilityHint: "Details")
        header.configureFollowing(followTitle: "Follow", followedTitle: "Following",
                                  accessibilityTitle: "Follow", isFollowing: false, isRequesting: false)
        let proposal = CGSize(width: 620, height: CGFloat.infinity)
        let initial = header.sizeThatFits(proposal)
        for width in [280.0, 620.0, 320.0, 620.0] {
            header.frame = CGRect(x: 0, y: 0, width: width, height: 160)
            header.setNeedsLayout()
            header.layoutIfNeeded()
            #expect(header.sizeThatFits(proposal) == initial)
        }
    }

    @Test func giftSheetMeasuresCurrentWidthBeforePlacement() {
        let sheet = GiftSheetView(recipients: VoiceRoomPreviewData.occupiedSeats, gifts: Gift.catalog,
                                  initiallySelectedRecipientSeatIDs: [], initialBalance: 12_800)
        for width in [320.0, 620.0, 340.0, 390.0, 320.0] {
            let proposal = CGSize(width: width, height: .infinity)
            let measured = sheet.sizeThatFits(proposal)
            sheet.frame = CGRect(origin: .zero, size: measured)
            sheet.setNeedsLayout()
            sheet.layoutIfNeeded()
            #expect(sheet.sizeThatFits(proposal) == measured)
            #expect(sheet.usesCompactMetrics == (width < 350))
        }
    }

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
                if controller.view.effectiveUserInterfaceLayoutDirection == .rightToLeft {
                    #expect(weekly.maxX <= profile.minX)
                } else {
                    #expect(weekly.minX >= profile.maxX)
                }
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

private final class MutableSafeAreaLayoutView: QuickLayoutView {
    var testInsets = UIEdgeInsets.zero
    override var safeAreaInsets: UIEdgeInsets { testInsets }
}
