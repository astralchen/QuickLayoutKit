import CoreGraphics
import QuickLayout
import UIKit

/// 声明参照容器，让标记的子元素以所选轴的完整容器长度作为尺寸上限。
///
/// 不强制内容撑满；嵌套声明只覆盖所选轴的上限。空轴集合不建立新参照容器。
/// 声明保留内容在各轴上的尺寸弹性，由父布局分配空间后结合上限和内容测量确定尺寸。
///
/// - Parameters:
///   - axes: 以完整容器长度建立尺寸上限的轴。
///   - content: 立即执行一次的内容构建器。
/// - Returns: 向后代提供容器参照和尺寸上限的布局元素。
public func ContainerRelativeSize(
    _ axes: AxisSet,
    @LayoutBuilder content: () -> Layout
) -> Element & Layout {
    ContainerRelativeSize(axes, length: { length, _ in length }, content: content)
}

/// 按轴自定义相对于当前声明容器尺寸的上限。
///
/// 每次测量对所选轴分别调用一次 length，参数为参照容器收到的建议长度和当前轴。
/// 无界建议也会传入闭包，以便返回有限上限；负数结果使用 0，NaN 和正无穷表示无界。
/// 未选择的轴继承外层上限；空集合不调用闭包，也不建立新参照容器。
/// 闭包应无副作用；布局系统可以进行多次测量，但内容只在构建时生成一次。
/// 声明透传内容的尺寸弹性；父布局重新测量时，使用当次建议长度重新计算上限。
///
/// - Parameters:
///   - axes: 需要计算尺寸上限的轴。
///   - length: 接收建议长度和当前轴，返回该轴的尺寸上限。
///   - content: 立即构建的布局内容。
/// - Returns: 向后代提供逐轴自定义尺寸上限的布局元素。
public func ContainerRelativeSize(
    _ axes: AxisSet,
    length: @escaping @Sendable (CGFloat, Axis) -> CGFloat,
    @LayoutBuilder content: () -> Layout
) -> Element & Layout {
    ContainerRelativeSizeElement(child: content(), axes: axes, calculation: .length(length))
}

/// 根据完整容器尺寸计算共享上限，支持跨轴计算和基于宽高的断点策略。
///
/// 每次测量调用一次 maxSize，接收此声明收到的完整建议尺寸，只应用所选轴的结果。
/// 未选轴继承外层上限；空轴集合不调用闭包，也不改变后代的参照容器。
/// 输入可以无界；结果逐轴将负数归零，NaN 和正无穷视为无界。
/// 闭包应无副作用；内容只在构建时生成一次。
/// 声明透传内容的尺寸弹性；父布局重新测量时，使用当次建议尺寸重新计算上限。
///
/// - Parameters:
///   - axes: 需要应用计算结果的轴。
///   - maxSize: 接收完整建议尺寸并返回逐轴上限的纯值闭包。
///   - content: 立即执行一次的内容构建器。
/// - Returns: 向后代提供完整容器参照及所选轴上限的布局元素。
public func ContainerRelativeSize(
    _ axes: AxisSet,
    maxSize: @escaping @Sendable (CGSize) -> CGSize,
    @LayoutBuilder content: () -> Layout
) -> Element & Layout {
    ContainerRelativeSizeElement(child: content(), axes: axes, calculation: .size(maxSize))
}

/// 为后代建立容器尺寸与逐轴上限作用域的声明元素。
private struct ContainerRelativeSizeElement: Layout, _LayoutValueProvidingElement {
    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 本层覆盖尺寸上限的轴；未选轴保留外层上限。
    let axes: AxisSet
    /// 从本层收到的建议尺寸计算上限的策略。
    let calculation: ContainerRelativeSizeCalculation

    /// 继续向内查询自定义布局值时访问的子元素。
    var _layoutValueChild: Element { child }
    /// 本层不提供布局值，交由查询器继续访问子元素。
    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }

    /// 在嵌套任务局部作用域中测量子元素；空轴集合直接透传。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        guard !axes.isEmpty else { return child.quick_layoutThatFits(proposedSize) }
        let calculated = calculation.limits(for: proposedSize, axes: axes)
        var limits = ContainerRelativeSizeContext.maxSize
        if axes.contains(.horizontal) {
            limits.width = calculated.width
        }
        if axes.contains(.vertical) {
            limits.height = calculated.height
        }
        return ContainerRelativeSizeContext.$containerSize.withValue(proposedSize) {
            ContainerRelativeSizeContext.$maxSize.withValue(limits) {
                child.quick_layoutThatFits(proposedSize)
            }
        }
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }
}

/// 容器相对上限的逐轴计算或完整尺寸计算策略。
private enum ContainerRelativeSizeCalculation {
    /// 对每个所选轴分别计算长度上限。
    case length(@Sendable (CGFloat, Axis) -> CGFloat)
    /// 一次读取完整建议尺寸并计算两个轴的上限。
    case size(@Sendable (CGSize) -> CGSize)

    /// 执行策略并归一化各轴结果；逐轴策略不计算未选轴。
    func limits(for reference: CGSize, axes: AxisSet) -> CGSize {
        let result: CGSize
        switch self {
        case .length(let length):
            result = CGSize(
                width: axes.contains(.horizontal) ? length(reference.width, .horizontal) : .infinity,
                height: axes.contains(.vertical) ? length(reference.height, .vertical) : .infinity
            )
        case .size(let maxSize):
            result = maxSize(reference)
        }
        return CGSize(width: normalizedLimit(result.width), height: normalizedLimit(result.height))
    }
}

/// 将 `NaN` 视为无界、负数归零，并保留正无穷上限。
private func normalizedLimit(_ value: CGFloat) -> CGFloat {
    value.isNaN ? .infinity : max(0, value)
}

/// 嵌套测量结束后自动恢复外层尺寸，各次测量之间不保留临时状态。
private enum ContainerRelativeSizeContext {
    /// 最近显式声明收到的完整建议尺寸；无声明时为 `nil`。
    @TaskLocal static var containerSize: CGSize?
    /// 沿嵌套声明逐轴继承的上限；初始值为两个轴均无界。
    @TaskLocal static var maxSize = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
}

public extension Element {
    /// 应用容器相对尺寸上限，保留内容自身的收紧尺寸。
    ///
    /// 使用最近显式 ContainerRelativeSize 声明提供的上限；没有显式声明时，
    /// 使用最近 QuickLayoutKit 宿主的容器尺寸，宿主也不存在时使用父布局建议尺寸。
    /// 宿主尺寸遵循安全区域及滚动视口规则。空轴集合不改变布局。
    /// 上限通过测量建议传递，不创建占位框架或裁剪内容；拒绝收缩的子元素仍遵循
    /// 自身的布局规则。固定尺寸、最小尺寸、对齐及宽高比由其他布局 API 组合完成。
    /// - Parameter axes: 要应用上限的轴，默认包含水平和垂直轴。
    /// - Returns: 按所选轴收紧测量建议的布局元素。
    func containerRelativeSize(_ axes: AxisSet = [.horizontal, .vertical]) -> Element & Layout {
        ContainerRelativeSizeModifierElement(child: self, axes: axes, calculation: nil)
    }

    /// 自定义各轴尺寸上限，闭包接收容器长度和当前轴。
    ///
    /// 参照最近显式 ContainerRelativeSize 声明收到的尺寸，或最近 QuickLayoutKit 宿主
    /// 的容器尺寸；没有容器时使用父布局建议尺寸。结果仍受显式容器的上限和可用空间约束。
    /// 无界长度也会传入闭包；负数结果使用 0，NaN 和正无穷表示无界。
    /// 每次测量对每个所选轴调用一次；空轴集合不调用。闭包应无副作用。
    ///
    /// - Parameters:
    ///   - axes: 需要限制测量建议的轴。
    ///   - length: 接收参照容器长度及当前轴，返回该轴上限的闭包。
    /// - Returns: 同时受计算上限、继承上限及父布局建议约束的布局元素。
    func containerRelativeSize(
        _ axes: AxisSet,
        _ length: @escaping @Sendable (CGFloat, Axis) -> CGFloat
    ) -> Element & Layout {
        ContainerRelativeSizeModifierElement(child: self, axes: axes, calculation: .length(length))
    }

    /// 根据同一参照容器的完整宽高计算上限，支持跨轴计算。
    ///
    /// 参照最近显式声明的完整尺寸；没有声明时使用最近宿主尺寸，再回退到父布局建议。
    /// 宽高不会混合不同层级的容器。每次测量调用一次
    /// maxSize，只应用所选轴的结果，并受显式容器上限和父布局可用空间约束。
    /// 空轴集合不调用闭包。输入可包含无界长度；负结果归零，`NaN` 和正无穷视为无界。
    /// 闭包应无副作用。
    ///
    /// - Parameters:
    ///   - axes: 需要应用尺寸上限的轴。
    ///   - maxSize: 接收完整参照尺寸并返回逐轴上限的闭包。
    /// - Returns: 按所选轴应用上限的布局元素。
    func containerRelativeSize(
        _ axes: AxisSet,
        maxSize: @escaping @Sendable (CGSize) -> CGSize
    ) -> Element & Layout {
        ContainerRelativeSizeModifierElement(child: self, axes: axes, calculation: .size(maxSize))
    }
}

/// 将容器相对上限收紧到父布局建议中的修饰元素。
private struct ContainerRelativeSizeModifierElement: Layout, _LayoutValueProvidingElement {
    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 需要限制子元素测量建议的轴。
    let axes: AxisSet
    /// 额外上限计算策略；`nil` 表示直接使用声明或宿主提供的上限。
    let calculation: ContainerRelativeSizeCalculation?

    /// 继续向内查询自定义布局值时访问的子元素。
    var _layoutValueChild: Element { child }
    /// 本层不提供布局值，交由查询器继续访问子元素。
    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }

    /// 按显式声明、宿主、父建议的顺序选取参照，并与继承上限取交集。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        guard !axes.isEmpty else { return child.quick_layoutThatFits(proposedSize) }
        let explicitContainer = ContainerRelativeSizeContext.containerSize
        let reference = explicitContainer
            ?? QuickLayoutSafeAreaContext.current?.resolvedContainerSize
            ?? QuickLayoutContainerRelativeFrameContext.containerSize
            ?? proposedSize
        let inherited = ContainerRelativeSizeContext.maxSize
        let limits: CGSize
        if let calculation {
            let calculated = calculation.limits(for: reference, axes: axes)
            limits = CGSize(
                width: min(inherited.width, calculated.width),
                height: min(inherited.height, calculated.height)
            )
        } else if explicitContainer != nil {
            limits = inherited
        } else {
            limits = CGSize(width: normalizedLimit(reference.width), height: normalizedLimit(reference.height))
        }
        return child.quick_layoutThatFits(CGSize(
            width: axes.contains(.horizontal)
                ? min(proposedSize.width, limits.width)
                : proposedSize.width,
            height: axes.contains(.vertical)
                ? min(proposedSize.height, limits.height)
                : proposedSize.height
        ))
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }

    /// 受限轴允许部分伸缩，其余轴保留子元素的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        axes.contains(axis == .horizontal ? .horizontal : .vertical)
            ? .partial : child.quick_flexibility(for: axis)
    }
}
