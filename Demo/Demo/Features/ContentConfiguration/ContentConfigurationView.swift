//
//  ContentConfigurationView.swift
//  Demo
//
//  Created by Sondra on 2025/12/17.
//

import UIKit
import QuickLayout
import QuickLayoutKit

final class ContentConfigurationView: QuickLayoutContentView {

    struct Configuration: UIContentConfiguration {
        var model: ContentConfigurationModel
        var cornerRadius: CGFloat = 0
        var isHighlighted = false
        var isSelected = false

        func makeContentView() -> UIView & UIContentView {
            ContentConfigurationView(configuration: self)
        }

        func updated(for state: UIConfigurationState) -> Self {
            guard let state = state as? UICellConfigurationState else {
                return self
            }
            var configuration = self
            configuration.isHighlighted = state.isHighlighted
            configuration.isSelected = state.isSelected
            return configuration
        }
    }

    let iconView = UIImageView()
    let titleLabel = UILabel()
    let detailLabel = UILabel()

    override var body: Layout {
        HStack(alignment: .top, spacing: 8) {
            iconView
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                detailLabel
            }
            Spacer()
        }
        .padding(12)
    }

    init(configuration: Configuration) {
        super.init(configuration: configuration)

        iconView.backgroundColor = .systemPink.withAlphaComponent(0.2)
        iconView.contentMode = .scaleAspectFill
        iconView.layer.cornerRadius = 20
        iconView.clipsToBounds = true

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0

        applyCurrentContentConfiguration()
    }

    override var intrinsicContentSize: CGSize {
        // UIKit 通过 intrinsicContentSize 测量配置内容，正文高度随可用宽度变化。
        let width = bounds.width > 0 ? bounds.width : CGFloat.infinity
        let size = sizeThatFits(
            CGSize(width: width, height: .infinity)
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }

    override var bounds: CGRect {
        didSet {
            if bounds.width != oldValue.width {
                invalidateIntrinsicContentSize()
            }
        }
    }

    override func applyContentConfiguration(
        _ configuration: UIContentConfiguration
    ) {
        guard let configuration = configuration as? Configuration else {
            assertionFailure("Unexpected content configuration")
            return
        }
        let model = configuration.model
        titleLabel.text = model.title
        detailLabel.text = model.detail
        iconView.image = UIImage(systemName: model.imageName)
        iconView.tintColor = model.themeColor
        backgroundColor = configuration.isSelected
            ? .tertiarySystemGroupedBackground
            : .secondarySystemGroupedBackground
        layer.cornerRadius = configuration.cornerRadius
        clipsToBounds = true
        let contentAlpha: CGFloat = configuration.isHighlighted
            || configuration.isSelected ? 0.72 : 1
        iconView.alpha = contentAlpha
        titleLabel.alpha = contentAlpha
        detailLabel.alpha = contentAlpha
        super.applyContentConfiguration(configuration)
    }

    override func setNeedsQuickLayout() {
        super.setNeedsQuickLayout()
        invalidateIntrinsicContentSize()
    }
}

#Preview("简短") {
    previewContent(ContentConfigurationModel.mockData[0])
}

#Preview("节选") {
    previewContent(ContentConfigurationModel.mockData[1])
}

private func previewContent(
    _ model: ContentConfigurationModel
) -> QuickLayoutHostingController {
    let contentView = ContentConfigurationView(
        configuration: .init(model: model, cornerRadius: 8)
    )
    contentView.backgroundColor = .secondarySystemFill
    contentView.layer.cornerRadius = 8

    return QuickLayoutHostingController {
        contentView
            .padding(16)
    }
}
