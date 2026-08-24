//
//  QuickLayoutScrollView.swift
//  QuickLayoutKit
//
//  由 Sondra 创建于 2025/12/26。
//

import QuartzCore
import QuickLayout
import UIKit

/// 沿单一滚动轴排列 QuickLayout 元素的滚动视图。
///
/// 主要初始化方法与 SwiftUI 的 `ScrollView` 形式一致：指定滚动轴、是否显示指示器，
/// 并通过构建器提供内容。不同于 SwiftUI，该类型是 UIKit 引用类型，也可以使用
/// `init(frame:)` 创建，再传入 ``ScrollView(_:_:showsIndicators:content:)``。
/// 运行时布局方向变化会重新布局现有内容，但不会修改数值形式的滚动位置；该行为与
/// SwiftUI 的 `ScrollView` 一致。
open class QuickLayoutScrollView:
    UIScrollView,
    HasBody,
    QuickLayoutUpdating,
    QuickLayoutEnvironmentUpdating {

    /// 可滚动内容的边缘。
    public enum Edge: Equatable, Sendable {
        /// 垂直内容的顶部边缘。
        case top

        /// 垂直内容的底部边缘。
        case bottom

        /// 水平内容的语义前缘。
        case leading

        /// 水平内容的语义后缘。
        case trailing

        fileprivate func isCompatible(with axis: QuickLayout.Axis) -> Bool {
            switch (self, axis) {
            case (.top, .vertical), (.bottom, .vertical),
                 (.leading, .horizontal), (.trailing, .horizontal):
                return true
            default:
                return false
            }
        }
    }

    // MARK: - 公开属性

    /// 接收者滚动的轴。
    ///
    /// `QuickLayoutScrollView` 每次只支持一个轴，并根据该轴选择隐式 `VStack` 或
    /// `HStack` 来承载构建器生成的元素。
    open var axis: QuickLayout.Axis = .vertical {
        didSet {
            guard axis != oldValue else { return }
            if let pendingScroll, !pendingScroll.edge.isCompatible(with: axis) {
                self.pendingScroll = nil
            }
            configureAxisBehavior()
            quickLayoutUpdateContentMarginAxis()
            setNeedsQuickLayout()
        }
    }

    /// 指示是否显示当前滚动轴的滚动指示器。
    open var showsIndicators = true {
        didSet {
            guard showsIndicators != oldValue else { return }
            configureIndicators()
        }
    }

    /// 滚动宿主在附加和布局时采用的语义方向策略。
    ///
    /// 默认值 `.preserve` 会保护局部固定语义。滚动视图可能在运行时切换语言期间被移除，
    /// 或在不同容器之间移动时，应设置为 `.followEnclosingContainer`。
    open var quickLayoutSemanticDirectionBehavior:
        QuickLayoutSemanticDirectionBehavior = .preserve {
        didSet {
            guard quickLayoutSemanticDirectionBehavior != oldValue else {
                return
            }
            synchronizeQuickLayoutSemanticDirectionIfNeeded(
                for: self,
                behavior: quickLayoutSemanticDirectionBehavior
            )
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    /// 用于解析接收者布局方向的语义角色。
    ///
    /// 应用内切换语言时通常会直接更新该属性。属性变化会立即发布新的有效方向，并使宿主内容
    /// 失效，以便下一次布局重新测量和放置内容。
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    private var contentElements: [Element] = [] {
        didSet {
            setNeedsQuickLayout()
        }
    }

    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()
    private var pendingScroll: (edge: Edge, animated: Bool)?
    private var needsContentMarginStartPosition = false
    private var lastResolvedAdjustedContentInset: UIEdgeInsets?
    let quickLayoutContentMarginState = QuickLayoutContentMarginState()

    // MARK: - 初始化

    /// 创建不包含内容的垂直滚动视图。
    public override init(frame: CGRect) {
        super.init(frame: frame)
        configureAxisBehavior()
    }

    /// 创建不包含内容且沿单一轴滚动的视图。
    ///
    /// - Parameters:
    ///   - axis: 内容滚动的单一轴。
    ///   - showsIndicators: 是否显示相应轴的滚动指示器。
    public convenience init(
        _ axis: QuickLayout.Axis,
        showsIndicators: Bool = true
    ) {
        self.init(frame: .zero)
        configure(axis: axis, showsIndicators: showsIndicators, content: [])
    }

    /// 创建包含构建器所生成内容的滚动视图。
    ///
    /// - Parameters:
    ///   - axis: 内容滚动的单一轴。
    ///   - showsIndicators: 是否显示相应轴的滚动指示器。
    ///   - content: 要放入滚动视图的元素。多个根元素会使用零间距堆栈，并在交叉轴上居中。
    public convenience init(
        _ axis: QuickLayout.Axis = .vertical,
        showsIndicators: Bool = true,
        @FastArrayBuilder<Element> content: () -> [Element]
    ) {
        self.init(frame: .zero)
        configure(axis: axis, showsIndicators: showsIndicators, content: content())
    }

    /// 从归档或故事板创建滚动视图。
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAxisBehavior()
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
        quickLayoutContentMarginState.updateSafeArea(
            on: self,
            keepsContentAtStart: true
        )
        quickLayoutEnvironmentState.update(self)
        setNeedsQuickLayout()
    }

    open override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .traitCollection
        )
        setNeedsQuickLayout()
    }

    open override func safeAreaInsetsDidChange() {
        let previousAdjustedContentInset = lastResolvedAdjustedContentInset
        let wasAtContentStart = previousAdjustedContentInset.map {
            quickLayoutIsAtContentStart(adjustedContentInset: $0)
        } ?? false

        super.safeAreaInsetsDidChange()
        quickLayoutContentMarginState.updateSafeArea(
            on: self,
            keepsContentAtStart: false
        )
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)

        if wasAtContentStart,
           previousAdjustedContentInset != adjustedContentInset {
            quickLayoutKeepContentAtStartAfterMarginChange()
        }
    }

    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    // MARK: - 布局内容

    /// 滚动视图渲染的 QuickLayout 内容。
    @LayoutBuilder
    open var body: Layout {
        if contentElements.isEmpty {
            EmptyLayout()
        } else {
            axisLayout
        }
    }

    @LayoutBuilder
    private var axisLayout: Layout {
        switch axis {
        case .vertical:
            VStack(alignment: .center, spacing: 0) {
                ForEach(contentElements)
            }
        case .horizontal:
            HStack(alignment: .center, spacing: 0) {
                ForEach(contentElements)
            }
        }
    }

    // MARK: - 布局

    /// 返回最适合宿主滚动内容的视口尺寸。
    ///
    /// 水平滚动视图使用内容的自然高度，宽度则继续由外层容器提供。该行为与 SwiftUI
    /// `ScrollView` 的交叉轴尺寸处理一致，使本地化内容或动态字体可以决定轮播视图高度，
    /// 而无需由拥有者缓存固定值。
    func quickLayoutViewportSizeThatFits(_ size: CGSize) -> CGSize {
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
        quickLayoutEnvironmentState.update(self)
        quickLayoutUpdateContentMarginDirectionIfNeeded()

        let containerSize = measurementContainerSize(for: size)
        let safeAreaRegionInsets = quickLayoutSafeAreaRegionInsets
        let measuredContentSize = withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(
                containerSize,
                insets: safeAreaRegionInsets.container,
                keyboardInsets: safeAreaRegionInsets.keyboard
            ) {
                _QuickLayoutViewImplementation.sizeThatFits(
                    self,
                    size: measurementContentProposal(for: containerSize)
                ) ?? .zero
            }
        }

        return CGSize(
            width: resolvedViewportLength(
                proposed: size.width,
                fallback: measuredContentSize.width
            ),
            height: measuredContentSize.height
        )
    }

    override open func layoutSubviews() {
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
        super.layoutSubviews()

        withQuickLayoutManagedViewState {
            quickLayoutEnvironmentState.update(self)
            quickLayoutUpdateContentMarginDirectionIfNeeded()
            let layoutDirection = quickLayoutDirection
            let layoutProposal = proposedContentSize
            let safeAreaRegionInsets = quickLayoutSafeAreaRegionInsets
            let measuredContentSize = withQuickLayoutContainerSize(
                bounds.size,
                insets: safeAreaRegionInsets.container,
                keyboardInsets: safeAreaRegionInsets.keyboard
            ) {
                _QuickLayoutViewImplementation.sizeThatFits(
                    self,
                    size: layoutProposal
                ) ?? .zero
            }
            let contentLayoutSize = resolvedContentLayoutSize(
                measuredContentSize
            )

            withQuickLayoutContainerSize(
                bounds.size,
                insets: safeAreaRegionInsets.container,
                keyboardInsets: safeAreaRegionInsets.keyboard
            ) {
                body.applyFrame(
                    CGRect(origin: .zero, size: contentLayoutSize),
                    alignment: contentAlignment,
                    layoutDirection: layoutDirection
                )
            }

            if contentSize != contentLayoutSize {
                contentSize = contentLayoutSize
            }

            applyContentMarginStartPositionIfPossible()
            applyPendingScrollIfPossible()
            lastResolvedAdjustedContentInset = adjustedContentInset
        }
    }

    /// 将宿主滚动内容标记为需要更新。
    ///
    /// 本地化内容发生变化但布局方向未改变时，应调用此方法，因为 UIKit 不会为应用自定义
    /// 区域设置发送通知。
    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    /// 根据需要立即布局宿主滚动内容。
    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }

    /// 响应可能影响滚动内容的 UIKit 环境变化。
    ///
    /// 默认实现会使测量和放置失效，同时保留现有的数值内容偏移量。
    ///
    /// - Parameters:
    ///   - environment: 变化后的当前环境快照。
    ///   - reason: 描述发生变化部分的原因集合。
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    private var contentAlignment: Alignment {
        switch axis {
        case .vertical:
            return .top
        case .horizontal:
            return .leading
        }
    }

    private var proposedContentSize: CGSize {
        let viewportSize = contentMarginViewportSize
        switch axis {
        case .vertical:
            return CGSize(width: viewportSize.width, height: .infinity)
        case .horizontal:
            return CGSize(width: .infinity, height: viewportSize.height)
        }
    }

    private func measurementContainerSize(for proposedSize: CGSize) -> CGSize {
        CGSize(
            width: resolvedMeasurementContainerLength(
                proposed: proposedSize.width,
                current: bounds.width
            ),
            height: resolvedMeasurementContainerLength(
                proposed: proposedSize.height,
                current: bounds.height
            )
        )
    }

    private func measurementContentProposal(
        for containerSize: CGSize
    ) -> CGSize {
        let insets = quickLayoutAppliedContentMarginInsets
        let viewportSize = CGSize(
            width: max(0, containerSize.width - insets.left - insets.right),
            height: max(0, containerSize.height - insets.top - insets.bottom)
        )

        switch axis {
        case .vertical:
            return CGSize(width: viewportSize.width, height: .infinity)
        case .horizontal:
            return CGSize(
                width: CGFloat.infinity,
                height: CGFloat.infinity
            )
        }
    }

    private func resolvedMeasurementContainerLength(
        proposed: CGFloat,
        current: CGFloat
    ) -> CGFloat {
        if proposed.isFinite {
            return max(0, proposed)
        }
        return max(0, current)
    }

    private func resolvedViewportLength(
        proposed: CGFloat,
        fallback: CGFloat
    ) -> CGFloat {
        proposed.isFinite ? max(0, proposed) : max(0, fallback)
    }

    private var contentMarginViewportSize: CGSize {
        let insets = quickLayoutAppliedContentMarginInsets
        return CGSize(
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom)
        )
    }

    private var quickLayoutSafeAreaRegionInsets: (
        container: UIEdgeInsets,
        keyboard: UIEdgeInsets
    ) {
        // 即使全屏滚动视图仍与水平安全区域相交，UIKit 也可能不会将该物理边距计入
        // adjustedContentInset。保留所有自动栏位和内容调整，同时确保传递给 QuickLayout
        // 内容的值不小于滚动视图自身的物理安全区域。
        let resolvedContainerInsets = UIEdgeInsets(
            top: max(adjustedContentInset.top, safeAreaInsets.top),
            left: max(adjustedContentInset.left, safeAreaInsets.left),
            bottom: max(adjustedContentInset.bottom, safeAreaInsets.bottom),
            right: max(adjustedContentInset.right, safeAreaInsets.right)
        )
        let keyboardDelta = max(0, quickLayoutKeyboardInsetDelta)
        guard keyboardDelta > 0 else {
            return (resolvedContainerInsets, .zero)
        }

        var containerInsets = resolvedContainerInsets
        containerInsets.bottom = max(0, containerInsets.bottom - keyboardDelta)
        let keyboardInsets = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: resolvedContainerInsets.bottom,
            right: 0
        )
        return (containerInsets, keyboardInsets)
    }

    private func resolvedContentLayoutSize(_ measuredSize: CGSize) -> CGSize {
        let viewportSize = contentMarginViewportSize
        switch axis {
        case .vertical:
            return CGSize(
                width: max(viewportSize.width, measuredSize.width),
                height: measuredSize.height
            )
        case .horizontal:
            return CGSize(
                width: measuredSize.width,
                height: max(viewportSize.height, measuredSize.height)
            )
        }
    }

    // MARK: - 滚动

    /// 滚动到当前轴对应的内容边缘。
    ///
    /// 内容尚未完成测量时提出的请求，会延迟到下一次成功布局后执行。与当前滚动轴不匹配的
    /// 边缘请求会被忽略。
    ///
    /// - Parameters:
    ///   - edge: 要显示的内容边缘。
    ///   - animated: 传入 `true` 以动画方式执行滚动。
    open func scrollTo(_ edge: Edge, animated: Bool = true) {
        guard edge.isCompatible(with: axis) else { return }

        layoutIfNeeded()
        guard canResolveScrollOffset(for: edge) else {
            pendingScroll = (edge, animated)
            return
        }

        setContentOffset(targetOffset(for: edge), requestedAnimated: animated)
    }

    // MARK: - 内部配置

    func configure(
        axis: QuickLayout.Axis,
        showsIndicators: Bool,
        content: [Element]
    ) {
        quickLayoutResetContentMargins()
        self.axis = axis
        self.showsIndicators = showsIndicators
        contentElements = content
    }

    func quickLayoutIsAtContentStart(
        adjustedContentInset: UIEdgeInsets? = nil
    ) -> Bool {
        let edge: Edge = axis == .vertical ? .top : .leading
        let target = targetOffset(
            for: edge,
            adjustedContentInset: adjustedContentInset
        )

        switch axis {
        case .vertical:
            return abs(contentOffset.y - target.y) < 0.5
        case .horizontal:
            return abs(contentOffset.x - target.x) < 0.5
        }
    }

    func quickLayoutKeepContentAtStartAfterMarginChange() {
        needsContentMarginStartPosition = true
        setNeedsQuickLayout()
    }

    // MARK: - 私有辅助方法

    private func configureAxisBehavior() {
        alwaysBounceVertical = axis == .vertical
        alwaysBounceHorizontal = axis == .horizontal
        configureIndicators()
    }

    private func configureIndicators() {
        showsVerticalScrollIndicator = showsIndicators && axis == .vertical
        showsHorizontalScrollIndicator = showsIndicators && axis == .horizontal
    }

    private func applyContentMarginStartPositionIfPossible() {
        guard needsContentMarginStartPosition else { return }

        let edge: Edge = axis == .vertical ? .top : .leading
        guard canResolveScrollOffset(for: edge) else { return }

        needsContentMarginStartPosition = false
        setContentOffset(
            targetOffset(for: edge),
            requestedAnimated: false
        )
    }

    private func applyPendingScrollIfPossible() {
        guard let pendingScroll,
              pendingScroll.edge.isCompatible(with: axis),
              canResolveScrollOffset(for: pendingScroll.edge) else {
            return
        }

        self.pendingScroll = nil
        setContentOffset(
            targetOffset(for: pendingScroll.edge),
            requestedAnimated: pendingScroll.animated
        )
    }

    private func canResolveScrollOffset(for edge: Edge) -> Bool {
        switch edge {
        case .top, .bottom:
            return bounds.height > 0 && contentSize.height > 0
        case .leading, .trailing:
            return bounds.width > 0 && contentSize.width > 0
        }
    }

    private func targetOffset(
        for edge: Edge,
        adjustedContentInset customAdjustedContentInset: UIEdgeInsets? = nil
    ) -> CGPoint {
        let inset = customAdjustedContentInset ?? adjustedContentInset

        switch edge {
        case .top:
            return CGPoint(x: contentOffset.x, y: -inset.top)
        case .bottom:
            let maximumY = contentSize.height - bounds.height + inset.bottom
            return CGPoint(x: contentOffset.x, y: max(-inset.top, maximumY))
        case .leading:
            return CGPoint(x: horizontalOffset(for: .leading, inset: inset), y: contentOffset.y)
        case .trailing:
            return CGPoint(x: horizontalOffset(for: .trailing, inset: inset), y: contentOffset.y)
        }
    }

    private func horizontalOffset(for edge: Edge, inset: UIEdgeInsets) -> CGFloat {
        let minimumX = -inset.left
        let maximumX = max(minimumX, contentSize.width - bounds.width + inset.right)
        let isRightToLeft = quickLayoutDirection == .rightToLeft

        switch (edge, isRightToLeft) {
        case (.leading, false), (.trailing, true):
            return minimumX
        case (.leading, true), (.trailing, false):
            return maximumX
        default:
            return contentOffset.x
        }
    }

    private func setContentOffset(_ offset: CGPoint, requestedAnimated animated: Bool) {
        guard !animated else {
            setContentOffset(offset, animated: true)
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            setContentOffset(offset, animated: false)
            layer.removeAnimation(forKey: "bounds")
            layer.removeAnimation(forKey: "position")
        }
        CATransaction.commit()
    }
}
