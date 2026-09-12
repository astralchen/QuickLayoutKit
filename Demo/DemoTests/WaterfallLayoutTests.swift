import UIKit
import Testing
import QuickLayout
import QuickLayoutKit
@testable import Demo

@MainActor
func waterfallBoundary(_ kind: String, length: CGFloat, direction: UICollectionView.ScrollDirection = .vertical, pinned: Bool = false) -> NSCollectionLayoutBoundarySupplementaryItem {
    let horizontal = direction == .horizontal
    let header = kind == UICollectionView.elementKindSectionHeader
    let item = NSCollectionLayoutBoundarySupplementaryItem(
        layoutSize: .init(widthDimension: horizontal ? .absolute(length) : .fractionalWidth(1), heightDimension: horizontal ? .fractionalHeight(1) : .absolute(length)),
        elementKind: kind, alignment: horizontal ? (header ? .leading : .trailing) : (header ? .top : .bottom))
    item.pinToVisibleBounds = pinned
    return item
}

@MainActor
final class WaterfallLayoutTestSource: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
    var counts: [Int]
    var identifiers: [[Int]]
    var revision = 0
    var section = ContentConfigurationWaterfallLayout.Section() { didSet { layout?.invalidateSectionConfigurations(reason: "test-section") } }
    var customized = false { didSet { layout?.invalidateSectionConfigurations(reason: "test-section") } }
    var sectionInsetsOverride: NSDirectionalEdgeInsets?
    var headerLength: CGFloat = 0 { didSet { layout?.invalidateSectionConfigurations(reason: "test-header") } }
    var footerLength: CGFloat = 0 { didSet { layout?.invalidateSectionConfigurations(reason: "test-footer") } }
    var pinsHeaders = false { didSet { layout?.invalidateSectionConfigurations(reason: "test-header-pin") } }
    var pinsFooters = false { didSet { layout?.invalidateSectionConfigurations(reason: "test-footer-pin") } }
    private weak var layout: ContentConfigurationWaterfallLayout?
    init(counts: [Int]) {
        self.counts = counts
        identifiers = counts.enumerated().map { section, count in (0..<count).map { section * 1000 + $0 } }
    }
    func numberOfSections(in collectionView: UICollectionView) -> Int { counts.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { counts[section] }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "test")
        return collectionView.dequeueReusableCell(withReuseIdentifier: "test", for: indexPath)
    }
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        collectionView.register(UICollectionReusableView.self, forSupplementaryViewOfKind: kind, withReuseIdentifier: kind)
        return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath)
    }
    func bind(_ layout: ContentConfigurationWaterfallLayout) {
        self.layout = layout
        layout.itemMetadataProvider = { [weak self] path in
            guard let self else { return .init(identifier: path) }
            return .init(identifier: self.identifiers[path.section][path.item], contentVersion: self.revision)
        }
    }
    func makeLayout() -> ContentConfigurationWaterfallLayout {
        let result = ContentConfigurationWaterfallLayout(sectionProvider: { [weak self] index, _ in
            guard let self else { return nil }
            var value = self.section
            value.laneCount = self.customized ? index + 1 : value.laneCount
            value.contentInsets = self.sectionInsetsOverride ?? value.contentInsets
            if self.customized { value.itemLengthDimensionProvider = { item, _ in .absolute(CGFloat(60 + item * 20)) } }
            let direction = self.layout?.configuration.scrollDirection ?? .vertical
            value.boundarySupplementaryItems = []
            if self.headerLength > 0 { value.boundarySupplementaryItems.append(waterfallBoundary(UICollectionView.elementKindSectionHeader, length: self.headerLength, direction: direction, pinned: self.pinsHeaders)) }
            if self.footerLength > 0 { value.boundarySupplementaryItems.append(waterfallBoundary(UICollectionView.elementKindSectionFooter, length: self.footerLength, direction: direction, pinned: self.pinsFooters)) }
            return value
        })
        bind(result)
        return result
    }
}

@MainActor
extension ContentConfigurationCollectionTests {
    @Test func waterfallStrategiesTrackDirectionAndFixedMode() throws {
        let source = WaterfallLayoutTestSource(counts: [4])
        let layout = source.makeLayout()
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 360, height: 600), collectionViewLayout: layout)
        collection.dataSource = source
        collection.delegate = source
        source.bind(layout)
        collection.reloadData()
        let path = IndexPath(item: 0, section: 0)
        layout.prepare()
        let fixed = layout.sizingForItem(at: path)
        #expect(fixed.constraint == CGSize(width: 175, height: 50))
        #expect(fixed.horizontalFlexibility == .fixedSize && fixed.verticalFlexibility == .fixedSize)
        let fixedAttributes = try #require(layout.layoutAttributesForItem(at: path))
        let preferred = fixedAttributes.copy() as! UICollectionViewLayoutAttributes
        preferred.size.height = 200
        #expect(!layout.shouldInvalidateLayout(forPreferredLayoutAttributes: preferred, withOriginalAttributes: fixedAttributes))

        source.section.itemLengthDimension = .estimated(240)
        layout.prepare()
        #expect(layout.sizingForItem(at: path).constraint == CGSize(width: 175, height: CGFloat.infinity))
        #expect(layout.sizingForItem(at: path).verticalFlexibility == .fullyFlexible)
        let stale = try #require(layout.layoutAttributesForItem(at: path))
        layout.configuration.scrollDirection = .horizontal
        source.section.laneCount = 3
        layout.prepare()
        let horizontal = layout.sizingForItem(at: path)
        #expect(horizontal.constraint == CGSize(width: CGFloat.infinity, height: 580 / 3))
        #expect(horizontal.horizontalFlexibility == .fullyFlexible && horizontal.verticalFlexibility == .fixedSize)
        #expect(!layout.shouldInvalidateLayout(forPreferredLayoutAttributes: preferred, withOriginalAttributes: stale))
        let original = try #require(layout.layoutAttributesForItem(at: path))
        let fitted = original.copy() as! UICollectionViewLayoutAttributes
        fitted.size = CGSize(width: 121.01, height: 999)
        #expect(layout.shouldInvalidateLayout(forPreferredLayoutAttributes: fitted, withOriginalAttributes: original))
        layout.invalidateLayout(with: layout.invalidationContext(forPreferredLayoutAttributes: fitted, withOriginalAttributes: original))
        layout.prepare()
        let actual = try #require(layout.layoutAttributesForItem(at: path))
        #expect(actual.size.height == horizontal.constraint.height)
        let scale = max(1, collection.traitCollection.displayScale)
        #expect(actual.size.width == ceil(121.01 * scale) / scale)
        #expect(!layout.shouldInvalidateLayout(forPreferredLayoutAttributes: actual, withOriginalAttributes: actual))
        source.section.itemLengthDimension = .absolute(50)
        layout.prepare()
        #expect(layout.sizingForItem(at: path).constraint.width == 50)
        layout.configuration.scrollDirection = .vertical
        layout.prepare()
        #expect(source.section.laneCount == 3)
        #expect(layout.sizingForItem(at: path).constraint == CGSize(width: CGFloat(340) / 3, height: 50))
        withExtendedLifetime(source) {}
    }

    @Test func waterfallSectionsSupplementariesPinAndMirrorInBothDirections() throws {
        for direction in [UICollectionView.ScrollDirection.vertical, .horizontal] {
            let source = WaterfallLayoutTestSource(counts: [4, 0, 4])
            let layout = source.makeLayout()
            layout.configuration.scrollDirection = direction
            source.headerLength = 30
            source.footerLength = 20
            source.pinsHeaders = true
            source.pinsFooters = true
            source.section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            source.customized = true
            let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 300), collectionViewLayout: layout)
            collection.dataSource = source
            collection.delegate = source
            source.bind(layout)
            collection.semanticContentAttribute = .forceLeftToRight
            collection.reloadData()
            layout.prepare()
            let frames = (0..<3).flatMap { section in
                (0..<source.counts[section]).compactMap { layout.layoutAttributesForItem(at: IndexPath(item: $0, section: section))?.frame }
            }
            for (index, frame) in frames.enumerated() {
                for other in frames.dropFirst(index + 1) { #expect(!frame.intersects(other)) }
            }
            let path = IndexPath(item: 0, section: 0)
            #expect(try #require(layout.layoutAttributesForItem(at: path)).size == (direction == .vertical ? CGSize(width: 276, height: 60) : CGSize(width: 60, height: 276)))
            #expect(layout.layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 1)) != nil)
            collection.contentOffset = direction == .vertical ? CGPoint(x: 0, y: 70) : CGPoint(x: 70, y: 0)
            let pinned = try #require(layout.layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: path))
            #expect((direction == .vertical ? pinned.frame.minY : pinned.frame.minX) == 70)
            #expect(pinned.zIndex > 0)
            let before = try #require(layout.layoutAttributesForItem(at: path)).frame
            collection.semanticContentAttribute = .forceRightToLeft
            layout.invalidateMeasurements(reason: "rtl-test")
            layout.prepare()
            let after = try #require(layout.layoutAttributesForItem(at: path)).frame
            #expect(after.minX == layout.collectionViewContentSize.width - before.maxX)
            #expect(after.size == before.size)
            source.headerLength = 0
            layout.prepare()
            #expect(layout.layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: path) == nil)
            withExtendedLifetime(source) {}
        }
    }

    @Test func waterfallMountedSupplementariesAndDeletionPreserveVisibleAnchor() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        let source = WaterfallLayoutTestSource(counts: [40])
        let layout = source.makeLayout()
        source.section.itemLengthDimension = .absolute(120)
        source.headerLength = 30
        source.footerLength = 20
        source.pinsHeaders = true
        source.pinsFooters = true
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.dataSource = source
        collection.delegate = source
        source.bind(layout)
        window.rootViewController = host
        host.view.addSubview(collection)
        window.isHidden = false
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 430
        collection.layoutIfNeeded()
        let path = IndexPath(item: 0, section: 0)
        let header = try #require(collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: path))
        let footer = try #require(collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: path))
        #expect(header.frame.minY == 430)
        #expect(footer.frame.maxY == 730)
        #expect(!header.frame.intersects(footer.frame))
        let anchorPath = try #require(collection.indexPathsForVisibleItems.min())
        let anchorID = source.identifiers[0][anchorPath.item]
        let anchorFrame = try #require(layout.layoutAttributesForItem(at: anchorPath)).frame
        let previousOffset = anchorFrame.minY - collection.contentOffset.y
        source.identifiers[0].removeFirst(2)
        source.counts[0] -= 2
        collection.reloadData()
        collection.layoutIfNeeded()
        let nextItem = try #require(source.identifiers[0].firstIndex(of: anchorID))
        let nextFrame = try #require(layout.layoutAttributesForItem(at: IndexPath(item: nextItem, section: 0))).frame
        #expect(abs(nextFrame.minY - collection.contentOffset.y - previousOffset) <= 1)
        withExtendedLifetime(source) {}
    }

    @Test func waterfallDirectionalInsetsMirrorAsymmetricEdgesAndProviderOverrides() throws {
        for usesProvider in [false, true] {
            for direction in [UICollectionView.ScrollDirection.vertical, .horizontal] {
                let source = WaterfallLayoutTestSource(counts: [4])
                let layout = source.makeLayout()
                layout.configuration.scrollDirection = direction
                let insets = NSDirectionalEdgeInsets(top: 7, leading: 20, bottom: 13, trailing: 40)
                if usesProvider { source.sectionInsetsOverride = insets } else { source.section.contentInsets = insets }
                let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 360, height: 600), collectionViewLayout: layout)
                collection.contentInsetAdjustmentBehavior = .never
                collection.dataSource = source
                collection.delegate = source
                source.bind(layout)
                collection.semanticContentAttribute = .forceLeftToRight
                collection.reloadData()
                layout.prepare()
                let paths = (0..<4).map { IndexPath(item: $0, section: 0) }
                let ltr = try paths.map { try #require(layout.layoutAttributesForItem(at: $0)).frame }
                #expect(ltr[0].minX == 20)
                #expect(ltr[0].minY == 7)
                let end = try #require(ltr.map(\.maxX).max())
                #expect(layout.collectionViewContentSize.width - end == 40)
                collection.semanticContentAttribute = .forceRightToLeft
                layout.invalidateMeasurements(reason: "directional-inset-test")
                layout.prepare()
                for (index, path) in paths.enumerated() {
                    let rtl = try #require(layout.layoutAttributesForItem(at: path)).frame
                    #expect(rtl.minX == layout.collectionViewContentSize.width - ltr[index].maxX)
                    #expect(rtl.minY == ltr[index].minY)
                    #expect(rtl.size == ltr[index].size)
                }
                collection.semanticContentAttribute = .forceLeftToRight
                layout.invalidateMeasurements(reason: "directional-inset-round-trip")
                layout.prepare()
                #expect(try #require(layout.layoutAttributesForItem(at: paths[0])).frame == ltr[0])
                withExtendedLifetime(source) {}
            }
        }
    }

    @Test func waterfallInsetReferencesRespectAdjustedInsetsWithoutDoubleCounting() throws {
        let source = WaterfallLayoutTestSource(counts: [2])
        let layout = source.makeLayout()
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 360, height: 600), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset = UIEdgeInsets(top: 5, left: 30, bottom: 5, right: 20)
        collection.layoutMargins = UIEdgeInsets(top: 20, left: 50, bottom: 20, right: 40)
        collection.dataSource = source
        collection.delegate = source
        source.bind(layout)
        source.section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        collection.reloadData()
        for reference in [UIContentInsetsReference.none, .safeArea, .layoutMargins] {
            source.section.contentInsetsReference = reference
            layout.prepare()
            let first = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            let expectedStart: CGFloat = reference == .none ? 12 : reference == .safeArea ? 0 : 32
            #expect(first.frame.minX == expectedStart)
            #expect(layout.collectionViewContentSize.width == 310)
        }
        withExtendedLifetime(source) {}
    }
}

@MainActor
extension ContentConfigurationCollectionTests {
    @Test func waterfallSectionProviderUsesNativeEnvironmentAndIndependentSizing() throws {
        var environments: [CGSize] = []
        var first = ContentConfigurationWaterfallLayout.Section()
        first.laneCount = 1
        first.itemLengthDimension = .estimated(120)
        first.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 6, trailing: 20)
        var second = ContentConfigurationWaterfallLayout.Section()
        second.laneCount = 3
        second.itemLengthDimension = .absolute(75)
        let layout = ContentConfigurationWaterfallLayout(sectionProvider: { index, environment in
            environments.append(environment.container.effectiveContentSize)
            #expect(environment.container.contentSize == CGSize(width: 360, height: 600))
            #expect(environment.container.effectiveContentInsets.leading == 8)
            return index == 0 ? first : index == 1 ? second : nil
        })
        let source = WaterfallLayoutTestSource(counts: [3, 3, 1])
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 360, height: 600), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset = UIEdgeInsets(top: 10, left: 8, bottom: 20, right: 12)
        collection.dataSource = source
        collection.delegate = source
        source.bind(layout)
        collection.reloadData()
        layout.prepare()
        let adaptive = IndexPath(item: 0, section: 0)
        let fixed = IndexPath(item: 0, section: 1)
        #expect(layout.sizingForItem(at: adaptive).constraint == CGSize(width: 310, height: CGFloat.infinity))
        #expect(layout.sizingForItem(at: fixed).constraint == CGSize(width: CGFloat(320) / 3, height: 75))
        #expect(try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 2))).size.height == 50)
        #expect(environments.allSatisfy { $0 == CGSize(width: 340, height: 570) })
        let count = environments.count
        _ = layout.sizingForItem(at: adaptive)
        _ = layout.sizingForItem(at: fixed)
        #expect(environments.count == count)
        let stale = try #require(layout.layoutAttributesForItem(at: adaptive))
        first.itemLengthDimension = .absolute(120) // Same initial frame, different fitting policy.
        layout.invalidateSectionConfigurations(reason: "fixed-mode")
        let preferred = stale.copy() as! UICollectionViewLayoutAttributes
        preferred.size.height = 200
        #expect(!layout.shouldInvalidateLayout(forPreferredLayoutAttributes: preferred, withOriginalAttributes: stale))
        #expect(layout.sizingForItem(at: adaptive).verticalFlexibility == .fixedSize)
        withExtendedLifetime(source) {}
    }

    @Test func waterfallDecorationSnapshotsTrackFitsAndPreserveMeasurements() throws {
        let background = NSCollectionLayoutDecorationItem.background(elementKind: "background")
        background.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 3, bottom: 5, trailing: 7)
        var section = ContentConfigurationWaterfallLayout.Section()
        section.laneCount = 1
        section.itemLengthDimension = .estimated(100)
        section.boundarySupplementaryItems = [waterfallBoundary(UICollectionView.elementKindSectionHeader, length: 20, pinned: true), waterfallBoundary(UICollectionView.elementKindSectionFooter, length: 10)]
        section.decorationItems = [background]
        let layout = ContentConfigurationWaterfallLayout(sectionProvider: { _, _ in section })
        layout.configuration.interSectionSpacing = 12
        layout.register(UICollectionReusableView.self, forDecorationViewOfKind: "background")
        layout.register(UICollectionReusableView.self, forDecorationViewOfKind: "overlay")
        let source = WaterfallLayoutTestSource(counts: [1, 1])
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 100), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.dataSource = source
        collection.delegate = source
        source.bind(layout)
        collection.reloadData()
        layout.prepare()
        let path = IndexPath(item: 0, section: 0)
        let next = IndexPath(item: 0, section: 1)
        let originalBackground = try #require(layout.layoutAttributesForDecorationView(ofKind: "background", at: path))
        #expect(originalBackground.frame == CGRect(x: 3, y: 2, width: 290, height: 123))
        #expect(originalBackground.zIndex == 0)
        #expect(try #require(layout.layoutAttributesForItem(at: path)).zIndex == 1)
        originalBackground.frame = .zero
        #expect(try #require(layout.layoutAttributesForDecorationView(ofKind: "background", at: path)).frame.height == 123)
        background.contentInsets.top = 9
        #expect(layout.section(at: 0).decorationItems[0].contentInsets.top == 2)
        let original = try #require(layout.layoutAttributesForItem(at: path))
        let preferred = original.copy() as! UICollectionViewLayoutAttributes
        preferred.size.height = 175
        layout.invalidateLayout(with: layout.invalidationContext(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original))
        layout.prepare()
        #expect(try #require(layout.layoutAttributesForDecorationView(ofKind: "background", at: path)).frame.height == 198)
        #expect(try #require(layout.layoutAttributesForDecorationView(ofKind: "background", at: next)).frame.minY == 219)
        let accepted = layout.acceptedMeasurementCount
        let overlay = NSCollectionLayoutDecorationItem.background(elementKind: "overlay")
        overlay.zIndex = 7
        section.decorationItems.append(overlay)
        layout.invalidateSectionConfigurations(reason: "decoration-only")
        layout.prepare()
        #expect(try #require(layout.layoutAttributesForItem(at: path)).size.height == 175)
        #expect(layout.acceptedMeasurementCount == accepted)
        #expect(try #require(layout.layoutAttributesForDecorationView(ofKind: "overlay", at: path)).zIndex == 7)
        let natural = try #require(layout.layoutAttributesForDecorationView(ofKind: "background", at: path)).frame
        collection.contentOffset.y = 60
        #expect(try #require(layout.layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: path)).frame.minY == 60)
        #expect(try #require(layout.layoutAttributesForDecorationView(ofKind: "background", at: path)).frame == natural)
        #expect(layout.layoutAttributesForElements(in: natural)?.filter { $0.representedElementCategory == .decorationView }.count == 2)
        withExtendedLifetime(source) {}
    }

    @Test func waterfallDecorationMirrorsAndEmptySectionsHaveNaturalBounds() throws {
        for direction in [UICollectionView.ScrollDirection.vertical, .horizontal] {
            var empty = ContentConfigurationWaterfallLayout.Section()
            let background = NSCollectionLayoutDecorationItem.background(elementKind: "background")
            background.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 3, bottom: 5, trailing: 7)
            empty.decorationItems = [background]
            var content = empty
            content.boundarySupplementaryItems = [waterfallBoundary(UICollectionView.elementKindSectionHeader, length: 20, direction: direction), waterfallBoundary(UICollectionView.elementKindSectionFooter, length: 10, direction: direction)]
            let layout = ContentConfigurationWaterfallLayout(sectionProvider: { index, _ in index == 0 ? empty : content }, configuration: .init(scrollDirection: direction, interSectionSpacing: 12))
            layout.register(UICollectionReusableView.self, forDecorationViewOfKind: "background")
            let source = WaterfallLayoutTestSource(counts: [0, 0, 2])
            let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 300), collectionViewLayout: layout)
            collection.contentInsetAdjustmentBehavior = .never
            collection.dataSource = source
            collection.delegate = source
            source.bind(layout)
            collection.semanticContentAttribute = .forceLeftToRight
            collection.reloadData()
            layout.prepare()
            #expect(layout.layoutAttributesForDecorationView(ofKind: "background", at: IndexPath(item: 0, section: 0)) == nil)
            let path = IndexPath(item: 0, section: 1)
            let ltr = try #require(layout.layoutAttributesForDecorationView(ofKind: "background", at: path)).frame
            #expect(direction == .vertical ? ltr.height == 23 : ltr.width == 20)
            collection.semanticContentAttribute = .forceRightToLeft
            layout.invalidateSectionConfigurations(reason: "rtl")
            layout.prepare()
            let mirrored = try #require(layout.layoutAttributesForDecorationView(ofKind: "background", at: path)).frame
            #expect(mirrored.minX == layout.collectionViewContentSize.width - ltr.maxX)
            #expect(mirrored.size == ltr.size)
            withExtendedLifetime(source) {}
        }
    }

    @Test func waterfallMountedDecorationsSurviveSectionMovesAndDeletion() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        var section = ContentConfigurationWaterfallLayout.Section()
        section.itemLengthDimension = .absolute(90)
        section.decorationItems = [.background(elementKind: ContentConfigurationWaterfallBackground.elementKind)]
        let layout = ContentConfigurationWaterfallLayout(section: section, configuration: .init(interSectionSpacing: 12))
        layout.register(ContentConfigurationWaterfallBackground.self, forDecorationViewOfKind: ContentConfigurationWaterfallBackground.elementKind)
        let source = WaterfallLayoutTestSource(counts: [8, 8, 8])
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.dataSource = source
        collection.delegate = source
        source.bind(layout)
        host.view.addSubview(collection)
        window.isHidden = false
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        #expect(collection.subviews.contains { $0 is ContentConfigurationWaterfallBackground })
        collection.contentOffset.y = 450
        collection.layoutIfNeeded()
        let path = IndexPath(item: 2, section: 1)
        let frame = try #require(layout.layoutAttributesForItem(at: path)).frame
        let relative = frame.minY - collection.contentOffset.y
        collection.performBatchUpdates {
            source.counts.remove(at: 0)
            source.identifiers.remove(at: 0)
            collection.deleteSections(IndexSet(integer: 0))
        }
        for _ in 0..<10 { collection.layoutIfNeeded(); try? await Task.sleep(nanoseconds: 20_000_000) }
        let moved = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 2, section: 0))).frame
        #expect(abs(moved.minY - collection.contentOffset.y - relative) <= 1)
        collection.performBatchUpdates {
            source.counts.swapAt(0, 1)
            source.identifiers.swapAt(0, 1)
            collection.moveSection(0, toSection: 1)
        }
        for _ in 0..<10 { collection.layoutIfNeeded(); try? await Task.sleep(nanoseconds: 20_000_000) }
        #expect(collection.subviews.contains { $0 is ContentConfigurationWaterfallBackground })
        let a = try #require(layout.layoutAttributesForDecorationView(ofKind: ContentConfigurationWaterfallBackground.elementKind, at: IndexPath(item: 0, section: 0)))
        let b = try #require(layout.layoutAttributesForDecorationView(ofKind: ContentConfigurationWaterfallBackground.elementKind, at: IndexPath(item: 0, section: 1)))
        #expect(!a.frame.intersects(b.frame))
        #expect(b.frame.minY - a.frame.maxY == 12)
        collection.performBatchUpdates {
            source.counts.insert(2, at: 0)
            source.identifiers.insert([4000, 4001], at: 0)
            collection.insertSections(IndexSet(integer: 0))
        }
        for _ in 0..<10 { collection.layoutIfNeeded(); try? await Task.sleep(nanoseconds: 20_000_000) }
        #expect(collection.numberOfSections == 3)
        for section in 0..<3 {
            #expect(layout.layoutAttributesForDecorationView(ofKind: ContentConfigurationWaterfallBackground.elementKind, at: IndexPath(item: 0, section: section)) != nil)
        }
        withExtendedLifetime(source) {}
    }
}

@MainActor
extension ContentConfigurationCollectionTests {
    @Test func waterfallCompositionalSurfaceResolvesDimensionsAndCustomBoundaryKinds() throws {
        var section = ContentConfigurationWaterfallLayout.Section()
        section.itemLengthDimension = .fractionalHeight(0.25)
        var calls = 0
        section.itemLengthDimensionProvider = { index, environment in
            calls += 1
            #expect(environment.container.effectiveContentSize == CGSize(width: 300, height: 400))
            return index == 0 ? .estimated(123) : nil
        }
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(25)),
            elementKind: "custom.header", alignment: .top)
        header.pinToVisibleBounds = true
        header.zIndex = 2048
        section.boundarySupplementaryItems = [header]
        let layout = ContentConfigurationWaterfallLayout(section: section, configuration: .init(contentInsetsReference: .layoutMargins))
        let source = WaterfallLayoutTestSource(counts: [4])
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 400), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 30)
        collection.dataSource = source
        collection.delegate = source
        source.bind(layout)
        collection.reloadData()
        layout.prepare()
        let first = IndexPath(item: 0, section: 0)
        let second = IndexPath(item: 1, section: 0)
        #expect(layout.sizingForItem(at: first).constraint.height == .infinity)
        #expect(layout.sizingForItem(at: second).constraint.height == 100)
        #expect(layout.sizingForItem(at: first).constraint.width == 120)
        #expect(try #require(layout.layoutAttributesForItem(at: first)).frame.minX == 20)
        #expect(try #require(layout.layoutAttributesForItem(at: first)).size.height == 123)
        #expect(calls == 4)
        _ = layout.sizingForItem(at: second)
        #expect(calls == 4)
        header.pinToVisibleBounds = false // Initialization captured an independent snapshot.
        collection.contentOffset.y = 40
        let pinned = try #require(layout.layoutAttributesForSupplementaryView(ofKind: "custom.header", at: first))
        #expect(pinned.frame.minY == 40)
        #expect(pinned.zIndex == 2048)
        layout.configuration.contentInsetsReference = .none
        layout.prepare()
        #expect(layout.sizingForItem(at: first).constraint.width == 145)
        withExtendedLifetime(source) {}
    }
}
