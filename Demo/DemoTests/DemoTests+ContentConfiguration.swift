import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func contentConfigurationViewUpdatesAndSelfSizes() throws {
        let firstModel = ContentConfigurationModel(
            title: "First",
            detail: "Short message",
            imageName: "sun.max.fill",
            themeColor: .systemOrange
        )
        let contentView = ContentConfigurationView(
            configuration: .init(model: firstModel)
        )

        #expect(contentView.titleLabel.text == firstModel.title)
        #expect(contentView.detailLabel.text == firstModel.detail)

        let secondModel = ContentConfigurationModel(
            title: "Updated",
            detail: String(
                repeating: "A longer message that should wrap. ",
                count: 8
            ),
            imageName: "moon.stars.fill",
            themeColor: .systemIndigo
        )
        contentView.configuration = ContentConfigurationView.Configuration(
            model: secondModel
        )

        let wideSize = contentView.sizeThatFits(
            CGSize(
                width: 320,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        let narrowSize = contentView.sizeThatFits(
            CGSize(
                width: 180,
                height: CGFloat.greatestFiniteMagnitude
            )
        )

        #expect(contentView.titleLabel.text == secondModel.title)
        #expect(contentView.detailLabel.text == secondModel.detail)
        #expect(narrowSize.height > wideSize.height)

        let controller = ContentConfigurationCollectionViewController()
        let window = try makeVisibleTestWindow(
            rootViewController: controller,
            size: CGSize(width: 204, height: 640)
        )
        defer { window.isHidden = true }
        let collectionView = try #require(
            controller.view.allSubviews(of: UICollectionView.self).first
        )
        collectionView.layoutIfNeeded()
        let cell = try #require(
            collectionView.cellForItem(at: IndexPath(item: 0, section: 0))
                as? UICollectionViewListCell
        )
        cell.contentConfiguration = ContentConfigurationView.Configuration(
            model: firstModel
        )
        cell.layoutIfNeeded()
        let initialCellContentView = try #require(
            cell.allSubviews(of: ContentConfigurationView.self).first
        )
        #expect(initialCellContentView.titleLabel.text == firstModel.title)
        cell.isHighlighted = true
        cell.setNeedsUpdateConfiguration()
        cell.layoutIfNeeded()
        #expect(initialCellContentView.titleLabel.alpha < 1)

        cell.isHighlighted = false
        cell.isSelected = true
        cell.setNeedsUpdateConfiguration()
        cell.layoutIfNeeded()
        #expect(
            initialCellContentView.backgroundColor
                == .tertiarySystemGroupedBackground
        )
        #expect(initialCellContentView.titleLabel.alpha < 1)

        cell.prepareForReuse()
        cell.isSelected = false
        cell.contentConfiguration = ContentConfigurationView.Configuration(
            model: secondModel
        )
        cell.setNeedsUpdateConfiguration()
        cell.layoutIfNeeded()
        let reusedCellContentView = try #require(
            cell.allSubviews(of: ContentConfigurationView.self).first
        )
        #expect(reusedCellContentView === initialCellContentView)
        #expect(reusedCellContentView.titleLabel.text == secondModel.title)
        #expect(reusedCellContentView.detailLabel.text == secondModel.detail)
        #expect(reusedCellContentView.titleLabel.alpha == 1)

        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        #expect(abs(cell.bounds.height - narrowSize.height) <= 1)
        #expect(cell.bounds.width == 180)
    }

    @Test func tableContentConfigurationControllerUsesSelfSizingViews() throws {
        let fittingTolerance: CGFloat = 1.01
        let viewController = ContentConfigurationTableViewController()
        viewController.loadViewIfNeeded()
        let tableView = try #require(viewController.tableView)
        tableView.estimatedRowHeight = 1
        tableView.estimatedSectionHeaderHeight = 1
        tableView.estimatedSectionFooterHeight = 1
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 320,
            height: 640
        )
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        tableView.reloadData()
        tableView.layoutIfNeeded()

        #expect(tableView.numberOfRows(inSection: 0) == 12)
        #expect(
            tableView.rectForRow(
                at: IndexPath(row: 0, section: 0)
            ).height > 60
        )
        #expect(tableView.rectForHeader(inSection: 0).height > 44)

        let cell = try #require(
            tableView.cellForRow(at: IndexPath(row: 0, section: 0))
        )
        let cellContentView = try #require(
            cell.allSubviews(of: ContentConfigurationView.self).first
        )
        #expect(cellContentView.titleLabel.text?.isEmpty == false)
        let cellFittingSize = cell.systemLayoutSizeFitting(
            CGSize(width: cell.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(cell.bounds.height - cellFittingSize.height)
                <= fittingTolerance
        )

        let header = try #require(
            tableView.headerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        #expect(header.sectionContentView.titleLabel.text?.isEmpty == false)
        let headerFittingSize = header.systemLayoutSizeFitting(
            CGSize(width: header.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(header.bounds.height - headerFittingSize.height)
                <= fittingTolerance
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
        let footerFittingSize = footer.systemLayoutSizeFitting(
            CGSize(width: footer.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(footer.sectionContentView.titleLabel.text?.isEmpty == false)
        #expect(footer.bounds.height > 20)
        #expect(
            abs(footer.bounds.height - footerFittingSize.height)
                <= fittingTolerance
        )
    }

    @Test func tableContentConfigurationSupplementariesStartRTLOnFirstAppearance() async throws {
        let edgePadding: CGFloat = 16
        let tolerance: CGFloat = 1.01
        let listView = ContentConfigurationTableListView()

        let model = ContentConfigurationModel(
            title: "رسالة",
            detail: "محتوى الرسالة",
            imageName: "moon.stars.fill",
            themeColor: .systemIndigo
        )
        let items = [
            ContentConfigurationListItem(
                id: ContentConfigurationListItemID(group: 0, symbolName: model.imageName),
                model: model
            )
        ]
        let headerText = "رسائل ذاتية التحجيم عند الظهور الأول"
        let detailText = "يجب أن يبدأ هذا الرأس من الحافة اليمنى مباشرة."
        let footerText = "يظهر هذا التذييل باتجاه صحيح وارتفاع مناسب من المرة الأولى."

        await withCheckedContinuation { continuation in
            listView.render(
                items: items,
                headerTitle: headerText,
                headerDetail: detailText,
                footerTitle: footerText,
                completion: { continuation.resume() }
            )
        }

        #expect(listView.bounds == .zero)
        #expect(listView.tableView.bounds == .zero)
        #expect(listView.window == nil)
        #expect(listView.tableView.headerView(forSection: 0) == nil)
        #expect(listView.tableView.footerView(forSection: 0) == nil)
        #expect(
            listView.tableView.semanticContentAttribute == .unspecified
        )

        let viewController = UIViewController()
        viewController.view = listView
        viewController.view.semanticContentAttribute = .forceRightToLeft
        listView.applyLayoutDirection(.rightToLeft)
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 640)
        )
        defer { window.isHidden = true }
        listView.tableView.layoutIfNeeded()

        let header = try #require(
            listView.tableView.headerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let footer = try #require(
            listView.tableView.footerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let headerContent = header.sectionContentView
        let footerContent = footer.sectionContentView
        headerContent.layoutIfNeeded()
        footerContent.layoutIfNeeded()

        let headerTitle = headerContent.titleLabel
        let headerDetail = headerContent.detailLabel
        let footerTitle = footerContent.titleLabel
        #expect(headerTitle.text == headerText)
        #expect(headerDetail.text == detailText)
        #expect(footerTitle.text == footerText)
        let headerTitleFrame = headerTitle.convert(
            headerTitle.bounds,
            to: headerContent
        )
        let headerDetailFrame = headerDetail.convert(
            headerDetail.bounds,
            to: headerContent
        )
        let footerTitleFrame = footerTitle.convert(
            footerTitle.bounds,
            to: footerContent
        )
        let headerFittingSize = header.systemLayoutSizeFitting(
            CGSize(width: header.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let footerFittingSize = footer.systemLayoutSizeFitting(
            CGSize(width: footer.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(window.semanticContentAttribute == .unspecified)
        #expect(listView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            listView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        #expect(
            listView.tableView.semanticContentAttribute == .forceRightToLeft
        )
        #expect(
            listView.tableView.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(
            header.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footer.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(header.semanticContentAttribute == .forceRightToLeft)
        #expect(footer.semanticContentAttribute == .forceRightToLeft)
        #expect(
            headerContent.semanticContentAttribute == .forceRightToLeft
        )
        #expect(
            footerContent.semanticContentAttribute == .forceRightToLeft
        )
        #expect(
            header.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(headerContent.frame)
        )
        #expect(
            footer.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(footerContent.frame)
        )
        #expect(
            headerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                headerTitleFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                headerDetailFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                footerTitleFrame.maxX
                    - (footerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(header.bounds.height - headerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(footer.bounds.height - footerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(
                listView.tableView.rectForHeader(inSection: 0).height
                    - header.bounds.height
            ) <= tolerance
        )
        #expect(
            abs(
                listView.tableView.rectForFooter(inSection: 0).height
                    - footer.bounds.height
            ) <= tolerance
        )
        #expect(
            abs(
                listView.tableView.contentOffset.y
                    + listView.tableView.adjustedContentInset.top
            ) <= tolerance
        )
    }

    @Test func tableContentConfigurationSupplementariesRelayoutImmediatelyAfterLocalizationAndDirectionChange() async throws {
        let edgePadding: CGFloat = 16
        let tolerance: CGFloat = 1.01
        let listView = ContentConfigurationTableListView()
        let viewController = UIViewController()
        viewController.view = listView
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 640)
        )
        defer { window.isHidden = true }

        let model = ContentConfigurationModel(
            title: "Message",
            detail: "Body",
            imageName: "moon.stars.fill",
            themeColor: .systemIndigo
        )
        let items = [
            ContentConfigurationListItem(
                id: ContentConfigurationListItemID(group: 0, symbolName: model.imageName),
                model: model
            )
        ]

        listView.applyLayoutDirection(.leftToRight)
        await withCheckedContinuation { continuation in
            listView.render(
                items: items,
                headerTitle: "Header",
                headerDetail: "Detail",
                footerTitle: "Footer",
                completion: { continuation.resume() }
            )
        }
        listView.tableView.layoutIfNeeded()

        let initialHeader = try #require(
            listView.tableView.headerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let initialFooter = try #require(
            listView.tableView.footerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let initialHeaderHeight = listView.tableView.rectForHeader(
            inSection: 0
        ).height
        let initialFooterHeight = listView.tableView.rectForFooter(
            inSection: 0
        ).height
        let initialContentOffset = listView.tableView.contentOffset

        let arabicHeader = "رسائل ذاتية التحجيم طويلة لاختبار الارتفاع"
        let arabicDetail = "يجب أن يتغير اتجاه هذا الرأس وارتفاعه فورًا من دون تمرير القائمة."
        let arabicFooter = "يجب أن يحدّث الرأس والتذييل الارتفاع مباشرة عند تبديل اللغة من الصينية إلى العربية من دون تمرير القائمة."

        await withCheckedContinuation { continuation in
            listView.render(
                items: items,
                headerTitle: arabicHeader,
                headerDetail: arabicDetail,
                footerTitle: arabicFooter,
                completion: { continuation.resume() }
            )
            // Match production ordering: localized content starts an
            // asynchronous ListKit apply before direction is updated.
            listView.applyLayoutDirection(.rightToLeft)
        }

        let updatedHeader = try #require(
            listView.tableView.headerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let updatedFooter = try #require(
            listView.tableView.footerView(forSection: 0)
                as? ContentConfigurationTableHeaderFooterView
        )
        let headerContent = updatedHeader.sectionContentView
        let footerContent = updatedFooter.sectionContentView

        let headerTitle = headerContent.titleLabel
        let headerDetail = headerContent.detailLabel
        let footerTitle = footerContent.titleLabel
        #expect(headerTitle.text == arabicHeader)
        #expect(headerDetail.text == arabicDetail)
        #expect(footerTitle.text == arabicFooter)
        let headerTitleFrame = headerTitle.convert(
            headerTitle.bounds,
            to: headerContent
        )
        let headerDetailFrame = headerDetail.convert(
            headerDetail.bounds,
            to: headerContent
        )
        let footerTitleFrame = footerTitle.convert(
            footerTitle.bounds,
            to: footerContent
        )

        #expect(updatedHeader === initialHeader)
        #expect(updatedFooter === initialFooter)
        #expect(
            listView.tableView.semanticContentAttribute == .forceRightToLeft
        )
        #expect(headerContent.semanticContentAttribute == .forceRightToLeft)
        #expect(footerContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            updatedHeader.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(headerContent.frame)
        )
        #expect(
            updatedFooter.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(footerContent.frame)
        )
        #expect(
            updatedHeader.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            updatedFooter.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                headerTitleFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                headerDetailFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                footerTitleFrame.maxX
                    - (footerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            listView.tableView.rectForHeader(inSection: 0).height
                > initialHeaderHeight
        )
        #expect(
            listView.tableView.rectForFooter(inSection: 0).height
                > initialFooterHeight
        )

        let headerFittingSize = updatedHeader.systemLayoutSizeFitting(
            CGSize(width: updatedHeader.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let footerFittingSize = updatedFooter.systemLayoutSizeFitting(
            CGSize(width: updatedFooter.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(updatedHeader.bounds.height - headerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(updatedFooter.bounds.height - footerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(listView.tableView.contentOffset.y - initialContentOffset.y)
                <= tolerance
        )
    }

    @Test func collectionContentConfigurationControllerReusesItsCellRegistration() throws {
        let viewController = ContentConfigurationCollectionViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 320,
            height: 640
        )
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(
            viewController.view.allSubviews(of: UICollectionView.self).first
        )
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        #expect(collectionView.numberOfItems(inSection: 0) == 4)
        #expect(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) is UICollectionViewListCell
        )
    }
}
