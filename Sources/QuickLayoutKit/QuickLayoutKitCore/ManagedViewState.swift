import ObjectiveC
import UIKit

private enum QuickLayoutManagedViewStateAssociation {
    nonisolated(unsafe) static var zIndexOwnershipKey: UInt8 = 0
}

/// View state managed for the duration of QuickLayoutKit host render passes.
///
/// The store restores state from the preceding pass before recording the next
/// pass. Weak view references let removed-but-retained UIKit views recover their
/// original state without extending their lifetime.
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

            // A view can leave one host and enter another before its former
            // host renders again. Restore the former baseline during the
            // ownership transfer so the managed z-index never leaks hosts.
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
