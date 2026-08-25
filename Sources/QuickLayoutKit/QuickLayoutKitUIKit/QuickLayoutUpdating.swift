import UIKit

/// 能够使 QuickLayout 内容失效并立即执行布局的类型。
@MainActor
public protocol QuickLayoutUpdating: AnyObject {

    /// 将宿主 QuickLayout 内容标记为需要更新。
    func setNeedsQuickLayout()

    /// 根据需要立即布局宿主 QuickLayout 内容。
    func quickLayoutIfNeeded()
}

extension QuickLayoutUpdating where Self: UIView {

    /// 在 UIKit 动画中更新并布局 QuickLayout 内容。
    ///
    /// - Parameters:
    ///   - duration: 动画持续时间。
    ///   - delay: 动画开始前的延迟时间。
    ///   - options: UIKit 动画选项。
    ///   - animations: 与布局更新同时执行的附加动画；`nil` 表示只执行 QuickLayout
    ///     失效与布局。
    ///   - completion: 动画结束时调用的闭包；`nil` 表示不发送应用完成回调。
    public func performLayoutUpdate(
        duration: TimeInterval,
        delay: TimeInterval = 0,
        options: UIView.AnimationOptions = [],
        animations: (() -> Void)? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        setNeedsQuickLayout()
        UIView.animate(
            withDuration: duration,
            delay: delay,
            options: options,
            animations: {
                animations?()
                self.quickLayoutIfNeeded()
            },
            completion: completion
        )
    }
}

extension QuickLayoutUpdating where Self: UIViewController {

    /// 在 UIKit 动画中更新并布局 QuickLayout 内容。
    ///
    /// - Parameters:
    ///   - duration: 动画持续时间。
    ///   - delay: 动画开始前的延迟时间。
    ///   - options: UIKit 动画选项。
    ///   - animations: 与布局更新同时执行的附加动画；`nil` 表示只执行 QuickLayout
    ///     失效与布局。
    ///   - completion: 动画结束时调用的闭包；`nil` 表示不发送应用完成回调。
    public func performLayoutUpdate(
        duration: TimeInterval,
        delay: TimeInterval = 0,
        options: UIView.AnimationOptions = [],
        animations: (() -> Void)? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        setNeedsQuickLayout()
        UIView.animate(
            withDuration: duration,
            delay: delay,
            options: options,
            animations: {
                animations?()
                self.quickLayoutIfNeeded()
            },
            completion: completion
        )
    }
}
