import CoreGraphics
import QuickLayout
import UIKit

/// ``GeometryProxy`` 可使用的坐标空间。
public enum GeometryCoordinateSpace: Sendable {
    /// 被观察元素的局部坐标空间。
    case local

    /// UIKit 窗口的全局坐标空间。
    case global

    /// 最近上层滚动视图的坐标空间。
    ///
    /// 元素不在滚动视图中时，使用全局坐标空间。
    case scrollView
}

/// QuickLayout 应用元素框架后的几何信息快照。
public struct GeometryProxy: Sendable {

    /// 被观察元素的尺寸。
    public let size: CGSize

    /// 与被观察元素相交的安全区域边距。
    public let safeAreaInsets: EdgeInsets

    private let localFrame: CGRect
    private let globalFrame: CGRect
    private let scrollViewFrame: CGRect?

    /// 返回被观察元素在指定坐标空间中的框架。
    ///
    /// - Parameter coordinateSpace: 用于表示结果框架的坐标空间。
    /// - Returns: 被观察元素在指定坐标空间中的框架。
    public func frame(in coordinateSpace: GeometryCoordinateSpace) -> CGRect {
        switch coordinateSpace {
        case .local:
            localFrame
        case .global:
            globalFrame
        case .scrollView:
            scrollViewFrame ?? globalFrame
        }
    }

    @MainActor
    package init(
        observing view: UIView,
        layoutDirection: LayoutDirection
    ) {
        let size = view.bounds.size
        self.size = size
        localFrame = CGRect(origin: .zero, size: size)
        globalFrame = view.convert(view.bounds, to: nil)

        var ancestor = view.superview
        var scrollView: UIScrollView?
        while let current = ancestor {
            if let current = current as? UIScrollView {
                scrollView = current
                break
            }
            ancestor = current.superview
        }
        scrollViewFrame = scrollView.map { view.convert(view.bounds, to: $0) }

        let insets = view.safeAreaInsets
        switch layoutDirection {
        case .rightToLeft:
            safeAreaInsets = EdgeInsets(
                top: insets.top,
                leading: insets.right,
                bottom: insets.bottom,
                trailing: insets.left
            )
        case .leftToRight:
            safeAreaInsets = EdgeInsets(
                top: insets.top,
                leading: insets.left,
                bottom: insets.bottom,
                trailing: insets.right
            )
        }
    }
}

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
    /// 首次应用几何信息时，两个参数均包含初始值。后续调用分别包含先前值和当前值。
    ///
    /// - Parameters:
    ///   - type: 转换后值的类型。
    ///   - transform: 根据当前几何信息生成可比较值的闭包。
    ///   - action: 接收先前值和当前值的闭包。
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

/// 由 QuickLayoutKit 宿主持有的持久几何观察状态。
@MainActor
package final class QuickLayoutGeometryObservationRegistry: @unchecked Sendable {

    private var states: [GeometryObservationKey: AnyObject] = [:]
    private var anonymousUseCounts: [GeometryObservationKey: Int] = [:]
    private var accessDepth = 0

    package init() {}

    fileprivate func state<Value>(
        for key: GeometryObservationKey
    ) -> GeometryObservationState<Value> where Value: Equatable & Sendable {
        if let state = states[key] as? GeometryObservationState<Value> {
            return state
        }
        let state = GeometryObservationState<Value>()
        states[key] = state
        return state
    }

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

    fileprivate func withAccessScope<Result>(
        operation: () throws -> Result
    ) rethrows -> Result {
        if accessDepth == 0 {
            anonymousUseCounts.removeAll(keepingCapacity: true)
        }
        accessDepth += 1
        defer { accessDepth -= 1 }
        return try operation()
    }
}

/// QuickLayoutKit 宿主建立的任务局部几何观察注册表。
package enum QuickLayoutGeometryObservationContext {

    @TaskLocal package static var current: QuickLayoutGeometryObservationRegistry?

    @MainActor
    package static func withRegistry<Result>(
        _ registry: QuickLayoutGeometryObservationRegistry,
        operation: () throws -> Result
    ) rethrows -> Result {
        try registry.withAccessScope {
            try $current.withValue(registry, operation: operation)
        }
    }
}

private enum GeometryObservationActionKind: Hashable {
    case newValue
    case oldAndNewValues
}

private struct GeometryObservationKey: Hashable {
    let fileID: String
    let line: UInt
    let column: UInt
    let valueType: ObjectIdentifier
    let childView: ObjectIdentifier?
    let actionKind: GeometryObservationActionKind
    let occurrence: Int
}

@MainActor
private final class GeometryObservationState<Value>: @unchecked Sendable
where Value: Equatable & Sendable {

    let observerView: GeometryObserverView

    private var transform: (@Sendable (GeometryProxy) -> Value)?
    private var action: ((_ oldValue: Value?, _ newValue: Value) -> Void)?
    private var lastValue: Value?

    init() {
        observerView = GeometryObserverView()
        observerView.geometryDidChange = { [weak self] proxy in
            self?.receive(proxy)
        }
        observerView.didDetach = { [weak self] in
            self?.deactivate()
        }
    }

    func update(
        transform: @escaping @Sendable (GeometryProxy) -> Value,
        action: @escaping (_ oldValue: Value?, _ newValue: Value) -> Void
    ) {
        self.transform = transform
        self.action = action
    }

    private func receive(_ proxy: GeometryProxy) {
        guard let transform, let action else { return }
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

    private func deactivate() {
        transform = nil
        action = nil
        lastValue = nil
    }
}

private final class GeometryObserverView: UIView {

    var geometryDidChange: ((GeometryProxy) -> Void)?
    var didDetach: (() -> Void)?
    var observedLayoutDirection: LayoutDirection = .leftToRight

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var center: CGPoint {
        didSet {
            geometryDidChange?(
                GeometryProxy(
                    observing: self,
                    layoutDirection: observedLayoutDirection
                )
            )
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil {
            didDetach?()
        }
    }
}

@MainActor
private struct GeometryChangeElement<Value>: @MainActor Layout
where Value: Equatable & Sendable {

    let child: Element
    let state: GeometryObservationState<Value>

    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        state.observerView.observedLayoutDirection = LayoutContext.layoutDirection
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

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
        let observer = state.observerView
        if !views.contains(where: { $0 === observer }) {
            views.append(observer)
        }
    }
}

private struct GeometryPrecomputedLayoutElement: Layout {

    let layout: LayoutNode

    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { layout }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

@MainActor
private struct GeometryObserverLayoutElement: @MainActor Layout {

    let view: GeometryObserverView
    let size: CGSize

    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        LayoutNode(view: view, dimensions: ElementDimensions(size))
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

@MainActor
private func firstExtractedView(from element: Element) -> UIView? {
    var views: [UIView] = []
    element.quick_extractViewsIntoArray(&views)
    return views.first
}
