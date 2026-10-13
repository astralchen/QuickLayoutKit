import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    /// 验证内容偏移变化及宿主重建不会重复写入未改变的 UIKit 边距。
    ///
    /// 在窗口中完成首次布局后清零计数，再改变内容偏移并重建声明。最后移除边距修饰符，
    /// 验证框架覆盖可以恢复为基线，同时保留中途的滚动位置。
    ///
    /// - Note: 本测试直接设置 `contentOffset`，不验证触摸手势或减速过程。
    @Test func scrollMarginsRemainStableWhileScrollingAndRebuilding() {
        let scrollView = MarginWriteTrackingScrollView()
        scrollView.contentInsetAdjustmentBehavior = .never
        let card = UIView()
        var includesMargins = true
        let controller = QuickLayoutHostingController {
            if includesMargins {
                ScrollView(scrollView) { card.frame(height: 1600) }
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    .contentMargins(.top, 44, for: .scrollContent)
                    .contentMargins(.bottom, 8, for: .scrollContent)
                    .contentMargins(.top, 44, for: .scrollIndicators)
                    .contentMargins(.bottom, 8, for: .scrollIndicators)
            } else {
                ScrollView(scrollView) { card.frame(height: 1600) }
            }
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 951, height: 669))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        let expectedInsets = scrollView.contentInset
        #expect(expectedInsets.top >= 44)
        #expect(expectedInsets.left >= 16)

        scrollView.insetWrites = 0
        for y in [CGFloat(120), 240, 80, 300, 120] {
            scrollView.contentOffset.y = y
            controller.setNeedsQuickLayout()
            controller.quickLayoutIfNeeded()
            scrollView.layoutIfNeeded()
            #expect(scrollView.contentInset == expectedInsets)
            #expect(abs(scrollView.contentOffset.y - y) < 0.5)
        }
        #expect(scrollView.insetWrites == 0)

        // 删除修饰符仍应恢复调用方边距，不能通过保留旧声明来规避重复写入。
        includesMargins = false
        controller.setNeedsQuickLayout()
        controller.quickLayoutIfNeeded()
        scrollView.layoutIfNeeded()
        #expect(scrollView.contentInset == .zero)
        #expect(scrollView.verticalScrollIndicatorInsets == .zero)
        #expect(abs(scrollView.contentOffset.y - 120) < 0.5)
    }

    /// 验证列表填满宿主，并为安全区域内的悬浮操作按钮预留内容及指示器边距。
    @Test func dynamicScrollDemoFillsScreenAndProtectsItsOverlayAction() {
        let viewController = DynamicScrollViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let buttonFrame = viewController.addButton.convert(
            viewController.addButton.bounds,
            to: viewController.view
        )
        let scrollFrame = viewController.scrollView.convert(
            viewController.scrollView.bounds,
            to: viewController.view
        )

        #expect(abs(scrollFrame.minX - viewController.view.bounds.minX) < 1)
        #expect(abs(scrollFrame.minY - viewController.view.bounds.minY) < 1)
        #expect(abs(scrollFrame.maxX - viewController.view.bounds.maxX) < 1)
        #expect(abs(scrollFrame.maxY - viewController.view.bounds.maxY) < 1)
        #expect(
            abs(buttonFrame.minY - viewController.view.safeAreaInsets.top) < 1
        )
        #expect(
            abs(
                buttonFrame.maxX
                    - viewController.view.bounds.maxX
                    + viewController.view.safeAreaInsets.right
                    + 16
            ) < 1
        )
        #expect(
            viewController.scrollView.adjustedContentInset.top
                >= buttonFrame.maxY - scrollFrame.minY + 7
        )
        #expect(viewController.scrollView.contentInset.left == 16)
        #expect(viewController.scrollView.contentInset.bottom == 8)
        #expect(viewController.scrollView.contentInset.right == 16)
        let indicatorInsets = viewController.scrollView
            .verticalScrollIndicatorInsets
        #expect(
            abs(
                indicatorInsets.top
                    - viewController.scrollView.contentInset.top
            ) < 1
        )
        #expect(
            abs(
                indicatorInsets.bottom
                    - viewController.scrollView.contentInset.bottom
            ) < 1
        )
    }

    /// 验证卡片显示本地化文本，并仅通过独立删除按钮暴露可操作的删除入口。
    @Test func dynamicScrollCardsExposeLocalizedDeletionAffordance() throws {
        let localizer = Localizer { key, arguments in
            guard !arguments.isEmpty else { return key }
            return key + ": "
                + arguments.map { String(describing: $0) }
                    .joined(separator: " | ")
        }
        let viewController = DynamicScrollViewController(
            viewModel: DynamicScrollViewModel(
                initialItemCount: 2,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let card = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0"
            }
        )
        let titleLabel = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.title"
            }
        )
        let hintLabel = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.hint"
            }
        )
        let accentIcon = try #require(
            card.allSubviews(of: UIImageView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.icon"
            }
        )
        let deleteButton = try #require(
            card.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.0.deleteButton"
            }
        )
        let titleFrame = titleLabel.convert(titleLabel.bounds, to: card)
        let hintFrame = hintLabel.convert(hintLabel.bounds, to: card)
        let accentFrame = accentIcon.convert(accentIcon.bounds, to: card)
        let deleteFrame = deleteButton.convert(deleteButton.bounds, to: card)
        let titleCenter = titleLabel.convert(
            CGPoint(x: titleLabel.bounds.midX, y: titleLabel.bounds.midY),
            to: card
        )

        #expect(titleLabel.text == "dynamic.item.title: 1")
        #expect(hintLabel.text == "dynamic.item.deleteHint")
        #expect(accentIcon.image != nil)
        #expect(deleteButton.configuration?.image != nil)
        #expect(deleteButton.configuration?.cornerStyle == .capsule)
        #expect(card.bounds.height >= 80)
        #expect(deleteButton.bounds.width >= 44)
        #expect(deleteButton.bounds.height >= 44)
        #expect(card.bounds.contains(titleFrame))
        #expect(card.bounds.contains(hintFrame))
        #expect(card.bounds.contains(accentFrame))
        #expect(card.bounds.contains(deleteFrame))
        #expect(accentFrame.maxX <= min(titleFrame.minX, hintFrame.minX))
        #expect(max(titleFrame.maxX, hintFrame.maxX) <= deleteFrame.minX)

        #expect(!(card is UIControl))
        #expect(card.gestureRecognizers?.isEmpty ?? true)
        #expect(card.hitTest(titleCenter, with: nil) !== deleteButton)
        #expect(!card.isAccessibilityElement)
        #expect(titleLabel.isAccessibilityElement)
        #expect(titleLabel.accessibilityTraits.contains(.staticText))
        #expect(titleLabel.accessibilityLabel == "dynamic.item.title: 1")
        #expect(!hintLabel.isAccessibilityElement)
        #expect(!accentIcon.isAccessibilityElement)
        #expect(deleteButton.isAccessibilityElement)
        #expect(deleteButton.accessibilityTraits.contains(.button))
        #expect(
            deleteButton.accessibilityLabel
                == "dynamic.item.deleteButton: 1"
        )
        #expect(
            deleteButton.accessibilityHint
                == "dynamic.item.deleteAccessibilityHint"
        )
    }

    /// 验证已缓存卡片在布局方向和语言变化后复用视图实例，并更新排列及本地化文本。
    @Test func dynamicScrollCachedCardMirrorsAndRelocalizesFromLTRToRTL() throws {
        var prefix = "ltr."
        let localizer = Localizer { key, arguments in
            let suffix = arguments.isEmpty
                ? ""
                : ": " + arguments.map { String(describing: $0) }
                    .joined(separator: " | ")
            return prefix + key + suffix
        }
        let viewController = DynamicScrollViewController(
            viewModel: DynamicScrollViewModel(
                initialItemCount: 1,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 402,
            height: 844
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let card = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0"
            }
        )
        let icon = try #require(
            card.allSubviews(of: UIImageView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.icon"
            }
        )
        let title = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.title"
            }
        )
        let hint = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.hint"
            }
        )
        let deleteButton = try #require(
            card.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.0.deleteButton"
            }
        )
        card.layoutIfNeeded()

        let ltrCardWidth = card.bounds.width
        let ltrIconFrame = icon.convert(icon.bounds, to: card)
        let ltrDeleteFrame = deleteButton.convert(deleteButton.bounds, to: card)

        #expect(ltrIconFrame.midX < ltrDeleteFrame.midX)
        #expect(title.text == "ltr.dynamic.item.title: 1")

        prefix = "rtl."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        card.layoutIfNeeded()

        let updatedCard = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0"
            }
        )
        let updatedIcon = try #require(
            updatedCard.allSubviews(of: UIImageView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.icon"
            }
        )
        let updatedDeleteButton = try #require(
            updatedCard.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.0.deleteButton"
            }
        )
        let rtlIconFrame = updatedIcon.convert(updatedIcon.bounds, to: updatedCard)
        let rtlDeleteFrame = updatedDeleteButton.convert(
            updatedDeleteButton.bounds,
            to: updatedCard
        )
        let mirroredIconMidX = updatedCard.bounds.minX
            + updatedCard.bounds.maxX
            - ltrIconFrame.midX
        let mirroredDeleteMidX = updatedCard.bounds.minX
            + updatedCard.bounds.maxX
            - ltrDeleteFrame.midX

        #expect(updatedCard === card)
        #expect(updatedIcon === icon)
        #expect(updatedDeleteButton === deleteButton)
        #expect(updatedCard.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlIconFrame.midX > rtlDeleteFrame.midX)
        #expect(abs(rtlIconFrame.midX - mirroredIconMidX) < 1)
        #expect(abs(rtlDeleteFrame.midX - mirroredDeleteMidX) < 1)
        #expect(abs(updatedCard.bounds.width - ltrCardWidth) < 0.001)
        #expect(
            abs(rtlIconFrame.width - ltrIconFrame.width) < 0.001
                && abs(rtlIconFrame.height - ltrIconFrame.height) < 0.001
        )
        #expect(
            abs(rtlDeleteFrame.width - ltrDeleteFrame.width) < 0.001
                && abs(rtlDeleteFrame.height - ltrDeleteFrame.height) < 0.001
        )
        #expect(title.text == "rtl.dynamic.item.title: 1")
        #expect(hint.text == "rtl.dynamic.item.deleteHint")
        #expect(
            deleteButton.accessibilityLabel
                == "rtl.dynamic.item.deleteButton: 1"
        )
        #expect(
            deleteButton.accessibilityHint
                == "rtl.dynamic.item.deleteAccessibilityHint"
        )
    }

    /// 验证连续添加项目后的内容尺寸及最终底部偏移。
    ///
    /// 测试禁用动画以检查布局终态，不对插入动画的中间帧作出判断。
    @Test func dynamicScrollAdditionsFinishAtTheNewBottom() throws {
        let viewController = DynamicScrollViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let initialLastItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.9"
            }
        )
        let initialLastFrame = initialLastItem.convert(
            initialLastItem.bounds,
            to: viewController.scrollView
        )
        let initialContentHeight = viewController.scrollView.contentSize.height
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        viewController.addButton.sendActions(for: .touchUpInside)
        viewController.addButton.sendActions(for: .touchUpInside)

        let scrollView = viewController.scrollView
        let newLastItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.11"
            }
        )
        let newLastFrame = newLastItem.convert(
            newLastItem.bounds,
            to: scrollView
        )
        let expectedHeightIncrease = newLastFrame.maxY - initialLastFrame.maxY
        let inset = scrollView.adjustedContentInset
        let expectedBottomOffset = max(
            -inset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + inset.bottom
        )

        #expect(expectedHeightIncrease > 0)
        #expect(
            abs(
                scrollView.contentSize.height
                    - initialContentHeight
                    - expectedHeightIncrease
            ) < 1
        )
        #expect(abs(scrollView.contentOffset.y - expectedBottomOffset) < 1)
    }

    /// 验证删除项目后剩余视图按标识复用，内容收缩并限制底部偏移。
    ///
    /// 测试禁用动画以检查布局终态，并验证再次触发已删除项目的按钮不会重复删除。
    @Test func dynamicScrollDeleteButtonRemovesAndClampsAtTheBottom() throws {
        let viewController = DynamicScrollViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let scrollView = viewController.scrollView
        scrollView.scrollTo(.bottom, animated: false)

        let itemViews = viewController.view.allSubviews(of: UIView.self)
        let previousItem = try #require(
            itemViews.first {
                $0.accessibilityIdentifier == "dynamic.item.3"
            }
        )
        let removedItem = try #require(
            itemViews.first {
                $0.accessibilityIdentifier == "dynamic.item.4"
            }
        )
        let followingItem = try #require(
            itemViews.first {
                $0.accessibilityIdentifier == "dynamic.item.5"
            }
        )
        let deleteButton = try #require(
            removedItem.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.4.deleteButton"
            }
        )
        let previousFrame = previousItem.convert(previousItem.bounds, to: scrollView)
        let removedFrame = removedItem.convert(removedItem.bounds, to: scrollView)
        let followingFrame = followingItem.convert(followingItem.bounds, to: scrollView)
        let removedStride = followingFrame.minY - removedFrame.minY
        let initialContentHeight = scrollView.contentSize.height

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        deleteButton.sendActions(for: .touchUpInside)

        let survivingPreviousItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.3"
            }
        )
        let survivingFollowingItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.5"
            }
        )
        let updatedPreviousFrame = survivingPreviousItem.convert(
            survivingPreviousItem.bounds,
            to: scrollView
        )
        let updatedFollowingFrame = survivingFollowingItem.convert(
            survivingFollowingItem.bounds,
            to: scrollView
        )
        let inset = scrollView.adjustedContentInset
        let expectedBottomOffset = max(
            -inset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + inset.bottom
        )

        #expect(removedItem.superview == nil)
        #expect(survivingPreviousItem === previousItem)
        #expect(survivingFollowingItem === followingItem)
        #expect(removedFrame.height >= 80)
        #expect(removedStride > removedFrame.height)
        #expect(
            abs(
                scrollView.contentSize.height
                    - initialContentHeight
                    + removedStride
            ) < 1
        )
        #expect(abs(updatedPreviousFrame.minY - previousFrame.minY) < 1)
        #expect(
            abs(
                updatedFollowingFrame.minY
                    - followingFrame.minY
                    + removedStride
            ) < 1
        )
        #expect(abs(scrollView.contentOffset.y - expectedBottomOffset) < 1)

        let contentHeightAfterDeletion = scrollView.contentSize.height
        deleteButton.sendActions(for: .touchUpInside)
        #expect(
            abs(scrollView.contentSize.height - contentHeightAfterDeletion) < 1
        )
    }
}

/// 记录内容边距及两种滚动指示器边距 setter 调用次数的测试滚动视图。
///
/// 即使赋入相同值也会计数，用于识别最终数值不变但仍重复写入 UIKit 的情况。
private final class MarginWriteTrackingScrollView: QuickLayoutScrollView {
    /// 自上次清零以来三个边距属性的累计写入次数。
    var insetWrites = 0

    /// 记录内容边距的每次写入。
    override var contentInset: UIEdgeInsets {
        didSet { insetWrites += 1 }
    }

    /// 记录垂直滚动指示器边距的每次写入。
    override var verticalScrollIndicatorInsets: UIEdgeInsets {
        didSet { insetWrites += 1 }
    }

    /// 记录水平滚动指示器边距的每次写入。
    override var horizontalScrollIndicatorInsets: UIEdgeInsets {
        didSet { insetWrites += 1 }
    }
}
