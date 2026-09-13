import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func collectionContentConfigurationInheritsDirectionForVisibleAndNewContent() async throws {
        var prefix = "ltr."
        let localizer = Localizer { key, _ in prefix + key }
        let viewController = ContentConfigurationCollectionViewController(
            viewModel: ContentConfigurationListViewModel(
                configuration: .collection,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 220)
        )
        defer { window.isHidden = true }
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(
            viewController.view.allSubviews(of: UICollectionView.self).first
        )
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        #expect(
            !collectionView.indexPathsForVisibleItems.contains(
                IndexPath(item: 3, section: 0)
            )
        )

        let cell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? UICollectionViewListCell
        )
        let contentView = try #require(
            cell.allSubviews(of: ContentConfigurationView.self).first
        )
        contentView.layoutIfNeeded()
        let iconView = contentView.iconView
        let titleLabel = contentView.titleLabel
        let ltrIconFrame = iconView.convert(iconView.bounds, to: contentView)
        let ltrTitleFrame = titleLabel.convert(titleLabel.bounds, to: contentView)
        // Local QuickLayout frames can look correct while UICollectionView's
        // reusable-view coordinate mapping is still mirrored. Keep a physical
        // window-space baseline to catch that stale UIKit state.
        let ltrIconWindowFrame = iconView.convert(
            iconView.bounds,
            to: window
        )
        let ltrTitleWindowFrame = titleLabel.convert(
            titleLabel.bounds,
            to: window
        )

        #expect(titleLabel.text == "ltr.contentConfiguration.sample.title.1")
        #expect(collectionView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
        #expect(cell.semanticContentAttribute == .forceLeftToRight)
        #expect(cell.contentView.semanticContentAttribute == .forceLeftToRight)
        #expect(contentView.semanticContentAttribute == .forceLeftToRight)
        #expect(iconView.semanticContentAttribute == .unspecified)
        #expect(titleLabel.semanticContentAttribute == .unspecified)
        #expect(contentView.detailLabel.semanticContentAttribute == .unspecified)
        #expect(
            cell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            contentView.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(ltrIconFrame.midX < ltrTitleFrame.midX)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let rtlCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? UICollectionViewListCell
        )
        let rtlContentView = try #require(
            rtlCell.allSubviews(of: ContentConfigurationView.self).first
        )
        rtlContentView.layoutIfNeeded()
        let rtlIconFrame = rtlContentView.iconView.convert(
            rtlContentView.iconView.bounds,
            to: rtlContentView
        )
        let rtlTitleFrame = rtlContentView.titleLabel.convert(
            rtlContentView.titleLabel.bounds,
            to: rtlContentView
        )
        let rtlIconWindowFrame = rtlContentView.iconView.convert(
            rtlContentView.iconView.bounds,
            to: window
        )
        let rtlTitleWindowFrame = rtlContentView.titleLabel.convert(
            rtlContentView.titleLabel.bounds,
            to: window
        )

        #expect(collectionView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(rtlCell.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlCell.contentView.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(rtlContentView.semanticContentAttribute == .forceRightToLeft)
        #expect(rtlContentView.iconView.semanticContentAttribute == .unspecified)
        #expect(rtlContentView.titleLabel.semanticContentAttribute == .unspecified)
        #expect(rtlContentView.detailLabel.semanticContentAttribute == .unspecified)
        #expect(
            rtlCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlContentView.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(rtlIconFrame.midX > rtlTitleFrame.midX)
        #expect(rtlIconWindowFrame.midX > rtlTitleWindowFrame.midX)
        #expect(
            isHorizontalMirror(
                rtlIconFrame,
                of: ltrIconFrame,
                in: rtlContentView.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlTitleFrame,
                of: ltrTitleFrame,
                in: rtlContentView.bounds.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        let returnedCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? UICollectionViewListCell
        )
        let returnedContent = try #require(
            returnedCell.allSubviews(of: ContentConfigurationView.self).first
        )
        returnedContent.layoutIfNeeded()

        #expect(collectionView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
        #expect(returnedCell.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedCell.contentView.semanticContentAttribute
                == .forceLeftToRight
        )
        #expect(returnedContent.semanticContentAttribute == .forceLeftToRight)
        #expect(returnedContent.iconView.semanticContentAttribute == .unspecified)
        #expect(returnedContent.titleLabel.semanticContentAttribute == .unspecified)
        #expect(returnedContent.detailLabel.semanticContentAttribute == .unspecified)
        #expect(
            returnedCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedContent.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(returnedCell.transform == .identity)
        #expect(returnedCell.contentView.transform == .identity)
        #expect(returnedContent.transform == .identity)
        #expect(returnedContent.titleLabel.transform == .identity)
        #expect(CATransform3DIsIdentity(returnedCell.layer.transform))
        #expect(CATransform3DIsIdentity(returnedCell.layer.sublayerTransform))
        #expect(CATransform3DIsIdentity(returnedContent.layer.transform))
        #expect(
            CATransform3DIsIdentity(returnedContent.layer.sublayerTransform)
        )
        #expect(
            returnedContent.iconView.convert(
                returnedContent.iconView.bounds,
                to: returnedContent
            )
                .approximatelyEquals(ltrIconFrame)
        )
        #expect(
            returnedContent.titleLabel.convert(
                returnedContent.titleLabel.bounds,
                to: returnedContent
            )
                .approximatelyEquals(ltrTitleFrame)
        )
        #expect(
            returnedContent.iconView.convert(
                returnedContent.iconView.bounds,
                to: window
            )
                .approximatelyEquals(ltrIconWindowFrame)
        )
        #expect(
            returnedContent.titleLabel.convert(
                returnedContent.titleLabel.bounds,
                to: window
            )
                .approximatelyEquals(ltrTitleWindowFrame)
        )

        prefix = "rtl."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        let localizedContentDidApply = await waitForCondition {
            guard
                let cell = collectionView.cellForItem(
                    at: IndexPath(item: 0, section: 0)
                ) as? UICollectionViewListCell
            else {
                return false
            }
            return cell.allSubviews(of: ContentConfigurationView.self).first?.titleLabel.text
                == "rtl.contentConfiguration.sample.title.1"
        }
        #expect(localizedContentDidApply)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        let localizedCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? UICollectionViewListCell
        )
        let localizedContent = try #require(
            localizedCell.allSubviews(of: ContentConfigurationView.self).first
        )
        localizedContent.layoutIfNeeded()
        #expect(localizedContent.titleLabel.text == "rtl.contentConfiguration.sample.title.1")
        #expect(collectionView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(localizedCell.semanticContentAttribute == .forceRightToLeft)
        #expect(
            localizedCell.contentView.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(localizedContent.semanticContentAttribute == .forceRightToLeft)
        #expect(localizedContent.iconView.semanticContentAttribute == .unspecified)
        #expect(localizedContent.titleLabel.semanticContentAttribute == .unspecified)
        #expect(localizedContent.detailLabel.semanticContentAttribute == .unspecified)
        #expect(
            localizedCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedContent.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )

        collectionView.scrollToItem(
            at: IndexPath(item: 3, section: 0),
            at: .bottom,
            animated: false
        )
        collectionView.layoutIfNeeded()

        let newlyVisibleCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 3, section: 0)
            ) as? UICollectionViewListCell
        )
        let newlyVisibleContent = try #require(
            newlyVisibleCell.allSubviews(of: ContentConfigurationView.self).first
        )
        newlyVisibleCell.layoutIfNeeded()
        newlyVisibleContent.layoutIfNeeded()
        let newIconFrame = newlyVisibleContent.iconView.convert(
            newlyVisibleContent.iconView.bounds,
            to: newlyVisibleContent
        )
        let newTitleFrame = newlyVisibleContent.titleLabel.convert(
            newlyVisibleContent.titleLabel.bounds,
            to: newlyVisibleContent
        )

        #expect(
            collectionView.indexPathsForVisibleItems.contains(
                IndexPath(item: 3, section: 0)
            )
        )
        #expect(newlyVisibleContent.titleLabel.text == "rtl.contentConfiguration.sample.title.4")
        #expect(newlyVisibleCell.semanticContentAttribute == .forceRightToLeft)
        #expect(
            newlyVisibleCell.contentView.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(
            newlyVisibleContent.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(newlyVisibleContent.iconView.semanticContentAttribute == .unspecified)
        #expect(newlyVisibleContent.titleLabel.semanticContentAttribute == .unspecified)
        #expect(newlyVisibleContent.detailLabel.semanticContentAttribute == .unspecified)
        #expect(
            newlyVisibleCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            newlyVisibleContent.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(newIconFrame.midX > newTitleFrame.midX)

        prefix = "returned."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.leftToRight)
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: 0),
            at: .top,
            animated: false
        )
        let returnedLocalizedContentDidApply = await waitForCondition {
            guard
                let cell = collectionView.cellForItem(
                    at: IndexPath(item: 0, section: 0)
                ) as? UICollectionViewListCell
            else {
                return false
            }
            return cell.allSubviews(of: ContentConfigurationView.self).first?.titleLabel.text
                == "returned.contentConfiguration.sample.title.1"
        }
        #expect(returnedLocalizedContentDidApply)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let returnedLocalizedCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? UICollectionViewListCell
        )
        let returnedLocalizedContent = try #require(
            returnedLocalizedCell.allSubviews(of: ContentConfigurationView.self).first
        )
        returnedLocalizedContent.layoutIfNeeded()
        let returnedLocalizedIconWindowFrame =
            returnedLocalizedContent.iconView.convert(
                returnedLocalizedContent.iconView.bounds,
                to: window
            )
        let returnedLocalizedTitleWindowFrame =
            returnedLocalizedContent.titleLabel.convert(
                returnedLocalizedContent.titleLabel.bounds,
                to: window
            )

        #expect(
            returnedLocalizedContent.titleLabel.text
                == "returned.contentConfiguration.sample.title.1"
        )
        #expect(collectionView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedLocalizedContent.semanticContentAttribute
                == .forceLeftToRight
        )
        // 文本宽度可以因语言变化而不同；物理 leading 坐标必须回到初始 LTR，
        // 这能捕获局部 frame 正确但 window 坐标仍残留 RTL 镜像的回归。
        #expect(
            abs(
                returnedLocalizedIconWindowFrame.minX
                    - ltrIconWindowFrame.minX
            ) < 0.5
        )
        #expect(
            abs(
                returnedLocalizedTitleWindowFrame.minX
                    - ltrTitleWindowFrame.minX
            ) < 0.5
        )
        #expect(
            returnedLocalizedIconWindowFrame.midX
                < returnedLocalizedTitleWindowFrame.midX
        )
    }
}
