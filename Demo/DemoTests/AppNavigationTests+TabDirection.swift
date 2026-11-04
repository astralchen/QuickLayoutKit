import AppLocalization
import Testing
import UIKit
@testable import Demo

extension AppNavigationTests {
    @Test func tabDirectionChangesPreserveSelectedChatAndDraft() async throws {
        guard #available(iOS 26.0, *) else { return }
        let previousLocale = Localization.localizationController.currentLocale.identifier
        let followedSystem = Localization.localizationController.followsSystemLocale
        Localization.setLocale(identifier: "zh-Hans")
        let tabs = AppTabBarController()
        let window = try makeVisibleTestWindow(rootViewController: tabs)
        window.makeKeyAndVisible()
        Localization.register(window: window)
        defer {
            Localization.unregister(window: window)
            window.isHidden = true
            Localization.setLocale(identifier: followedSystem
                ? LocalizationController.followSystemLocaleIdentifier : previousLocale)
        }
        tabs.select(.chat)
        let navigation = try #require(tabs.featureControllers[.chat] as? UINavigationController)
        let chat = try #require(navigation.viewControllers.first as? ChatViewController)
        #expect(await waitForCondition { !chat.isRestoringDraft })
        chat.composerView.textView.text = "语言切换保留草稿"
        chat.composerView.textView.selectedRange = NSRange(location: chat.composerView.textView.text.utf16.count, length: 0)
        chat.composerView.textView.becomeFirstResponder()
        #expect(await waitForCondition { chat.composerView.textView.isFirstResponder })
        var expectedDraft = "语言切换保留草稿"
        let originalModel = tabs.viewModel
        for language in ["ar", "zh-Hans", "en-US", "ar", "zh-Hans"] {
            Localization.setLocale(identifier: language)
            #expect(await waitForCondition {
                tabs.viewModel.state.items.first(where: { $0.id == .chat })?.title == Localization.text("app.tab.chat")
                    && chat.view.effectiveUserInterfaceLayoutDirection == Localization.currentUIKitDirection
            })
            try await Task.sleep(for: .milliseconds(300))
            window.layoutIfNeeded()
            #expect(tabs.selectedFeature == .chat)
            #expect(tabs.selectedViewController === navigation)
            #expect(tabs.viewModel === originalModel)
            #expect(navigation.viewControllers.first === chat)
            #expect(!chat.hasCleanedUpChat)
            #expect(chat.composerView.textView.text == expectedDraft)
            #expect(chat.composerView.textView.selectedRange == NSRange(location: expectedDraft.utf16.count, length: 0))
            #expect(chat.composerView.textView.isFirstResponder)
            #expect(window.rootViewController === tabs)
            #expect(navigation.tabBarController === tabs)
            chat.composerView.textView.insertText("续")
            expectedDraft += "续"
            #expect(chat.composerView.textView.text == expectedDraft)
            Localization.synchronize(window: window)
            #expect(window.rootViewController === tabs)
            #expect(chat.composerView.textView.isFirstResponder)
        }
    }

    @Test(arguments: ["zh-Hans", "ar", "en-US"])
    func tabLabelsKeepTheirOrientationAcrossLanguageRoundTrips(initialLanguage: String) async throws {
        let previousLocale = Localization.localizationController.currentLocale.identifier
        let followedSystem = Localization.localizationController.followsSystemLocale
        Localization.setLocale(identifier: initialLanguage)
        let tabs = AppTabBarController()
        let window = try makeVisibleTestWindow(rootViewController: tabs)
        window.makeKeyAndVisible()
        Localization.register(window: window)
        defer {
            Localization.unregister(window: window)
            window.isHidden = true
            Localization.setLocale(identifier: followedSystem
                ? LocalizationController.followSystemLocaleIdentifier : previousLocale)
        }
        let originalControllers = tabs.featureControllers
        let split = try #require(originalControllers[.examples] as? ExampleSplitViewController)
        split.select(.frame)
        let detail = try #require(split.detailNavigationController.viewControllers.first)
        let originalTabBar = tabs.tabBar
        var originalFloatingCollection: UICollectionView?

        for language in [initialLanguage, "zh-Hans", "en-US", "zh-Hans", "ar", "zh-Hans", "ar", "en-US", "zh-Hans"] {
            split.tabBarItem.badgeValue = "7"
            Localization.setLocale(identifier: language)
            let expectedDirection: UIUserInterfaceLayoutDirection = language == "ar" ? .rightToLeft : .leftToRight
            #expect(await waitForCondition {
                split.view.effectiveUserInterfaceLayoutDirection == expectedDirection
                    && tabs.featureControllers[.examples]?.tabBarItem.title == Localization.text("app.tab.examples")
            })
            // 让系统消费 trait、语义方向及标题更新后再检查最终绘制坐标。
            try await Task.sleep(nanoseconds: 300_000_000)
            window.layoutIfNeeded()
            #expect(tabs.tabBar === originalTabBar)
            #expect(split.tabBarItem.badgeValue == "7")
            let floatingCollections = tabs.view.allSubviews(of: UICollectionView.self).filter {
                NSStringFromClass(type(of: $0)) == "_UIFloatingTabBarCollectionView"
            }
            if tabs.traitCollection.userInterfaceIdiom == .pad,
               tabs.traitCollection.horizontalSizeClass == .regular {
                #expect(floatingCollections.count == 1)
            }
            if let originalFloatingCollection {
                #expect(floatingCollections.first === originalFloatingCollection)
            } else {
                originalFloatingCollection = floatingCollections.first
            }
            func expectReadableLabels() {
                let titles = tabs.viewModel.state.items.map(\.title)
                if let floatingCollection = floatingCollections.first {
                    let visibleTitles = floatingCollection.visibleCells.flatMap {
                        $0.allSubviews(of: UILabel.self)
                    }.filter { !$0.isHidden && $0.bounds.width > 0 }.compactMap(\.text)
                    for title in titles {
                        #expect(visibleTitles.contains(title), "Missing tab title \(title); visible: \(visibleTitles)")
                    }
                }
                let labels = tabs.view.allSubviews(of: UILabel.self).filter {
                    titles.contains($0.text ?? "") && !$0.isHidden && $0.bounds.width > 0
                }
                #expect(!labels.isEmpty)
                for label in labels {
                    let left = label.convert(CGPoint.zero, to: window)
                    let right = label.convert(CGPoint(x: label.bounds.width, y: 0), to: window)
                    #expect(right.x > left.x, "\(language): mirrored label \(label.text ?? "")")
                }
            }
            expectReadableLabels()
            // 防止只在语言切换结束时暂时正常，后续内容/尺寸更新又读到旧 RTL 缓存。
            let item = split.tabBarItem
            item?.badgeValue = language
            let originalBounds = window.bounds
            window.bounds.size.width = max(320, originalBounds.width - 40)
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            expectReadableLabels()
            window.bounds = originalBounds
            item?.badgeValue = nil
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            expectReadableLabels()
            #expect(window.rootViewController === tabs)
            #expect(tabs.traitCollection.layoutDirection == (language == "ar" ? .rightToLeft : .leftToRight))
            #expect(tabs.view.effectiveUserInterfaceLayoutDirection == expectedDirection)
            let logical = tabs.viewModel.state.items.compactMap { originalControllers[$0.id] }
            #expect(tabs.viewControllers == logical)
            #expect(tabs.selectedFeature == .examples)
            #expect(tabs.selectedViewController === split)
            #expect(split.detailNavigationController.viewControllers.first === detail)
            for (tab, controller) in originalControllers {
                #expect(tabs.featureControllers[tab] === controller)
            }
        }
    }
}
