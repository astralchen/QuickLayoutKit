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
        let effectiveInsets = UIEdgeInsets(
            top: max(insets.top, keyboardInsets.top),
            left: max(insets.left, keyboardInsets.left),
            bottom: max(insets.bottom, keyboardInsets.bottom),
            right: max(insets.right, keyboardInsets.right)
        )
        let normalizedSize = CGSize(
            width: normalizedContainerDimension(proposedSize.width),
            height: normalizedContainerDimension(proposedSize.height)
        )
        let safeAreaValues = QuickLayoutSafeAreaValues(
            containerSize: normalizedSize,
            physicalContainerInsets: insets,
            physicalKeyboardInsets: keyboardInsets
        )
        let geometryObservationRegistry = quickLayoutGeometryObservationRegistry
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

        return try QuickLayoutGeometryObservationContext.withRegistry(
            geometryObservationRegistry
        ) {
            try QuickLayoutSafeAreaContext.withValues(safeAreaValues) {
                try QuickLayoutContainerRelativeFrameContext.withContainerSize(
                    containerSize,
                    operation: operation
                )
            }
        }
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
