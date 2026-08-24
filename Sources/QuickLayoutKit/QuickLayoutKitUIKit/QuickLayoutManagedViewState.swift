import ObjectiveC
import QuickLayoutKitCore
import UIKit

private enum QuickLayoutManagedViewStateAssociation {
    nonisolated(unsafe) static var storeKey: UInt8 = 0
}

@MainActor
extension UIView {

    package func withQuickLayoutManagedViewState<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        try quickLayoutManagedViewStateStore.withRenderPass(operation)
    }

    private var quickLayoutManagedViewStateStore:
        QuickLayoutManagedViewStateStore {
        if let store = objc_getAssociatedObject(
            self,
            &QuickLayoutManagedViewStateAssociation.storeKey
        ) as? QuickLayoutManagedViewStateStore {
            return store
        }

        let store = QuickLayoutManagedViewStateStore()
        objc_setAssociatedObject(
            self,
            &QuickLayoutManagedViewStateAssociation.storeKey,
            store,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return store
    }
}
