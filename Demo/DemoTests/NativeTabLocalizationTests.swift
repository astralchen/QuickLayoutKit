import AppLocalization
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct NativeTabLocalizationTests {
    @Test
    func legacyBoundaryPreservesChildSemanticExceptions() {
        let boundary = UIView()
        let playback = UIView()
        let spatial = UIView()
        let fixedLTR = UIView()
        playback.semanticContentAttribute = .playback
        spatial.semanticContentAttribute = .spatial
        fixedLTR.semanticContentAttribute = .forceLeftToRight
        [playback, spatial, fixedLTR].forEach(boundary.addSubview)

        Localization.applyBoundary(.forceRightToLeft, to: boundary)
        if #available(iOS 17.0, *) {
            #expect(boundary.semanticContentAttribute == .unspecified)
        } else {
            #expect(boundary.semanticContentAttribute == .forceRightToLeft)
        }
        #expect(playback.semanticContentAttribute == .playback)
        #expect(spatial.semanticContentAttribute == .spatial)
        #expect(fixedLTR.semanticContentAttribute == .forceLeftToRight)
        Localization.applyBoundary(.unspecified, to: boundary)
        #expect(boundary.semanticContentAttribute == .unspecified)
        #expect(playback.semanticContentAttribute == .playback)
        #expect(spatial.semanticContentAttribute == .spatial)
        #expect(fixedLTR.semanticContentAttribute == .forceLeftToRight)
    }

    @Test
    func followingSystemRestoresResolvedDirectionWithoutOverwritingLocalSemantics() throws {
        let localization = LocalizationController(
            resourceBundle: .main,
            preferenceStore: InMemoryLocalePreferenceStore(localeIdentifier: "ar"),
            systemLocaleIdentifiersProvider: { ["en"] }
        )
        let coordinator = UIWindowSceneLocalizationCoordinator(localizationController: localization)
        let page = UIViewController()
        let inherited = UIView()
        let fixed = UIView()
        fixed.semanticContentAttribute = .forceLeftToRight
        page.view.addSubview(inherited)
        page.view.addSubview(fixed)
        let window = try makeVisibleTestWindow(rootViewController: page)
        coordinator.register(window: window)
        defer { coordinator.unregister(window: window); window.isHidden = true }
        #expect(inherited.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(fixed.effectiveUserInterfaceLayoutDirection == .leftToRight)
        fixed.semanticContentAttribute = .unspecified
        #expect(fixed.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        fixed.semanticContentAttribute = .forceLeftToRight
        localization.setFollowsSystemLocale()
        #expect(localization.followsSystemLocale)
        #expect(localization.currentLocale.identifier == "en")
        #expect(inherited.semanticContentAttribute == .unspecified)
        #expect(inherited.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(fixed.semanticContentAttribute == .forceLeftToRight)
    }

    @Test
    func coordinatorSynchronizesTabTraitsBeforeChildRefresh() throws {
        let localization = LocalizationController(
            resourceBundle: .main,
            preferenceStore: InMemoryLocalePreferenceStore(localeIdentifier: "zh-Hans")
        )
        localization.setLocale(identifier: "zh-Hans")
        let coordinator = UIWindowSceneLocalizationCoordinator(localizationController: localization)
        let child = DirectionRecordingPage()
        let tabs = UITabBarController()
        tabs.viewControllers = [child, UIViewController()]
        let window = try makeVisibleTestWindow(rootViewController: tabs)
        child.loadViewIfNeeded()
        coordinator.register(window: window)
        defer { coordinator.unregister(window: window); window.isHidden = true }
        for language in ["zh-Hans", "ar", "zh-Hans", "ar", "zh-Hans"] {
            localization.setLocale(identifier: language)
            coordinator.synchronize(window: window)
            let expected: UITraitEnvironmentLayoutDirection = language == "ar" ? .rightToLeft : .leftToRight
            #expect(tabs.traitCollection.layoutDirection == expected)
            #expect(child.observedContainerDirection == expected)
            #expect(tabs.view.effectiveUserInterfaceLayoutDirection == localization.layoutDirection)
            #expect(tabs.tabBar.effectiveUserInterfaceLayoutDirection == localization.layoutDirection)
            #expect(window.rootViewController === tabs)
            #expect(tabs.selectedViewController === child)
        }
    }
}

@MainActor
private final class DirectionRecordingPage: UIViewController, UIKitLocalizationApplying {
    var observedContainerDirection: UITraitEnvironmentLayoutDirection?
    func applyLocalization(_ update: LocalizationUpdate) {
        observedContainerDirection = tabBarController?.traitCollection.layoutDirection
    }
}
