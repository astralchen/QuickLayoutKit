import AppLocalization
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct NativeTabLocalizationTests {
    @Test
    func coordinatorSynchronizesTabTraitsBeforeChildRefresh() throws {
        let localization = LocalizationController(
            supportedLocales: [.simplifiedChinese, .arabic],
            fallbackLocale: .simplifiedChinese,
            preferenceStore: InMemoryLocalePreferenceStore(localeIdentifier: "zh-Hans")
        )
        localization.setLocale(identifier: "zh-Hans")
        let coordinator = UIWindowSceneLocalizationCoordinator(localizationController: localization)
        let child = DirectionRecordingPage()
        let tabs = UITabBarController()
        tabs.viewControllers = [child, UIViewController()]
        let window = try makeVisibleTestWindow(rootViewController: tabs)
        window.traitOverrides.layoutDirection = .rightToLeft
        child.loadViewIfNeeded()
        coordinator.register(window: window)
        defer { coordinator.unregister(window: window); window.isHidden = true }
        for language in ["zh-Hans", "ar", "zh-Hans", "ar", "zh-Hans"] {
            localization.setLocale(identifier: language)
            coordinator.synchronize(window: window)
            let expected: UITraitEnvironmentLayoutDirection = language == "ar" ? .rightToLeft : .leftToRight
            #expect(tabs.traitCollection.layoutDirection == expected)
            #expect(child.observedContainerDirection == expected)
            #expect(tabs.view.semanticContentAttribute == (language == "ar" ? .forceRightToLeft : .forceLeftToRight))
            #expect(tabs.tabBar.semanticContentAttribute == tabs.view.semanticContentAttribute)
            #expect(window.rootViewController === tabs)
            #expect(tabs.selectedViewController === child)
        }
    }
}

@MainActor
private final class DirectionRecordingPage: UIViewController, UIKitLocalizationApplying {
    var observedContainerDirection: UITraitEnvironmentLayoutDirection?
    func applyLocalization(_ update: UIKitLocalizationUpdate) {
        observedContainerDirection = tabBarController?.traitCollection.layoutDirection
    }
}
