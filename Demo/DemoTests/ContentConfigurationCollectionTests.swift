import UIKit
import Testing
@testable import Demo

@MainActor
@Suite(.serialized)
struct ContentConfigurationCollectionTests {

    @Test func headerAndFooterResizeAndMirrorWhenContentChanges() async throws {
        var usesLongText = false
        let headerKey = "demo.contentConfiguration.collection.header"
        let detailKey = "demo.contentConfiguration.collection.header.detail"
        let footerKey = "demo.contentConfiguration.collection.footer"
        let longTitle = String(repeating: "عنوان طويل متعدد الأسطر ", count: 8)
        let longDetail = String(repeating: "تفاصيل المحتوى القابل لإعادة الاستخدام ", count: 5)
        let longFooter = String(repeating: "تذييل متعدد الأسطر ", count: 8)
        let localizer = Localizer { key, _ in
            switch key {
            case headerKey: return usesLongText ? longTitle : "Header"
            case detailKey: return usesLongText ? longDetail : "Supporting detail"
            case footerKey: return usesLongText ? longFooter : "Footer"
            default: return "Content"
            }
        }
        let controller = ContentConfigurationCollectionViewController(
            viewModel: ContentConfigurationListViewModel(
                configuration: .collection,
                localizer: localizer
            )
        )
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 360, height: 1400)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.reloadLayoutDirection(.leftToRight)
        controller.view.layoutIfNeeded()
        let collectionView = try #require(
            controller.view.subviews.compactMap { $0 as? UICollectionView }.first
        )
        collectionView.layoutIfNeeded()

        func supplementary(_ kind: String) -> ContentConfigurationCollectionHeaderFooterView? {
            collectionView.supplementaryView(
                forElementKind: kind,
                at: IndexPath(item: 0, section: 0)
            ) as? ContentConfigurationCollectionHeaderFooterView
        }
        let headerKind = UICollectionView.elementKindSectionHeader
        let footerKind = UICollectionView.elementKindSectionFooter
        func contentKeepsEightPointSupplementarySpacing() -> Bool {
            guard let header = supplementary(headerKind),
                  let footer = supplementary(footerKind),
                  let first = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)),
                  let last = collectionView.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))
            else { return false }
            return abs(first.frame.minY - header.frame.maxY - 8) <= 1
                && abs(footer.frame.minY - last.frame.maxY - 8) <= 1
        }
        let header = try #require(supplementary(headerKind))
        let footer = try #require(supplementary(footerKind))
        #expect(header.sectionContentView.titleLabel.text == "Header")
        #expect(header.sectionContentView.detailLabel.text == "Supporting detail")
        #expect(footer.sectionContentView.titleLabel.text == "Footer")
        #expect(footer.sectionContentView.detailLabel.text == nil)
        let headerHeight = header.bounds.height
        let footerHeight = footer.bounds.height
        #expect(headerHeight > 0)
        #expect(footerHeight > 0)
        #expect(contentKeepsEightPointSupplementarySpacing())

        usesLongText = true
        controller.reloadLocalizedContent()
        controller.reloadLayoutDirection(.rightToLeft)
        let expanded = await eventually {
            collectionView.layoutIfNeeded()
            guard let header = supplementary(headerKind),
                  let footer = supplementary(footerKind) else { return false }
            return header.sectionContentView.titleLabel.text == longTitle
                && footer.sectionContentView.titleLabel.text == longFooter
                && header.bounds.height > headerHeight
                && footer.bounds.height > footerHeight
        }
        #expect(expanded)
        #expect(contentKeepsEightPointSupplementarySpacing())
        for kind in [headerKind, footerKind] {
            let view = try #require(supplementary(kind))
            view.layoutIfNeeded()
            let content = view.sectionContentView
            content.layoutIfNeeded()
            #expect(content.effectiveUserInterfaceLayoutDirection == .rightToLeft)
            let label = content.titleLabel
            let frame = label.convert(label.bounds, to: content)
            #expect(abs(frame.maxX - (content.bounds.maxX - 16)) <= 1)
            #expect(view.bounds.insetBy(dx: -1, dy: -1).contains(content.frame))
        }

        usesLongText = false
        controller.reloadLocalizedContent()
        controller.reloadLayoutDirection(.leftToRight)
        let restored = await eventually {
            collectionView.layoutIfNeeded()
            guard let header = supplementary(headerKind),
                  let footer = supplementary(footerKind) else { return false }
            return header.sectionContentView.titleLabel.text == "Header"
                && footer.sectionContentView.titleLabel.text == "Footer"
                && abs(header.bounds.height - headerHeight) <= 1
                && abs(footer.bounds.height - footerHeight) <= 1
        }
        #expect(restored)
        #expect(contentKeepsEightPointSupplementarySpacing())
        for kind in [headerKind, footerKind] {
            let view = try #require(supplementary(kind))
            view.layoutIfNeeded()
            let content = view.sectionContentView
            content.layoutIfNeeded()
            #expect(content.effectiveUserInterfaceLayoutDirection == .leftToRight)
            let label = content.titleLabel
            #expect(abs(label.convert(label.bounds, to: content).minX - 16) <= 1)
        }
    }

    @Test func directionRoundTripKeepsSupplementaryGeometry() throws {
        let controller = ContentConfigurationCollectionViewController(
            viewModel: ContentConfigurationListViewModel(
                configuration: .collection,
                localizer: Localizer { key, _ in "ltr." + key }
            )
        )
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 220)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.reloadLayoutDirection(.leftToRight)
        controller.view.layoutIfNeeded()
        let collection = try #require(
            controller.view.subviews.compactMap { $0 as? UICollectionView }.first
        )
        collection.reloadData()
        collection.layoutIfNeeded()
        let path = IndexPath(item: 0, section: 0)
        let initialOffset = collection.contentOffset
        let initialCellFrame = try #require(collection.cellForItem(at: path)).frame
        let initialHeader = try #require(collection.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: path
        ))
        #expect(initialHeader.frame.maxY <= initialCellFrame.minY)
        for direction in [UIUserInterfaceLayoutDirection.rightToLeft, .leftToRight] {
            controller.reloadLayoutDirection(direction)
            controller.view.layoutIfNeeded()
            collection.layoutIfNeeded()
            let header = try #require(collection.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader, at: path
            ))
            let cellFrame = try #require(collection.cellForItem(at: path)).frame
            #expect(header.frame.maxY <= cellFrame.minY)
            #expect(abs(collection.contentOffset.y - initialOffset.y) <= 1)
            #expect(abs(cellFrame.minY - initialCellFrame.minY) <= 1)
        }
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
