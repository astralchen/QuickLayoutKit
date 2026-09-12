import UIKit
import Testing
import QuickLayoutKit
import QuickLayout
import AppLocalization
@testable import Demo

@MainActor
extension ContentConfigurationCollectionTests {
    @Test func waterfallRouteAndThreeLanguagesUseContentConfiguration() async throws {
        let previousLocale = Localization.localizationController.currentLocale.identifier
        let followedSystem = Localization.localizationController.followsSystemLocale
        defer {
            Localization.setLocale(identifier: followedSystem ? LocalizationController.followSystemLocaleIdentifier : previousLocale)
        }
        let source = UIViewController()
        let navigation = UINavigationController(rootViewController: source)
        MainRouter().navigate(to: .waterfallContentConfiguration, from: source)
        #expect(navigation.topViewController is ContentConfigurationWaterfallViewController)
        let routes = MainViewModel().state.sections.flatMap(\.routes).map(\.route)
        let collectionIndex = try #require(routes.firstIndex(of: .collectionContentConfiguration))
        #expect(routes[collectionIndex + 1] == .waterfallContentConfiguration)

        Localization.setLocale(identifier: "en-US")
        let fixture = try WaterfallFixture(localizer: .live)
        defer { fixture.window.isHidden = true }
        for language in ["en-US", "zh-Hans", "ar"] {
            Localization.setLocale(identifier: language)
            fixture.controller.reloadLayoutDirection(Localization.currentUIKitDirection)
            fixture.controller.reloadLocalizedContent()
            await fixture.settle()
            let cell = try #require(fixture.controller.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
            let card = try #require(WaterfallFixture.card(in: cell))
            #expect(card.titleLabel.text == Localizer.live.text("contentConfiguration.sample.title.1"))
            #expect(fixture.controller.title == Localizer.live.text("demo.contentConfiguration.waterfall.title"))
            try fixture.verifyVisibleGeometry()
            try fixture.saveSnapshot(name: "waterfall-\(language)")
        }
    }

    @Test func waterfallPlacesItemsInShortestColumnAndRejectsStaleMeasurements() throws {
        let source = WaterfallLayoutTestSource(counts: [4])
        let layout = source.makeLayout()
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 360, height: 800), collectionViewLayout: layout)
        collection.dataSource = source
        collection.delegate = source
        source.bind(layout)
        source.section.interItemSpacing = 12
        source.section.interLaneSpacing = 12
        source.section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        source.section.itemLengthDimension = .estimated(240)
        collection.reloadData()
        layout.prepare()
        for (index, height) in [CGFloat(100), 200, 80].enumerated() {
            let original = try #require(layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)))
            let fitted = original.copy() as! UICollectionViewLayoutAttributes
            fitted.size = CGSize(width: 500, height: height)
            #expect(layout.shouldInvalidateLayout(forPreferredLayoutAttributes: fitted, withOriginalAttributes: original))
            layout.invalidateLayout(with: layout.invalidationContext(forPreferredLayoutAttributes: fitted, withOriginalAttributes: original))
            layout.prepare()
        }
        let fourth = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 3, section: 0)))
        #expect(fourth.frame == CGRect(x: 12, y: 216, width: 162, height: 240))
        let original = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        #expect(!layout.shouldInvalidateLayout(forPreferredLayoutAttributes: original, withOriginalAttributes: original))
        source.revision += 1
        layout.invalidateMeasurements(reason: "new-content")
        let stale = original.copy() as! UICollectionViewLayoutAttributes
        stale.size.height = 900
        #expect(!layout.shouldInvalidateLayout(forPreferredLayoutAttributes: stale, withOriginalAttributes: original))
        withExtendedLifetime((collection, source)) {}
    }

    @Test func waterfallUsesNativeFittingAndResizesExpandedContent() async throws {
        let fixture = try WaterfallFixture()
        defer { fixture.window.isHidden = true }
        await fixture.settle()
        let controller = fixture.controller
        #expect(controller.items.count == 40)
        #expect(controller.collectionView.numberOfSections == 4)
        #expect((0..<4).allSatisfy { controller.collectionView.numberOfItems(inSection: $0) == 10 })
        #expect(controller.collectionView.subviews.contains { $0 is ContentConfigurationWaterfallBackground })
        #expect(controller.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)) is ContentConfigurationWaterfallHeader)
        #expect(controller.waterfallLayout.acceptedMeasurementCount > 0)
        try fixture.verifyVisibleGeometry()
        let first = IndexPath(item: 0, section: 0)
        let originalHeight = try #require(controller.collectionView.cellForItem(at: first)).bounds.height

        controller.toggleItem(id: 0)
        await fixture.settle()
        let expanded = try #require(controller.collectionView.cellForItem(at: first))
        #expect(expanded.bounds.height > originalHeight)
        try fixture.verifyVisibleGeometry()

        controller.toggleItem(id: 0)
        await fixture.settle()
        let restored = try #require(controller.collectionView.cellForItem(at: first))
        #expect(abs(restored.bounds.height - originalHeight) <= 1)
        let count = controller.waterfallLayout.acceptedMeasurementCount
        await fixture.settle()
        #expect(controller.waterfallLayout.acceptedMeasurementCount == count)
    }

    @Test func waterfallRemeasuresColumnsWidthDynamicTypeAndDirection() async throws {
        let fixture = try WaterfallFixture()
        defer { fixture.window.isHidden = true }
        let controller = fixture.controller
        await fixture.settle()
        fixture.resize(width: 600)
        await fixture.settle()
        #expect(controller.laneCount == 3)
        try fixture.verifyVisibleGeometry()
        fixture.resize(width: 320)
        await fixture.settle()
        try fixture.verifyVisibleGeometry()
        fixture.resize(width: 600)
        await fixture.settle()
        try fixture.verifyVisibleGeometry()

        let first = IndexPath(item: 0, section: 0)
        let beforeType = try #require(controller.collectionView.cellForItem(at: first)).bounds.height
        fixture.parent.setOverrideTraitCollection(
            UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge), forChild: controller
        )
        await fixture.settle()
        #expect(try #require(controller.collectionView.cellForItem(at: first)).bounds.height > beforeType)
        try fixture.verifyVisibleGeometry()

        let ltr = try #require(controller.waterfallLayout.layoutAttributesForItem(at: first)).frame
        controller.reloadLayoutDirection(.rightToLeft)
        await fixture.settle()
        let rtl = try #require(controller.waterfallLayout.layoutAttributesForItem(at: first)).frame
        #expect(abs(rtl.minX - (controller.waterfallLayout.collectionViewContentSize.width - ltr.maxX)) <= 1)
        #expect(controller.collectionView.visibleCells.allSatisfy {
            $0.contentView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        })
        try fixture.verifyVisibleGeometry()
        controller.reloadLayoutDirection(.leftToRight)
        await fixture.settle()
        #expect(try #require(controller.waterfallLayout.layoutAttributesForItem(at: first)).frame == ltr)
    }

    @Test func waterfallDirectionControlsAndVisualReview() async throws {
        let previousLocale = Localization.localizationController.currentLocale.identifier
        let followedSystem = Localization.localizationController.followsSystemLocale
        defer { Localization.setLocale(identifier: followedSystem ? LocalizationController.followSystemLocaleIdentifier : previousLocale) }
        Localization.setLocale(identifier: "zh-Hans")
        let fixture = try WaterfallFixture(localizer: .live)
        defer { fixture.window.isHidden = true }
        let controller = fixture.controller
        await fixture.settle()
        let control = try #require(controller.view.subviews.compactMap { $0 as? UISegmentedControl }.first)
        let countLabel = try #require(controller.view.subviews.compactMap { $0 as? UILabel }.first)
        #expect(control.accessibilityIdentifier == "waterfall.direction")
        #expect(control.titleForSegment(at: 0) == "纵向")
        #expect(controller.laneCount == 2)
        #expect(countLabel.text == "自动 · 2 列")
        try fixture.verifyVisibleGeometry()
        try fixture.saveSnapshot(name: "waterfall-review-after-vertical")
        let nextHeader = try #require(controller.waterfallLayout.layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 1)))
        controller.collectionView.contentOffset.y = nextHeader.frame.minY - controller.collectionView.adjustedContentInset.top - 120
        await fixture.settle()
        try fixture.verifyVisibleGeometry()
        try fixture.saveSnapshot(name: "waterfall-review-after-sections")
        controller.collectionView.contentOffset.y = -controller.collectionView.adjustedContentInset.top
        await fixture.settle()
        control.selectedSegmentIndex = 1
        control.sendActions(for: .valueChanged)
        await fixture.settle()
        #expect(controller.waterfallLayout.configuration.scrollDirection == .horizontal)
        #expect(countLabel.text == "自动 · 3 行")
        #expect(controller.collectionView.showsHorizontalScrollIndicator)
        #expect(!controller.collectionView.showsVerticalScrollIndicator)
        let background = try #require(controller.view.subviews.first { $0.accessibilityIdentifier == "waterfall.controlsBackground" })
        for cell in controller.collectionView.visibleCells {
            let card = try #require(WaterfallFixture.card(in: cell))
            #expect(card.coverView.bounds.height <= 96)
            let frame = cell.convert(cell.bounds, to: controller.view)
            #expect(frame.minY >= background.frame.maxY + 11)
        }
        let first = try #require(controller.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        #expect(abs(first.convert(first.bounds, to: controller.view).minX - controller.waterfallLayout.section(at: 0).boundarySupplementaryItems[0].layoutSize.widthDimension.dimension - 12) <= 1)
        try fixture.saveSnapshot(name: "waterfall-review-after-horizontal")
        // 横屏高度减小时自动减少行数，无需手动选择。
        fixture.resize(width: 844)
        controller.view.frame.size.height = 390
        controller.view.setNeedsLayout()
        await fixture.settle()
        #expect(controller.laneCount == 1)
        #expect(countLabel.text == "自动 · 1 行")
        try fixture.saveSnapshot(name: "waterfall-review-after-landscape")
        fixture.resize(width: 390)
        controller.view.frame.size.height = 900
        controller.overrideUserInterfaceStyle = .dark
        await fixture.settle()
        try fixture.saveSnapshot(name: "waterfall-review-after-dark")
        controller.overrideUserInterfaceStyle = .light
        fixture.parent.setOverrideTraitCollection(
            UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraLarge), forChild: controller
        )
        await fixture.settle()
        #expect(controller.laneCount == 1)
        try fixture.saveSnapshot(name: "waterfall-review-after-large-type")
        fixture.parent.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .large), forChild: controller)
        Localization.setLocale(identifier: "ar")
        controller.reloadLayoutDirection(.rightToLeft)
        controller.reloadLocalizedContent()
        await fixture.settle()
        #expect(control.titleForSegment(at: 1) == Localizer.live.text("demo.contentConfiguration.waterfall.horizontal"))
        #expect(countLabel.text == Localizer.live.text("demo.contentConfiguration.waterfall.automaticRows", controller.laneCount))
        try fixture.saveSnapshot(name: "waterfall-review-after-arabic")
        // 在宽容器中纵向增加列数；缩窄后自动退为一列。
        control.selectedSegmentIndex = 0
        control.sendActions(for: .valueChanged)
        fixture.resize(width: 600)
        await fixture.settle()
        #expect(controller.laneCount == 3)
        fixture.resize(width: 320)
        await fixture.settle()
        #expect(controller.laneCount == 1)
        #expect(controller.waterfallLayout.configuration.scrollDirection == .vertical)
        try fixture.verifyVisibleGeometry()
        let settledCount = controller.waterfallLayout.acceptedMeasurementCount
        await fixture.settle()
        #expect(controller.waterfallLayout.acceptedMeasurementCount == settledCount)
    }

    @Test func waterfallNativeCellsFitHorizontallyAndReturnToVertical() async throws {
        let fixture = try WaterfallFixture()
        defer { fixture.window.isHidden = true }
        let controller = fixture.controller
        let layout = controller.waterfallLayout
        let collection = try #require(controller.collectionView)
        await fixture.settle()
        controller.setScrollDirection(.horizontal)
        await fixture.settle()
        func verifyHorizontal() throws {
            #expect(!collection.visibleCells.isEmpty)
            for path in collection.indexPathsForVisibleItems {
                let cell = try #require(collection.cellForItem(at: path))
                let card = try #require(WaterfallFixture.card(in: cell))
                cell.layoutIfNeeded()
                card.layoutIfNeeded()
                let sizing = layout.sizingForItem(at: path)
                #expect(card.quickLayoutHorizontalFlexibility == .fullyFlexible)
                #expect(card.quickLayoutVerticalFlexibility == .fixedSize)
                let expected = card.sizeThatFits(sizing.constraint)
                #expect(abs(cell.bounds.width - expected.width) <= 1)
                #expect(abs(cell.bounds.height - sizing.constraint.height) <= 1)
                #expect(abs(card.coverView.bounds.width / card.coverView.bounds.height - controller.items[path.section * 10 + path.item].imageAspectRatio) <= 0.01)
                let detail = card.detailLabel.convert(card.detailLabel.bounds, to: card)
                #expect(detail.maxY <= card.bounds.height + 1)
                #expect(detail.minX >= -1 && detail.maxX <= card.bounds.width + 1)
                let textSize = card.detailLabel.sizeThatFits(CGSize(width: card.detailLabel.bounds.width, height: .infinity))
                #expect(textSize.height <= card.detailLabel.bounds.height + 1)
            }
        }
        try verifyHorizontal()
        let count = layout.acceptedMeasurementCount
        await fixture.settle()
        #expect(layout.acceptedMeasurementCount == count)
        controller.view.frame.size.height = 600
        controller.view.setNeedsLayout()
        await fixture.settle()
        try verifyHorizontal()
        controller.toggleItem(id: 0)
        await fixture.settle()
        try verifyHorizontal()
        fixture.controller.view.frame.size.height = 750
        fixture.controller.view.setNeedsLayout()
        fixture.parent.setOverrideTraitCollection(
            UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge), forChild: controller
        )
        await fixture.settle()
        try verifyHorizontal()
        fixture.parent.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .large), forChild: controller)
        controller.reloadLayoutDirection(.rightToLeft)
        await fixture.settle()
        try verifyHorizontal()
        let rtlCount = layout.acceptedMeasurementCount
        await fixture.settle()
        #expect(layout.acceptedMeasurementCount == rtlCount)
        collection.scrollToItem(at: IndexPath(item: 0, section: 1), at: .right, animated: false)
        await fixture.settle()
        try verifyHorizontal()
        controller.reloadLayoutDirection(.leftToRight)
        controller.setScrollDirection(.vertical)
        collection.contentOffset = CGPoint(x: 0, y: -collection.adjustedContentInset.top)
        controller.view.setNeedsLayout()
        await fixture.settle()
        try fixture.verifyVisibleGeometry()
        controller.itemLengthDimension = .absolute(600)
        controller.view.setNeedsLayout()
        await fixture.settle()
        #expect(collection.visibleCells.allSatisfy { abs($0.bounds.height - 600) <= 1 })
        let fixedCount = layout.acceptedMeasurementCount
        await fixture.settle()
        #expect(layout.acceptedMeasurementCount == fixedCount)
        controller.itemLengthDimension = .estimated(240)
        controller.view.setNeedsLayout()
        await fixture.settle()
        try fixture.verifyVisibleGeometry()
    }

    @Test func waterfallReusesCellsAndPreservesAnchorDuringContentChanges() async throws {
        var longText = false
        let fixture = try WaterfallFixture(localizer: Localizer { key, _ in
            if key.contains("sample.detail") {
                return longText ? String(repeating: "Updated wrapping text. ", count: 12) : "Short content."
            }
            return "Title"
        })
        defer { fixture.window.isHidden = true }
        let controller = fixture.controller
        let collection = try #require(controller.collectionView)
        // 禁用测试中的预取，确保离屏 cell 进入复用池，而不是保留为预备 cell。
        collection.isPrefetchingEnabled = false
        await fixture.settle()
        var seen: [ObjectIdentifier: (cell: UICollectionViewCell, id: String)] = [:]
        var reused = false
        func recordCells() {
            for cell in collection.visibleCells {
                let identity = ObjectIdentifier(cell)
                let id = cell.accessibilityIdentifier ?? ""
                if let previous = seen[identity], previous.id != id { reused = true }
                seen[identity] = (cell, id)
            }
        }
        recordCells()
        for item in [10, 20, 30, 39, 20] {
            collection.scrollToItem(at: IndexPath(item: item % 10, section: item / 10), at: .top, animated: false)
            await fixture.settle()
            recordCells()
            try fixture.verifyVisibleGeometry()
        }
        #expect(reused)
        let anchor = try #require(collection.indexPathsForVisibleItems.min())
        let oldFrame = try #require(controller.waterfallLayout.layoutAttributesForItem(at: anchor)).frame
        let offset = oldFrame.minY - collection.contentOffset.y
        longText = true
        controller.reloadLocalizedContent()
        await fixture.settle()
        let newFrame = try #require(controller.waterfallLayout.layoutAttributesForItem(at: anchor)).frame
        #expect(abs(newFrame.minY - collection.contentOffset.y - offset) <= 1)
        try fixture.verifyVisibleGeometry()
        collection.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)
        await fixture.settle()
        let cell = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        let card = try #require(WaterfallFixture.card(in: cell))
        #expect(card.detailLabel.text?.contains("Updated wrapping text.") == true)
        try fixture.verifyVisibleGeometry()
    }
}

@MainActor
private final class WaterfallFixture {
    let window: UIWindow
    let parent = UIViewController()
    let controller: ContentConfigurationWaterfallViewController

    init(localizer: Localizer? = nil) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 900)
        controller = ContentConfigurationWaterfallViewController(localizer: localizer ?? Localizer { key, _ in
            key.contains("sample.detail") ? "Content wraps naturally across multiple lines. A longer sentence verifies the measured height." : "Card title"
        })
        window.rootViewController = parent
        parent.addChild(controller)
        parent.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .large), forChild: controller)
        parent.view.addSubview(controller.view)
        controller.view.frame = parent.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.didMove(toParent: parent)
        window.isHidden = false
        controller.reloadLayoutDirection(.leftToRight)
    }

    static func card(in view: UIView) -> ContentConfigurationWaterfallCard? {
        if let card = view as? ContentConfigurationWaterfallCard { return card }
        return view.subviews.lazy.compactMap { card(in: $0) }.first
    }

    func resize(width: CGFloat) {
        // 改变实际容器宽度，不依赖宿主设备屏幕尺寸。
        controller.view.autoresizingMask = []
        controller.view.frame.size.width = width
        controller.view.setNeedsLayout()
    }

    func settle() async {
        for _ in 0..<20 {
            controller.view.layoutIfNeeded()
            controller.collectionView.layoutIfNeeded()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func verifyVisibleGeometry() throws {
        let collection = try #require(controller.collectionView)
        #expect(controller.view is QuickLayoutView)
        #expect(collection.superview === controller.view)
        let direction = try #require(controller.view.subviews.compactMap { $0 as? UISegmentedControl }.first)
        #expect(direction.accessibilityIdentifier == "waterfall.direction")
        #expect(direction.bounds.width <= min(320, controller.view.bounds.width - 24) + 1)
        #expect(direction.bounds.height >= 44)
        #expect(abs(direction.frame.minY - controller.view.safeAreaInsets.top - 8) <= 1)
        let hit = controller.view.hitTest(CGPoint(x: direction.frame.midX, y: direction.frame.midY), with: nil)
        #expect(hit?.isDescendant(of: direction) == true)
        #expect(collection.frame == controller.view.bounds)
        #expect(collection.contentInsetAdjustmentBehavior == .always)
        #expect(!collection.visibleCells.isEmpty)
        for path in collection.indexPathsForVisibleItems {
            let cell = try #require(collection.cellForItem(at: path))
            let card = try #require(WaterfallFixture.card(in: cell))
            cell.layoutIfNeeded()
            card.layoutIfNeeded()
            let expected = card.sizeThatFits(CGSize(width: cell.bounds.width, height: .infinity))
            #expect(abs(cell.bounds.height - expected.height) <= 1)
            let attributes = try #require(controller.waterfallLayout.layoutAttributesForItem(at: path))
            #expect(abs(cell.frame.minX - attributes.frame.minX) <= 1)
            #expect(abs(cell.frame.minY - attributes.frame.minY) <= 1)
            #expect(abs(cell.bounds.width - attributes.size.width) <= 1)
            #expect(cell.bounds.height.isFinite && cell.bounds.height > 0)
            #expect(abs(card.coverView.bounds.height * controller.items[path.section * 10 + path.item].imageAspectRatio - card.bounds.width) <= 1)
            let detailFrame = card.detailLabel.convert(card.detailLabel.bounds, to: card)
            #expect(detailFrame.maxY <= card.bounds.maxY + 1)
            let textHeight = card.detailLabel.sizeThatFits(CGSize(width: card.detailLabel.bounds.width, height: .infinity)).height
            #expect(card.detailLabel.bounds.height + 1 >= textHeight)
        }
        let all = controller.items.indices.compactMap {
            controller.waterfallLayout.layoutAttributesForItem(at: IndexPath(item: $0 % 10, section: $0 / 10))?.frame
        }
        for (index, frame) in all.enumerated() {
            #expect(frame.minX >= 11 && frame.maxX <= collection.bounds.width - 11)
            for other in all.dropFirst(index + 1) { #expect(!frame.intersects(other)) }
        }
    }

    func saveSnapshot(name: String) throws {
        let renderer = UIGraphicsImageRenderer(bounds: controller.view.bounds)
        let data = renderer.pngData { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        try data.write(to: url)
        print("[WaterfallSnapshot] \(url.path)")
    }
}
