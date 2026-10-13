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

    /// 在接收者的受管理视图状态作用域中同步执行渲染操作。
    ///
    /// 开始接收者的最外层渲染时，恢复上一轮管理的视图状态，并记录本轮更新。
    /// 渲染期间的内容边距声明在共享更新作用域中合并，按测量需要提前提交，
    /// 或在最外层边距更新作用域退出时提交。
    ///
    /// - Parameter operation: 用于构建、测量或放置宿主内容的同步操作。
    /// - Returns: `operation` 返回的值。
    /// - Throws: `operation` 抛出的错误。退出时仍完成作用域清理和待提交边距更新。
    package func withQuickLayoutManagedViewState<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        try QuickLayoutContentMarginTransaction.withUpdates {
            try quickLayoutManagedViewStateStore.withRenderPass(operation)
        }
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
