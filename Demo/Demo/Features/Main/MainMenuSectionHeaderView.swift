//
//  MainMenuSectionHeaderView.swift
//  Demo
//

import UIKit
import QuickLayout
import QuickLayoutKit

/// ListKit 注册补充视图，由 QuickLayoutKit 布局并保留 UIKit 列表文字样式和动态字体。
final class MainMenuSectionHeaderView: QuickLayoutCollectionReusableView {
    let listContentView = UIListContentView(configuration: UIListContentConfiguration.header())

    override var semanticContentAttribute: UISemanticContentAttribute {
        didSet { listContentView.semanticContentAttribute = semanticContentAttribute }
    }

    override var body: Layout {
        listContentView
            .resizable(axis: .horizontal)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
        isAccessibilityElement = true
        accessibilityTraits = .header
        listContentView.accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, identifier: String) {
        var content = UIListContentConfiguration.header()
        content.text = title
        content.textProperties.numberOfLines = 0
        listContentView.configuration = content
        listContentView.semanticContentAttribute = semanticContentAttribute
        accessibilityLabel = title
        accessibilityIdentifier = identifier
        setNeedsQuickLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        listContentView.configuration = UIListContentConfiguration.header()
        accessibilityLabel = nil
        accessibilityIdentifier = nil
        setNeedsQuickLayout()
    }
}

#if DEBUG
@MainActor
private func makeMainMenuSectionHeaderPreview(
    title: String = "QuickLayout 示例",
    contentSizeCategory: UIContentSizeCategory = .large,
    semanticContentAttribute: UISemanticContentAttribute = .forceLeftToRight
) -> UIViewController {
    let header = MainMenuSectionHeaderView(frame: .zero)
    header.semanticContentAttribute = semanticContentAttribute
    header.configure(title: title, identifier: "main.section.preview")
    let controller = QuickLayoutHostingController {
        header
            .resizable(axis: .horizontal)
            .fixedSize(axis: .vertical)
            .padding(.horizontal, 20)
    }
    controller.loadViewIfNeeded()
    controller.view.backgroundColor = .systemGroupedBackground
    controller.view.semanticContentAttribute = semanticContentAttribute
    controller.traitOverrides.preferredContentSizeCategory = contentSizeCategory
    return controller
}

#Preview("分组标题") {
    makeMainMenuSectionHeaderPreview()
}

#Preview("多行 · 辅助功能大字体") {
    makeMainMenuSectionHeaderPreview(
        title: "QuickLayout 布局与交互示例",
        contentSizeCategory: .accessibilityExtraExtraExtraLarge
    )
}

#Preview("阿拉伯语 · RTL") {
    makeMainMenuSectionHeaderPreview(
        title: "أمثلة QuickLayout",
        semanticContentAttribute: .forceRightToLeft
    )
}
#endif

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
        case .imessageChat, .collectionContentConfiguration, .waterfallContentConfiguration, .tableContentConfiguration:
            .systemGreen
        case .representable, .swiftUIBridge:
            .systemOrange
        case .semanticContent, .localizationOverview, .uikitLocalization,
             .directionalNavigation, .semanticGesture, .localizationBoundary:
            .systemPurple
        }
    }
}
