//
//  DemoLocalizedViewControllers.swift
//  Demo
//
//  Created by Codex on 2026/6/2.
//

import UIKit
import AppLocalization
import QuickLayoutKit

class DemoQuickLayoutHostingController: QuickLayoutHostingController, UIKitLocalizationApplying {
    var localizedTitleKey: String? { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        installDemoLanguageMenu()
        applyLocalization(
            .initial(snapshot: DemoLocalization.localizationController.currentSnapshot)
        )
    }

    func applyLocalization(_ update: UIKitLocalizationUpdate) {
        if update.requiresLayoutDirectionRefresh {
            UIViewLayoutDirectionUpdater.apply(
                update,
                to: [UIViewLayoutDirectionTarget(view, policy: .followApplication)]
            )
            reloadLayoutDirection(update.layoutDirection)
        }
        if update.requiresLocalizedContentRefresh {
            reloadLocalizedContent()
        }
    }

    func reloadLocalizedContent() {
        if let localizedTitleKey {
            title = DemoLocalization.text(localizedTitleKey)
            navigationItem.title = title
        }
        reloadDemoLanguageMenu()
        setNeedsQuickLayout()
    }

    func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        applyDemoLayoutDirection(direction)
        setNeedsQuickLayout()
    }
}

class DemoViewController: UIViewController, UIKitLocalizationApplying {
    var localizedTitleKey: String? { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        installDemoLanguageMenu()
        applyLocalization(
            .initial(snapshot: DemoLocalization.localizationController.currentSnapshot)
        )
    }

    func applyLocalization(_ update: UIKitLocalizationUpdate) {
        if update.requiresLayoutDirectionRefresh {
            UIViewLayoutDirectionUpdater.apply(
                update,
                to: [UIViewLayoutDirectionTarget(view, policy: .followApplication)]
            )
            reloadLayoutDirection(update.layoutDirection)
        }
        if update.requiresLocalizedContentRefresh {
            reloadLocalizedContent()
        }
    }

    func reloadLocalizedContent() {
        if let localizedTitleKey {
            title = DemoLocalization.text(localizedTitleKey)
            navigationItem.title = title
        }
        reloadDemoLanguageMenu()
    }

    func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        applyDemoLayoutDirection(direction)
    }
}

#Preview {
   UINavigationController(rootViewController: DemoQuickLayoutHostingController())
}
