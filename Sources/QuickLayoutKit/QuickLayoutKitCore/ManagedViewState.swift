import ObjectiveC
import UIKit

/// 保存视图层级所有权记录所用的 Objective-C 关联键。
private enum QuickLayoutManagedViewStateAssociation {
    /// 视图上层级所有权对象的唯一关联地址。
    nonisolated(unsafe) static var zIndexOwnershipKey: UInt8 = 0
}

/// QuickLayoutKit 宿主渲染过程中管理的视图状态。
///
/// 该存储会在记录下一次渲染前恢复上一次渲染中的状态。通过弱引用视图，已经移除但仍被
/// 外部持有的 UIKit 视图可以恢复原始状态，同时不会延长视图生命周期。
@MainActor
package final class QuickLayoutManagedViewStateStore {

    /// 跨宿主转移时保留原始层级的所有权记录。
    private final class Ownership {
        /// 当前管理层级的宿主存储；弱引用避免循环持有。
        weak var owner: QuickLayoutManagedViewStateStore?
        /// 首次接管前的图层层级，跨宿主转移时仍以此为恢复基线。
        let originalZPosition: CGFloat

        /// 记录层级所有者和接管前的基线。
        init(
            owner: QuickLayoutManagedViewStateStore,
            originalZPosition: CGFloat
        ) {
            self.owner = owner
            self.originalZPosition = originalZPosition
        }
    }

    /// 单轮渲染中被修改视图的弱引用及恢复基线。
    private final class Entry {
        /// 本轮修改的视图；记录不会延长其生命周期。
        weak var view: UIView?
        /// 应用受管理层级前的原始值。
        let originalZPosition: CGFloat

        /// 记录视图及其原始层级，不持有视图。
        init(view: UIView, originalZPosition: CGFloat) {
            self.view = view
            self.originalZPosition = originalZPosition
        }
    }

    /// 上一轮渲染结束后仍需恢复的视图记录。
    private var previousEntries: [ObjectIdentifier: Entry] = [:]
    /// 当前最外层渲染期间收集的视图记录。
    private var currentEntries: [ObjectIdentifier: Entry] = [:]
    /// 嵌套渲染深度，只有最外层负责切换恢复记录。
    private var passDepth = 0

    /// 创建尚未接管任何视图的状态存储。
    package init() {}

    /// 恢复上一轮状态后执行渲染，并在退出时保存本轮记录；支持嵌套和抛错。
    package func withRenderPass<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        let startsPass = passDepth == 0
        if startsPass {
            restorePreviousState()
            currentEntries.removeAll(keepingCapacity: true)
        }

        passDepth += 1
        defer {
            passDepth -= 1
            if startsPass {
                previousEntries = currentEntries
                currentEntries.removeAll(keepingCapacity: true)
            }
        }

        return try QuickLayoutManagedViewStateContext.$current.withValue(self) {
            try operation()
        }
    }

    /// 首次修改时接管并记录原始层级，再向图层写入指定值。
    package func applyZIndex(_ value: CGFloat, to view: UIView) {
        let identifier = ObjectIdentifier(view)
        if currentEntries[identifier] == nil {
            let originalZPosition = claimZIndexOwnership(of: view)
            currentEntries[identifier] = Entry(
                view: view,
                originalZPosition: originalZPosition
            )
        }
        view.layer.zPosition = value
    }

    /// 只恢复仍由当前存储拥有的视图，避免覆盖其他宿主的更新。
    private func restorePreviousState() {
        for entry in previousEntries.values {
            guard let view = entry.view else { continue }
            guard zIndexOwnership(of: view)?.owner === self else {
                continue
            }
            view.layer.zPosition = entry.originalZPosition
            objc_setAssociatedObject(
                view,
                &QuickLayoutManagedViewStateAssociation.zIndexOwnershipKey,
                nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
        previousEntries.removeAll(keepingCapacity: true)
    }

    /// 接管视图层级并返回原始值；跨宿主转移时先恢复原基线。
    private func claimZIndexOwnership(of view: UIView) -> CGFloat {
        if let ownership = zIndexOwnership(of: view) {
            if ownership.owner === self {
                return ownership.originalZPosition
            }

            // 视图可能在原宿主再次渲染前离开并进入另一宿主。所有权转移时恢复原始基线，
            // 避免受管理的显示层级泄漏到其他宿主。
            view.layer.zPosition = ownership.originalZPosition
        }

        let originalZPosition = view.layer.zPosition
        let ownership = Ownership(
            owner: self,
            originalZPosition: originalZPosition
        )
        objc_setAssociatedObject(
            view,
            &QuickLayoutManagedViewStateAssociation.zIndexOwnershipKey,
            ownership,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return originalZPosition
    }

    /// 读取视图当前关联的层级所有权记录。
    private func zIndexOwnership(of view: UIView) -> Ownership? {
        objc_getAssociatedObject(
            view,
            &QuickLayoutManagedViewStateAssociation.zIndexOwnershipKey
        ) as? Ownership
    }
}

/// 沿当前渲染调用链传递状态存储的任务局部作用域。
package enum QuickLayoutManagedViewStateContext {
    /// 当前渲染使用的存储；直接使用上游 QuickLayout 时可为 `nil`。
    @TaskLocal package static var current: QuickLayoutManagedViewStateStore?
}
