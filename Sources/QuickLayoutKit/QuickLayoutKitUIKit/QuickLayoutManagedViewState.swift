import ObjectiveC
import QuickLayoutKitCore
import UIKit

/// 保存宿主受管理视图状态存储的关联键。
private enum QuickLayoutManagedViewStateAssociation {
    /// 状态存储关联对象的唯一键地址。
    nonisolated(unsafe) static var storeKey: UInt8 = 0
}

@MainActor
extension UIView {

    /// 在宿主渲染作用域中执行操作，进入下一轮时恢复先前管理的视图状态。
    package func withQuickLayoutManagedViewState<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        try quickLayoutManagedViewStateStore.withRenderPass(operation)
    }

    /// 延迟创建并与当前视图关联的状态存储。
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
