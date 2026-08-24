import UIKit

/// 控制独立 QuickLayout 宿主加入 UIKit 层级时是否恢复语义方向。
public enum QuickLayoutSemanticDirectionBehavior: Equatable, Sendable {
    /// 保持 `semanticContentAttribute` 不变。
    ///
    /// 这是默认行为，可避免隐式覆盖播放、空间和其他局部固定语义。
    case preserve

    /// 在附加、测量或布局前解析直接外层容器的有效方向。
    ///
    /// 对于可能在运行时切换语言期间被移除、复用，或者在容器和窗口之间移动的宿主，
    /// 使用此选项。
    case followEnclosingContainer

    /// 解析最近的公开 UIKit 复用视图边界的有效方向。
    ///
    /// 此选项适用于由 `UITableViewCell`、`UICollectionViewCell`、
    /// `UITableViewHeaderFooterView` 或 `UICollectionReusableView` 承载的内容。
    /// UIKit 可能在这些容器与应用内容之间插入私有配置宿主，因此运行时方向变化不能只跟随
    /// 直接父视图。
    case followEnclosingReusableView
}

@MainActor
@discardableResult
func synchronizeQuickLayoutSemanticDirectionIfNeeded(
    for view: UIView,
    behavior: QuickLayoutSemanticDirectionBehavior
) -> Bool {
    let container: UIView?
    switch behavior {
    case .preserve:
        container = nil
    case .followEnclosingContainer:
        container = view.superview
    case .followEnclosingReusableView:
        container = enclosingReusableView(for: view)
    }

    guard let container else {
        return false
    }

    let attribute: UISemanticContentAttribute =
        container.effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? .forceRightToLeft
            : .forceLeftToRight
    guard view.semanticContentAttribute != attribute else { return false }

    view.semanticContentAttribute = attribute
    return true
}

@MainActor
private func enclosingReusableView(for view: UIView) -> UIView? {
    var ancestor = view.superview
    while let current = ancestor {
        if current is UITableViewCell
            || current is UITableViewHeaderFooterView
            || current is UICollectionReusableView {
            return current
        }
        ancestor = current.superview
    }
    return nil
}
