//
//  MessageCell.swift
//  MessageCell
//
//  Created by Sondra on 2025/12/17.
//

import UIKit
import QuickLayout
import QuickLayoutKit

final class MessageCell: QuickLayoutCollectionViewCell {

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

        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible

        avatarView.backgroundColor = .systemPink.withAlphaComponent(0.2)
        avatarView.contentMode = .scaleAspectFill
        avatarView.layer.cornerRadius = 20
        avatarView.clipsToBounds = true

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.numberOfLines = 0
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(_ model: MessageModel) {
        titleLabel.text = model.title
        messageLabel.text = model.message
        avatarView.image = UIImage(systemName: model.imageName)
        avatarView.tintColor = model.themeColor
        setNeedsQuickLayout()
    }
}


#Preview("简短") {
    previewCell(MessageModel.mockData[0])
}


#Preview("节选") {
    previewCell(MessageModel.mockData[8])
}


func makeMessageCell(with model: MessageModel) -> MessageCell {
    let cell = MessageCell()
    cell.backgroundColor = .secondarySystemFill
    cell.layer.cornerRadius = 8
    cell.configure(model)
    return cell
}

private func previewCell(_ model: MessageModel) -> QuickLayoutHostingController {
    QuickLayoutHostingController {
        makeMessageCell(with: model)
            .padding(16)
    }
}
