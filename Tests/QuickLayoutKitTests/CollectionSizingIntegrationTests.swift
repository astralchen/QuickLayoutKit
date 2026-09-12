import Testing
import UIKit
import QuickLayout
import QuickLayoutKitUIKit

@MainActor
extension QuickLayoutKitTests {
    @Test func estimatedElementsResizeForContentWidthAndDynamicType() throws {
        let fixture = SizingCollectionFixture()
        defer { fixture.window.isHidden = true }
        fixture.layout()
        let shortHeights = try fixture.visibleHeights()
        #expect(shortHeights.allSatisfy { $0 > 0 && $0 < 30 })

        fixture.source.text = String(repeating: "A wrapping collection view title. ", count: 5)
        fixture.collection.reloadData()
        fixture.layout()
        let longHeights = try fixture.visibleHeights()
        #expect(zip(longHeights, shortHeights).allSatisfy { $0 > $1 })

        fixture.controller.view.frame.size.width = 240
        fixture.collection.frame = fixture.controller.view.bounds
        fixture.collection.collectionViewLayout.invalidateLayout()
        fixture.layout()
        let narrowHeights = try fixture.visibleHeights()
        #expect(zip(narrowHeights, longHeights).allSatisfy { $0 > $1 })

        fixture.parent.setOverrideTraitCollection(
            UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge),
            forChild: fixture.controller
        )
        fixture.collection.reloadData()
        fixture.collection.collectionViewLayout.invalidateLayout()
        fixture.layout()
        let largeTextHeights = try fixture.visibleHeights()
        #expect(zip(largeTextHeights, narrowHeights).allSatisfy { $0 > $1 })

        fixture.collection.semanticContentAttribute = .forceRightToLeft
        fixture.collection.collectionViewLayout.invalidateLayout()
        fixture.layout()
        let rtlHeights = try fixture.visibleHeights()
        #expect(rtlHeights == largeTextHeights)
        #expect(fixture.collection.visibleCells.allSatisfy {
            $0.effectiveUserInterfaceLayoutDirection == .rightToLeft
        })
    }

    @Test func reusedCellRemeasuresChangedContent() async throws {
        let fixture = SizingCollectionFixture(itemCount: 40)
        defer { fixture.window.isHidden = true }
        fixture.source.text = String(repeating: "A wrapping collection view title. ", count: 5)
        fixture.collection.reloadData()
        fixture.layout()
        let firstPath = IndexPath(item: 0, section: 0)
        let initialHeight = try #require(fixture.collection.cellForItem(at: firstPath)).bounds.height

        fixture.collection.scrollToItem(
            at: IndexPath(item: 39, section: 0), at: .bottom, animated: false
        )
        fixture.layout()
        #expect(!fixture.collection.indexPathsForVisibleItems.contains(firstPath))
        fixture.source.text = "Short"
        // 通知 UIKit 更新离屏 item；离屏 cell 仍可能处于已准备但尚未回收的状态。
        fixture.collection.reloadItems(at: [firstPath])
        fixture.collection.scrollToItem(at: firstPath, at: .top, animated: false)
        for _ in 0..<50 {
            fixture.layout()
            if let cell = fixture.collection.cellForItem(at: firstPath) as? SizingTextCell,
               cell.label.text == "Short", cell.wasReused {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let cell = try #require(fixture.collection.cellForItem(at: firstPath) as? SizingTextCell)
        #expect(cell.label.text == "Short")
        #expect(cell.bounds.height < initialHeight)
        #expect(cell.wasReused)
    }

    @Test func fixedGridKeepsLayoutDimensions() throws {
        let fixture = SizingCollectionFixture(fixedHeight: 64)
        defer { fixture.window.isHidden = true }
        fixture.source.text = String(repeating: "Long fixed grid content ", count: 20)
        fixture.collection.reloadData()
        fixture.layout()

        let cell = try #require(fixture.collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        #expect(cell.bounds.size == CGSize(width: 320, height: 64))
    }
}

@MainActor
private final class SizingCollectionFixture {
    let window: UIWindow
    let parent = UIViewController()
    let controller = UIViewController()
    let collection: UICollectionView
    let source: SizingCollectionDataSource

    init(itemCount: Int = 1, fixedHeight: CGFloat? = nil) {
        source = SizingCollectionDataSource(itemCount: itemCount, fixedHeight: fixedHeight)
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: fixedHeight.map { .absolute($0) } ?? .estimated(20)
        )
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.boundarySupplementaryItems = [
            (UICollectionView.elementKindSectionHeader, NSRectAlignment.top),
            (UICollectionView.elementKindSectionFooter, NSRectAlignment.bottom),
        ].map { kind, alignment in
            NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .estimated(20)
                ), elementKind: kind, alignment: alignment
            )
        }
        collection = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewCompositionalLayout(section: section)
        )
        collection.contentInsetAdjustmentBehavior = .never
        collection.isPrefetchingEnabled = false
        collection.register(SizingTextCell.self, forCellWithReuseIdentifier: "cell")
        for kind in [UICollectionView.elementKindSectionHeader, UICollectionView.elementKindSectionFooter] {
            collection.register(
                SizingTextSupplementaryView.self,
                forSupplementaryViewOfKind: kind, withReuseIdentifier: "supplementary"
            )
        }
        collection.dataSource = source
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 1600))
        window.rootViewController = parent
        parent.addChild(controller)
        parent.setOverrideTraitCollection(
            UITraitCollection(preferredContentSizeCategory: .large), forChild: controller
        )
        parent.view.addSubview(controller.view)
        controller.didMove(toParent: parent)
        controller.view.addSubview(collection)
        window.isHidden = false
        window.layoutIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 1600)
        collection.frame = controller.view.bounds
    }

    func layout() {
        controller.view.layoutIfNeeded()
        collection.layoutIfNeeded()
    }

    func visibleHeights() throws -> [CGFloat] {
        let path = IndexPath(item: 0, section: 0)
        let cell = try #require(collection.cellForItem(at: path))
        let header = try #require(collection.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: path
        ))
        let footer = try #require(collection.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionFooter, at: path
        ))
        #expect(cell.bounds.width == collection.bounds.width)
        #expect(header.bounds.width == collection.bounds.width)
        #expect(footer.bounds.width == collection.bounds.width)
        return [cell.bounds.height, header.bounds.height, footer.bounds.height]
    }
}

@MainActor
private final class SizingCollectionDataSource: NSObject, UICollectionViewDataSource {
    let itemCount: Int
    let fixedHeight: CGFloat?
    var text = "Short"

    init(itemCount: Int, fixedHeight: CGFloat?) {
        self.itemCount = itemCount
        self.fixedHeight = fixedHeight
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        itemCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SizingTextCell
        cell.quickLayoutHorizontalFlexibility = .fixedSize
        cell.quickLayoutVerticalFlexibility = fixedHeight == nil ? .fullyFlexible : .fixedSize
        cell.label.text = text
        cell.setNeedsQuickLayout()
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: "supplementary", for: indexPath
        ) as! SizingTextSupplementaryView
        view.quickLayoutHorizontalFlexibility = .fixedSize
        view.label.text = text
        view.setNeedsQuickLayout()
        return view
    }
}

@MainActor
private final class SizingTextCell: QuickLayoutCollectionViewCell {
    let label = makeSizingLabel()
    var wasReused = false

    @LayoutBuilder
    override var body: Layout {
        label.frame(maxWidth: .infinity, alignment: .leading)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        wasReused = true
    }

    override func quickLayoutEnvironmentDidChange(_ environment: QuickLayoutEnvironment, reason: QuickLayoutEnvironmentChangeReason) {
        label.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
    }
}

@MainActor
private final class SizingTextSupplementaryView: QuickLayoutCollectionReusableView {
    let label = makeSizingLabel()

    @LayoutBuilder
    override var body: Layout {
        label.frame(maxWidth: .infinity, alignment: .leading)
    }

    override func quickLayoutEnvironmentDidChange(_ environment: QuickLayoutEnvironment, reason: QuickLayoutEnvironmentChangeReason) {
        label.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
    }
}

@MainActor
private func makeSizingLabel() -> UILabel {
    let label = UILabel()
    label.numberOfLines = 0
    label.font = .preferredFont(forTextStyle: .body)
    label.adjustsFontForContentSizeCategory = true
    return label
}
