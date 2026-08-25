//
//  DynamicScrollViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

class DynamicScrollViewController: DemoQuickLayoutHostingController {

    private enum Metrics {
        static let horizontalContentMargin: CGFloat = 16
        static let bottomContentMargin: CGFloat = 8
        static let actionTopSpacing: CGFloat = 0
        static let actionContentSpacing: CGFloat = 8
    }

    override var localizedTitleKey: String? { "demo.dynamicScroll.title" }

    private let viewModel: DynamicScrollViewModel
    private var itemViewCache: [
        DynamicScrollViewModel.Item.ID: DynamicScrollItemView
    ] = [:]
    private var itemViews: [UIView] = []

    lazy var addButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.buttonSize = .medium
        config.image = UIImage(systemName: "plus")
        config.imagePlacement = .leading
        config.imagePadding = 6
        
        let addButton = UIButton(configuration: config)
        addButton.addTarget(self, action: #selector(addItemTapped), for: .touchUpInside)
        addButton.accessibilityIdentifier = "dynamic.addButton"
        return addButton
    }()

    let scrollView: QuickLayoutScrollView = QuickLayoutScrollView()

    convenience init() {
        self.init(viewModel: DynamicScrollViewModel())
    }

    init(viewModel: DynamicScrollViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = DynamicScrollViewModel()
        super.init(coder: coder)
    }

    override var body: Layout {
        ScrollView(scrollView) {
            VStack(spacing: 12) {
                ForEach(itemViews) { item in
                    item
                        .resizable(axis: .horizontal)
                }
            }
        }
        .contentMargins(
            .horizontal,
            Metrics.horizontalContentMargin,
            for: .scrollContent
        )
        .contentMargins(.top, actionContentMargin, for: .scrollContent)
        .contentMargins(
            .bottom,
            Metrics.bottomContentMargin,
            for: .scrollContent
        )
        .contentMargins(.top, actionContentMargin, for: .scrollIndicators)
        .contentMargins(
            .bottom,
            Metrics.bottomContentMargin,
            for: .scrollIndicators
        )
        .overlay(alignment: .topTrailing) {
            addButton
                .safeAreaPadding(
                    .top,
                    Metrics.actionTopSpacing
                )
                .safeAreaPadding(
                    .horizontal,
                    Metrics.horizontalContentMargin
                )
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        scrollView.backgroundColor = .systemGroupedBackground
        scrollView.contentInsetAdjustmentBehavior = .automatic

        viewModel.bind { [weak self] state in
            self?.render(state)
        }
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        viewModel.reloadLocalizedContent()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)

        let semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        scrollView.semanticContentAttribute = semanticContentAttribute
        addButton.semanticContentAttribute = semanticContentAttribute
        // 重新应用配置，刷新 UIButton.Configuration 内部的图文排列。
        if let configuration = addButton.configuration {
            addButton.configuration = configuration
        }
        itemViewCache.values.forEach {
            $0.applyLayoutDirection(semanticContentAttribute)
        }

        scrollView.setNeedsLayout()
        setNeedsQuickLayout()
    }

    @objc private func addItemTapped() {
        let newItemID = viewModel.addItem()
        guard let newItem = itemViewCache[newItemID] else { return }

        // ① 先在无动画状态下完成布局。
        UIView.performWithoutAnimation {
            setNeedsQuickLayout()
            quickLayoutIfNeeded()
            scrollView.layoutIfNeeded()
            newItem.alpha = 0
        }

        let bottomOffset = bottomContentOffset

        guard !UIAccessibility.isReduceMotionEnabled else {
            UIView.performWithoutAnimation {
                newItem.alpha = 1
                scrollView.contentOffset = bottomOffset
            }
            return
        }

        // 让可视区域移动和插入动画共用同一时间线，避免新项目滚入时叠加第二段
        // 相互竞争的垂直位移动画。
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [
                .curveEaseOut,
                .beginFromCurrentState,
                .allowUserInteraction,
            ]
        ) {
            newItem.alpha = 1
            self.scrollView.contentOffset = bottomOffset
        }
    }

    @objc private func deleteButtonTapped(_ sender: UIButton) {
        guard let itemView = itemViewCache.values.first(where: {
            $0.deleteButton === sender
        }),
              itemViewCache[itemView.itemID] === itemView,
              sender.isEnabled,
              itemView.isUserInteractionEnabled else {
            return
        }

        sender.isEnabled = false
        itemView.isUserInteractionEnabled = false

        let visibleOffset = scrollView.layer.presentation()?.bounds.origin
            ?? scrollView.contentOffset
        let visibleAlpha = CGFloat(
            itemView.layer.presentation()?.opacity
                ?? Float(itemView.alpha)
        )

        // 如果该项目仍在执行出现动画，删除前先固定当前可见透明度，
        // 避免它瞬间恢复完全不透明后再消失。
        UIView.performWithoutAnimation {
            itemView.layer.removeAllAnimations()
            itemView.alpha = visibleAlpha
        }

        guard viewModel.removeItem(id: itemView.itemID) else {
            sender.isEnabled = true
            itemView.isUserInteractionEnabled = true
            itemView.alpha = 1
            return
        }
        itemViewCache.removeValue(forKey: itemView.itemID)

        let layoutChanges = {
            self.setNeedsQuickLayout()
            self.quickLayoutIfNeeded()
            self.scrollView.layoutIfNeeded()
            self.scrollView.contentOffset = self.clampedContentOffset(
                visibleOffset
            )
        }

        guard !UIAccessibility.isReduceMotionEnabled,
              UIView.areAnimationsEnabled else {
            UIView.performWithoutAnimation(layoutChanges)
            return
        }

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [
                .curveEaseOut,
                .beginFromCurrentState,
                .allowUserInteraction,
            ],
            animations: layoutChanges
        )
    }

    private func render(_ state: DynamicScrollViewModel.State) {
        if var configuration = addButton.configuration {
            configuration.title = state.addButtonTitle
            addButton.configuration = configuration
        }
        itemViews = state.items.map { item in
            let itemView: DynamicScrollItemView
            if let cachedView = itemViewCache[item.id] {
                itemView = cachedView
            } else {
                itemView = DynamicScrollItemView(itemID: item.id)
                itemView.deleteButton.addTarget(
                    self,
                    action: #selector(deleteButtonTapped(_:)),
                    for: .touchUpInside
                )
                itemViewCache[item.id] = itemView
            }

            itemView.configure(with: item)
            itemView.applyLayoutDirection(
                view.semanticContentAttribute
            )
            return itemView
        }
        setNeedsQuickLayout()
    }

    private var actionContentMargin: CGFloat {
        Metrics.actionTopSpacing
            + addButton.intrinsicContentSize.height
            + Metrics.actionContentSpacing
    }

    private var verticalContentOffsetRange: ClosedRange<CGFloat> {
        let inset = scrollView.adjustedContentInset
        let minimumY = -inset.top
        let maximumY = max(
            minimumY,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + inset.bottom
        )
        return minimumY...maximumY
    }

    private var bottomContentOffset: CGPoint {
        CGPoint(
            x: scrollView.contentOffset.x,
            y: verticalContentOffsetRange.upperBound
        )
    }

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        let range = verticalContentOffsetRange
        return CGPoint(
            x: offset.x,
            y: min(max(offset.y, range.lowerBound), range.upperBound)
        )
    }
}

@QuickLayout
private final class DynamicScrollItemView: UIView {

    private enum Metrics {
        static let minimumHeight: CGFloat = 80
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 12
        static let contentSpacing: CGFloat = 12
        static let accentSize: CGFloat = 40
        static let accentIconSize: CGFloat = 18
        static let deleteButtonSize: CGFloat = 44
    }

    let itemID: DynamicScrollViewModel.Item.ID

    private let accentBackgroundView = UIView()
    private let accentIconView = UIImageView()
    private let titleLabel = UILabel()
    private let deleteHintLabel = UILabel()
    let deleteButton: UIButton = {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: "trash")
        configuration.baseForegroundColor = .systemRed
        configuration.baseBackgroundColor = .systemRed
        configuration.cornerStyle = .capsule
        return UIButton(configuration: configuration)
    }()

    var body: Layout {
        HStack(alignment: .center, spacing: Metrics.contentSpacing) {
            ZStack {
                accentBackgroundView
                    .resizable()
                    .frame(
                        width: Metrics.accentSize,
                        height: Metrics.accentSize
                    )

                accentIconView
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: Metrics.accentIconSize,
                        height: Metrics.accentIconSize
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                titleLabel
                deleteHintLabel
            }

            Spacer()

            deleteButton
                .resizable()
                .frame(
                    width: Metrics.deleteButtonSize,
                    height: Metrics.deleteButtonSize
                )
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
        .frame(minHeight: Metrics.minimumHeight)
    }

    init(itemID: DynamicScrollViewModel.Item.ID) {
        self.itemID = itemID
        super.init(frame: .zero)

        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        clipsToBounds = true

        accentBackgroundView.layer.cornerRadius = 12
        accentBackgroundView.layer.cornerCurve = .continuous

        accentIconView.image = UIImage(systemName: "rectangle.stack.fill")
        accentIconView.contentMode = .scaleAspectFit

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        deleteHintLabel.font = .preferredFont(forTextStyle: .footnote)
        deleteHintLabel.adjustsFontForContentSizeCategory = true
        deleteHintLabel.textColor = .secondaryLabel
        deleteHintLabel.numberOfLines = 0

        isAccessibilityElement = false
        shouldGroupAccessibilityChildren = true
        accessibilityIdentifier = "dynamic.item.\(itemID)"

        titleLabel.isAccessibilityElement = true
        titleLabel.accessibilityTraits = .staticText
        deleteHintLabel.isAccessibilityElement = false
        accentIconView.isAccessibilityElement = false
        deleteButton.isAccessibilityElement = true
        deleteButton.accessibilityTraits.insert(.button)

        accentIconView.accessibilityIdentifier = "dynamic.item.\(itemID).icon"
        titleLabel.accessibilityIdentifier = "dynamic.item.\(itemID).title"
        deleteHintLabel.accessibilityIdentifier = "dynamic.item.\(itemID).hint"
        deleteButton.accessibilityIdentifier = "dynamic.item.\(itemID).deleteButton"
    }

    func configure(with item: DynamicScrollViewModel.Item) {
        precondition(item.id == itemID)

        let accentColor = item.color.uiColor
        accentBackgroundView.backgroundColor = accentColor.withAlphaComponent(0.14)
        accentIconView.tintColor = accentColor
        titleLabel.text = item.title
        deleteHintLabel.text = item.deleteHint
        titleLabel.accessibilityLabel = item.title
        deleteButton.accessibilityLabel = item.deleteButtonAccessibilityLabel
        deleteButton.accessibilityHint = item.deleteAccessibilityHint
        setNeedsLayout()
    }

    func applyLayoutDirection(
        _ semanticContentAttribute: UISemanticContentAttribute
    ) {
        self.semanticContentAttribute = semanticContentAttribute
        [
            accentBackgroundView,
            accentIconView,
            titleLabel,
            deleteHintLabel,
            deleteButton,
        ].forEach {
            $0.semanticContentAttribute = semanticContentAttribute
        }
        if let configuration = deleteButton.configuration {
            deleteButton.configuration = configuration
        }
        setNeedsLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension DynamicScrollViewModel.ColorToken {
    var uiColor: UIColor {
        switch self {
        case .red: .systemRed
        case .blue: .systemBlue
        case .green: .systemGreen
        case .yellow: .systemYellow
        case .orange: .systemOrange
        case .purple: .systemPurple
        case .pink: .systemPink
        case .indigo: .systemIndigo
        case .teal: .systemTeal
        }
    }
}

#Preview {
    UINavigationController(rootViewController: DynamicScrollViewController())
}
