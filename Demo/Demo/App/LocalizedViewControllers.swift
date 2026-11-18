//
//  LocalizedViewControllers.swift
//  Demo
//
//  Created by Codex on 2026/6/2.
//

import UIKit
import AppLocalization
import QuickLayoutKit

/// 两种基础控制器共用刷新顺序；各页面的方向钩子负责自己拥有的视图边界。
@MainActor
private enum LocalizedScreenUpdater {
    static func apply(
        _ update: LocalizationUpdate,
        reloadDirection: (UIUserInterfaceLayoutDirection) -> Void,
        reloadContent: () -> Void
    ) {
        if update.requiresLayoutDirectionRefresh {
            reloadDirection(update.layoutDirection)
        }
        if update.requiresLocalizedContentRefresh {
            reloadContent()
        }
    }

    static func reloadTitle(on controller: UIViewController, key: String?) {
        if let key {
            controller.title = Localization.text(key)
            controller.navigationItem.title = controller.title
        }
        controller.reloadLanguageMenu()
    }
}

/// 将父级有效方向变化送到页面刷新钩子；继承刷新不能重新建立强制边界。
@MainActor
private final class LocalizedScreenDirectionState {
    private var renderedDirection: UIUserInterfaceLayoutDirection?
    private var isRefreshingInheritance = false

    func didApply(_ direction: UIUserInterfaceLayoutDirection, on controller: UIViewController) {
        renderedDirection = direction
        if !isRefreshingInheritance { controller.applyLayoutDirection(direction) }
    }

    func refresh(on controller: UIViewController, reload: (UIUserInterfaceLayoutDirection) -> Void) {
        let direction = controller.view.effectiveUserInterfaceLayoutDirection
        guard renderedDirection != direction else { return }
        renderedDirection = direction
        isRefreshingInheritance = true
        defer { isRefreshingInheritance = false }
        reload(direction)
    }
}

class LocalizedQuickLayoutHostingController: QuickLayoutHostingController, UIKitLocalizationApplying {
    var localizedTitleKey: String? { nil }
    private let directionState = LocalizedScreenDirectionState()

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        directionState.refresh(on: self, reload: reloadLayoutDirection)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // iOS 15/16 同样经过此入口；挂载和撤销局部覆盖由布局阶段复核。
        viewIfLoaded?.setNeedsLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installLanguageMenu()
        applyLocalization(
            .init(snapshot: Localization.localizationController.currentSnapshot)
        )
    }

    func applyLocalization(_ update: LocalizationUpdate) {
        LocalizedScreenUpdater.apply(
            update,
            reloadDirection: reloadLayoutDirection,
            reloadContent: reloadLocalizedContent
        )
    }

    func reloadLocalizedContent() {
        LocalizedScreenUpdater.reloadTitle(on: self, key: localizedTitleKey)
        setNeedsQuickLayout()
    }

    func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        directionState.didApply(direction, on: self)
        setNeedsQuickLayout()
    }
}

class LocalizedViewController: UIViewController, UIKitLocalizationApplying {
    var localizedTitleKey: String? { nil }
    private let directionState = LocalizedScreenDirectionState()

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        directionState.refresh(on: self, reload: reloadLayoutDirection)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // iOS 15/16 同样经过此入口；挂载和撤销局部覆盖由布局阶段复核。
        viewIfLoaded?.setNeedsLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installLanguageMenu()
        applyLocalization(
            .init(snapshot: Localization.localizationController.currentSnapshot)
        )
    }

    func applyLocalization(_ update: LocalizationUpdate) {
        LocalizedScreenUpdater.apply(
            update,
            reloadDirection: reloadLayoutDirection,
            reloadContent: reloadLocalizedContent
        )
    }

    func reloadLocalizedContent() {
        LocalizedScreenUpdater.reloadTitle(on: self, key: localizedTitleKey)
    }

    func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        directionState.didApply(direction, on: self)
    }
}

@available(iOS 17.0, *)
#Preview {
   UINavigationController(rootViewController: LocalizedQuickLayoutHostingController())
}
