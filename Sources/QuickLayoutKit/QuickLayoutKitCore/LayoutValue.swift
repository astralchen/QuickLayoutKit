import QuickLayout

/// 布局用于从子元素读取自定义值的键。
public protocol LayoutValueKey {

    associatedtype Value

    /// 元素未设置该键时返回的默认值。
    static var defaultValue: Value { get }
}

public extension Element {

    /// 将自定义布局值与元素关联，供最近的 `LayoutAlgorithm` 容器读取。
    ///
    /// 应在尺寸修饰符之后调用此方法，以确保自定义布局从直接子元素上读取到该值。
    ///
    /// - Parameters:
    ///   - key: 标识自定义布局值的键类型。
    ///   - value: 与元素关联的值。
    /// - Returns: 关联指定布局值后的元素。
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
