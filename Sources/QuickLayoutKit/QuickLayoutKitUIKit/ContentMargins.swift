import QuickLayout
import UIKit

/// 支持内容边距的容器中需要应用边距的部分。
public struct ContentMarginPlacement: Hashable, Sendable {

    /// 边距接收位置的内部判别值。
    fileprivate enum Kind: Hashable, Sendable {
        /// 为未显式配置的位置提供共享覆盖值。
        case automatic
        /// 仅覆盖滚动内容位置。
        case scrollContent
        /// 仅覆盖滚动指示器位置。
        case scrollIndicators
    }

    /// 当前边距配置的目标位置。
    fileprivate let kind: Kind

    /// 将边距应用到容器支持的所有位置。
    ///
    /// 某个位置存在显式配置时，该位置使用显式配置，不再继承自动位置的其他边缘。
    public static var automatic: ContentMarginPlacement {
        ContentMarginPlacement(kind: .automatic)
    }

    /// 将边距应用到可滚动内容，但不移动滚动指示器。
    public static var scrollContent: ContentMarginPlacement {
        ContentMarginPlacement(kind: .scrollContent)
    }

    /// 将边距应用到滚动指示器，但不移动可滚动内容。
    public static var scrollIndicators: ContentMarginPlacement {
        ContentMarginPlacement(kind: .scrollIndicators)
    }
}

public extension Element {

    /// 为支持的容器配置方向性内容边距。
    ///
    /// `QuickLayoutScrollView` 支持所有位置。自动位置会同时将边距应用到内容和滚动指示器。
    ///
    /// - Parameters:
    ///   - edges: 需要配置内容边距的边缘。
    ///   - insets: 应用于各边缘的方向性边距。
    ///   - placement: 接收内容边距的容器部分。
    /// - Returns: 配置内容边距后的元素。
    @MainActor
    func contentMargins(
        _ edges: EdgeSet = .all,
        _ insets: EdgeInsets,
        for placement: ContentMarginPlacement = .automatic
    ) -> Element & Layout {
        ContentMarginsElement(
            child: self,
            edges: edges,
            insets: insets.sanitizedContentMargins,
            placement: placement
        )
    }

    /// 在选定边缘上配置相同的内容边距。
    ///
    /// 传入 `nil` 会保持选定边缘未指定。因此，同一位置上先前设置的边距或容器默认值
    /// 仍然有效。这是 QuickLayout 的稳定契约，不采用平台默认边距。
    ///
    /// - Parameters:
    ///   - edges: 需要配置内容边距的边缘。
    ///   - length: 应用于选定边缘的边距；传入 `nil` 表示不指定这些边缘。
    ///   - placement: 接收内容边距的容器部分。
    /// - Returns: 配置内容边距后的元素。
    @MainActor
    func contentMargins(
        _ edges: EdgeSet = .all,
        _ length: CGFloat?,
        for placement: ContentMarginPlacement = .automatic
    ) -> Element & Layout {
        guard let length else {
            return ContentMarginsElement(
                child: self,
                edges: [],
                insets: .zero,
                placement: placement
            )
        }
        let sanitizedLength = sanitizedContentMargin(length)
        return contentMargins(
            edges,
            EdgeInsets(
                top: edges.contains(.top) ? sanitizedLength : 0,
                leading: edges.contains(.leading) ? sanitizedLength : 0,
                bottom: edges.contains(.bottom) ? sanitizedLength : 0,
                trailing: edges.contains(.trailing) ? sanitizedLength : 0
            ),
            for: placement
        )
    }

    /// 在所有边缘上配置相同的内容边距。
    ///
    /// - Parameters:
    ///   - length: 应用于所有边缘的边距。
    ///   - placement: 接收内容边距的容器部分。
    /// - Returns: 配置内容边距后的元素。
    @MainActor
    func contentMargins(
        _ length: CGFloat,
        for placement: ContentMarginPlacement = .automatic
    ) -> Element & Layout {
        contentMargins(.all, length, for: placement)
    }
}

// MARK: - 布局声明

/// 向内容直接暴露的滚动宿主应用方向性边距的布局包装器。
@MainActor
private struct ContentMarginsElement: @MainActor Layout {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 构建时从子元素直接提取的滚动宿主，不递归搜索 UIKit 后代。
    let scrollViews: [QuickLayoutScrollView]
    /// 本层显式覆盖的边缘，空集合表示没有新增覆盖。
    let edges: EdgeSet
    /// 已将非有限分量归零的方向性边距。
    let insets: EdgeInsets
    /// 该声明作用于内容、指示器或自动位置。
    let placement: ContentMarginPlacement

    /// 提取内容中的滚动宿主，并立即应用声明边距。
    init(
        child: Element,
        edges: EdgeSet,
        insets: EdgeInsets,
        placement: ContentMarginPlacement
    ) {
        self.child = child
        self.edges = edges
        self.insets = insets
        self.placement = placement

        var views: [UIView] = []
        child.quick_extractViewsIntoArray(&views)
        scrollViews = views.compactMap { $0 as? QuickLayoutScrollView }
        applyMargins()
    }

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 先测量内容再重放边距声明，确保嵌套构建后仍应用当前包装层配置。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let node = child.quick_layoutThatFits(proposedSize)
        applyMargins()
        return node
    }

    /// 提取子视图后重放边距声明，保持视图提取阶段的容器配置一致。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
        applyMargins()
    }

    /// 向构建时记录的每个滚动宿主应用当前位置和边缘覆盖。
    private func applyMargins() {
        for scrollView in scrollViews {
            scrollView.quickLayoutSetContentMargins(
                edges: edges,
                insets: insets,
                placement: placement
            )
        }
    }
}

// MARK: - 边距解析与应用

/// 管理方向性覆盖与上次应用量，重算时保留调用方原有 UIKit 边距。
final class QuickLayoutContentMarginState {

    /// 逐边保存可选覆盖，区分未指定与显式零边距。
    private struct Overrides {
        /// 顶部覆盖；`nil` 表示未指定。
        var top: CGFloat?
        /// 前缘覆盖；`nil` 表示未指定。
        var leading: CGFloat?
        /// 底部覆盖；`nil` 表示未指定。
        var bottom: CGFloat?
        /// 后缘覆盖；`nil` 表示未指定。
        var trailing: CGFloat?

        /// 将指定边缘写入本位置覆盖，其他边缘保持原值。
        mutating func set(_ edges: EdgeSet, to insets: EdgeInsets) {
            if edges.contains(.top) { top = insets.top }
            if edges.contains(.leading) { leading = insets.leading }
            if edges.contains(.bottom) { bottom = insets.bottom }
            if edges.contains(.trailing) { trailing = insets.trailing }
        }

        /// 将未指定边缘补零后的方向性边距。
        var resolved: EdgeInsets {
            EdgeInsets(
                top: top ?? 0,
                leading: leading ?? 0,
                bottom: bottom ?? 0,
                trailing: trailing ?? 0
            )
        }

        /// 以零和一表示各边是否被显式指定的分量标记。
        var specified: EdgeInsets {
            EdgeInsets(
                top: top == nil ? 0 : 1,
                leading: leading == nil ? 0 : 1,
                bottom: bottom == nil ? 0 : 1,
                trailing: trailing == nil ? 0 : 1
            )
        }

        /// 是否所有边缘都未指定，用于决定整个位置是否继承自动配置。
        var isEmpty: Bool {
            top == nil
                && leading == nil
                && bottom == nil
                && trailing == nil
        }
    }

    /// 内容和指示器位置尚无显式配置时采用的覆盖值。
    private var automatic = Overrides()
    /// 滚动内容位置的显式覆盖值。
    private var scrollContent = Overrides()
    /// 滚动指示器位置的显式覆盖值。
    private var scrollIndicators = Overrides()

    /// 上次写入内容边距的框架增量，重算前从 UIKit 当前值中扣除。
    private(set) var appliedContentInsets: UIEdgeInsets = .zero
    /// 上次写入垂直指示器边距的框架增量。
    private(set) var appliedVerticalIndicatorInsets: UIEdgeInsets = .zero
    /// 上次写入水平指示器边距的框架增量。
    private(set) var appliedHorizontalIndicatorInsets: UIEdgeInsets = .zero
    /// 上次应用边距时的有效布局方向。
    private var appliedLayoutDirection: UIUserInterfaceLayoutDirection?
    /// 上次参与补偿的物理安全区域。
    private var appliedSafeAreaInsets: UIEdgeInsets?
    /// 上次记录的 UIKit 自动内容边距调整量。
    private var appliedAutomaticAdjustmentInsets: UIEdgeInsets?

    /// 清空声明覆盖并重算边距，同时保留调用方自身的 UIKit 基线。
    @MainActor
    func reset(on scrollView: UIScrollView) {
        automatic = Overrides()
        scrollContent = Overrides()
        scrollIndicators = Overrides()
        updateInsets(on: scrollView)
    }

    /// 按目标位置合并显式覆盖，并立即重算滚动视图边距。
    @MainActor
    func set(
        edges: EdgeSet,
        insets: EdgeInsets,
        placement: ContentMarginPlacement,
        on scrollView: UIScrollView
    ) {
        switch placement.kind {
        case .automatic:
            automatic.set(edges, to: insets)
        case .scrollContent:
            scrollContent.set(edges, to: insets)
        case .scrollIndicators:
            scrollIndicators.set(edges, to: insets)
        }
        updateInsets(on: scrollView)
    }

    /// 方向、安全区域或自动调整量变化时重算边距，不主动恢复内容起点。
    @MainActor
    func updateLayoutDirectionIfNeeded(on scrollView: UIScrollView) {
        let automaticAdjustmentInsets = scrollView
            .quickLayoutAutomaticContentInsetAdjustment
        guard appliedLayoutDirection
                != scrollView.effectiveUserInterfaceLayoutDirection
                || appliedSafeAreaInsets != scrollView.safeAreaInsets
                || appliedAutomaticAdjustmentInsets
                    != automaticAdjustmentInsets else {
            return
        }

        updateInsets(on: scrollView, keepsContentAtStart: false)
    }

    /// 按调用方指定的起点保持策略重算安全区域补偿。
    @MainActor
    func updateSafeArea(
        on scrollView: UIScrollView,
        keepsContentAtStart: Bool
    ) {
        updateInsets(
            on: scrollView,
            keepsContentAtStart: keepsContentAtStart
        )
    }

    /// 切换滚动轴后重算对应指示器边距，不主动改变起点。
    @MainActor
    func updateAxis(on scrollView: UIScrollView) {
        updateInsets(on: scrollView, keepsContentAtStart: false)
    }

    /// 先减去旧框架增量，再解析位置覆盖及安全区域补偿；必要时请求保持内容起点。
    @MainActor
    private func updateInsets(
        on scrollView: UIScrollView,
        keepsContentAtStart: Bool = true
    ) {
        let previousContentMargins = appliedContentInsets
        let baseContentInsets = scrollView.contentInset
            .subtracting(appliedContentInsets)
        let baseVerticalIndicatorInsets = scrollView.verticalScrollIndicatorInsets
            .subtracting(appliedVerticalIndicatorInsets)
        let baseHorizontalIndicatorInsets = scrollView.horizontalScrollIndicatorInsets
            .subtracting(appliedHorizontalIndicatorInsets)
        let layoutDirection = scrollView.effectiveUserInterfaceLayoutDirection

        // 与 SwiftUI.ContentMarginPlacement 对齐：显式 placement 按位置覆盖
        // `.automatic`，而不是逐边回退。比如先为 `.scrollContent` 设置水平
        // 16，再为 `.automatic` 设置底部 24，内容只保留水平 16；底部 24
        // 仅由没有显式配置的滚动指示器采用。
        let contentOverrides = scrollContent.isEmpty
            ? automatic
            : scrollContent
        let indicatorOverrides = scrollIndicators.isEmpty
            ? automatic
            : scrollIndicators
        let automaticAdjustmentInsets = scrollView
            .quickLayoutAutomaticContentInsetAdjustment
        let contentMargins = contentOverrides.resolved
            .uiInsets(for: layoutDirection)
            .adding(
                scrollView.quickLayoutMissingSafeAreaInsets(
                    specified: contentOverrides.specified
                        .uiInsets(for: layoutDirection),
                    automaticAdjustment: automaticAdjustmentInsets
                )
            )
        let indicatorMargins = indicatorOverrides.resolved
            .uiInsets(for: layoutDirection)
            .adding(
                scrollView.quickLayoutMissingSafeAreaInsets(
                    specified: indicatorOverrides.specified
                        .uiInsets(for: layoutDirection),
                    automaticAdjustment: automaticAdjustmentInsets
                )
            )
        let verticalIndicatorMargins: UIEdgeInsets
        let horizontalIndicatorMargins: UIEdgeInsets
        if let quickLayoutScrollView = scrollView as? QuickLayoutScrollView {
            verticalIndicatorMargins = quickLayoutScrollView.axis == .vertical
                ? indicatorMargins
                : .zero
            horizontalIndicatorMargins = quickLayoutScrollView.axis == .horizontal
                ? indicatorMargins
                : .zero
        } else {
            verticalIndicatorMargins = indicatorMargins
            horizontalIndicatorMargins = indicatorMargins
        }
        let shouldKeepContentAtStart = keepsContentAtStart
            && contentMargins != previousContentMargins
            && (scrollView as? QuickLayoutScrollView)?
                .quickLayoutIsAtContentStart() == true

        appliedLayoutDirection = layoutDirection
        appliedSafeAreaInsets = scrollView.safeAreaInsets
        appliedAutomaticAdjustmentInsets = automaticAdjustmentInsets
        appliedContentInsets = contentMargins
        appliedVerticalIndicatorInsets = verticalIndicatorMargins
        appliedHorizontalIndicatorInsets = horizontalIndicatorMargins

        scrollView.contentInset = baseContentInsets.adding(contentMargins)
        scrollView.verticalScrollIndicatorInsets = baseVerticalIndicatorInsets
            .adding(verticalIndicatorMargins)
        scrollView.horizontalScrollIndicatorInsets = baseHorizontalIndicatorInsets
            .adding(horizontalIndicatorMargins)

        if shouldKeepContentAtStart {
            (scrollView as? QuickLayoutScrollView)?
                .quickLayoutKeepContentAtStartAfterMarginChange()
        }
    }
}

extension QuickLayoutScrollView {

    /// 在新一轮滚动内容配置前清空旧的声明覆盖。
    @MainActor
    func quickLayoutResetContentMargins() {
        quickLayoutContentMarginState.reset(on: self)
    }

    /// 按当前环境按需重新映射方向性边距。
    @MainActor
    func quickLayoutUpdateContentMarginDirectionIfNeeded() {
        quickLayoutContentMarginState.updateLayoutDirectionIfNeeded(on: self)
    }

    /// 按新的单一滚动轴重新分配指示器边距。
    @MainActor
    func quickLayoutUpdateContentMarginAxis() {
        quickLayoutContentMarginState.updateAxis(on: self)
    }

    /// 将修饰符声明交给宿主边距状态合并并应用。
    @MainActor
    fileprivate func quickLayoutSetContentMargins(
        edges: EdgeSet,
        insets: EdgeInsets,
        placement: ContentMarginPlacement
    ) {
        quickLayoutContentMarginState.set(
            edges: edges,
            insets: insets,
            placement: placement,
            on: self
        )
    }
}

extension UIScrollView {

    /// QuickLayout 最近添加的内容边距增量；普通滚动视图为零。
    var quickLayoutAppliedContentMarginInsets: UIEdgeInsets {
        (self as? QuickLayoutScrollView)?
            .quickLayoutContentMarginState.appliedContentInsets ?? .zero
    }

    /// 当前滚动轴对应的框架指示器边距增量；普通滚动视图为零。
    var quickLayoutAppliedIndicatorMarginInsets: UIEdgeInsets {
        guard let scrollView = self as? QuickLayoutScrollView else {
            return .zero
        }
        switch scrollView.axis {
        case .vertical:
            return scrollView.quickLayoutContentMarginState
                .appliedVerticalIndicatorInsets
        case .horizontal:
            return scrollView.quickLayoutContentMarginState
                .appliedHorizontalIndicatorInsets
        }
    }
}

private extension EdgeInsets {

    /// 将非有限边距分量归零，保留有限负值。
    var sanitizedContentMargins: EdgeInsets {
        EdgeInsets(
            top: sanitizedContentMargin(top),
            leading: sanitizedContentMargin(leading),
            bottom: sanitizedContentMargin(bottom),
            trailing: sanitizedContentMargin(trailing)
        )
    }

    /// 根据有效方向将前后边距映射为物理左右边距，未知方向按 LTR 处理。
    func uiInsets(
        for direction: UIUserInterfaceLayoutDirection
    ) -> UIEdgeInsets {
        switch direction {
        case .rightToLeft:
            UIEdgeInsets(
                top: top,
                left: trailing,
                bottom: bottom,
                right: leading
            )
        case .leftToRight:
            UIEdgeInsets(
                top: top,
                left: leading,
                bottom: bottom,
                right: trailing
            )
        @unknown default:
            UIEdgeInsets(
                top: top,
                left: leading,
                bottom: bottom,
                right: trailing
            )
        }
    }
}

extension UIEdgeInsets {

    /// 逐物理边相加，不执行裁剪或归一化。
    func adding(_ other: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: top + other.top,
            left: left + other.left,
            bottom: bottom + other.bottom,
            right: right + other.right
        )
    }

    /// 逐物理边相减，用于移除已经应用的框架增量。
    func subtracting(_ other: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: top - other.top,
            left: left - other.left,
            bottom: bottom - other.bottom,
            right: right - other.right
        )
    }
}

private extension UIScrollView {

    /// UIKit 在显式内容边距之外添加的非负调整量。
    var quickLayoutAutomaticContentInsetAdjustment: UIEdgeInsets {
        UIEdgeInsets(
            top: max(0, adjustedContentInset.top - contentInset.top),
            left: max(0, adjustedContentInset.left - contentInset.left),
            bottom: max(0, adjustedContentInset.bottom - contentInset.bottom),
            right: max(0, adjustedContentInset.right - contentInset.right)
        )
    }

    /// 仅对显式指定的边缘补足 UIKit 尚未加入的安全区域差额。
    func quickLayoutMissingSafeAreaInsets(
        specified: UIEdgeInsets,
        automaticAdjustment: UIEdgeInsets
    ) -> UIEdgeInsets {
        UIEdgeInsets(
            top: specified.top == 0
                ? 0
                : max(0, safeAreaInsets.top - automaticAdjustment.top),
            left: specified.left == 0
                ? 0
                : max(0, safeAreaInsets.left - automaticAdjustment.left),
            bottom: specified.bottom == 0
                ? 0
                : max(0, safeAreaInsets.bottom - automaticAdjustment.bottom),
            right: specified.right == 0
                ? 0
                : max(0, safeAreaInsets.right - automaticAdjustment.right)
        )
    }
}

/// 将非有限边距归零，有限负边距保持原值。
private func sanitizedContentMargin(_ value: CGFloat) -> CGFloat {
    value.isFinite ? value : 0
}
