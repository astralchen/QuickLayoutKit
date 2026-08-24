import UIKit

/// Controls whether a standalone QuickLayout host restores semantic direction
/// when it joins a UIKit hierarchy.
public enum QuickLayoutSemanticDirectionBehavior: Equatable, Sendable {
    /// Leaves `semanticContentAttribute` unchanged.
    ///
    /// This is the default so playback, spatial, and other locally fixed
    /// semantics are never overwritten implicitly.
    case preserve

    /// Resolves the direct enclosing container's effective direction before
    /// attachment, measurement, or layout work.
    ///
    /// Use this for hosts that can be detached during a runtime language
    /// switch, reused, or moved between containers and windows.
    case followEnclosingContainer

    /// Resolves the nearest public UIKit reusable-view boundary's effective
    /// direction.
    ///
    /// This is intended for content hosted by `UITableViewCell`,
    /// `UICollectionViewCell`, `UITableViewHeaderFooterView`, or
    /// `UICollectionReusableView`. UIKit may insert private configuration
    /// hosts between those owners and application content, so following the
    /// direct superview is not sufficient for runtime direction changes.
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
