import QuickLayout
import QuickLayoutKitCore
import ObjectiveC
import UIKit

extension UIView {

    /// 使用 `containerRelativeFrame` 修饰符所需的安全区域调整后容器尺寸执行布局操作。
    func withQuickLayoutContainerSize<Result>(
        _ proposedSize: CGSize,
        insets explicitInsets: UIEdgeInsets? = nil,
        keyboardInsets: UIEdgeInsets = .zero,
        operation: () throws -> Result
    ) rethrows -> Result {
        let insets = explicitInsets ?? safeAreaInsets
        var effectiveInsets = UIEdgeInsets(
            top: max(insets.top, keyboardInsets.top),
            left: max(insets.left, keyboardInsets.left),
            bottom: max(insets.bottom, keyboardInsets.bottom),
            right: max(insets.right, keyboardInsets.right)
        )
        let normalizedSize = CGSize(
            width: normalizedContainerDimension(proposedSize.width),
            height: normalizedContainerDimension(proposedSize.height)
        )
        // 滚动内容的建议尺寸已扣除 adjustedContentInset，普通宿主由默认包装器消费。
        var safeAreaValues: QuickLayoutSafeAreaValues
        if let scroll = self as? UIScrollView {
            let applied = scroll.adjustedContentInset
            let viewport = CGSize(width: containerDimension(normalizedSize.width, before: applied.left, after: applied.right),
                                  height: containerDimension(normalizedSize.height, before: applied.top, after: applied.bottom))
            // 相对尺寸参照包含内容边距；安全区的消费与恢复只计算系统区域。
            effectiveInsets = UIEdgeInsets(top: max(effectiveInsets.top, applied.top),
                                           left: max(effectiveInsets.left, applied.left),
                                           bottom: max(effectiveInsets.bottom, applied.bottom),
                                           right: max(effectiveInsets.right, applied.right))
            safeAreaValues = QuickLayoutSafeAreaValues(containerSize: viewport,
                physicalContainerInsets: insets, physicalKeyboardInsets: keyboardInsets)
                .consumingAppliedInsets(scroll.quickLayoutInsetsAppliedToSafeArea)
            safeAreaValues.scrollContentAxis = (scroll as? QuickLayoutScrollView)?.axis
        } else {
            safeAreaValues = QuickLayoutSafeAreaHostContext.values(for: self, size: normalizedSize,
                container: insets, keyboard: keyboardInsets)
        }
        let geometryObservationRegistry = quickLayoutGeometryObservationRegistry
        let inheritedExpansion = safeAreaValues.expansion(ignoring: .all, edges: .all)
        let rtl = LayoutContext.layoutDirection == .rightToLeft
        let sourceExpansion = UIEdgeInsets(top: inheritedExpansion.top,
            left: rtl ? inheritedExpansion.trailing : inheritedExpansion.leading,
            bottom: inheritedExpansion.bottom,
            right: rtl ? inheritedExpansion.leading : inheritedExpansion.trailing)
        let containerSize = CGSize(
            width: containerDimension(
                proposedSize.width,
                before: effectiveInsets.left,
                after: effectiveInsets.right
            ),
            height: containerDimension(
                proposedSize.height,
                before: effectiveInsets.top,
                after: effectiveInsets.bottom
            )
        )

        // 普通布局宿主不是新的参照容器；滚动视口和控制器根视图建立新边界。
        // 测量期间继承任务作用域，UIKit 独立重排后代时从视图祖先恢复同一容器。
        let startsContainer = self is UIScrollView || next is UIViewController
        let inheritedSize = QuickLayoutContainerRelativeFrameContext.containerSize
            ?? inheritedRelativeContainerSize
        let relativeSize = startsContainer ? containerSize : (inheritedSize ?? containerSize)
        objc_setAssociatedObject(
            self,
            &QuickLayoutGeometryObservationAssociatedKeys.relativeContainerSize,
            NSValue(cgSize: relativeSize),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        return try QuickLayoutGeometryObservationContext.withRegistry(
            geometryObservationRegistry
        ) {
            try QuickLayoutSafeAreaContext.withValues(safeAreaValues) {
                try QuickLayoutContainerRelativeFrameContext.withContainerSize(
                    relativeSize,
                    operation: {
                        try QuickLayoutSafeAreaHostContext.$source.withValue(self) {
                            try QuickLayoutSafeAreaHostContext.$sourceExpansion.withValue(sourceExpansion) {
                                try QuickLayoutSafeAreaContext.$touchingEdges.withValue({ [weak self] views, values in
                                    guard let self else { return [] }
                                    return QuickLayoutSafeAreaHostContext.touchingEdges(views, source: self, values: values)
                                }) {
                                    try QuickLayoutSafeAreaContext.$capture.withValue({ [weak self] views, values in
                                        guard let self else { return }
                                        QuickLayoutSafeAreaHostContext.capture(views, from: self, values: values)
                                    }, operation: operation)
                                }
                            }
                        }
                    }
                )
            }
        }
    }

    /// 跳过普通 UIKit 包装，找到祖先发布的参照尺寸；不保存对子视图或容器的强引用。
    private var inheritedRelativeContainerSize: CGSize? {
        var ancestor = superview
        while let view = ancestor {
            if let value = objc_getAssociatedObject(
                view,
                &QuickLayoutGeometryObservationAssociatedKeys.relativeContainerSize
            ) as? NSValue {
                return value.cgSizeValue
            }
            ancestor = view.superview
        }
        return nil
    }

    /// 与宿主视图关联的持久几何注册表，首次访问时创建。
    private var quickLayoutGeometryObservationRegistry: QuickLayoutGeometryObservationRegistry {
        if let registry = objc_getAssociatedObject(
            self,
            &QuickLayoutGeometryObservationAssociatedKeys.registry
        ) as? QuickLayoutGeometryObservationRegistry {
            return registry
        }
        let registry = QuickLayoutGeometryObservationRegistry()
        objc_setAssociatedObject(
            self,
            &QuickLayoutGeometryObservationAssociatedKeys.registry,
            registry,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return registry
    }
}

/// 保存宿主几何注册表所用的关联键。
private enum QuickLayoutGeometryObservationAssociatedKeys {
    /// 几何注册表关联对象的唯一键地址。
    nonisolated(unsafe) static var registry: UInt8 = 0
    /// 独立 UIKit 重排时用于恢复最近容器尺寸的关联键。
    nonisolated(unsafe) static var relativeContainerSize: UInt8 = 0
}

/// 从规范化建议长度扣除有限的两端边距；无界建议保持无界。
private func containerDimension(
    _ proposedLength: CGFloat,
    before: CGFloat,
    after: CGFloat
) -> CGFloat {
    let length = normalizedContainerDimension(proposedLength)

    guard length.isFinite else {
        return length
    }

    let leadingInset = before.isFinite ? before : 0
    let trailingInset = after.isFinite ? after : 0
    return max(0, length - leadingInset - trailingInset)
}

/// 将 `NaN` 和负值归零，将最大有限长度哨兵转换为无穷。
private func normalizedContainerDimension(_ proposedLength: CGFloat) -> CGFloat {
    if proposedLength.isNaN {
        return 0
    }
    if proposedLength == .greatestFiniteMagnitude {
        return .infinity
    }
    return max(0, proposedLength)
}
