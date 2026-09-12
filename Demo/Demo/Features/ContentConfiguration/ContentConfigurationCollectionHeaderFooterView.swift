import UIKit
import QuickLayout
import QuickLayoutKit

final class ContentConfigurationCollectionHeaderFooterView:
    QuickLayoutCollectionReusableView {

    let sectionContentView = ContentConfigurationSectionView(frame: .zero)

    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [
            sectionContentView,
            sectionContentView.titleLabel,
            sectionContentView.detailLabel,
        ]
    }

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
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        sectionContentView.reset()
        setNeedsQuickLayout()
    }
}
