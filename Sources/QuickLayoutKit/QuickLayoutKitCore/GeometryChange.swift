import CoreGraphics
import QuickLayout
import UIKit

public extension Element {

    /// 在转换后的几何值发生变化时执行操作。
    ///
    /// 该操作会在首次应用几何信息时执行一次，此后仅在 `transform` 返回的 `Equatable`
    /// 值发生变化时执行。使用 `sizeThatFits` 测量元素不会触发该操作。
    ///
    /// - Parameters:
    ///   - type: 转换后值的类型。
    ///   - transform: 根据当前几何信息生成可比较值的闭包。
    ///   - action: 值发生变化时执行的闭包。
    ///   - _fileID: 自动记录的调用文件，用于复用观察状态。
    ///   - _line: 自动记录的调用行。
    ///   - _column: 自动记录的调用列。
    /// - Returns: 在实际布局应用后观察几何变化的布局元素。
    ///
    /// 转换与操作闭包在主线程执行。通常应保留调用位置参数的默认值。
    @MainActor
    func onGeometryChange<Value>(
        for type: Value.Type,
        of transform: @escaping @Sendable (GeometryProxy) -> Value,
        action: @escaping (_ newValue: Value) -> Void,
        _fileID: StaticString = #fileID,
        _line: UInt = #line,
        _column: UInt = #column
    ) -> Element & Layout where Value: Equatable & Sendable {
        geometryChangeElement(
            type: type,
            transform: transform,
            actionKind: .newValue,
            fileID: _fileID,
            line: _line,
            column: _column
        ) { _, newValue in
            action(newValue)
        }
    }

    /// 使用转换前后的新旧几何值执行操作。
    ///
    /// 首次应用几何信息时，两个参数均包含初始值。后续仅在转换值变化时调用，
    /// 分别传入先前值和当前值。单独测量元素不会触发回调。
    ///
    /// - Parameters:
    ///   - type: 转换后值的类型。
    ///   - transform: 根据当前几何信息生成可比较值的闭包。
    ///   - action: 接收先前值和当前值的闭包。
    ///   - _fileID: 自动记录的调用文件，用于复用观察状态。
    ///   - _line: 自动记录的调用行。
    ///   - _column: 自动记录的调用列。
    /// - Returns: 在实际布局应用后观察几何变化的布局元素。
    ///
    /// 转换与操作闭包在主线程执行。通常应保留调用位置参数的默认值。
    @MainActor
    func onGeometryChange<Value>(
        for type: Value.Type,
        of transform: @escaping @Sendable (GeometryProxy) -> Value,
        action: @escaping (_ oldValue: Value, _ newValue: Value) -> Void,
        _fileID: StaticString = #fileID,
        _line: UInt = #line,
        _column: UInt = #column
    ) -> Element & Layout where Value: Equatable & Sendable {
        geometryChangeElement(
            type: type,
            transform: transform,
            actionKind: .oldAndNewValues,
            fileID: _fileID,
            line: _line,
            column: _column
        ) { oldValue, newValue in
            action(oldValue ?? newValue, newValue)
        }
    }

    /// 按调用位置、值类型与子视图身份复用观察状态，并替换本轮业务闭包。
    @MainActor
    private func geometryChangeElement<Value>(
        type: Value.Type,
        transform: @escaping @Sendable (GeometryProxy) -> Value,
        actionKind: GeometryObservationActionKind,
        fileID: StaticString,
        line: UInt,
        column: UInt,
        action: @escaping (_ oldValue: Value?, _ newValue: Value) -> Void
    ) -> Element & Layout where Value: Equatable & Sendable {
        let childViewID = firstExtractedView(from: self).map(ObjectIdentifier.init)
        let baseKey = GeometryObservationKey(
            fileID: String(describing: fileID),
            line: line,
            column: column,
            valueType: ObjectIdentifier(type),
            childView: childViewID,
            actionKind: actionKind,
            occurrence: 0
        )
        let state: GeometryObservationState<Value>
        if let registry = QuickLayoutGeometryObservationContext.current {
            let key = registry.resolveKey(baseKey)
            state = registry.state(for: key)
        } else {
            state = GeometryObservationState()
        }
        state.update(transform: transform, action: action)
        return GeometryChangeElement(child: self, state: state)
    }
}

// MARK: - 宿主观察状态

/// 由 QuickLayoutKit 宿主持有的持久几何观察状态。
@MainActor
package final class QuickLayoutGeometryObservationRegistry: @unchecked Sendable {

    /// 按稳定观察键保存的类型擦除状态，确认卸载后移除。
    private var states: [GeometryObservationKey: AnyObject] = [:]
    /// 当前构建轮次中同位置匿名观察器的出现计数。
    private var anonymousUseCounts: [GeometryObservationKey: Int] = [:]
    /// 注册表访问的嵌套深度，用于识别最外层构建边界。
    private var accessDepth = 0
    /// 按声明身份复用的几何作用域。
    private var scopeStates: [GeometryScopeKey: GeometryScope] = [:]
    /// 当前轮次同位置匿名作用域的出现计数。
    private var scopeCounts: [GeometryScopeKey: Int] = [:]

    /// 创建空的宿主几何注册表。
    package init() {}

    /// 复用或创建作用域，并在标记确认卸载后移除对应状态。
    func scope(for base: GeometryScopeKey, name: GeometryCoordinateSpace?, container: GeometryContainerValues?, anchorID: UUID?) -> GeometryScope {
        var key = base
        if key.childView == nil {
            key.occurrence = scopeCounts[base, default: 0]
            scopeCounts[base, default: 0] += 1
        }
        if let scope = scopeStates[key] {
            scope.update(name: name, container: container, anchorID: anchorID)
            return scope
        }
        let scope = GeometryScope(name: name, container: container, anchorID: anchorID)
        scopeStates[key] = scope
        scope.view.onDetach = { [weak self, weak scope] in
            guard let self, let scope, self.scopeStates[key] === scope else { return }
            self.scopeStates.removeValue(forKey: key)
        }
        return scope
    }

    /// 按观察键复用匹配值类型的状态，失活时仅移除仍对应的实例。
    fileprivate func state<Value>(
        for key: GeometryObservationKey
    ) -> GeometryObservationState<Value> where Value: Equatable & Sendable {
        if let state = states[key] as? GeometryObservationState<Value> {
            return state
        }
        let state = GeometryObservationState<Value>()
        states[key] = state
        state.onDeactivate = { [weak self, weak state] in
            guard let self, let state, self.states[key] === state else { return }
            self.states.removeValue(forKey: key)
        }
        return state
    }

    /// 为没有实际子视图身份的观察器附加本轮出现序号。
    fileprivate func resolveKey(
        _ key: GeometryObservationKey
    ) -> GeometryObservationKey {
        guard key.childView == nil else { return key }

        let occurrence = anonymousUseCounts[key, default: 0]
        anonymousUseCounts[key] = occurrence + 1
        return GeometryObservationKey(
            fileID: key.fileID,
            line: key.line,
            column: key.column,
            valueType: key.valueType,
            childView: nil,
            actionKind: key.actionKind,
            occurrence: occurrence
        )
    }

    /// 在最外层构建开始时清空匿名计数，退出时恢复嵌套深度。
    fileprivate func withAccessScope<Result>(
        operation: () throws -> Result
    ) rethrows -> Result {
        if accessDepth == 0 {
            anonymousUseCounts.removeAll(keepingCapacity: true)
            scopeCounts.removeAll(keepingCapacity: true)
        }
        accessDepth += 1
        defer { accessDepth -= 1 }
        return try operation()
    }
}

/// QuickLayoutKit 宿主建立的任务局部几何观察注册表。
package enum QuickLayoutGeometryObservationContext {

    /// 当前宿主发布的几何注册表；独立构建元素时可为 `nil`。
    @TaskLocal package static var current: QuickLayoutGeometryObservationRegistry?

    /// 建立注册表访问和几何应用批次，退出时恢复上下文并发送待处理快照。
    @MainActor
    package static func withRegistry<Result>(
        _ registry: QuickLayoutGeometryObservationRegistry,
        operation: () throws -> Result
    ) rethrows -> Result {
        try GeometryApplicationUpdate.withUpdates {
            try registry.withAccessScope {
                try $current.withValue(registry, operation: operation)
            }
        }
    }
}

// MARK: - 布局应用与回调交付

/// 宿主布局结束后同步发送完整快照；action 产生的新布局延后到下一次更新。
@MainActor
private enum GeometryApplicationUpdate {
    /// 当前嵌套几何应用批次的深度。
    static var depth = 0
    /// 是否正在发送批量回调，用于阻止回调触发的布局同步重入。
    static var delivering = false
    /// 本批次待采样的观察者，以对象身份合并重复更新。
    static var pending: [ObjectIdentifier: GeometryObserverView] = [:]

    /// 在最外层退出时先冻结再发送快照；回调引起的更新安排到后续主线程轮次。
    static func withUpdates<Result>(_ operation: () throws -> Result) rethrows -> Result {
        depth += 1
        defer {
            depth -= 1
            if depth == 0, !delivering {
                let observers = Array(pending.values)
                pending.removeAll(keepingCapacity: true)
                // 必须先冻结整个批次，再执行可能修改其他视图的业务回调。
                let snapshots = observers.map { ($0, $0.snapshot()) }
                delivering = true
                for (observer, snapshot) in snapshots { observer.deliver(snapshot) }
                delivering = false
                let deferred = Array(pending.values)
                pending.removeAll(keepingCapacity: true)
                for observer in deferred { observer.requestRefresh() }
            }
        }
        return try operation()
    }

    /// 在批次或回调发送期间合并观察者；无批次时返回 `false` 交由调用者立即发送。
    static func enqueue(_ observer: GeometryObserverView) -> Bool {
        guard depth > 0 || delivering else { return false }
        pending[ObjectIdentifier(observer)] = observer
        return true
    }
}

/// 几何观察回调的参数形式，用于区分同位置的不同重载。
private enum GeometryObservationActionKind: Hashable {
    /// 仅向业务发送新的几何值。
    case newValue
    /// 同时向业务发送先前值与新值。
    case oldAndNewValues
}

/// 几何观察器跨布局构建复用所需的稳定身份。
private struct GeometryObservationKey: Hashable {
    /// 观察声明的源文件标识。
    let fileID: String
    /// 观察声明所在的源码行。
    let line: UInt
    /// 观察声明所在的源码列。
    let column: UInt
    /// 转换结果类型的身份，防止不同值类型误用同一状态。
    let valueType: ObjectIdentifier
    /// 首个实际子视图的身份；纯布局元素为 `nil`。
    let childView: ObjectIdentifier?
    /// 观察闭包接收新值或新旧值的形式。
    let actionKind: GeometryObservationActionKind
    /// 同位置匿名观察器在本轮构建中的出现序号。
    let occurrence: Int
}

/// 持有观察视图及最后一次业务值，并抑制回调同步重入的状态对象。
@MainActor
private final class GeometryObservationState<Value>: @unchecked Sendable
where Value: Equatable & Sendable {

    /// 与此状态绑定的透明几何观察视图。
    let observerView: GeometryObserverView
    /// 确认卸载后通知宿主注册表释放状态的回调。
    var onDeactivate: (() -> Void)?

    /// 将冻结几何转换为业务可比较值的闭包。
    private var transform: (@Sendable (GeometryProxy) -> Value)?
    /// 业务值首次产生或变化后执行的回调。
    private var action: ((_ oldValue: Value?, _ newValue: Value) -> Void)?
    /// 最近一次交付的业务值；首次交付或失活后为 `nil`。
    private var lastValue: Value?
    /// 是否正在转换或交付业务值，用于防止递归进入。
    private var isReceiving = false

    /// 创建观察视图，并以弱引用连接采样及卸载回调。
    init() {
        observerView = GeometryObserverView()
        observerView.geometryDidChange = { [weak self] proxy in
            self?.receive(proxy)
        }
        observerView.didDetach = { [weak self] in
            self?.deactivate()
        }
    }

    /// 替换本轮转换和操作闭包，并使快照比较缓存失效。
    func update(
        transform: @escaping @Sendable (GeometryProxy) -> Value,
        action: @escaping (_ oldValue: Value?, _ newValue: Value) -> Void
    ) {
        self.transform = transform
        self.action = action
        observerView.invalidateSnapshot()
    }

    /// 比较转换后的值，仅在首次或变化时调用业务；重入时延迟重新采样。
    private func receive(_ proxy: GeometryProxy) {
        guard !isReceiving else {
            observerView.invalidateSnapshot()
            observerView.requestRefresh()
            return
        }
        guard let transform, let action else { return }
        isReceiving = true
        defer { isReceiving = false }
        let newValue = transform(proxy)
        if let oldValue = lastValue {
            guard oldValue != newValue else { return }
            lastValue = newValue
            action(oldValue, newValue)
        } else {
            lastValue = newValue
            action(nil, newValue)
        }
    }

    /// 释放业务闭包和最后值，并通知注册表删除该观察状态。
    private func deactivate() {
        transform = nil
        action = nil
        lastValue = nil
        onDeactivate?()
    }
}

// MARK: - UIKit 几何采样

/// 以实际 UIKit 几何为采样来源的透明观察视图。
final class GeometryObserverView: UIView {

    /// 冻结快照发生变化后执行的内部回调。
    var geometryDidChange: ((GeometryProxy) -> Void)?
    /// 确认视图已卸载后执行的状态清理回调。
    var didDetach: (() -> Void)?
    /// 最近一次布局应用提交的方向。
    var observedLayoutDirection: LayoutDirection = .leftToRight
    /// 最近一次布局应用提交的显式几何作用域。
    var scopes: [GeometryScope] = []
    /// 测量阶段暂存、等待应用的布局方向。
    var pendingLayoutDirection: LayoutDirection = .leftToRight
    /// 测量阶段暂存、等待应用的作用域链。
    var pendingScopes: [GeometryScope] = []
    /// 是否至少应用过一次真实布局；纯测量不会启用交付。
    private(set) var hasAppliedGeometry = false
    /// 当前窗口监测器的弱引用，跨窗口时重新登记。
    private weak var monitor: GeometryWindowMonitor?
    /// 最近一次交付的几何快照，供重复快照去重。
    private var lastSnapshot: GeometryProxy?
    /// 是否已排入异步刷新，用于合并同一轮请求。
    private var refreshScheduled = false

    /// 创建不参与交互的透明观察视图，并在可用系统上监听铰链变化。
    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, _ in self?.requestRefresh() })
        }
    }

    /// 不支持归档初始化；该内部观察视图仅由框架创建。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 布局应用设置中心时提交待定元数据，并将几何交付加入当前批次。
    override var center: CGPoint {
        didSet {
            observedLayoutDirection = pendingLayoutDirection
            scopes = pendingScopes
            hasAppliedGeometry = true
            if !GeometryApplicationUpdate.enqueue(self) { deliver(snapshot()) }
        }
    }

    /// 冻结当前已应用布局及作用域中的几何信息。
    func snapshot() -> GeometryProxy {
        GeometryProxy(observing: self, layoutDirection: observedLayoutDirection, scopes: scopes)
    }

    /// 清除快照去重基线，使后续采样重新经过业务值比较。
    func invalidateSnapshot() { lastSnapshot = nil }

    /// 仅在已经应用布局且快照变化时发送内部回调。
    func deliver(_ snapshot: GeometryProxy) {
        guard hasAppliedGeometry, snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        geometryDidChange?(snapshot)
    }

    /// 合并刷新请求，在后续主线程轮次通过窗口监测器或独立采样更新。
    func requestRefresh() {
        guard hasAppliedGeometry, !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            guard self.hasAppliedGeometry else { return }
            if let monitor = self.monitor { monitor.refresh() }
            else { self.deliver(self.snapshot()) }
        }
    }

    /// 在 UIKit 布局周期读取受自动失效跟踪的几何，再延迟发送刷新。
    override func layoutSubviews() {
        super.layoutSubviews()
        // UIKit 在布局生命周期中追踪 reservedRegions 和有效圆角依赖。
        if hasAppliedGeometry {
            // 在受 UIKit 自动失效跟踪的生命周期内读取系统几何；布局结束后才发送回调。
            _ = snapshot()
            requestRefresh()
        }
    }

    /// 安全区域变化后请求重新采样。
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); requestRefresh() }
    /// 布局边距变化后请求重新采样。
    override func layoutMarginsDidChange() { super.layoutMarginsDidChange(); requestRefresh() }

    /// 切换窗口监测器并使快照失效，确保跨窗口坐标重新采样。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        monitor?.remove(self)
        monitor = window.map(GeometryWindowMonitor.forWindow)
        monitor?.add(self)
        invalidateSnapshot()
        requestRefresh()
    }

    /// 卸载时停止窗口采样，延迟确认后清理状态；重新挂载时请求刷新。
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil {
            monitor?.remove(self)
            monitor = nil
            lastSnapshot = nil
            // UIKit 重挂载会先移除再添加。仅在本轮结束仍未挂载时释放闭包与观察状态。
            DispatchQueue.main.async { [weak self] in
                guard let self, self.superview == nil else { return }
                self.hasAppliedGeometry = false
                self.scopes = []
                self.pendingScopes = []
                self.didDetach?()
            }
        } else {
            requestRefresh()
        }
    }
}

/// 将内容测量结果与透明观察节点叠放的布局包装器。
@MainActor
private struct GeometryChangeElement<Value>: @MainActor Layout
where Value: Equatable & Sendable {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 跨布局构建复用的业务观察状态。
    let state: GeometryObservationState<Value>

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 测量内容并暂存方向与作用域，仅在节点实际应用时触发几何交付。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        state.observerView.pendingLayoutDirection = LayoutContext.layoutDirection
        state.observerView.pendingScopes = GeometryScopeContext.scopes
        let childLayout = child.quick_layoutThatFits(proposedSize)
        return ZStackElement(
            children: [
                GeometryPrecomputedLayoutElement(layout: childLayout),
                GeometryObserverLayoutElement(
                    view: state.observerView,
                    size: childLayout.size
                ),
            ],
            alignment: .topLeading
        )
        .quick_layoutThatFits(proposedSize)
    }

    /// 收集内容及观察视图，避免同一观察视图重复加入。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
        let observer = state.observerView
        if !views.contains(where: { $0 === observer }) {
            views.append(observer)
        }
    }
}

/// 保存内容的测量结果，避免观察包装层重复测量。
private struct GeometryPrecomputedLayoutElement: Layout {

    /// 已完成测量的布局节点，供包装层直接复用。
    let layout: LayoutNode

    /// 以固定尺寸参与父布局，不要求额外伸缩空间。
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    /// 使用默认布局优先级，不额外影响父布局的空间分配。
    func quick_layoutPriority() -> CGFloat { 0 }
    /// 直接返回已测量的节点，忽略包装层的新尺寸建议。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { layout }
    /// 不重复提取视图；实际视图由原内容或布局节点管理。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

/// 以内容尺寸创建观察节点，使观察矩形与内容边界一致。
@MainActor
private struct GeometryObserverLayoutElement: @MainActor Layout {

    /// 实际接收布局应用的观察视图。
    let view: GeometryObserverView
    /// 当前内容测量得到的观察尺寸。
    let size: CGSize

    /// 以固定尺寸参与父布局，不要求额外伸缩空间。
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    /// 使用默认布局优先级，不额外影响父布局的空间分配。
    func quick_layoutPriority() -> CGFloat { 0 }

    /// 生成包含观察视图与已测量尺寸的布局节点。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        LayoutNode(view: view, dimensions: ElementDimensions(size))
    }

    /// 不重复提取视图；实际视图由原内容或布局节点管理。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

/// 提取第一个实际内容视图作为观察身份，跳过框架内部标记视图。
@MainActor
private func firstExtractedView(from element: Element) -> UIView? {
    var views: [UIView] = []
    element.quick_extractViewsIntoArray(&views)
    return views.first { !($0 is GeometryScopeView) && !($0 is GeometryObserverView) }
}
