import QuickLayout

/// 布局用于从子元素读取自定义值的键。
public protocol LayoutValueKey {

    /// 与键关联的值类型。
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

/// 保留已找到值的类型擦除包装，允许区分未找到与可选值为 `nil`。
struct _AnyLayoutValue {
    /// 通过布局键恢复具体类型的原始值。
    let value: Any
}

/// 允许布局值查询穿过修饰元素并继续访问子元素的内部协议。
protocol _LayoutValueProvidingElement {
    /// 继续向内查询自定义布局值时访问的子元素。
    var _layoutValueChild: Element { get }
    /// 查询本层是否提供指定键；返回 `nil` 时继续向子元素查找。
    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue?
}

/// 保存单个布局键值，同时透传子元素测量行为的包装器。
private struct LayoutValueElement<Key: LayoutValueKey>: Layout, _LayoutValueProvidingElement {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 本层为 `Key` 提供的值，可覆盖更内层的同名键。
    let value: Key.Value

    /// 继续向内查询自定义布局值时访问的子元素。
    var _layoutValueChild: Element { child }

    /// 只响应当前键类型的标识；其他键返回 `nil` 以继续查询。
    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? {
        guard key == ObjectIdentifier(Key.self) else { return nil }
        return _AnyLayoutValue(value: value as Any)
    }

    /// 原样传递尺寸建议并返回子元素的测量结果。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        child.quick_layoutThatFits(proposedSize)
    }

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

extension Element {

    /// 沿支持布局值传递的包装器向内查询，未找到时返回键的默认值。
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
