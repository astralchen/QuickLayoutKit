import UIKit
import Testing
@testable import Demo

/// 以原生控制器边界驱动媒体子树，不把宿主的 semantic 强制复制到子视图。
@MainActor
final class MediaDirectionTestHost {
    let parent = UIViewController()
    let content: UIViewController
    let window: UIWindow

    init(content: UIViewController = UIViewController()) throws {
        self.content = content
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.rootViewController = parent
        parent.addChild(content)
        parent.view.addSubview(content.view)
        content.view.frame = window.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.didMove(toParent: parent)
        window.isHidden = false
    }

    /// unspecified 撤销本地边界，恢复从父控制器／Scene 继承。
    func setBoundary(_ semantic: UISemanticContentAttribute) {
        precondition([.unspecified, .forceLeftToRight, .forceRightToLeft].contains(semantic))
        let direction: UITraitEnvironmentLayoutDirection = semantic == .forceRightToLeft ? .rightToLeft : .leftToRight
        if #available(iOS 17.0, *) {
            if semantic == .unspecified {
                content.traitOverrides.remove(UITraitLayoutDirection.self)
            } else {
                content.traitOverrides.layoutDirection = direction
            }
            content.updateTraitsIfNeeded()
            content.view.updateTraitsIfNeeded()
        } else {
            parent.setOverrideTraitCollection(
                semantic == .unspecified ? nil : UITraitCollection(layoutDirection: direction),
                forChild: content
            )
            Localization.applyBoundary(semantic, to: content.view)
        }
        content.view.setNeedsLayout()
        window.layoutIfNeeded()
        content.view.layoutIfNeeded()
    }
}
