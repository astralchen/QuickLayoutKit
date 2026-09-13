import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct MainNavigationRTLTests {
    @MainActor
    private final class InputLocaleState {
        var locale: AppLocale = .simplifiedChinese { didSet { revision += 1 } }
        private var revision: UInt64 = 0
        var snapshot: LocalizationSnapshot {
            LocalizationSnapshot(locale: locale, followsSystemLocale: false, revision: revision)
        }
    }

    @Test func inputBindingsPreserveCaretAndCompositionInARealWindow() async throws {
        for kind in ["field", "secure", "multiline"] {
            let controller = UIViewController()
            let view: UIView = kind == "multiline" ? UITextView() : UITextField()
            view.frame = CGRect(x: 20, y: 150, width: 310, height: kind == "multiline" ? 140 : 44)
            controller.view.addSubview(view)
            let window = try makeVisibleTestWindow(rootViewController: controller)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            let state = InputLocaleState()
            let context = UIKitLocalizationContext {
                state.snapshot
            }
            let binding: UIKitTextInputLocalizationBinding
            if let field = view as? UITextField {
                field.isSecureTextEntry = kind == "secure"
                field.autocorrectionType = .no
                binding = context.makeTextInputBinding(to: field)
            } else {
                binding = context.makeTextInputBinding(to: view as! UITextView)
            }
            let input = view as! any UITextInput
            view.becomeFirstResponder()
            try #require(await waitForCondition { view.isFirstResponder })
            for next in [AppLocale.simplifiedChinese, .arabic, .englishUS, .arabic] {
                state.locale = next
                binding.refresh()
                for text in ["", "VV77", "uu天", "مرحبا", ""] {
                    input.selectedTextRange = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)
                    if text.isEmpty { input.deleteBackward() } else { input.insertText(text) }
                    let rtl = next == .arabic
                    #expect(await waitForCondition {
                        view.layoutIfNeeded()
                        let start = view.convert(input.caretRect(for: input.beginningOfDocument), from: input.textInputView)
                        let end = view.convert(input.caretRect(for: input.endOfDocument), from: input.textInputView)
                        let edge = rtl ? max(start.midX, end.midX) : min(start.midX, end.midX)
                        return rtl ? edge > view.bounds.midX : edge < view.bounds.midX
                    }, "控件：\(kind)，语言：\(next.identifier)，文本：\(text)")
                }
            }
            if kind != "secure" {
                state.locale = .simplifiedChinese
                binding.refresh()
                input.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0))
                try #require(input.markedTextRange != nil)
                state.locale = .arabic
                binding.refresh()
                #expect(input.markedTextRange != nil)
                #expect(view.isFirstResponder)
                // 通过真实 UITextInput 提交组合文本，不伪造编辑通知。
                input.insertText("中")
                #expect(await waitForCondition {
                    input.markedTextRange == nil
                        && ((view as? UITextField)?.textAlignment ?? (view as? UITextView)?.textAlignment) == .right
                })
                #expect(input.text(in: input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)!) == "中")
            }
            view.resignFirstResponder()
            view.becomeFirstResponder()
            #expect(view.isFirstResponder)
            withExtendedLifetime(binding) {}
        }
    }

    @Test func formAndKeyboardInputsRefreshAcrossLanguageChanges() async throws {
        defer { Localization.setLocale(identifier: "zh-Hans") }
        for controller in [ScrollViewWithKeyboardViewController(), KeyboardHandlingViewController()] as [LocalizedQuickLayoutHostingController] {
            let navigation = UINavigationController(rootViewController: controller)
            let window = try makeVisibleTestWindow(rootViewController: navigation)
            window.makeKeyAndVisible()
            Localization.register(window: window)
            defer {
                Localization.unregister(window: window)
                window.isHidden = true
            }
            let fields = controller.view.allSubviews(of: UITextField.self)
            let notes = controller.view.allSubviews(of: UITextView.self).filter(\.isEditable)
            try #require(!fields.isEmpty)
            for language in ["zh-Hans", "ar", "en-US", "ar"] {
                Localization.setLocale(identifier: language)
                let expected: NSTextAlignment = language == "ar" ? .right : .left
                #expect(await waitForCondition {
                    fields.allSatisfy { $0.textAlignment == expected }
                        && notes.allSatisfy { $0.textAlignment == expected }
                })
                for field in fields {
                    field.becomeFirstResponder()
                    field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
                    field.insertText("uu天123")
                    #expect(await waitForCondition { field.textAlignment == expected })
                    #expect(field.text == "uu天123")
                    field.resignFirstResponder()
                }
            }
        }
    }

    @Test func localizedTextViewKeepsUndoHistory() async throws {
        let controller = UIViewController()
        let view = UITextView(frame: CGRect(x: 20, y: 150, width: 310, height: 140))
        controller.view.addSubview(view)
        let window = try makeVisibleTestWindow(rootViewController: controller)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let state = InputLocaleState()
        let binding = UIKitLocalizationContext {
            state.snapshot
        }.makeTextInputBinding(to: view)
        view.becomeFirstResponder()
        try #require(await waitForCondition { view.isFirstResponder })
        let undo = try #require(view.undoManager)
        undo.beginUndoGrouping()
        view.insertText("hello")
        undo.endUndoGrouping()
        state.locale = .arabic
        binding.refresh()
        #expect(undo.canUndo)
        undo.undo()
        #expect(view.text.isEmpty)
        #expect(view.isFirstResponder)
    }

    @Test func searchCaretAndTextFollowInterfaceAlignment() async throws {
        Localization.setLocale(identifier: "ar")
        let main = MainViewController()
        let navigation = UINavigationController(rootViewController: main)
        let window = try makeVisibleTestWindow(rootViewController: navigation, size: CGSize(width: 390, height: 844))
        window.makeKeyAndVisible()
        Localization.register(window: window)
        let search = try #require(main.navigationItem.searchController)
        let field = search.searchBar.searchTextField
        defer {
            search.isActive = false
            Localization.unregister(window: window)
            window.isHidden = true
            Localization.setLocale(identifier: "en-US")
        }
        search.isActive = true
        #expect(await waitForCondition { field.window != nil })
        field.becomeFirstResponder()
        #expect(await waitForCondition { field.isFirstResponder && field.bounds.width > 100 })

        for language in ["ar", "zh-Hans", "en-US", "ar"] {
            Localization.setLocale(identifier: language)
            try #require(await waitForCondition {
                main.title == Localization.text("main.title")
                    && navigation.navigationBar.traitCollection.layoutDirection == (language == "ar" ? .rightToLeft : .leftToRight)
            }, "语言：\(language)，当前：\(Localization.currentLanguageSummary())，标题：\(main.title ?? "nil")")
            let isRTL = language == "ar"
            // 空内容、英文数字、中文混排、阿拉伯文都应对齐到界面的同一侧。
            for text in ["", "VV77", "uu天", "مرحبا", ""] {
                field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
                if text.isEmpty {
                    field.deleteBackward()
                } else {
                    field.insertText(text)
                }
                var start = CGRect.zero
                var end = CGRect.zero
                // UIKit 编辑布局可能延迟到下一轮主线程，等待实际光标几何完成更新。
                let aligned = await waitForCondition {
                    navigation.view.layoutIfNeeded()
                    field.layoutIfNeeded()
                    start = field.convert(field.caretRect(for: field.beginningOfDocument), from: field.textInputView)
                    end = field.convert(field.caretRect(for: field.endOfDocument), from: field.textInputView)
                    let edge = isRTL ? max(start.midX, end.midX) : min(start.midX, end.midX)
                    let followsWritingOrder = text.isEmpty || (text == "مرحبا"
                        ? start.minX > end.minX : start.minX < end.minX)
                    return followsWritingOrder && (isRTL ? edge > field.bounds.midX : edge < field.bounds.midX)
                }
                #expect(aligned,
                        "语言：\(language)，文本：\(text)，实际文本：\(field.text ?? "")，对齐：\(field.textAlignment.rawValue)，起点：\(start)，终点：\(end)，输入框：\(field.bounds)")
            }
            field.resignFirstResponder()
            field.becomeFirstResponder()
            navigation.view.layoutIfNeeded()
            let emptyCaret = field.convert(field.caretRect(for: field.beginningOfDocument), from: field.textInputView)
            #expect(isRTL ? emptyCaret.midX > field.bounds.midX : emptyCaret.midX < field.bounds.midX)
        }
    }

    @Test(arguments: ["zh-Hans", "ar"])
    func mainNavigationEnvironmentFollowsRuntimeLanguageChanges(initialLanguage: String) async throws {
        Localization.setLocale(identifier: initialLanguage)
        let main = MainViewController()
        let navigation = UINavigationController(rootViewController: main)
        let window = try makeVisibleTestWindow(
            rootViewController: navigation,
            size: CGSize(width: 390, height: 844),
            contentSizeCategory: .large
        )
        Localization.register(window: window)
        defer {
            Localization.unregister(window: window)
            window.isHidden = true
            Localization.setLocale(identifier: "en-US")
        }

        for identifier in [initialLanguage, "ar", "zh-Hans", "ar"] {
            Localization.setLocale(identifier: identifier)
            #expect(await waitForCondition {
                main.title == Localization.text("main.title")
                    && main.collectionView.effectiveUserInterfaceLayoutDirection
                        == Localization.currentUIKitDirection
            })
            let isRTL = identifier == "ar"
            #expect(await waitForCondition {
                navigation.navigationBar.traitCollection.layoutDirection
                    == (isRTL ? .rightToLeft : .leftToRight)
            })
            #expect(navigation.navigationBar.effectiveUserInterfaceLayoutDirection
                == Localization.currentUIKitDirection)
            #expect(main.navigationItem.largeTitleDisplayMode == .always)
            #expect(main.navigationItem.titleView == nil)
            #expect(main.contentScrollView(for: .top) === main.collectionView)
        }
    }

    @Test func rapidLanguageChangesPreserveThePendingDirectionChange() async throws {
        Localization.setLocale(identifier: "ar")
        let main = MainViewController()
        let navigation = UINavigationController(rootViewController: main)
        let window = try makeVisibleTestWindow(rootViewController: navigation, size: CGSize(width: 390, height: 844))
        Localization.register(window: window)
        defer {
            Localization.unregister(window: window)
            window.isHidden = true
            Localization.setLocale(identifier: "en-US")
        }
        #expect(await waitForCondition { navigation.navigationBar.traitCollection.layoutDirection == .rightToLeft })
        // 中间通知尚未执行时继续选择同方向语言，最终仍必须刷新导航容器。
        Localization.setLocale(identifier: "zh-Hans")
        Localization.setLocale(identifier: "en-US")
        #expect(await waitForCondition {
            main.title == Localization.text("main.title")
                && navigation.navigationBar.traitCollection.layoutDirection == .leftToRight
                && main.collectionView.effectiveUserInterfaceLayoutDirection == .leftToRight
        })
    }

    @Test func mainControllerReleasesAfterConfiguringItsList() async throws {
        weak var retained: MainViewController?
        autoreleasepool {
            let main = MainViewController()
            retained = main
            main.loadViewIfNeeded()
            main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            main.view.layoutIfNeeded()
        }
        #expect(await waitForCondition { retained == nil })
    }

    @Test(arguments: ["zh-Hans", "ar"])
    func languageChangesPreserveTheVisibleRoute(initialLanguage: String) async throws {
        Localization.setLocale(identifier: initialLanguage)
        let main = MainViewController()
        let navigation = UINavigationController(rootViewController: main)
        let window = try makeVisibleTestWindow(rootViewController: navigation, size: CGSize(width: 390, height: 844))
        Localization.register(window: window)
        defer {
            Localization.unregister(window: window)
            window.isHidden = true
            Localization.setLocale(identifier: "en-US")
        }
        #expect(await waitForCondition { main.collectionView.numberOfItems(inSection: 0) > 10 })
        main.collectionView.scrollToItem(at: IndexPath(item: 10, section: 0), at: .top, animated: false)
        main.collectionView.contentOffset.y += 17
        // 等待导航栏完成滚动联动，再记录用户实际看到的条目与偏移。
        try await Task.sleep(nanoseconds: 100_000_000)
        let before = try #require(main.collectionView.captureLocalizationAnchor())
        for language in [initialLanguage == "ar" ? "zh-Hans" : "ar", initialLanguage] {
            Localization.setLocale(identifier: language)
            let restored = await waitForCondition {
                navigation.view.layoutIfNeeded()
                guard main.title == Localization.text("main.title"),
                      let after = main.collectionView.captureLocalizationAnchor() else { return false }
                return main.collectionView.effectiveUserInterfaceLayoutDirection == Localization.currentUIKitDirection
                    && after.indexPath == before.indexPath
                    && abs(after.offsetFromViewportTop - before.offsetFromViewportTop) < 2
            }
            let after = main.collectionView.captureLocalizationAnchor()
            #expect(restored, "语言：\(language)，原位置：\(before)，实际位置：\(String(describing: after))")
        }
    }

    @Test func directionUpdatesPreserveTheActualLanguageSnapshot() {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }
        let snapshot = Localization.localizationController.currentSnapshot
        let update = Localization.layoutDirectionUpdate(.leftToRight)
        #expect(update.snapshot == snapshot)
    }

    @Test func swiftUIBridgeKeepsItsHostedControllerAcrossLanguageChanges() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        let bridge = SwiftUILocalizationBridgeDemoViewController()
        let navigation = UINavigationController(rootViewController: bridge)
        let window = try makeVisibleTestWindow(rootViewController: navigation)
        Localization.register(window: window)
        defer {
            Localization.unregister(window: window)
            window.isHidden = true
            Localization.setLocale(identifier: "en-US")
        }
        let host = try #require(bridge.children.first)
        for language in ["ar", "en-US"] {
            Localization.setLocale(identifier: language)
            #expect(await waitForCondition {
                bridge.title == Localization.text("demo.swiftUIBridge.title")
                    && host.view.effectiveUserInterfaceLayoutDirection == Localization.currentUIKitDirection
            })
            #expect(bridge.children.count == 1)
            #expect(bridge.children.first === host)
        }
    }
}
