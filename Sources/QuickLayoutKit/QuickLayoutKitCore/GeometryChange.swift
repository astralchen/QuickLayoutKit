import CoreGraphics
import QuickLayout
import UIKit

/// A coordinate space available from ``GeometryProxy``.
public enum GeometryCoordinateSpace: Sendable {
    /// The observed element's local coordinate space.
    case local

    /// The global UIKit window coordinate space.
    case global

    /// The coordinate space of the nearest ancestor scroll view.
    ///
    /// This falls back to the global coordinate space when the element isn't
    /// contained in a scroll view.
    case scrollView
}

/// A snapshot of an element's geometry after QuickLayout applies its frame.
public struct GeometryProxy: Sendable {

    /// The size of the observed element.
    public let size: CGSize

    /// The safe-area insets intersecting the observed element.
    public let safeAreaInsets: EdgeInsets

    private let localFrame: CGRect
    private let globalFrame: CGRect
    private let scrollViewFrame: CGRect?

    /// Returns the observed element's frame in a coordinate space.
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
    fileprivate init(observing view: UIView) {
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
        switch view.effectiveUserInterfaceLayoutDirection {
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
        @unknown default:
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

    /// Performs an action when a transformed geometry value changes.
    ///
    /// The action runs once for the initial applied geometry and then only
    /// when the `Equatable` value returned by `transform` changes. Measuring
    /// the element with `sizeThatFits` doesn't invoke the action.
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

    /// Performs an action with the old and new transformed geometry values.
    ///
    /// For the initial applied geometry, both parameters contain the initial
    /// value. Later invocations contain the previous and current values.
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

/// Persistent geometry-observation state owned by a QuickLayoutKit host.
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

/// The task-local observation registry established by QuickLayoutKit hosts.
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
            geometryDidChange?(GeometryProxy(observing: self))
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
