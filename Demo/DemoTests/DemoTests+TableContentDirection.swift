import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func tableContentConfigurationInheritsDirectionForVisibleAndNewContent() async throws {
        let sectionHorizontalPadding: CGFloat = 16
        let sectionEdgeTolerance: CGFloat = 1
        let sectionSizingTolerance: CGFloat = 1.01
        var prefix = "ltr."
        let localizer = Localizer { key, _ in prefix + key }
        let viewController = ContentConfigurationTableViewController(
            viewModel: ContentConfigurationListViewModel(
                configuration: .table,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 260)
        )
        defer { window.isHidden = true }
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let tableView = try #require(viewController.tableView)
        tableView.reloadData()
        tableView.layoutIfNeeded()
        #expect(
            tableView.cellForRow(
                at: IndexPath(row: 11, section: 0)
            ) == nil
        )

        let cell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            )
        )
        let contentView = try #require(
            cell.allSubviews(of: ContentConfigurationView.self).first
        )
        contentView.layoutIfNeeded()
        let iconView = contentView.iconView
        let titleLabel = contentView.titleLabel
        let ltrIconFrame = iconView.convert(iconView.bounds, to: contentView)
        let ltrTitleFrame = titleLabel.convert(titleLabel.bounds, to: contentView)

        let header = try #require(
            tableView.headerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let headerContent = header.sectionContentView
        headerContent.layoutIfNeeded()
        let headerTitleLabel = headerContent.titleLabel
        let headerDetailLabel = headerContent.detailLabel
        #expect(headerTitleLabel.text == "ltr.demo.contentConfiguration.table.header")
        #expect(
            headerDetailLabel.text
                == "ltr.demo.contentConfiguration.table.header.detail"
        )
        let ltrHeaderTitleFrame = headerTitleLabel.convert(
            headerTitleLabel.bounds,
            to: headerContent
        )
        let ltrHeaderDetailFrame = headerDetailLabel.convert(
            headerDetailLabel.bounds,
            to: headerContent
        )

        #expect(titleLabel.text == "ltr.contentConfiguration.sample.title.1")
        #expect(tableView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .leftToRight
        )
        #expect(contentView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            cell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            cell.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(ltrIconFrame.midX < ltrTitleFrame.midX)
        #expect(headerContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            header.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(headerContent.frame)
        )
        #expect(
            header.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            header.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                ltrHeaderTitleFrame.minX
                    - (headerContent.bounds.minX + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                ltrHeaderDetailFrame.minX
                    - (headerContent.bounds.minX + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )

        tableView.scrollToRow(
            at: IndexPath(row: 11, section: 0),
            at: .top,
            animated: false
        )
        tableView.layoutIfNeeded()
        let footer = try #require(
            tableView.footerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let footerContent = footer.sectionContentView
        footerContent.layoutIfNeeded()
        let footerTitleLabel = footerContent.titleLabel
        let footerDetailLabel = footerContent.detailLabel
        #expect(footerTitleLabel.text == "ltr.demo.contentConfiguration.table.footer")
        #expect(footerDetailLabel.text == nil)
        let ltrFooterTitleFrame = footerTitleLabel.convert(
            footerTitleLabel.bounds,
            to: footerContent
        )

        #expect(footerContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            footer.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(footerContent.frame)
        )
        #expect(
            footer.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footer.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                ltrFooterTitleFrame.minX
                    - (footerContent.bounds.minX + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )

        tableView.scrollToRow(
            at: IndexPath(row: 0, section: 0),
            at: .top,
            animated: false
        )
        tableView.layoutIfNeeded()

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        tableView.layoutIfNeeded()

        let rtlCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            )
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
        let rtlHeader = try #require(
            tableView.headerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let rtlHeaderContent = rtlHeader.sectionContentView
        rtlHeaderContent.layoutIfNeeded()
        let rtlHeaderTitleLabel = rtlHeaderContent.titleLabel
        let rtlHeaderDetailLabel = rtlHeaderContent.detailLabel
        #expect(rtlHeaderTitleLabel.text == "ltr.demo.contentConfiguration.table.header")
        #expect(
            rtlHeaderDetailLabel.text
                == "ltr.demo.contentConfiguration.table.header.detail"
        )
        let rtlHeaderTitleFrame = rtlHeaderTitleLabel.convert(
            rtlHeaderTitleLabel.bounds,
            to: rtlHeaderContent
        )
        let rtlHeaderDetailFrame = rtlHeaderDetailLabel.convert(
            rtlHeaderDetailLabel.bounds,
            to: rtlHeaderContent
        )

        #expect(tableView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        #expect(rtlContentView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlCell.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlContentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(rtlIconFrame.midX > rtlTitleFrame.midX)
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
        #expect(rtlHeaderContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlHeader.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(rtlHeaderContent.frame)
        )
        #expect(
            rtlHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeader.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeaderTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeaderDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                rtlHeaderTitleFrame.maxX
                    - (rtlHeaderContent.bounds.maxX - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                rtlHeaderDetailFrame.maxX
                    - (rtlHeaderContent.bounds.maxX - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            isHorizontalMirror(
                rtlHeaderTitleFrame,
                of: ltrHeaderTitleFrame,
                in: rtlHeaderContent.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlHeaderDetailFrame,
                of: ltrHeaderDetailFrame,
                in: rtlHeaderContent.bounds.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        tableView.layoutIfNeeded()
        let returnedCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            )
        )
        let returnedContent = try #require(
            returnedCell.allSubviews(of: ContentConfigurationView.self).first
        )
        returnedContent.layoutIfNeeded()
        let returnedHeader = try #require(
            tableView.headerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let returnedHeaderContent = returnedHeader.sectionContentView
        returnedHeaderContent.layoutIfNeeded()
        let returnedHeaderTitleLabel = returnedHeaderContent.titleLabel
        let returnedHeaderDetailLabel = returnedHeaderContent.detailLabel
        #expect(
            returnedHeaderTitleLabel.text
                == "ltr.demo.contentConfiguration.table.header"
        )
        #expect(
            returnedHeaderDetailLabel.text
                == "ltr.demo.contentConfiguration.table.header.detail"
        )
        let returnedHeaderTitleFrame = returnedHeaderTitleLabel.convert(
            returnedHeaderTitleLabel.bounds,
            to: returnedHeaderContent
        )
        let returnedHeaderDetailFrame = returnedHeaderDetailLabel.convert(
            returnedHeaderDetailLabel.bounds,
            to: returnedHeaderContent
        )

        #expect(tableView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .leftToRight
        )
        #expect(returnedContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(returnedHeaderContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                returnedHeaderTitleFrame.minX
                    - (returnedHeaderContent.bounds.minX
                        + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                returnedHeaderDetailFrame.minX
                    - (returnedHeaderContent.bounds.minX
                        + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
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

        prefix = "rtl."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        let localizedContentDidApply = await waitForCondition {
            guard
                let header = tableView.headerView(forSection: 0)
                    as? ContentConfigurationTableHeaderFooterView,
                let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0))
            else {
                return false
            }
            return header.sectionContentView.titleLabel.text
                    == "rtl.demo.contentConfiguration.table.header"
                && cell.allSubviews(of: ContentConfigurationView.self).first?.titleLabel.text
                    == "rtl.contentConfiguration.sample.title.1"
        }
        #expect(localizedContentDidApply)
        viewController.view.layoutIfNeeded()
        tableView.layoutIfNeeded()
        let localizedCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            )
        )
        let localizedContent = try #require(
            localizedCell.allSubviews(of: ContentConfigurationView.self).first
        )
        localizedContent.layoutIfNeeded()
        let localizedHeader = try #require(
            tableView.headerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let localizedHeaderContent = localizedHeader.sectionContentView
        localizedHeaderContent.layoutIfNeeded()
        let localizedHeaderTitleLabel = localizedHeaderContent.titleLabel
        let localizedHeaderDetailLabel = localizedHeaderContent.detailLabel
        #expect(
            localizedHeaderTitleLabel.text
                == "rtl.demo.contentConfiguration.table.header"
        )
        #expect(
            localizedHeaderDetailLabel.text
                == "rtl.demo.contentConfiguration.table.header.detail"
        )
        let localizedHeaderTitleFrame = localizedHeaderTitleLabel.convert(
            localizedHeaderTitleLabel.bounds,
            to: localizedHeaderContent
        )
        let localizedHeaderDetailFrame = localizedHeaderDetailLabel.convert(
            localizedHeaderDetailLabel.bounds,
            to: localizedHeaderContent
        )

        #expect(localizedContent.titleLabel.text == "rtl.contentConfiguration.sample.title.1")
        #expect(tableView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        #expect(localizedContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            localizedCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(localizedHeaderContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            localizedHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedHeaderTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedHeaderDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                localizedHeaderTitleFrame.maxX
                    - (localizedHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                localizedHeaderDetailFrame.maxX
                    - (localizedHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )

        tableView.scrollToRow(
            at: IndexPath(row: 11, section: 0),
            at: .top,
            animated: false
        )
        tableView.layoutIfNeeded()
        #expect(tableView.headerView(forSection: 0) == nil)

        let newlyVisibleCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 11, section: 0)
            )
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
        let rtlFooter = try #require(
            tableView.footerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let rtlFooterContent = rtlFooter.sectionContentView
        rtlFooterContent.layoutIfNeeded()
        let rtlFooterTitleLabel = rtlFooterContent.titleLabel
        let rtlFooterDetailLabel = rtlFooterContent.detailLabel
        #expect(rtlFooterTitleLabel.text == "rtl.demo.contentConfiguration.table.footer")
        #expect(rtlFooterDetailLabel.text == nil)
        let rtlFooterTitleFrame = rtlFooterTitleLabel.convert(
            rtlFooterTitleLabel.bounds,
            to: rtlFooterContent
        )

        #expect(newlyVisibleContent.titleLabel.text == "rtl.contentConfiguration.sample.title.4")
        #expect(newlyVisibleContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            newlyVisibleCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            newlyVisibleCell.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            newlyVisibleContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(newIconFrame.midX > newTitleFrame.midX)
        #expect(rtlFooterContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlFooter.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(rtlFooterContent.frame)
        )
        #expect(
            rtlFooter.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlFooterContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlFooterTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlFooterDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                rtlFooterTitleFrame.maxX
                    - (rtlFooterContent.bounds.maxX - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        let rtlFooterFittingSize = rtlFooter.systemLayoutSizeFitting(
            CGSize(width: rtlFooter.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(rtlFooter.bounds.height - rtlFooterFittingSize.height)
                <= sectionSizingTolerance
        )
        #expect(
            abs(
                tableView.rectForFooter(inSection: 0).height
                    - rtlFooter.bounds.height
            ) <= sectionSizingTolerance
        )

        tableView.setContentOffset(
            CGPoint(
                x: tableView.contentOffset.x,
                y: -tableView.adjustedContentInset.top
            ),
            animated: false
        )
        tableView.layoutIfNeeded()
        #expect(tableView.footerView(forSection: 0) == nil)

        let returnedRTLHeader = try #require(
            tableView.headerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let returnedRTLHeaderContent = returnedRTLHeader.sectionContentView
        returnedRTLHeaderContent.layoutIfNeeded()
        let returnedRTLHeaderTitleLabel = returnedRTLHeaderContent.titleLabel
        let returnedRTLHeaderDetailLabel = returnedRTLHeaderContent.detailLabel
        #expect(
            returnedRTLHeaderTitleLabel.text
                == "rtl.demo.contentConfiguration.table.header"
        )
        #expect(
            returnedRTLHeaderDetailLabel.text
                == "rtl.demo.contentConfiguration.table.header.detail"
        )
        let returnedRTLHeaderTitleFrame = returnedRTLHeaderTitleLabel.convert(
            returnedRTLHeaderTitleLabel.bounds,
            to: returnedRTLHeaderContent
        )
        let returnedRTLHeaderDetailFrame = returnedRTLHeaderDetailLabel.convert(
            returnedRTLHeaderDetailLabel.bounds,
            to: returnedRTLHeaderContent
        )
        let returnedRTLHeaderFittingSize = returnedRTLHeader
            .systemLayoutSizeFitting(
                CGSize(width: returnedRTLHeader.bounds.width, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )

        #expect(tableView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            returnedRTLHeaderContent.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(
            returnedRTLHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedRTLHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedRTLHeaderTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedRTLHeaderDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                returnedRTLHeaderTitleFrame.maxX
                    - (returnedRTLHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                returnedRTLHeaderDetailFrame.maxX
                    - (returnedRTLHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                returnedRTLHeader.bounds.height
                    - returnedRTLHeaderFittingSize.height
            ) <= sectionSizingTolerance
        )
        #expect(
            abs(
                tableView.rectForHeader(inSection: 0).height
                    - returnedRTLHeader.bounds.height
            ) <= sectionSizingTolerance
        )
    }
}
