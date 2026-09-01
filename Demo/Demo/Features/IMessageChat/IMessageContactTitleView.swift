//
//  IMessageContactTitleView.swift
//  Demo
//

import UIKit

final class IMessageContactTitleView: UIView {

    private static let maximumTitleWidth: CGFloat = 220
    private static let navigationBarHeight: CGFloat = 44

    let avatarView = UIImageView()
    let nameLabel = UILabel()
    let subtitleLabel = UILabel()
    private let contentStack = UIStackView()
    private let labelsStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 7
        addSubview(contentStack)

        avatarView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarView.tintColor = .systemGray
        avatarView.contentMode = .scaleAspectFit
        avatarView.setContentHuggingPriority(.required, for: .horizontal)
        avatarView.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        nameLabel.text = "Alex"
        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textAlignment = .natural
        nameLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = .preferredFont(forTextStyle: .caption2)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .natural
        subtitleLabel.lineBreakMode = .byTruncatingTail

        labelsStack.axis = .vertical
        labelsStack.alignment = .leading
        labelsStack.spacing = 0
        labelsStack.addArrangedSubview(nameLabel)
        labelsStack.addArrangedSubview(subtitleLabel)
        contentStack.addArrangedSubview(avatarView)
        contentStack.addArrangedSubview(labelsStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 30),
            avatarView.heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(lessThanOrEqualToConstant: Self.maximumTitleWidth),
            heightAnchor.constraint(lessThanOrEqualToConstant: Self.navigationBarHeight),
        ])
        isAccessibilityElement = true
    }

    override var intrinsicContentSize: CGSize {
        let measuredSize = contentStack.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(
            width: min(Self.maximumTitleWidth, ceil(measuredSize.width)),
            height: min(
                Self.navigationBarHeight,
                max(30, ceil(measuredSize.height))
            )
        )
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        intrinsicContentSize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(subtitle: String) {
        subtitleLabel.text = subtitle
        accessibilityLabel = "Alex, \(subtitle)"
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}
