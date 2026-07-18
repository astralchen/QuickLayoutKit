import QuickLayout

/// A key for a custom value that a layout reads from one of its subviews.
public protocol LayoutValueKey {

    associatedtype Value

    /// The value returned for an element that doesn't set this key.
    static var defaultValue: Value { get }
}

public extension Element {

    /// Associates a custom value with this element for its nearest
    /// `LayoutAlgorithm` container.
    ///
    /// Put this modifier after sizing modifiers so the layout value remains on
    /// the direct child that the custom layout receives.
    func layoutValue<Key: LayoutValueKey>(
        key: Key.Type,
        value: Key.Value
    ) -> Element & Layout {
        LayoutValueElement<Key>(child: self, value: value)
    }
}

struct _AnyLayoutValue {
    let value: Any
}

protocol _LayoutValueProvidingElement {
    var _layoutValueChild: Element { get }
    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue?
}

private struct LayoutValueElement<Key: LayoutValueKey>: Layout, _LayoutValueProvidingElement {

    let child: Element
    let value: Key.Value

    var _layoutValueChild: Element { child }

    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? {
        guard key == ObjectIdentifier(Key.self) else { return nil }
        return _AnyLayoutValue(value: value as Any)
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        child.quick_layoutThatFits(proposedSize)
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

extension Element {

    func _layoutValue<Key: LayoutValueKey>(for key: Key.Type) -> Key.Value {
        var current: Element = self

        while let provider = current as? _LayoutValueProvidingElement {
            if let value = provider._layoutValue(for: ObjectIdentifier(key)) {
                return value.value as! Key.Value
            }
            current = provider._layoutValueChild
        }

        return Key.defaultValue
    }
}
