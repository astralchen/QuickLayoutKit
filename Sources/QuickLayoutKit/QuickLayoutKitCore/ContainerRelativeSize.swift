import CoreGraphics
import QuickLayout
import UIKit

/// 声明参照容器，让标记的子元素以所选轴的完整容器长度作为尺寸上限。
///
/// 不强制内容撑满；嵌套声明只覆盖所选轴的上限。空轴集合不建立新参照容器。
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
///
/// - Parameters:
///   - axes: 需要计算尺寸上限的轴。
///   - length: 接收建议长度和当前轴，返回该轴的尺寸上限。
///   - content: 立即构建的布局内容。
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
public func ContainerRelativeSize(
    _ axes: AxisSet,
    maxSize: @escaping @Sendable (CGSize) -> CGSize,
    @LayoutBuilder content: () -> Layout
) -> Element & Layout {
    ContainerRelativeSizeElement(child: content(), axes: axes, calculation: .size(maxSize))
}

private struct ContainerRelativeSizeElement: Layout, _LayoutValueProvidingElement {
    let child: Element
    let axes: AxisSet
    let calculation: ContainerRelativeSizeCalculation

    var _layoutValueChild: Element { child }
    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }

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

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }

    func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        axes.contains(axis == .horizontal ? .horizontal : .vertical)
            ? .fixedSize : child.quick_flexibility(for: axis)
    }
}

private enum ContainerRelativeSizeCalculation {
    case length(@Sendable (CGFloat, Axis) -> CGFloat)
    case size(@Sendable (CGSize) -> CGSize)

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

private func normalizedLimit(_ value: CGFloat) -> CGFloat {
    value.isNaN ? .infinity : max(0, value)
}

/// 嵌套测量结束后自动恢复外层尺寸，各次测量之间不保留临时状态。
private enum ContainerRelativeSizeContext {
    @TaskLocal static var containerSize: CGSize?
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
    func containerRelativeSize(_ axes: AxisSet = [.horizontal, .vertical]) -> Element & Layout {
        ContainerRelativeSizeModifierElement(child: self, axes: axes, calculation: nil)
    }

    /// 自定义各轴尺寸上限，闭包接收容器长度和当前轴。
    ///
    /// 参照最近显式 ContainerRelativeSize 声明收到的尺寸，或最近 QuickLayoutKit 宿主
    /// 的容器尺寸；没有容器时使用父布局建议尺寸。结果仍受显式容器的上限和可用空间约束。
    /// 无界长度也会传入闭包；负数结果使用 0，NaN 和正无穷表示无界。
    /// 每次测量对每个所选轴调用一次；空轴集合不调用。闭包应无副作用。
    func containerRelativeSize(
        _ axes: AxisSet,
        _ length: @escaping @Sendable (CGFloat, Axis) -> CGFloat
    ) -> Element & Layout {
        ContainerRelativeSizeModifierElement(child: self, axes: axes, calculation: .length(length))
    }

    /// 根据同一参照容器的完整宽高计算上限，支持跨轴计算。
    ///
    /// 容器来源与逐轴重载一致，宽高不会混合不同层级的容器。每次测量调用一次
    /// maxSize，只应用所选轴的结果，并受显式容器上限和父布局可用空间约束。
    /// 空轴集合不调用闭包；无界输入、异常结果的处理与逐轴重载一致。
    func containerRelativeSize(
        _ axes: AxisSet,
        maxSize: @escaping @Sendable (CGSize) -> CGSize
    ) -> Element & Layout {
        ContainerRelativeSizeModifierElement(child: self, axes: axes, calculation: .size(maxSize))
    }
}

private struct ContainerRelativeSizeModifierElement: Layout, _LayoutValueProvidingElement {
    let child: Element
    let axes: AxisSet
    let calculation: ContainerRelativeSizeCalculation?

    var _layoutValueChild: Element { child }
    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }

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

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }

    func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        axes.contains(axis == .horizontal ? .horizontal : .vertical)
            ? .partial : child.quick_flexibility(for: axis)
    }
}
