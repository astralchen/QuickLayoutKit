//
//  MessageCell.swift
//  MessageCell
//
//  Created by Sondra on 2025/12/17.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

final class MessageContentView: QuickLayoutView {

    let avatarView = UIImageView()
    let titleLabel = UILabel()
    let messageLabel = UILabel()

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

    override init(frame: CGRect) {
        super.init(frame: frame)

        avatarView.backgroundColor = .systemPink.withAlphaComponent(0.2)
        avatarView.contentMode = .scaleAspectFill
        avatarView.layer.cornerRadius = 20
        avatarView.clipsToBounds = true

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: MessageModel) {
        titleLabel.text = model.title
        messageLabel.text = model.message
        avatarView.image = UIImage(systemName: model.imageName)
        avatarView.tintColor = model.themeColor
        setNeedsQuickLayout()
    }

    func reset() {
        titleLabel.text = nil
        messageLabel.text = nil
        avatarView.image = nil
        avatarView.tintColor = nil
        alpha = 1
        setNeedsQuickLayout()
    }
}

final class MessageCell: QuickLayoutCollectionViewCell {

    let messageContentView = MessageContentView(frame: .zero)

    // semanticContentAttribute 不会可靠地逐层复制给已物化的 reusable
    // 子视图；声明实际 QuickLayout host，由框架跟随 collection 统一同步。
    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [messageContentView]
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            updateVisualState()
        }
    }

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            updateVisualState()
        }
    }

    override var body: Layout {
        ZStack {
            messageContentView
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
        updateVisualState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: MessageModel) {
        messageContentView.configure(model)
        setNeedsQuickLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        messageContentView.reset()
        isHighlighted = false
        isSelected = false
        updateVisualState()
    }

    private func updateVisualState() {
        contentView.backgroundColor = isSelected
            ? .tertiarySystemGroupedBackground
            : .secondarySystemGroupedBackground
        messageContentView.alpha = isHighlighted || isSelected ? 0.72 : 1
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
    let contentView = MessageContentView(frame: .zero)
    contentView.configure(model)
    contentView.backgroundColor = .secondarySystemFill
    contentView.layer.cornerRadius = 8

    return QuickLayoutHostingController {
        contentView
            .padding(16)
    }
}
