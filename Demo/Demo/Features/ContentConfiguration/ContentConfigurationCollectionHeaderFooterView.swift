import UIKit
import QuickLayout
import QuickLayoutKit

final class ContentConfigurationCollectionHeaderFooterView:
    QuickLayoutCollectionReusableView {

    let sectionContentView = ContentConfigurationSectionView(frame: .zero)


    override var body: Layout {
        sectionContentView
            .resizable(axis: .horizontal)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String,
        detail: String?,
        role: ContentConfigurationSectionRole
    ) {
        sectionContentView.configure(title: title, detail: detail, role: role)
        setNeedsQuickLayout()
        // 同一补充视图被重配时，原生组合布局可能仍持有上次的估算高度。
        // 在数据源更新完成后走 UIKit 的自适应失效入口，不重建视图或覆盖语义。
        DispatchQueue.main.async { [weak self] in self?.invalidatePreferredSize() }
    }

    private func invalidatePreferredSize() {
        var ancestor = superview
        while let view = ancestor, !(view is UICollectionView) { ancestor = view.superview }
        guard let collection = ancestor as? UICollectionView else { return }
        let layout = collection.collectionViewLayout
        for kind in [UICollectionView.elementKindSectionHeader, UICollectionView.elementKindSectionFooter] {
            for path in collection.indexPathsForVisibleSupplementaryElements(ofKind: kind)
            where collection.supplementaryView(forElementKind: kind, at: path) === self {
                guard let original = layout.layoutAttributesForSupplementaryView(ofKind: kind, at: path) else { continue }
                let preferred = preferredLayoutAttributesFitting(original)
                guard layout.shouldInvalidateLayout(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original) else { continue }
                layout.invalidateLayout(with: layout.invalidationContext(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original))
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        sectionContentView.reset()
        setNeedsQuickLayout()
    }
}
