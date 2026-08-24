import ObjectiveC
import UIKit

private enum QuickLayoutManagedViewStateAssociation {
    nonisolated(unsafe) static var zIndexOwnershipKey: UInt8 = 0
}

/// QuickLayoutKit 宿主渲染过程中管理的视图状态。
///
/// 该存储会在记录下一次渲染前恢复上一次渲染中的状态。通过弱引用视图，已经移除但仍被
/// 外部持有的 UIKit 视图可以恢复原始状态，同时不会延长视图生命周期。
@MainActor
package final class QuickLayoutManagedViewStateStore {

    private final class Ownership {
        weak var owner: QuickLayoutManagedViewStateStore?
        let originalZPosition: CGFloat

        init(
            owner: QuickLayoutManagedViewStateStore,
            originalZPosition: CGFloat
        ) {
            self.owner = owner
            self.originalZPosition = originalZPosition
        }
    }

    private final class Entry {
        weak var view: UIView?
        let originalZPosition: CGFloat

        init(view: UIView, originalZPosition: CGFloat) {
            self.view = view
            self.originalZPosition = originalZPosition
        }
    }

    private var previousEntries: [ObjectIdentifier: Entry] = [:]
    private var currentEntries: [ObjectIdentifier: Entry] = [:]
    private var passDepth = 0

    package init() {}

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

    private func zIndexOwnership(of view: UIView) -> Ownership? {
        objc_getAssociatedObject(
            view,
            &QuickLayoutManagedViewStateAssociation.zIndexOwnershipKey
        ) as? Ownership
    }
}

package enum QuickLayoutManagedViewStateContext {
    @TaskLocal package static var current: QuickLayoutManagedViewStateStore?
}
