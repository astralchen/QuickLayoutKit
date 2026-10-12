//
//  QuickLayoutScrollView.swift
//  QuickLayoutKit
//
//  由 Sondra 创建于 2025/12/26。
//

import QuartzCore
import QuickLayout
import QuickLayoutKitCore
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

        /// 判断目标边缘是否属于当前单一滚动轴。
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
    /// 交叉轴的内容范围固定为扣除实际边距后的视口尺寸；固定尺寸子视图的溢出
    /// 不会启用另一方向的滚动。iOS 17.4 及以上还会关闭交叉轴回弹，切换轴时
    /// 保留原主轴的回弹开关。
    open var axis: QuickLayout.Axis = .vertical {
        didSet {
            guard axis != oldValue else { return }
            if let pendingScroll, !pendingScroll.edge.isCompatible(with: axis) {
                self.pendingScroll = nil
            }
            configureAxisBehavior(previousAxis: oldValue)
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

    /// 当前构建器生成的根元素，替换时使滚动布局失效。
    private var contentElements: [Element] = [] {
        didSet {
            setNeedsQuickLayout()
        }
    }

    /// 记录上一次环境快照，并向宿主合并发布实际环境变化。
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()
    /// 等待有效视口与内容尺寸后执行的最近一次滚动请求。
    private var pendingScroll: (edge: Edge, animated: Bool)?
    /// 边距改变后是否需要在下一次布局恢复内容起点。
    private var needsContentMarginStartPosition = false
    /// 上次布局结束的调整后边距，用于判断安全区域变化前是否停留在起点。
    private var lastResolvedAdjustedContentInset: UIEdgeInsets?
    /// 内容和指示器边距的覆盖值及最近应用量。
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

    /// 进入窗口后同步方向、安全区域边距与环境，并请求重新布局。
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

    /// 将 UIKit 特征变化发布给宿主环境，触发依赖环境的内容更新。
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

    /// 按旧边距记录起点状态，重算边距后在需要时保持内容位于起点。
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

    /// 将布局边距变化发布给宿主环境。
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

    /// 按滚动轴选择零间距栈，并在交叉轴上居中排列根元素。
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

    /// 按当前视口测量并应用内容，更新滚动范围后执行起点恢复和待处理滚动请求。
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

    /// 垂直滚动从顶部排列，水平滚动从语义前缘排列。
    private var contentAlignment: Alignment {
        switch axis {
        case .vertical:
            return .top
        case .horizontal:
            return .leading
        }
    }

    /// 沿滚动轴提供无界建议，交叉轴使用扣除实际边距后的视口长度。
    private var proposedContentSize: CGSize {
        let viewportSize = contentMarginViewportSize
        switch axis {
        case .vertical:
            return CGSize(width: viewportSize.width, height: .infinity)
        case .horizontal:
            return CGSize(width: .infinity, height: viewportSize.height)
        }
    }

    /// 优先使用有限建议，非有限轴回退到当前边界尺寸。
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

    /// 垂直内容以视口宽度测量；水平内容双轴无界以获得自然高度。
    private func measurementContentProposal(
        for containerSize: CGSize
    ) -> CGSize {
        let viewportSize = contentViewportSize(for: containerSize)

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

    /// 有限建议优先，否则使用当前容器长度，并将负值归零。
    private func resolvedMeasurementContainerLength(
        proposed: CGFloat,
        current: CGFloat
    ) -> CGFloat {
        if proposed.isFinite {
            return max(0, proposed)
        }
        return max(0, current)
    }

    /// 有限建议确定视口长度，未受约束时采用内容测量长度。
    private func resolvedViewportLength(
        proposed: CGFloat,
        fallback: CGFloat
    ) -> CGFloat {
        proposed.isFinite ? max(0, proposed) : max(0, fallback)
    }

    /// 当前边界扣除调整后内容边距所得的实际视口尺寸。
    private var contentMarginViewportSize: CGSize {
        contentViewportSize(for: bounds.size)
    }

    /// 使用实际滚动边距计算内容视口，使测量建议与最终内容尺寸保持一致。
    ///
    /// `adjustedContentInset` 已包含显式内容边距、调用方的 `contentInset` 及 UIKit
    /// 自动加入的安全区；只扣除框架记录的内容边距会遗漏 Duo 侧栏等水平安全区，
    /// 使纵向内容宽度加上左右边距后超过视口，产生额外的横向滚动范围。
    private func contentViewportSize(for containerSize: CGSize) -> CGSize {
        let insets = adjustedContentInset
        return CGSize(
            width: max(0, containerSize.width - insets.left - insets.right),
            height: max(0, containerSize.height - insets.top - insets.bottom)
        )
    }

    /// 区分容器与键盘占用量，向内容发布不小于物理安全区域的边距。
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

    /// 滚动轴保留内容测量长度，交叉轴固定为视口长度以维持单轴滚动。
    private func resolvedContentLayoutSize(_ measuredSize: CGSize) -> CGSize {
        let viewportSize = contentMarginViewportSize
        // 子内容可保留自身的固定尺寸，但不能把单轴容器扩展成双轴滚动范围。
        // 交叉轴始终使用视口尺寸，超出的子视图仍由布局对齐及裁剪处理。
        switch axis {
        case .vertical:
            return CGSize(
                width: viewportSize.width,
                height: measuredSize.height
            )
        case .horizontal:
            return CGSize(
                width: measuredSize.width,
                height: viewportSize.height
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

    /// 重置本轮声明的内容边距，再设置轴、指示器及根内容。
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

    /// 用指定或当前边距计算起点，在滚动轴上以半点容差判断是否已到达。
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

    /// 登记恢复内容起点的请求，等待新的边距和布局尺寸可用。
    func quickLayoutKeepContentAtStartAfterMarginChange() {
        needsContentMarginStartPosition = true
        setNeedsQuickLayout()
    }

    // MARK: - 私有辅助方法

    /// 配置单轴滚动与回弹，并在切换轴时保留调用方对主轴回弹的选择。
    private func configureAxisBehavior(previousAxis: QuickLayout.Axis? = nil) {
        alwaysBounceVertical = axis == .vertical
        alwaysBounceHorizontal = axis == .horizontal
        if #available(iOS 17.4, *) {
            let previousAxis = previousAxis ?? axis
            let allowsBounce = previousAxis == .vertical ? bouncesVertically : bouncesHorizontally
            // alwaysBounce 仅控制内容不足一屏时的回弹，不能关闭交叉轴本身的回弹。
            bouncesVertically = axis == .vertical && allowsBounce
            bouncesHorizontally = axis == .horizontal && allowsBounce
        }
        configureIndicators()
    }

    /// 仅在当前滚动轴上按公开开关显示指示器。
    private func configureIndicators() {
        showsVerticalScrollIndicator = showsIndicators && axis == .vertical
        showsHorizontalScrollIndicator = showsIndicators && axis == .horizontal
    }

    /// 尺寸有效时无动画恢复内容起点，并消费本轮恢复请求。
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

    /// 目标边缘与轴匹配且尺寸有效时消费延迟滚动请求。
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

    /// 要求滚动轴上视口及内容长度均为正，才能解析目标偏移。
    private func canResolveScrollOffset(for edge: Edge) -> Bool {
        switch edge {
        case .top, .bottom:
            return bounds.height > 0 && contentSize.height > 0
        case .leading, .trailing:
            return bounds.width > 0 && contentSize.width > 0
        }
    }

    /// 结合内容长度和调整后边距计算目标偏移，保持交叉轴偏移不变。
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

    /// 将语义前后缘映射到物理最小或最大水平偏移，处理 RTL 方向。
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

    /// 按请求滚动；无动画路径同时禁用隐式动画并清理图层位置动画。
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

extension QuickLayoutScrollView: GeometryScrollAxisProviding {
    /// 向 Core 几何查询发布当前显式滚动轴。
    package var geometryScrollAxis: Axis { axis }
}
