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

/// 展示支持动态插入、删除和本地化的垂直滚动列表。
///
/// 控制器按项目标识复用卡片视图。添加操作将内容滚动到更新后的底部；删除操作
/// 尽量保留当前可见偏移，并将其限制在更新后的有效滚动范围内。
/// 添加按钮位于滚动内容之外，其位置遵循宿主视图的安全区域。
class DynamicScrollViewController: LocalizedQuickLayoutHostingController {

    // MARK: - 布局配置

    /// 内容边距及悬浮操作按钮的布局常量，单位为点。
    private enum Metrics {
        /// 滚动内容两侧及操作按钮后缘使用的水平边距。
        static let horizontalContentMargin: CGFloat = 16
        /// 末项之后预留的内容边距。
        static let bottomContentMargin: CGFloat = 8
        /// 操作按钮与安全区域顶部之间的间距。
        static let actionTopSpacing: CGFloat = 0
        /// 操作按钮底部与列表起始内容之间的间距。
        static let actionContentSpacing: CGFloat = 8
    }

    /// 导航标题所使用的本地化键。
    override var localizedTitleKey: String? { "demo.dynamicScroll.title" }

    // MARK: - 内容与视图

    /// 提供有序项目状态及本地化内容的视图模型。
    private let viewModel: DynamicScrollViewModel
    /// 按稳定项目标识缓存的卡片视图，用于在内容更新时保留视图实例。
    private var itemViewCache: [
        DynamicScrollViewModel.Item.ID: DynamicScrollItemView
    ] = [:]
    /// 按当前模型顺序参与布局的卡片视图。
    private var itemViews: [UIView] = []

    /// 向列表末尾添加项目的悬浮按钮。
    ///
    /// 按钮遵循宿主安全区域，不参与列表内容的滚动。系统导航栏改变安全区域时，
    /// 按钮会随安全区域重新布局，其屏幕坐标并非固定值。
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

    /// 承载全部项目并沿垂直方向滚动的内容视图。
    let scrollView: QuickLayoutScrollView = QuickLayoutScrollView()

    // MARK: - 初始化

    /// 使用默认视图模型创建动态滚动示例。
    convenience init() {
        self.init(viewModel: DynamicScrollViewModel())
    }

    /// 使用指定视图模型创建动态滚动示例。
    ///
    /// - Parameter viewModel: 提供项目状态的模型。控制器在视图加载时绑定其状态更新。
    init(viewModel: DynamicScrollViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    /// 从归档创建控制器，并使用默认视图模型。
    ///
    /// - Parameter coder: 包含控制器归档信息的解码器。
    required init?(coder: NSCoder) {
        viewModel = DynamicScrollViewModel()
        super.init(coder: coder)
    }

    // MARK: - 布局与环境

    /// 填满宿主的列表及位于安全区域顶部后缘的添加按钮。
    ///
    /// 列表顶部内容边距为按钮预留空间，滚动指示器采用相应的顶部和底部边距。
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

    /// 配置滚动视图的背景和边距调整策略，并绑定模型状态更新。
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        scrollView.backgroundColor = .systemGroupedBackground
        scrollView.accessibilityIdentifier = "dynamic.scrollView"
        scrollView.contentInsetAdjustmentBehavior = .automatic

        viewModel.bind { [weak self] state in
            self?.render(state)
        }
    }

    /// 刷新导航标题及模型提供的本地化文本。
    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        viewModel.reloadLocalizedContent()
    }

    /// 将布局方向应用于滚动内容、操作按钮及所有已缓存的卡片。
    ///
    /// - Parameter direction: 当前界面应采用的有效布局方向。
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

    // MARK: - 项目操作

    /// 在列表末尾插入项目，并将滚动位置移至更新后的底部。
    ///
    /// 先完成新内容布局以取得目标偏移，再同步执行淡入和滚动动画。
    /// 启用“减弱动态效果”时，直接显示项目并更新偏移。
    @objc private func addItemTapped() {
        let newItemID = viewModel.addItem()
        guard let newItem = itemViewCache[newItemID] else { return }

        // 先完成布局，使底部偏移基于插入后的内容尺寸计算。
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

    /// 删除发送按钮所属的有效项目，并调整布局和滚动位置。
    ///
    /// 删除期间禁用项目交互，忽略失效或重复的删除请求。若存在正在执行的动画，
    /// 使用表现层的可见偏移作为位置保留基线。更新后的偏移不会超出有效滚动范围。
    /// 启用“减弱动态效果”或全局禁用动画时，立即应用布局变化。
    ///
    /// - Parameter sender: 用户触发的卡片删除按钮。
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

    /// 根据模型状态更新操作标题和有序卡片内容，并请求重新布局。
    ///
    /// 已有项目复用缓存视图；新项目创建卡片并连接删除操作。
    ///
    /// - Parameter state: 包含操作标题和有序项目的当前状态。
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

    // MARK: - 内容边距与滚动范围

    /// 为操作按钮预留的顶部内容边距，不包含系统安全区域的自动调整量。
    private var actionContentMargin: CGFloat {
        Metrics.actionTopSpacing
            + addButton.intrinsicContentSize.height
            + Metrics.actionContentSpacing
    }

    /// 按当前内容尺寸、视口高度及调整后边距计算的有效垂直偏移范围。
    ///
    /// 内容不足以填满视口时，上下界均为顶部偏移，不额外产生底部滚动距离。
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

    /// 保留当前水平偏移、并将垂直偏移置于有效范围上界的位置。
    private var bottomContentOffset: CGPoint {
        CGPoint(
            x: scrollView.contentOffset.x,
            y: verticalContentOffsetRange.upperBound
        )
    }

    /// 将指定位置的垂直分量限制在当前有效滚动范围内。
    ///
    /// - Parameter offset: 希望保留的内容偏移。
    /// - Returns: 水平分量不变、垂直分量不超出有效范围的内容偏移。
    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        let range = verticalContentOffsetRange
        return CGPoint(
            x: offset.x,
            y: min(max(offset.y, range.lowerBound), range.upperBound)
        )
    }
}

// MARK: - 项目卡片

/// 展示单个项目的装饰图标、标题、删除提示及独立删除按钮。
///
/// 卡片按项目标识复用，文本支持动态字体和多行显示。辅助功能分别暴露标题和删除按钮，
/// 避免装饰图标及可见提示造成重复朗读。
@QuickLayout
private final class DynamicScrollItemView: UIView {

    /// 卡片尺寸和内部间距，单位为点。
    private enum Metrics {
        /// 内容较少时仍需保持的卡片最小高度。
        static let minimumHeight: CGFloat = 80
        /// 卡片内容两侧的内边距。
        static let horizontalPadding: CGFloat = 16
        /// 卡片内容顶部和底部的内边距。
        static let verticalPadding: CGFloat = 12
        /// 图标、文本及按钮之间的水平间距。
        static let contentSpacing: CGFloat = 12
        /// 装饰图标背景的边长。
        static let accentSize: CGFloat = 40
        /// 装饰图标的边长。
        static let accentIconSize: CGFloat = 18
        /// 删除按钮的布局边长。
        static let deleteButtonSize: CGFloat = 44
    }

    /// 卡片创建时绑定的稳定项目标识。
    let itemID: DynamicScrollViewModel.Item.ID

    /// 用于显示项目强调色的图标背景。
    private let accentBackgroundView = UIView()
    /// 不参与辅助功能朗读的装饰图标。
    private let accentIconView = UIImageView()
    /// 支持动态字体和多行显示的项目标题。
    private let titleLabel = UILabel()
    /// 说明删除操作的可见提示文本。
    private let deleteHintLabel = UILabel()
    /// 由控制器连接删除操作的独立按钮。
    let deleteButton: UIButton = {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: "trash")
        configuration.baseForegroundColor = .systemRed
        configuration.baseBackgroundColor = .systemRed
        configuration.cornerStyle = .capsule
        return UIButton(configuration: configuration)
    }()

    /// 按当前布局方向排列图标、文本和删除按钮的卡片内容。
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

    /// 创建绑定指定项目标识的卡片，并配置外观及辅助功能元素。
    ///
    /// - Parameter itemID: 此卡片在其生命周期内对应的项目标识。
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

    /// 更新卡片的颜色、可见文本及辅助功能描述。
    ///
    /// - Parameter item: 与卡片标识对应的最新项目内容。
    /// - Precondition: `item.id` 必须等于 `itemID`。
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

    /// 将指定语义方向应用于卡片及其内容视图。
    ///
    /// 重新应用按钮配置，使其内部内容同步采用新的语义方向。
    ///
    /// - Parameter semanticContentAttribute: 卡片及其子视图应采用的语义方向属性。
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

    /// 不支持从归档创建卡片；请使用 `init(itemID:)`。
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension DynamicScrollViewModel.ColorToken {
    /// 与模型颜色标记对应的动态系统颜色。
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

@available(iOS 17.0, *)
#Preview {
    UINavigationController(rootViewController: DynamicScrollViewController())
}
