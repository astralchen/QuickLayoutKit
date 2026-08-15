//
//  MessageCell.swift
//  MessageCell
//
//  Created by Sondra on 2025/12/17.
//

import UIKit
import QuickLayout
import QuickLayoutKit

struct MessageContentConfiguration: UIContentConfiguration {

    let model: MessageModel
    private(set) var isHighlighted = false
    private(set) var isSelected = false

    init(model: MessageModel) {
        self.model = model
    }

    @MainActor
    func makeContentView() -> UIView & UIContentView {
        MessageContentView(configuration: self)
    }

    func updated(
        for state: any UIConfigurationState
    ) -> MessageContentConfiguration {
        guard let state = state as? UICellConfigurationState else {
            return self
        }

        var configuration = self
        configuration.isHighlighted = state.isHighlighted
        configuration.isSelected = state.isSelected
        return configuration
    }
}

final class MessageContentView: QuickLayoutView, UIContentView {

    let avatarView = UIImageView()
    let titleLabel = UILabel()
    let messageLabel = UILabel()

    private var messageConfiguration: MessageContentConfiguration

    var configuration: any UIContentConfiguration {
        get { messageConfiguration }
        set {
            guard
                let configuration = newValue
                    as? MessageContentConfiguration
            else {
                assertionFailure(
                    "Unsupported content configuration: \(type(of: newValue))"
                )
                return
            }
            apply(configuration)
        }
    }

    override var body: Layout {
        HStack(alignment: .top, spacing: 8) {
            avatarView
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                messageLabel
            }
            Spacer()
        }
        .padding(12)
    }

    init(configuration: MessageContentConfiguration) {
        self.messageConfiguration = configuration
        super.init(frame: .zero)

        avatarView.backgroundColor = .systemPink.withAlphaComponent(0.2)
        avatarView.contentMode = .scaleAspectFill
        avatarView.layer.cornerRadius = 20
        avatarView.clipsToBounds = true

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0

        apply(configuration)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func supports(_ configuration: any UIContentConfiguration) -> Bool {
        configuration is MessageContentConfiguration
    }

    private func apply(_ configuration: MessageContentConfiguration) {
        messageConfiguration = configuration
        titleLabel.text = configuration.model.title
        messageLabel.text = configuration.model.message
        avatarView.image = UIImage(
            systemName: configuration.model.imageName
        )
        avatarView.tintColor = configuration.model.themeColor
        alpha = configuration.isHighlighted || configuration.isSelected
            ? 0.72
            : 1
        setNeedsQuickLayout()
    }
}

final class MessageCell: QuickLayoutCollectionViewCell {

    private var model: MessageModel?

    override init(frame: CGRect) {
        super.init(
            frame: frame,
            contentSource: .contentConfiguration
        )
        automaticallyUpdatesContentConfiguration = false
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: MessageModel) {
        self.model = model
        setNeedsUpdateConfiguration()
    }

    override func updateConfiguration(
        using state: UICellConfigurationState
    ) {
        guard let model else {
            contentConfiguration = nil
            backgroundConfiguration = nil
            return
        }

        contentConfiguration = MessageContentConfiguration(model: model)
            .updated(for: state)

        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = state.isSelected
            ? .tertiarySystemGroupedBackground
            : .secondarySystemGroupedBackground
        background.cornerRadius = 8
        backgroundConfiguration = background
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        model = nil
        contentConfiguration = nil
        backgroundConfiguration = nil
    }
}

#Preview("简短") {
    previewContent(MessageModel.mockData[0])
}

#Preview("节选") {
    previewContent(MessageModel.mockData[8])
}

private func previewContent(
    _ model: MessageModel
) -> QuickLayoutHostingController {
    let contentView = MessageContentView(
        configuration: MessageContentConfiguration(model: model)
    )
    contentView.backgroundColor = .secondarySystemFill
    contentView.layer.cornerRadius = 8

    return QuickLayoutHostingController {
        contentView
            .padding(16)
    }
}
