//
//  Localization.swift
//  Demo
//
//  Created by Codex on 2026/6/2.
//

import UIKit
import AppLocalization

@MainActor
enum Localization {
    private static let languageMenuItemAccessibilityIdentifier =
        "demo.language.menu"

    static let localizationController = LocalizationController(
        resourceBundle: .main,
        preferenceStore: UserDefaultsLocalePreferenceStore(
            key: "quicklayoutkit.demo.locale.identifier"
        )
    )

    static let resolver = LocalizedStringResolver(
        localeProvider: { localizationController.currentLocale },
        fallbackLocale: AppLocale(identifier: localizationController.fallbackLocalization),
        missingKeyHandler: { key, locale, _ in
            assertionFailure("Missing localization key '\(key)' for \(locale.identifier)")
        }
    )

    private static let sceneCoordinator = UIWindowSceneLocalizationCoordinator(
        localizationController: localizationController
    )

    static var currentLayoutDirection: UIUserInterfaceLayoutDirection {
        localizationController.layoutDirection
    }

    static var currentUIKitDirection: UIUserInterfaceLayoutDirection {
        currentLayoutDirection
    }

    static var currentUIKitUpdate: LocalizationUpdate {
        .init(snapshot: localizationController.currentSnapshot)
    }

    /// 用于 iOS 15/16 中由 App 管理的视图的兼容边界。
    /// 不递归覆盖子视图，以保留 playback、spatial 和固定 LTR 等语义例外。
    /// 显式传入 `.unspecified` 可撤销此边界的强制方向，恢复 UIKit 继承。
    static func applyBoundary(_ semantic: UISemanticContentAttribute, to view: UIView) {
        if #available(iOS 17.0, *) { return }
        view.semanticContentAttribute = semantic
    }

    /// 独立方向演示的局部更新；应用语言切换使用控制器发布的真实快照。
    static func layoutDirectionUpdate(
        _ direction: UIUserInterfaceLayoutDirection
    ) -> LocalizationUpdate {
        let snapshot = localizationController.currentSnapshot
        guard direction != snapshot.layoutDirection else {
            return LocalizationUpdate(snapshot: snapshot)
        }
        return LocalizationUpdate(snapshot: LocalizationSnapshot(
            locale: AppLocale(identifier: direction == .rightToLeft ? "ar" : "en"),
            followsSystemLocale: snapshot.followsSystemLocale,
            revision: snapshot.revision
        ))
    }

    static func start() {
        // 协调器直接参与控制器事务；持有实例即可，不再异步转发完成通知。
        _ = sceneCoordinator
    }

    static func register(window: UIWindow) {
        sceneCoordinator.register(window: window)
    }

    static func unregister(window: UIWindow) {
        sceneCoordinator.unregister(window: window)
    }

    static func synchronize(window: UIWindow) {
        sceneCoordinator.synchronize(window: window)
    }

    @discardableResult
    static func setLocale(identifier: String) -> Bool {
        if identifier == LocalizationController.followSystemLocaleIdentifier {
            return localizationController.setFollowsSystemLocale()
        }

        return localizationController.setLocale(identifier: identifier)
    }

    @discardableResult
    static func refreshSystemLocaleIfNeeded() -> Bool {
        localizationController.refreshSystemLocaleIfNeeded()
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        resolver.string(key, bundle: .main, arguments: arguments)
    }

    static func text(_ key: String) -> String {
        resolver.string(key, bundle: .main)
    }

    /// 按当前应用语言格式化比例；例如 `0.72` 在英文下显示为 `72%`。
    static func percent(_ value: Double) -> String {
        value.formatted(.percent.locale(localizationController.locale))
    }

    static func localeDisplayName(_ locale: AppLocale) -> String {
        locale.localizedDisplayName(preferredBy: localizationController.currentLocale)
    }

    static func currentLanguageSummary() -> String {
        if localizationController.followsSystemLocale {
            return "\(text("language.follow.system")) (\(localizationController.currentLocale.identifier))"
        }

        return localizationController.currentLocale.identifier
    }

    static func installLanguageMenu(on viewController: UIViewController) {
        // 确保应用协调器已经创建；预览窗口由预览宿主显式注册。
        start()
        let item = UIBarButtonItem(
            image: UIImage(systemName: "globe"),
            primaryAction: nil,
            menu: languageMenu()
        )
        item.accessibilityLabel = text("language.menu.accessibility")
        item.accessibilityIdentifier = languageMenuItemAccessibilityIdentifier
        viewController.navigationItem.rightBarButtonItem = item
    }

    static func reloadLanguageMenu(on viewController: UIViewController) {
        let navigationItem = viewController.navigationItem
        guard let item = [
            navigationItem.leftBarButtonItem,
            navigationItem.rightBarButtonItem,
        ]
            .compactMap({ $0 })
            .first(where: {
                $0.accessibilityIdentifier
                    == languageMenuItemAccessibilityIdentifier
            }) else {
            return
        }

        item.menu = languageMenu()
        item.accessibilityLabel = text("language.menu.accessibility")
    }

    static func languageMenu() -> UIMenu {
        let follow = UIAction(
            title: text("language.follow.system"),
            subtitle: localeDisplayName(localizationController.currentLocale),
            image: localizationController.followsSystemLocale ? UIImage(systemName: "checkmark") : nil
        ) { _ in
            Task { @MainActor in
                setLocale(identifier: LocalizationController.followSystemLocaleIdentifier)
            }
        }

        let localeActions = localizationController.supportedLocalizations.map { identifier in
            let locale = AppLocale(identifier: identifier)
            return UIAction(
                title: locale.nativeDisplayName,
                subtitle: localeDisplayName(locale),
                image: (!localizationController.followsSystemLocale && locale == localizationController.currentLocale) ? UIImage(systemName: "checkmark") : nil
            ) { _ in
                Task { @MainActor in
                    setLocale(identifier: locale.identifier)
                }
            }
        }

        return UIMenu(
            title: text("language.menu.title"),
            image: UIImage(systemName: "globe"),
            children: [follow] + localeActions
        )
    }

}

extension UIViewController {
    @MainActor
    func installLanguageMenu() {
        Localization.installLanguageMenu(on: self)
    }

    @MainActor
    func reloadLanguageMenu() {
        Localization.reloadLanguageMenu(on: self)
    }

    @MainActor
    func applyLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        Localization.applyBoundary(
            direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight,
            to: view
        )
    }
}
