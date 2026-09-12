import UIKit
import QuickLayout
import QuickLayoutKit

enum ContentConfigurationSectionRole {
    case header
    case footer
}

final class ContentConfigurationSectionView: QuickLayoutView {

    let titleLabel = UILabel()
    let detailLabel = UILabel()

    private var role: ContentConfigurationSectionRole = .header

    override var body: Layout {
        VStack(alignment: .leading, spacing: 3) {
            titleLabel
            detailLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, role == .header ? 10 : 8)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String,
        detail: String?,
        role: ContentConfigurationSectionRole
    ) {
        self.role = role
        titleLabel.text = title
        detailLabel.text = detail

        switch role {
        case .header:
            titleLabel.font = .preferredFont(forTextStyle: .headline)
            titleLabel.textColor = .label
            detailLabel.font = .preferredFont(forTextStyle: .footnote)
            detailLabel.textColor = .secondaryLabel

        case .footer:
            titleLabel.font = .preferredFont(forTextStyle: .footnote)
            titleLabel.textColor = .secondaryLabel
            detailLabel.font = .preferredFont(forTextStyle: .caption1)
            detailLabel.textColor = .tertiaryLabel
        }

        backgroundColor = .clear
        setNeedsQuickLayout()
    }

    func reset() {
        role = .header
        titleLabel.text = nil
        detailLabel.text = nil
        backgroundColor = .clear
        setNeedsQuickLayout()
    }
}

