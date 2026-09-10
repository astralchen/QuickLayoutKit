//
//  MainMenuSectionHeaderView.swift
//  Demo
//

import UIKit

/// ListKit 注册补充视图，文字样式、动态字体和尺寸测量使用 UIKit 列表内容。
final class MainMenuSectionHeaderView: UICollectionReusableView {
    let listContentView = UIListContentView(configuration: UIListContentConfiguration.header())

    override var semanticContentAttribute: UISemanticContentAttribute {
        didSet { listContentView.semanticContentAttribute = semanticContentAttribute }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        listContentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(listContentView)
        NSLayoutConstraint.activate([
            listContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            listContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            listContentView.topAnchor.constraint(equalTo: topAnchor),
            listContentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .header
        listContentView.accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        // 预估高度不应限制多行标题的自然高度。
        attributes.size.height = systemLayoutSizeFitting(
            CGSize(width: layoutAttributes.size.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return attributes
    }

    func configure(title: String, identifier: String) {
        var content = UIListContentConfiguration.header()
        content.text = title
        content.textProperties.numberOfLines = 0
        listContentView.configuration = content
        listContentView.semanticContentAttribute = semanticContentAttribute
        accessibilityLabel = title
        accessibilityIdentifier = identifier
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        listContentView.configuration = UIListContentConfiguration.header()
        accessibilityLabel = nil
        accessibilityIdentifier = nil
    }
}

extension MainRoute {
    var menuIconColor: UIColor {
        switch self {
        case .horizontalScroll, .safeAreaPadding, .contentMargins,
             .positionAndZIndex, .viewThatFits, .dynamicScroll:
            .systemBlue
        case .profile, .dashboard:
            .systemIndigo
        case .counter, .keyboard, .form:
            .systemOrange
        case .liveRoom:
            .systemPink
        case .imessageChat, .messages, .tableMessages:
            .systemGreen
        case .representable, .swiftUIBridge:
            .systemOrange
        case .semanticContent, .localizationOverview, .uikitLocalization,
             .directionalNavigation, .semanticGesture, .localizationBoundary:
            .systemPurple
        }
    }
}
