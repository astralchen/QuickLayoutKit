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
    @Test func nativeInputsPreserveSelectionAndCompositionAcrossLanguageChanges() async throws {
        for kind in ["field", "secure", "multiline"] {
            let controller = UIViewController()
            let view: UIView = kind == "multiline" ? UITextView() : UITextField()
            view.frame = CGRect(x: 20, y: 150, width: 310, height: kind == "multiline" ? 140 : 44)
            controller.view.addSubview(view)
            let window = try makeVisibleTestWindow(rootViewController: controller)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            Localization.register(window: window)
            defer {
                Localization.unregister(window: window)
                Localization.setLocale(identifier: "zh-Hans")
            }
            if let field = view as? UITextField {
                field.isSecureTextEntry = kind == "secure"
                field.autocorrectionType = .no
            }
            let input = view as! any UITextInput
            view.becomeFirstResponder()
            try #require(await waitForCondition { view.isFirstResponder })
            for next in ["zh-Hans", "ar", "en", "ar"] {
                Localization.setLocale(identifier: next)
                for text in ["", "VV77", "uu天", "مرحبا", ""] {
                    input.selectedTextRange = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)
                    if text.isEmpty { input.deleteBackward() } else { input.insertText(text) }
                    let range = try #require(input.textRange(from: input.beginningOfDocument, to: input.endOfDocument))
                    let selected = try #require(input.selectedTextRange)
                    let selectionOffset = input.offset(from: input.beginningOfDocument, to: selected.start)
                    Localization.setLocale(identifier: next == "ar" ? "zh-Hans" : "ar")
                    #expect(input.text(in: range) == text)
                    #expect(input.offset(from: input.beginningOfDocument, to: try #require(input.selectedTextRange).start) == selectionOffset)
                    #expect(view.isFirstResponder)
                    #expect(((view as? UITextField)?.textAlignment ?? (view as? UITextView)?.textAlignment) == .natural)
                }
            }
            if kind != "secure" {
                Localization.setLocale(identifier: "zh-Hans")
                input.selectedTextRange = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)
                input.deleteBackward()
                input.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0))
                try #require(input.markedTextRange != nil)
                Localization.setLocale(identifier: "ar")
                #expect(input.markedTextRange != nil)
                #expect(view.isFirstResponder)
                // 通过真实 UITextInput 提交组合文本，不伪造编辑通知。
                input.insertText("中")
                #expect(await waitForCondition {
                    input.markedTextRange == nil
                        && ((view as? UITextField)?.textAlignment ?? (view as? UITextView)?.textAlignment) == .natural
                })
                #expect(input.text(in: input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)!) == "中")
            }
            view.resignFirstResponder()
            view.becomeFirstResponder()
            #expect(view.isFirstResponder)
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
            for language in ["zh-Hans", "ar", "en", "ar"] {
                Localization.setLocale(identifier: language)
                let expected = Localization.currentUIKitDirection
                #expect(await waitForCondition {
                    fields.allSatisfy { $0.effectiveUserInterfaceLayoutDirection == expected }
                        && notes.allSatisfy { $0.effectiveUserInterfaceLayoutDirection == expected }
                })
                for field in fields {
                    field.becomeFirstResponder()
                    field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
                    field.insertText("uu天123")
                    #expect(field.isFirstResponder)
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
        Localization.register(window: window)
        defer {
            Localization.unregister(window: window)
            Localization.setLocale(identifier: "zh-Hans")
        }
        view.becomeFirstResponder()
        try #require(await waitForCondition { view.isFirstResponder })
        let undo = try #require(view.undoManager)
        undo.beginUndoGrouping()
        view.insertText("hello")
        undo.endUndoGrouping()
        Localization.setLocale(identifier: "ar")
        #expect(undo.canUndo)
        undo.undo()
        #expect(view.text.isEmpty)
        #expect(view.isFirstResponder)
    }

    @Test func searchKeepsNaturalWritingOrderAcrossLanguageChanges() async throws {
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
            Localization.setLocale(identifier: "en")
        }
        search.isActive = true
        #expect(await waitForCondition { field.window != nil })
        field.becomeFirstResponder()
        #expect(await waitForCondition { field.isFirstResponder && field.bounds.width > 100 })

        for language in ["ar", "zh-Hans", "en", "ar"] {
            Localization.setLocale(identifier: language)
            try #require(await waitForCondition {
                main.title == Localization.text("main.title")
                    && navigation.navigationBar.traitCollection.layoutDirection == (language == "ar" ? .rightToLeft : .leftToRight)
            }, "语言：\(language)，当前：\(Localization.currentLanguageSummary())，标题：\(main.title ?? "nil")")
            // 自然对齐按文字书写方向决定，不再把所有草稿强制对齐到应用前缘。
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
                    let followsWritingOrder = text.isEmpty || (text == "مرحبا"
                        ? start.minX > end.minX : start.minX < end.minX)
                    return followsWritingOrder && field.textAlignment == .natural
                }
                #expect(aligned,
                        "语言：\(language)，文本：\(text)，实际文本：\(field.text ?? "")，对齐：\(field.textAlignment.rawValue)，起点：\(start)，终点：\(end)，输入框：\(field.bounds)")
            }
            field.resignFirstResponder()
            field.becomeFirstResponder()
            navigation.view.layoutIfNeeded()
            #expect(field.isFirstResponder)
            #expect(field.textAlignment == .natural)
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
            Localization.setLocale(identifier: "en")
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

    @Test func rapidLanguageChangesCompleteEachDirectionTransaction() async throws {
        Localization.setLocale(identifier: "ar")
        let main = MainViewController()
        let navigation = UINavigationController(rootViewController: main)
        let window = try makeVisibleTestWindow(rootViewController: navigation, size: CGSize(width: 390, height: 844))
        Localization.register(window: window)
        defer {
            Localization.unregister(window: window)
            window.isHidden = true
            Localization.setLocale(identifier: "en")
        }
        #expect(await waitForCondition { navigation.navigationBar.traitCollection.layoutDirection == .rightToLeft })
        // 语言选择返回时 UIKit 事务已经完成，同方向的后续选择不会丢失方向刷新。
        Localization.setLocale(identifier: "zh-Hans")
        #expect(navigation.navigationBar.traitCollection.layoutDirection == .leftToRight)
        #expect(main.title == Localization.text("main.title"))
        Localization.setLocale(identifier: "en")
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
            Localization.setLocale(identifier: "en")
        }
        #expect(await waitForCondition { main.collectionView.numberOfSections == 6 })
        main.collectionView.scrollToItem(at: IndexPath(item: 0, section: 4), at: .top, animated: false)
        main.collectionView.contentOffset.y += 17
        // 等待导航栏完成滚动联动，再记录用户实际看到的条目与偏移。
        try await Task.sleep(nanoseconds: 100_000_000)
        let before = try #require(main.collectionView.captureReadingAnchor())
        for language in [initialLanguage == "ar" ? "zh-Hans" : "ar", initialLanguage] {
            Localization.setLocale(identifier: language)
            let restored = await waitForCondition {
                navigation.view.layoutIfNeeded()
                guard main.title == Localization.text("main.title"),
                      let after = main.collectionView.captureReadingAnchor() else { return false }
                return main.collectionView.effectiveUserInterfaceLayoutDirection == Localization.currentUIKitDirection
                    && after.indexPath == before.indexPath
                    && abs(after.offsetFromViewportTop - before.offsetFromViewportTop) < 2
            }
            let after = main.collectionView.captureReadingAnchor()
            #expect(restored, "语言：\(language)，原位置：\(before)，实际位置：\(String(describing: after))")
        }
    }

    @Test func directionUpdatesPreserveTheActualLanguageSnapshot() {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en") }
        let snapshot = Localization.localizationController.currentSnapshot
        let update = Localization.layoutDirectionUpdate(.leftToRight)
        #expect(update.snapshot == snapshot)
    }

    @Test func swiftUIBridgeKeepsItsHostedControllerAcrossLanguageChanges() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        let bridge = SwiftUILocalizationBridgeViewController()
        let navigation = UINavigationController(rootViewController: bridge)
        let window = try makeVisibleTestWindow(rootViewController: navigation)
        Localization.register(window: window)
        defer {
            Localization.unregister(window: window)
            window.isHidden = true
            Localization.setLocale(identifier: "en")
        }
        let host = try #require(bridge.children.first)
        for language in ["ar", "en"] {
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
