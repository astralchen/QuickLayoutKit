import QuickLayout
import ObjectiveC
import QuickLayoutKitCore
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
    /// `ScrollView` 与 `List` 入口支持所有位置。自动位置会同时应用到内容和滚动指示器。
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
private struct ContentMarginsElement: @MainActor Layout, @MainActor QuickLayoutSafeAreaInsetTarget {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 构建时从子元素直接提取的滚动宿主，不递归搜索 UIKit 后代。
    let scrollViews: [UIScrollView]
    /// 本层显式覆盖的边缘，空集合表示没有新增覆盖。
    let edges: EdgeSet
    /// 已将非有限分量归零的方向性边距。
    let insets: EdgeInsets
    /// 该声明作用于内容、指示器或自动位置。
    let placement: ContentMarginPlacement

    /// 创建向内容所暴露的滚动宿主声明边距的布局元素。
    ///
    /// 在宿主渲染作用域内，声明会合并到待提交的边距更新；作用域外会立即应用。
    /// 此初始化方法只提取子元素直接暴露的视图，不遍历 UIKit 子视图层级。
    ///
    /// - Parameters:
    ///   - child: 提供滚动宿主的子元素。
    ///   - edges: 本层需要覆盖的方向性边缘。
    ///   - insets: 已移除非有限分量的方向性边距。
    ///   - placement: 接收边距的容器部分。
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
        scrollViews = views.compactMap { $0 as? UIScrollView }.filter { $0 is QuickLayoutScrollView || $0.quickLayoutNativeMarginState != nil }
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

    var quickLayoutAcceptsSafeAreaInset: Bool {
        (child as? any QuickLayoutSafeAreaInsetTarget)?.quickLayoutAcceptsSafeAreaInset == true
    }

    func quick_layoutWithSafeAreaInset(
        _ proposedSize: CGSize,
        reservation: QuickLayoutSafeAreaInsetReservation
    ) -> LayoutNode {
        applyMargins()
        guard let target = child as? any QuickLayoutSafeAreaInsetTarget else {
            return child.quick_layoutThatFits(proposedSize)
        }
        return target.quick_layoutWithSafeAreaInset(proposedSize, reservation: reservation)
    }
}

// MARK: - 边距解析与应用

/// 在宿主渲染期间合并滚动视图的声明式边距更新。
///
/// 同一滚动视图在一次提交前只保留最近一次更新操作。嵌套渲染共享待提交记录，
/// 最外层作用域退出时应用更新；依赖边距的测量也可以提前调用 `flush()`。
/// 这种合并避免将声明重建过程中的临时零值写入 UIKit。
///
/// - Note: 所有操作均在主 actor 上执行。该类型不提供失败回滚；即使渲染操作抛出错误，
///   退出最外层作用域时仍会提交已登记的更新。
@MainActor
enum QuickLayoutContentMarginTransaction {
    /// 当前嵌套更新作用域的层数；零表示没有活动的更新作用域。
    private static var depth = 0
    /// 按滚动视图身份记录的待提交操作；记录之间没有执行顺序保证。
    private static var pending: [ObjectIdentifier: () -> Void] = [:]

    /// 在允许合并边距更新的作用域中同步执行操作。
    ///
    /// 退出最外层作用域时提交剩余更新。嵌套调用返回时不会自行提交，
    /// 但作用域中的测量可以通过 `flush()` 提前应用当前声明。
    ///
    /// - Parameter operation: 在更新作用域中执行的操作。
    /// - Returns: `operation` 返回的值。
    /// - Throws: `operation` 抛出的错误。
    static func withUpdates<Result>(_ operation: () throws -> Result) rethrows -> Result {
        depth += 1
        defer {
            depth -= 1
            if depth == 0 { flush() }
        }
        return try operation()
    }

    /// 登记指定滚动视图的边距更新，或在没有活动作用域时立即执行更新。
    ///
    /// 同一滚动视图的新操作会替换尚未提交的旧操作。操作应在执行时读取最新声明，
    /// 避免捕获声明重建过程中的中间值。
    ///
    /// - Parameters:
    ///   - scrollView: 用于标识待更新记录的滚动视图。
    ///   - update: 提交时执行的操作。在作用域内登记时，该闭包会保留到提交或被替换。
    static func schedule(on scrollView: UIScrollView, update: @escaping () -> Void) {
        if depth > 0 {
            pending[ObjectIdentifier(scrollView)] = update
        } else {
            update()
        }
    }

    /// 同步执行当前待提交的边距更新。
    ///
    /// 测量或放置依赖内容边距的视图前调用此方法，以使 UIKit 边距反映当前声明。
    /// 此方法不结束活动作用域；后续声明仍可继续合并。
    ///
    /// 方法先移除待提交记录，再执行其快照。执行过程中在活动作用域内登记的新更新
    /// 留待下一次提交；没有待提交记录时，此方法不执行任何操作。
    static func flush() {
        let updates = pending
        pending.removeAll(keepingCapacity: true)
        for update in updates.values { update() }
    }
}

/// 管理方向性覆盖与上次应用量，重算时保留调用方原有 UIKit 边距。
final class QuickLayoutContentMarginState {

    /// safeAreaInset 与内容边距共用写入端；保存测量结果供独立 UIKit 重排使用。
    private var safeAreaReservation = QuickLayoutSafeAreaInsetReservation()
    var ignoredContainerEdges: UIEdgeInsets { safeAreaReservation.ignoredContainerEdges }
    var declaredSafeArea: QuickLayoutSafeAreaInsetReservation { safeAreaReservation }
    private var appliedSafeAreaReservation = QuickLayoutSafeAreaInsetReservation()

    @MainActor
    func setSafeAreaReservation(_ value: QuickLayoutSafeAreaInsetReservation, on scrollView: UIScrollView) {
        guard safeAreaReservation != value else { return }
        safeAreaReservation = value
        scheduleInsetsUpdate(on: scrollView)
    }

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

    /// 仅记录已提交的显式内容边距，供嵌套视口区分排版留白和可恢复的安全区。
    private(set) var appliedExplicitContentMargins: UIEdgeInsets = .zero
    /// 上次写入内容边距的框架增量，重算前从 UIKit 当前值中扣除。
    private(set) var appliedContentInsets: UIEdgeInsets = .zero
    /// 上次写入垂直指示器边距的框架增量。
    private(set) var appliedVerticalIndicatorInsets: UIEdgeInsets = .zero
    /// 上次写入水平指示器边距的框架增量。
    private(set) var appliedHorizontalIndicatorInsets: UIEdgeInsets = .zero
    /// 上次应用边距时的有效布局方向。
    private var appliedLayoutDirection: UIUserInterfaceLayoutDirection?
    /// 上次写入 UIKit 边距时，列表局部横轴是否相对于父视图镜像。
    private var appliedHorizontalMirroring = false
    /// 上次参与补偿的滚动视图局部安全区域。
    private var appliedSafeAreaInsets: UIEdgeInsets?
    /// 上次记录的 UIKit 自动内容边距调整量。
    private var appliedAutomaticAdjustmentInsets: UIEdgeInsets?
    /// 指示器的自动安全区调整独立于内容，不能复用 adjustedContentInset 的差值。
    private var appliedAutomaticIndicatorAdjustmentInsets: UIEdgeInsets?

    /// 清空上一轮声明的边距覆盖，并安排更新 UIKit 边距。
    ///
    /// 在活动渲染作用域内，清空操作与后续声明合并提交。如果没有后续声明，
    /// 提交时移除框架此前添加的边距，保留调用方自身的 UIKit 边距基线。
    ///
    /// - Parameter scrollView: 持有这些声明覆盖的滚动视图。
    @MainActor
    func reset(on scrollView: UIScrollView) {
        automatic = Overrides()
        scrollContent = Overrides()
        scrollIndicators = Overrides()
        scheduleInsetsUpdate(on: scrollView)
    }

    /// 合并指定位置和边缘的声明覆盖，并安排应用结果。
    ///
    /// 未包含在 `edges` 中的边缘保留当前声明。活动渲染作用域中的多次调用会合并，
    /// 直到测量前提交或最外层作用域退出；在作用域外调用时立即应用结果。
    ///
    /// - Parameters:
    ///   - edges: 本次声明需要覆盖的方向性边缘。
    ///   - insets: 应用于选定边缘的方向性边距。
    ///   - placement: 接收本次覆盖的内容或指示器位置。
    ///   - scrollView: 接收解析后 UIKit 边距的滚动视图。
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
        scheduleInsetsUpdate(on: scrollView)
    }

    /// 安排在提交时读取并应用当前的边距声明。
    ///
    /// 更新操作弱引用接收者和滚动视图，不延长两者的生命周期；任一对象已释放时，
    /// 提交操作不产生效果。
    ///
    /// - Parameter scrollView: 接收边距更新的滚动视图。
    @MainActor
    private func scheduleInsetsUpdate(on scrollView: UIScrollView) {
        QuickLayoutContentMarginTransaction.schedule(on: scrollView) { [weak self, weak scrollView] in
            guard let self, let scrollView else { return }
            self.updateInsets(on: scrollView)
        }
    }

    /// 方向、安全区域或自动调整量变化时重算边距，不主动恢复内容起点。
    @MainActor
    func updateLayoutDirectionIfNeeded(on scrollView: UIScrollView) {
        let automaticAdjustmentInsets = scrollView
            .quickLayoutAutomaticContentInsetAdjustment
        guard appliedLayoutDirection
                != scrollView.effectiveUserInterfaceLayoutDirection
                || appliedHorizontalMirroring != scrollView.quickLayoutMirrorsInsetCoordinates
                || appliedSafeAreaInsets != scrollView.safeAreaInsets
                || appliedAutomaticAdjustmentInsets
                    != automaticAdjustmentInsets
                || appliedAutomaticIndicatorAdjustmentInsets
                    != scrollView.quickLayoutAutomaticIndicatorInsetAdjustment else {
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

    /// 根据当前声明和环境更新滚动内容及指示器边距。
    ///
    /// 先从 UIKit 当前边距中扣除上次记录的框架增量，再叠加新解析的覆盖值和安全区域
    /// 补偿。结果与 UIKit 当前值相同时不调用对应属性的 setter。
    ///
    /// - Parameters:
    ///   - scrollView: 接收边距的滚动视图。
    ///   - keepsContentAtStart: 是否在内容边距改变且原先停留于起点时，请求恢复起点。
    ///     默认值为 `true`。此参数不会将处于中途的内容主动滚回起点。
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
        let mirrored = scrollView.quickLayoutMirrorsInsetCoordinates
        let insetDirection: UIUserInterfaceLayoutDirection = mirrored
            ? (layoutDirection == .rightToLeft ? .leftToRight : .rightToLeft)
            : layoutDirection

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
        let automaticIndicatorInsets = scrollView.quickLayoutAutomaticIndicatorInsetAdjustment
        let explicitContentMargins = contentOverrides.resolved.uiInsets(for: insetDirection)
        let contentMargins = explicitContentMargins.adding(
            scrollView.quickLayoutMissingSafeAreaInsets(
                specified: contentOverrides.specified.uiInsets(for: insetDirection),
                automaticAdjustment: automaticAdjustmentInsets
            )
        )
        let indicatorMargins = indicatorOverrides.resolved
            .uiInsets(for: insetDirection)
            .adding(
                scrollView.quickLayoutMissingSafeAreaInsets(
                    specified: indicatorOverrides.specified
                        .uiInsets(for: insetDirection),
                    automaticAdjustment: automaticIndicatorInsets
                )
            )
        // 组合布局在交叉轴内部处理安全区，不一定反映在 adjustedContentInset 中。
        // 将这部分计入已消费区域，避免在全宽 contentSize 之外再次添加可滚动边距。
        let layoutManaged = scrollView.quickLayoutLayoutManagedSafeAreaInsets
        let consumed = UIEdgeInsets(
            top: max(automaticAdjustmentInsets.top, layoutManaged.top),
            left: max(automaticAdjustmentInsets.left, layoutManaged.left),
            bottom: max(automaticAdjustmentInsets.bottom, layoutManaged.bottom),
            right: max(automaticAdjustmentInsets.right, layoutManaged.right)
        )
        // UIKit 自动安全区和键盘增量已占用的区域不再添加。业务基线与显式 margins 保留。
        let required = safeAreaReservation.insets.inScrollCoordinates(mirrored: mirrored)
        let selected = safeAreaReservation.selected.inScrollCoordinates(mirrored: mirrored)
        let keyboard = scrollView.quickLayoutKeyboardInsetDelta
        let ignored = safeAreaReservation.ignoredContainerEdges.inScrollCoordinates(mirrored: mirrored)
        func supplement(_ margins: UIEdgeInsets, explicit: UIEdgeInsets,
                        automatic: UIEdgeInsets, consumed: UIEdgeInsets) -> UIEdgeInsets {
            let missing = margins.subtracting(explicit)
            return explicit.adding(UIEdgeInsets(
                top: ignored.top > 0 ? required.top - automatic.top : selected.top == 0 ? missing.top : max(0, required.top - consumed.top),
                left: ignored.left > 0 ? required.left - automatic.left : selected.left == 0 ? missing.left : max(0, required.left - consumed.left),
                bottom: ignored.bottom > 0 ? required.bottom - automatic.bottom : selected.bottom == 0 ? missing.bottom : max(0, required.bottom - consumed.bottom - keyboard),
                right: ignored.right > 0 ? required.right - automatic.right : selected.right == 0 ? missing.right : max(0, required.right - consumed.right)
            ))
        }
        let resolvedContentMargins = supplement(contentMargins, explicit: explicitContentMargins,
                                                automatic: automaticAdjustmentInsets, consumed: consumed)
        // 组合布局只消费内容的安全区，指示器仍由 UIKit 自己的自动调整开关决定。
        let resolvedIndicatorMargins = supplement(indicatorMargins, explicit: indicatorOverrides.resolved.uiInsets(for: insetDirection),
                                                  automatic: automaticIndicatorInsets, consumed: automaticIndicatorInsets)
        let verticalIndicatorMargins: UIEdgeInsets
        let horizontalIndicatorMargins: UIEdgeInsets
        if let quickLayoutScrollView = scrollView as? QuickLayoutScrollView {
            verticalIndicatorMargins = quickLayoutScrollView.axis == .vertical
                ? resolvedIndicatorMargins
                : .zero
            horizontalIndicatorMargins = quickLayoutScrollView.axis == .horizontal
                ? resolvedIndicatorMargins
                : .zero
        } else {
            verticalIndicatorMargins = resolvedIndicatorMargins
            horizontalIndicatorMargins = resolvedIndicatorMargins
        }
        let shouldKeepContentAtStart = keepsContentAtStart
            && resolvedContentMargins != previousContentMargins
            && (scrollView as? QuickLayoutScrollView)?
                .quickLayoutIsAtContentStart() == true

        // 只在 safeAreaInset 预留量变化前已停在尾部时跟随尾部，普通 contentMargins
        // 变化及中途浏览保持原行为。比较上次提交值，避免测量事务中的临时声明触发滚动。
        let shouldKeepContentAtEnd = safeAreaReservation != appliedSafeAreaReservation
            && resolvedContentMargins != previousContentMargins
            && !shouldKeepContentAtStart
            && !scrollView.isTracking && !scrollView.isDragging && !scrollView.isDecelerating
            && (scrollView as? QuickLayoutScrollView)?.quickLayoutIsAtContentEnd() == true

        appliedSafeAreaReservation = safeAreaReservation
        appliedLayoutDirection = layoutDirection
        appliedHorizontalMirroring = mirrored
        appliedSafeAreaInsets = scrollView.safeAreaInsets
        appliedAutomaticAdjustmentInsets = automaticAdjustmentInsets
        appliedAutomaticIndicatorAdjustmentInsets = automaticIndicatorInsets
        appliedExplicitContentMargins = explicitContentMargins
        appliedContentInsets = resolvedContentMargins
        appliedVerticalIndicatorInsets = verticalIndicatorMargins
        appliedHorizontalIndicatorInsets = horizontalIndicatorMargins

        let contentInsets = baseContentInsets.adding(resolvedContentMargins)
        let verticalIndicatorInsets = baseVerticalIndicatorInsets
            .adding(verticalIndicatorMargins)
        let horizontalIndicatorInsets = baseHorizontalIndicatorInsets
            .adding(horizontalIndicatorMargins)
        // UIKit 的 setter 即使收到相同值也可能更新导航栏的 Observation 状态。
        if scrollView.contentInset != contentInsets {
            scrollView.contentInset = contentInsets
        }
        if scrollView.verticalScrollIndicatorInsets != verticalIndicatorInsets {
            scrollView.verticalScrollIndicatorInsets = verticalIndicatorInsets
        }
        if scrollView.horizontalScrollIndicatorInsets != horizontalIndicatorInsets {
            scrollView.horizontalScrollIndicatorInsets = horizontalIndicatorInsets
        }

        if shouldKeepContentAtStart {
            (scrollView as? QuickLayoutScrollView)?
                .quickLayoutKeepContentAtStartAfterMarginChange()
        } else if shouldKeepContentAtEnd {
            (scrollView as? QuickLayoutScrollView)?
                .quickLayoutKeepContentAtEndAfterInsetChange()
        }
    }
}

extension UIScrollView {

    /// 在新一轮滚动内容配置前清空旧的声明覆盖。
    @MainActor
    func quickLayoutResetContentMargins() {
        quickLayoutScrollMarginState.reset(on: self)
    }

    /// 按当前环境按需重新映射方向性边距。
    @MainActor
    func quickLayoutUpdateContentMarginDirectionIfNeeded() {
        quickLayoutScrollMarginState.updateLayoutDirectionIfNeeded(on: self)
    }

    /// 按新的单一滚动轴重新分配指示器边距。
    @MainActor
    func quickLayoutUpdateContentMarginAxis() {
        quickLayoutScrollMarginState.updateAxis(on: self)
    }

    /// 将修饰符声明交给宿主边距状态合并并应用。
    @MainActor
    fileprivate func quickLayoutSetContentMargins(
        edges: EdgeSet,
        insets: EdgeInsets,
        placement: ContentMarginPlacement
    ) {
        quickLayoutScrollMarginState.set(
            edges: edges,
            insets: insets,
            placement: placement,
            on: self
        )
    }
}

extension UIScrollView {

    /// 分别读取两个轴已实际应用的增量，避免把另一轴的边距当作基线扣除或重复添加。
    var quickLayoutAppliedVerticalIndicatorMarginInsets: UIEdgeInsets {
        quickLayoutExistingMarginState?.appliedVerticalIndicatorInsets ?? .zero
    }

    var quickLayoutAppliedHorizontalIndicatorMarginInsets: UIEdgeInsets {
        quickLayoutExistingMarginState?.appliedHorizontalIndicatorInsets ?? .zero
    }

    /// 去掉显式排版留白，剩余的已应用边距才计入安全区消费。
    var quickLayoutInsetsAppliedToSafeArea: UIEdgeInsets {
        adjustedContentInset.subtracting(quickLayoutExistingMarginState?.appliedExplicitContentMargins ?? .zero)
    }

    /// QuickLayout 最近添加的内容边距增量；未接入适配的原生滚动视图为零。
    var quickLayoutAppliedContentMarginInsets: UIEdgeInsets {
        quickLayoutExistingMarginState?.appliedContentInsets ?? .zero
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

    fileprivate func inScrollCoordinates(mirrored: Bool) -> Self {
        mirrored ? Self(top: top, left: right, bottom: bottom, right: left) : self
    }

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

    /// 部分原生列表会镜像自身坐标系。外层的物理右边在列表局部变成左边，
    /// 必须先转换再与 UIKit 的安全区、内容和指示器 inset 逐边比较。
    var quickLayoutMirrorsInsetCoordinates: Bool {
        guard quickLayoutNativeMarginState != nil, let superview else { return false }
        let origin = convert(CGPoint.zero, to: superview)
        return convert(CGPoint(x: 1, y: 0), to: superview).x < origin.x
    }

    /// UICollectionViewCompositionalLayout 的安全区参考在交叉轴内部收窄项目，
    /// 不能把 adjustedContentInset 为零解释成该轴尚未避让。
    var quickLayoutLayoutManagedSafeAreaInsets: UIEdgeInsets {
        guard quickLayoutNativeMarginState != nil,
              let collection = self as? UICollectionView,
              let layout = collection.collectionViewLayout as? UICollectionViewCompositionalLayout else { return .zero }
        switch layout.configuration.contentInsetsReference {
        case .automatic, .safeArea, .layoutMargins, .readableContent:
            if layout.configuration.scrollDirection == .vertical {
                return UIEdgeInsets(top: 0, left: safeAreaInsets.left, bottom: 0, right: safeAreaInsets.right)
            }
            return UIEdgeInsets(top: safeAreaInsets.top, left: 0, bottom: safeAreaInsets.bottom, right: 0)
        case .none:
            return .zero
        @unknown default:
            return .zero
        }
    }

    /// UIKit 在显式内容边距之外添加的非负调整量。
    var quickLayoutAutomaticContentInsetAdjustment: UIEdgeInsets {
        UIEdgeInsets(
            top: max(0, adjustedContentInset.top - contentInset.top),
            left: max(0, adjustedContentInset.left - contentInset.left),
            bottom: max(0, adjustedContentInset.bottom - contentInset.bottom),
            right: max(0, adjustedContentInset.right - contentInset.right)
        )
    }

    /// UIKit 自动避让指示器的安全区不随内容是否可滚动或内容 inset 调整策略而关闭。
    /// 返回的是系统已负责的安全区域，实际轨道位置仍由系统结合屏幕边缘形状决定。
    /// 保留自动调整，Kit 只补足额外预留和显式 margins。
    var quickLayoutAutomaticIndicatorInsetAdjustment: UIEdgeInsets {
        automaticallyAdjustsScrollIndicatorInsets ? safeAreaInsets : .zero
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

/// 原生视图仅在显式声明为滚动容器时建立状态，普通 UIKit 叶子保持自身行为。
private enum NativeScrollMarginKey {
    nonisolated(unsafe) static var state: UInt8 = 0
}

extension UIScrollView {
    fileprivate var quickLayoutNativeMarginState: QuickLayoutContentMarginState? {
        objc_getAssociatedObject(self, &NativeScrollMarginKey.state) as? QuickLayoutContentMarginState
    }
    var quickLayoutUsesNativeListSafeArea: Bool {
        guard let state = quickLayoutNativeMarginState else { return false }
        return state.declaredSafeArea.selected != .zero
    }
    var quickLayoutNativeIgnoredContainerEdges: UIEdgeInsets {
        quickLayoutNativeMarginState?.ignoredContainerEdges ?? .zero
    }
    private var quickLayoutExistingMarginState: QuickLayoutContentMarginState? {
        (self as? QuickLayoutScrollView)?.quickLayoutContentMarginState ?? quickLayoutNativeMarginState
    }
    var quickLayoutScrollMarginState: QuickLayoutContentMarginState {
        if let existing = quickLayoutExistingMarginState { return existing }
        let state = QuickLayoutContentMarginState()
        objc_setAssociatedObject(self, &NativeScrollMarginKey.state, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }
}
