import CoreGraphics
import QuickLayout
import UIKit

/// 布局可以忽略的安全区域类型。
public struct SafeAreaRegions: OptionSet, Sendable {

    /// 选项集合的原始位掩码。
    public let rawValue: UInt

    /// 使用原始位掩码创建安全区域选项集合。
    ///
    /// - Parameter rawValue: 安全区域类型的位掩码。
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// 包含视图或滚动视口提供的安全区域。
    public static let container = SafeAreaRegions(rawValue: 1 << 0)

    /// 软件键盘占用的安全区域。
    ///
    /// `QuickLayoutView` 启用 `quickLayoutKeyboardSafeAreaBehavior` 时会自动发布该区域；
    /// `QuickLayoutKeyboardAvoider` 管理 `QuickLayoutScrollView` 时也会发布该区域。
    public static let keyboard = SafeAreaRegions(rawValue: 1 << 1)

    /// QuickLayoutKit 已知的所有安全区域类型。
    public static let all: SafeAreaRegions = [.container, .keyboard]
}

/// `safeAreaInset` 使用的垂直边缘。
public enum VerticalEdge: Sendable {
    /// 顶部边缘。
    case top

    /// 底部边缘。
    case bottom
}

/// `safeAreaInset` 使用的水平边缘。
public enum HorizontalEdge: Sendable {
    /// 前缘。
    case leading

    /// 后缘。
    case trailing
}

/// 测量 QuickLayout 层级时传递的安全区域值。
package struct QuickLayoutSafeAreaValues: Sendable {

    /// 本层收到的完整容器尺寸，尚未扣除有效安全区域。
    package var containerSize: CGSize
    /// 按物理左右方向保存的容器安全区域，避免局部 RTL 切换重复镜像。
    private var physicalContainerInsets: QuickLayoutPhysicalInsets
    /// 按物理左右方向保存的键盘占用区域。
    private var physicalKeyboardInsets: QuickLayoutPhysicalInsets

    /// 按当前布局方向读写的容器安全区域边距。
    package var containerInsets: EdgeInsets {
        get {
            physicalContainerInsets.directional(
                for: LayoutContext.layoutDirection
            )
        }
        set {
            physicalContainerInsets = QuickLayoutPhysicalInsets(
                newValue,
                layoutDirection: LayoutContext.layoutDirection
            )
        }
    }

    /// 按当前布局方向读写的键盘安全区域边距。
    package var keyboardInsets: EdgeInsets {
        get {
            physicalKeyboardInsets.directional(
                for: LayoutContext.layoutDirection
            )
        }
        set {
            physicalKeyboardInsets = QuickLayoutPhysicalInsets(
                newValue,
                layoutDirection: LayoutContext.layoutDirection
            )
        }
    }

    /// 将方向性边距按当前布局方向转为物理存储。
    package init(
        containerSize: CGSize,
        containerInsets: EdgeInsets = .zero,
        keyboardInsets: EdgeInsets = .zero
    ) {
        self.containerSize = containerSize
        physicalContainerInsets = QuickLayoutPhysicalInsets(
            containerInsets,
            layoutDirection: LayoutContext.layoutDirection
        )
        physicalKeyboardInsets = QuickLayoutPhysicalInsets(
            keyboardInsets,
            layoutDirection: LayoutContext.layoutDirection
        )
    }

    /// 直接保存 UIKit 物理边距，避免在宿主边界丢失左右语义。
    package init(
        containerSize: CGSize,
        physicalContainerInsets: UIEdgeInsets,
        physicalKeyboardInsets: UIEdgeInsets = .zero
    ) {
        self.containerSize = containerSize
        self.physicalContainerInsets = QuickLayoutPhysicalInsets(
            physicalContainerInsets
        )
        self.physicalKeyboardInsets = QuickLayoutPhysicalInsets(
            physicalKeyboardInsets
        )
    }

    /// 扣除逐边合并的有效安全区域后可用的容器尺寸。
    package var resolvedContainerSize: CGSize {
        let insets = effectiveInsets
        return CGSize(
            width: insetDimension(
                containerSize.width,
                before: insets.leading,
                after: insets.trailing
            ),
            height: insetDimension(
                containerSize.height,
                before: insets.top,
                after: insets.bottom
            )
        )
    }

    /// 容器与键盘边距逐边取较大值后的方向性结果，避免重复叠加。
    fileprivate var effectiveInsets: EdgeInsets {
        physicalContainerInsets
            .combined(with: physicalKeyboardInsets)
            .directional(for: LayoutContext.layoutDirection)
    }

    /// 仅清除指定区域和边缘，返回不修改原值的上下文副本。
    fileprivate func ignoring(
        _ regions: SafeAreaRegions,
        edges: EdgeSet
    ) -> QuickLayoutSafeAreaValues {
        var values = self
        if regions.contains(.container) {
            values.physicalContainerInsets.clear(
                edges,
                layoutDirection: LayoutContext.layoutDirection
            )
        }
        if regions.contains(.keyboard) {
            values.physicalKeyboardInsets.clear(
                edges,
                layoutDirection: LayoutContext.layoutDirection
            )
        }
        return values
    }

    /// 同时消费指定边缘上的容器与键盘安全区域，避免后代重复避让。
    fileprivate func consuming(_ edges: EdgeSet) -> QuickLayoutSafeAreaValues {
        var values = self
        values.physicalContainerInsets.clear(
            edges,
            layoutDirection: LayoutContext.layoutDirection
        )
        values.physicalKeyboardInsets.clear(
            edges,
            layoutDirection: LayoutContext.layoutDirection
        )
        return values
    }
}

/// 按物理边保存安全区域，以便跨局部布局方向稳定传递。
private struct QuickLayoutPhysicalInsets: Sendable {

    /// 物理顶部边距。
    var top: CGFloat
    /// 物理左侧边距。
    var left: CGFloat
    /// 物理底部边距。
    var bottom: CGFloat
    /// 物理右侧边距。
    var right: CGFloat

    /// 保存 UIKit 边距并将非有限分量归零，保留有限负值。
    init(_ insets: UIEdgeInsets) {
        top = sanitizedSafeAreaValue(insets.top)
        left = sanitizedSafeAreaValue(insets.left)
        bottom = sanitizedSafeAreaValue(insets.bottom)
        right = sanitizedSafeAreaValue(insets.right)
    }

    /// 按指定方向将前后边距映射到物理左右边距。
    init(
        _ insets: EdgeInsets,
        layoutDirection: LayoutDirection
    ) {
        let insets = insets.sanitized
        top = insets.top
        bottom = insets.bottom

        switch layoutDirection {
        case .leftToRight:
            left = insets.leading
            right = insets.trailing
        case .rightToLeft:
            left = insets.trailing
            right = insets.leading
        }
    }

    /// 逐边取较大值合并两个区域，重叠部分不重复累加。
    func combined(with other: QuickLayoutPhysicalInsets) -> Self {
        Self(
            UIEdgeInsets(
                top: max(top, other.top),
                left: max(left, other.left),
                bottom: max(bottom, other.bottom),
                right: max(right, other.right)
            )
        )
    }

    /// 按请求的布局方向将物理左右边距转为前后边距。
    func directional(for layoutDirection: LayoutDirection) -> EdgeInsets {
        switch layoutDirection {
        case .leftToRight:
            EdgeInsets(
                top: top,
                leading: left,
                bottom: bottom,
                trailing: right
            )
        case .rightToLeft:
            EdgeInsets(
                top: top,
                leading: right,
                bottom: bottom,
                trailing: left
            )
        }
    }

    /// 将指定方向性边缘映射为物理边并清零。
    mutating func clear(
        _ edges: EdgeSet,
        layoutDirection: LayoutDirection
    ) {
        if edges.contains(.top) { top = 0 }
        if edges.contains(.bottom) { bottom = 0 }

        switch layoutDirection {
        case .leftToRight:
            if edges.contains(.leading) { left = 0 }
            if edges.contains(.trailing) { right = 0 }
        case .rightToLeft:
            if edges.contains(.leading) { right = 0 }
            if edges.contains(.trailing) { left = 0 }
        }
    }
}

/// QuickLayoutKit 宿主建立的任务局部安全区域作用域。
package enum QuickLayoutSafeAreaContext {

    /// 当前测量继承的安全区域；没有宿主发布时为 `nil`。
    @TaskLocal package static var current: QuickLayoutSafeAreaValues?

    /// 临时发布安全区域上下文，闭包返回或抛错时恢复外层值。
    package static func withValues<Result>(
        _ values: QuickLayoutSafeAreaValues,
        operation: () throws -> Result
    ) rethrows -> Result {
        try $current.withValue(values, operation: operation)
    }
}

public extension Element {

    /// 向元素可见的安全区域添加固定边距。
    ///
    /// 该修饰符先占用继承的安全区域边距，再添加指定间距并布局元素。
    /// 负值与非有限值按 `0` 处理。
    ///
    /// - Parameter insets: 添加到各个安全区域边缘的间距。
    /// - Returns: 应用安全区域内边距后的元素。
    func safeAreaPadding(_ insets: EdgeInsets) -> Element & Layout {
        SafeAreaPaddingElement(
            child: self,
            edges: .all,
            additionalInsets: insets.sanitizedSafeAreaPadding
        )
    }

    /// 向选定的安全区域边缘添加固定内边距。
    ///
    /// 传入 `nil` 不会添加额外间距，但仍会消费选中边缘继承的安全区域。这是
    /// QuickLayout 的稳定契约，不采用 SwiftUI 的平台默认间距。负值与非有限值按 `0`
    /// 处理。
    ///
    /// - Parameters:
    ///   - edges: 需要添加内边距的安全区域边缘。
    ///   - length: 额外间距；传入 `nil` 表示零。
    /// - Returns: 应用安全区域内边距后的元素。
    func safeAreaPadding(
        _ edges: EdgeSet = .all,
        _ length: CGFloat? = nil
    ) -> Element & Layout {
        let value = sanitizedSafeAreaPaddingValue(length ?? 0)
        return SafeAreaPaddingElement(
            child: self,
            edges: edges,
            additionalInsets: EdgeInsets(
                top: edges.contains(.top) ? value : 0,
                leading: edges.contains(.leading) ? value : 0,
                bottom: edges.contains(.bottom) ? value : 0,
                trailing: edges.contains(.trailing) ? value : 0
            )
        )
    }

    /// 向所有安全区域边缘添加相同的固定内边距。
    ///
    /// 负值与非有限值按 `0` 处理。
    ///
    /// - Parameter length: 添加到每个安全区域边缘的间距。
    /// - Returns: 应用安全区域内边距后的元素。
    func safeAreaPadding(_ length: CGFloat) -> Element & Layout {
        safeAreaPadding(.all, length)
    }

    /// 在安全区域的垂直边缘放置内容并为其预留空间。
    ///
    /// `spacing` 为 `nil` 时按零处理。内容构建结果为 `nil` 时使用空布局，但仍消费并
    /// 预留选中边缘继承的安全区域。
    ///
    /// - Parameters:
    ///   - edge: 放置内容的垂直边缘。
    ///   - alignment: 内容在垂直边缘上的水平对齐方式。
    ///   - spacing: 插入内容与主体内容之间的间距。
    ///   - content: 生成插入内容的构建器。
    /// - Returns: 在指定边缘插入内容后的元素。
    func safeAreaInset(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @LayoutBuilder content: () -> Element?
    ) -> Element & Layout {
        SafeAreaInsetElement(
            child: self,
            inset: content() ?? EmptyLayout(),
            edge: edge.edge,
            alignment: Alignment(horizontal: alignment, vertical: edge.verticalAlignment),
            spacing: sanitized(spacing ?? 0)
        )
    }

    /// 在安全区域的水平边缘放置内容并为其预留空间。
    ///
    /// `spacing` 为 `nil` 时按零处理。内容构建结果为 `nil` 时使用空布局，但仍消费并
    /// 预留选中边缘继承的安全区域。
    ///
    /// - Parameters:
    ///   - edge: 放置内容的水平边缘。
    ///   - alignment: 内容在水平边缘上的垂直对齐方式。
    ///   - spacing: 插入内容与主体内容之间的间距。
    ///   - content: 生成插入内容的构建器。
    /// - Returns: 在指定边缘插入内容后的元素。
    func safeAreaInset(
        edge: HorizontalEdge,
        alignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        @LayoutBuilder content: () -> Element?
    ) -> Element & Layout {
        SafeAreaInsetElement(
            child: self,
            inset: content() ?? EmptyLayout(),
            edge: edge.edge,
            alignment: Alignment(horizontal: edge.horizontalAlignment, vertical: alignment),
            spacing: sanitized(spacing ?? 0)
        )
    }

    /// 在选定边缘上扩展元素可用的安全区域。
    ///
    /// - Parameters:
    ///   - regions: 要忽略的安全区域类型。
    ///   - edges: 要忽略安全区域的边缘。
    /// - Returns: 忽略指定安全区域后的元素。
    func ignoresSafeArea(
        _ regions: SafeAreaRegions = .all,
        edges: EdgeSet = .all
    ) -> Element & Layout {
        IgnoresSafeAreaElement(child: self, regions: regions, edges: edges)
    }
}

/// 消费继承安全区域并叠加显式内边距的布局包装器。
private struct SafeAreaPaddingElement: Layout {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 本层需要消费并添加内边距的边缘。
    let edges: EdgeSet
    /// 已归一化为有限非负值的额外边距。
    let additionalInsets: EdgeInsets

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 在所选边缘消费继承区域后包裹 padding，避免子元素再次消费同一边距。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let inheritedInsets = QuickLayoutSafeAreaContext.current?.effectiveInsets ?? .zero
        let padding = EdgeInsets(
            top: edges.contains(.top) ? inheritedInsets.top + additionalInsets.top : 0,
            leading: edges.contains(.leading) ? inheritedInsets.leading + additionalInsets.leading : 0,
            bottom: edges.contains(.bottom) ? inheritedInsets.bottom + additionalInsets.bottom : 0,
            trailing: edges.contains(.trailing) ? inheritedInsets.trailing + additionalInsets.trailing : 0
        )

        let scopedChild = SafeAreaScopedElement(
            child: child,
            values: QuickLayoutSafeAreaContext.current?.consuming(edges)
        )
        return scopedChild
            .padding(padding)
            .quick_layoutThatFits(proposedSize)
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

/// 先测量边缘插入内容，再为主体预留安全区域和插入长度的包装器。
private struct SafeAreaInsetElement: Layout {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 布局于选定边缘的插入内容。
    let inset: Element
    /// 插入内容所在的单一边缘。
    let edge: Edge
    /// 内容在结果框架中的对齐方式。
    let alignment: Alignment
    /// 插入内容与主体之间的间距；允许有限负值。
    let spacing: CGFloat

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 消费目标边缘，测量插入内容，并叠放预留空间后的主体与边缘内容。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let inheritedInsets = QuickLayoutSafeAreaContext.current?.effectiveInsets ?? .zero
        let consumedEdges = edge.edgeSet
        let childValues = QuickLayoutSafeAreaContext.current?.consuming(consumedEdges)
        let scopedInset = SafeAreaScopedElement(child: inset, values: childValues)
        let insetSize = scopedInset.sizeThatFits(insetProposal(for: proposedSize))
        let insetLength = insetSize.length(for: edge.axis)
        let inheritedLength = inheritedInsets.value(for: edge)
        let reservedLength = inheritedLength + insetLength + spacing

        let target = SafeAreaScopedElement(child: child, values: childValues)
            .padding(edge.edgeSet, reservedLength)
        let insetLayer = scopedInset
            .frame(
                width: edge.axis == .horizontal ? insetLength : nil,
                height: edge.axis == .vertical ? insetLength : nil
            )
            .padding(edge.edgeSet, inheritedLength)

        return target
            .overlay(alignment: alignment) {
                insetLayer
            }
            .quick_layoutThatFits(proposedSize)
    }

    /// 同时提取主体和插入内容的视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
        inset.quick_extractViewsIntoArray(&views)
    }

    /// 沿插入轴使用无界建议，交叉轴保留父布局约束。
    private func insetProposal(for proposedSize: CGSize) -> CGSize {
        switch edge.axis {
        case .horizontal:
            return CGSize(width: .infinity, height: proposedSize.height)
        case .vertical:
            return CGSize(width: proposedSize.width, height: .infinity)
        }
    }
}

/// 仅修改后代安全区域上下文的忽略区域包装器。
private struct IgnoresSafeAreaElement: Layout {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 需要忽略的安全区域种类。
    let regions: SafeAreaRegions
    /// 需要从指定区域中清除的边缘。
    let edges: EdgeSet

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 有上下文时清除选定区域后测量；没有上下文时直接透传。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        guard let values = QuickLayoutSafeAreaContext.current else {
            return child.quick_layoutThatFits(proposedSize)
        }
        return QuickLayoutSafeAreaContext.withValues(
            values.ignoring(regions, edges: edges)
        ) {
            child.quick_layoutThatFits(proposedSize)
        }
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

/// 在子元素测量时重新发布安全区域，并同步本层容器尺寸。
private struct SafeAreaScopedElement: Layout {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 待传给后代的区域副本；`nil` 表示无需建立新作用域。
    let values: QuickLayoutSafeAreaValues?

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 以本层建议更新容器尺寸，并在该安全区域作用域中测量内容。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        guard var values else {
            return child.quick_layoutThatFits(proposedSize)
        }
        values.containerSize = proposedSize.normalizedContainerSize
        return QuickLayoutSafeAreaContext.withValues(values) {
            child.quick_layoutThatFits(proposedSize)
        }
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

private extension VerticalEdge {

    /// 与垂直边缘对应的通用布局边缘。
    var edge: Edge {
        switch self {
        case .top: .top
        case .bottom: .bottom
        }
    }

    /// 使插入内容贴合该边缘的垂直对齐方式。
    var verticalAlignment: VerticalAlignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        }
    }
}

private extension HorizontalEdge {

    /// 与水平边缘对应的通用布局边缘。
    var edge: Edge {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    /// 使插入内容贴合该边缘的水平对齐方式。
    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

private extension Edge {

    /// 仅包含当前边缘的集合。
    var edgeSet: EdgeSet {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    /// 当前边缘占用长度所在的轴。
    var axis: Axis {
        switch self {
        case .top, .bottom: .vertical
        case .leading, .trailing: .horizontal
        }
    }
}

private extension EdgeInsets {

    /// 将各边的非有限值归零，保留有限负值。
    var sanitized: EdgeInsets {
        EdgeInsets(
            top: sanitizedSafeAreaValue(top),
            leading: sanitizedSafeAreaValue(leading),
            bottom: sanitizedSafeAreaValue(bottom),
            trailing: sanitizedSafeAreaValue(trailing)
        )
    }

    /// 将各边归一化为有限非负的额外 padding。
    var sanitizedSafeAreaPadding: EdgeInsets {
        EdgeInsets(
            top: sanitizedSafeAreaPaddingValue(top),
            leading: sanitizedSafeAreaPaddingValue(leading),
            bottom: sanitizedSafeAreaPaddingValue(bottom),
            trailing: sanitizedSafeAreaPaddingValue(trailing)
        )
    }

    /// 读取指定方向性边缘的边距。
    func value(for edge: Edge) -> CGFloat {
        switch edge {
        case .top: top
        case .bottom: bottom
        case .leading: leading
        case .trailing: trailing
        }
    }
}

private extension CGSize {

    /// 将尺寸归一化为非负建议，并将最大有限哨兵转为无穷。
    var normalizedContainerSize: CGSize {
        CGSize(width: normalized(width), height: normalized(height))
    }

    /// 读取指定轴对应的长度。
    func length(for axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: width
        case .vertical: height
        }
    }
}

/// 将非有限值归零，保留有限数值及其符号。
private func sanitized(_ value: CGFloat) -> CGFloat {
    value.isFinite ? value : 0
}

/// 归一化安全区域分量；负值按原样保留。
private func sanitizedSafeAreaValue(_ value: CGFloat) -> CGFloat {
    sanitized(value)
}

/// 将额外安全区域内边距限制为有限非负值。
private func sanitizedSafeAreaPaddingValue(_ value: CGFloat) -> CGFloat {
    max(0, sanitized(value))
}

/// 规范容器长度：`NaN` 和负值归零，最大有限哨兵转为无穷。
private func normalized(_ value: CGFloat) -> CGFloat {
    if value.isNaN {
        return 0
    }
    if value == .greatestFiniteMagnitude {
        return .infinity
    }
    return max(0, value)
}

/// 从有限长度中扣除两端边距并限制为非负；无界长度直接保留。
private func insetDimension(
    _ length: CGFloat,
    before: CGFloat,
    after: CGFloat
) -> CGFloat {
    let length = normalized(length)
    guard length.isFinite else {
        return length
    }
    return max(0, length - before - after)
}
