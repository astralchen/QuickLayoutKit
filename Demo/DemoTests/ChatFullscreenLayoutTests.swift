import AppLocalization
import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized, .enabled(if: ChatTestAvailability.isSupported))
struct ChatFullscreenLayoutTests {
    /// 使用实际系统照片 Sheet，检查容器边界和输入框内部都没有重复安全区留白。
    @Test(arguments: [false, true])
    func photoPickerMeetsComposerAfterPresentation(fromKeyboard: Bool) async throws {
        guard #available(iOS 26.0, *) else { return }
        let tabs = AppTabBarController()
        let window = try makeVisibleTestWindow(rootViewController: tabs)
        tabs.select(.chat)
        let navigation = try #require(tabs.featureControllers[.chat] as? UINavigationController)
        let page = try #require(navigation.viewControllers.first as? ChatViewController)
        defer { page.bottomObstructionCoordinator.stop(); window.isHidden = true }
        try await Task.sleep(for: .milliseconds(300))
        if fromKeyboard {
            page.composerView.textView.becomeFirstResponder()
            try await Task.sleep(for: .milliseconds(700))
        }
        page.photoController.present(from: page,
            keyboardHeight: page.bottomObstructionCoordinator.storedKeyboardContentHeight)
        let sheet = try #require(page.presentedViewController)
        #expect(await eventually {
            sheet.viewIfLoaded?.window === window && !sheet.isBeingPresented && sheet.transitionCoordinator == nil
        })
        let panel = try #require(sheet.presentationController?.presentedView)
        let input = page.composerView.inputGlassView
        // 系统可能在入场后的下一帧应用校准档位，等模型层与呈现层都到达落点。
        #expect(await eventually {
            guard let panelLayer = panel.layer.presentation(), let windowLayer = window.layer.presentation() else { return false }
            let modelTop = panel.convert(panel.bounds, to: window).minY
            let visibleTop = panelLayer.convert(panelLayer.bounds, to: windowLayer).minY
            let inputBottom = input.convert(input.bounds, to: window).maxY
            return abs(modelTop - visibleTop) <= 1
                && abs(modelTop - inputBottom - ComposerView.Metrics.verticalPadding) <= 1
        })
        let panelFrame = panel.convert(panel.bounds, to: window)
        let composer = page.composerView
        let composerFrame = composer.convert(composer.bounds, to: window)
        let inputFrame = composer.inputGlassView.convert(composer.inputGlassView.bounds, to: window)
        let diagnostic = "keyboard=\(fromKeyboard) panel=\(panelFrame) composer=\(composerFrame) input=\(inputFrame) safe=\(page.view.safeAreaInsets) obstruction=\(page.bottomObstruction) sheetView=\(sheet.view.convert(sheet.view.bounds, to: window))"
        #expect(abs(panelFrame.minY - inputFrame.maxY - ComposerView.Metrics.verticalPadding) <= 1, "\(diagnostic)")
        page.photoController.dismissPicker(animated: false)
        try await Task.sleep(for: .milliseconds(300))
    }

    @Test func directPhotoPickerMatchesCachedShortKeyboard() async throws {
        guard #available(iOS 26.0, *) else { return }
        let tabs = AppTabBarController()
        let window = try makeVisibleTestWindow(rootViewController: tabs)
        tabs.select(.chat)
        let nav = try #require(tabs.featureControllers[.chat] as? UINavigationController)
        let page = try #require(nav.viewControllers.first as? ChatViewController)
        defer { page.bottomObstructionCoordinator.stop(); window.isHidden = true }
        window.layoutIfNeeded()
        let host = page.view!
        let height = host.safeAreaInsets.bottom + 160
        let keyboard = CGRect(x: 0, y: host.bounds.maxY - height, width: host.bounds.width, height: height)
        let notification = Notification(name: UIResponder.keyboardWillShowNotification, object: window.screen,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: host.convert(keyboard, to: window.screen.coordinateSpace)])
        let coordinator = page.bottomObstructionCoordinator
        coordinator.updateKeyboard(try #require(QuickLayoutKeyboardContext(notification: notification)))
        coordinator.updateKeyboard(.hidden)
        #expect(abs(coordinator.storedKeyboardContentHeight - 160) < 1)
        page.photoController.present(from: page, keyboardHeight: coordinator.storedKeyboardContentHeight)
        defer { page.photoController.dismissPicker(animated: false) }
        try await Task.sleep(for: .milliseconds(1200))
        let sheet = try #require(page.presentedViewController?.presentationController?.presentedView)
        let panelTop = sheet.convert(sheet.bounds, to: window).minY
        let input = page.composerView.inputGlassView
        let gap = panelTop - input.convert(input.bounds, to: window).maxY
        #expect(abs(panelTop - host.convert(host.safeAreaLayoutGuide.layoutFrame, to: window).maxY + 160) <= 1)
        #expect(abs(gap - ComposerView.Metrics.verticalPadding) <= 1,
            "gap=\(gap), panelTop=\(panelTop), obstruction=\(coordinator.currentHeight), host=\(host.bounds), safe=\(host.safeAreaInsets), windowSafe=\(window.safeAreaInsets)")
    }

    /// 导航栏展开/收起只改变顶部遮挡，不能把刚离开底部的手势拉回，也不能移动历史消息。
    @Test(arguments: [false, true])
    func topInsetChangesPreserveScrollOffset(readingHistory: Bool) async throws {
        guard #available(iOS 26.0, *) else { return }
        let fixture = try Fixture(messageCount: 60)
        defer { fixture.close() }
        let page = fixture.page
        let conversation = page.conversationView
        let list = conversation.collectionView
        #expect(await eventually { conversation.initialPresentation.isPresented })
        if readingHistory {
            list.scrollToItem(at: IndexPath(item: 25, section: 0), at: .top, animated: false)
        } else {
            // 对应用户日志：离底部 32 点时，仍处于原来的 88 点自动跟随阈值内。
            list.contentOffset.y -= 32
        }
        list.layoutIfNeeded()
        let originalOffset = list.contentOffset
        let anchor = try #require(list.captureLocalizationAnchor())
        let originalFrame = try #require(list.layoutAttributesForItem(at: anchor.indexPath)?.frame)
        let safe = page.view.safeAreaInsets
        let bottom = list.contentInset.bottom
        for top: CGFloat in [24, 37, 24, 27.3333333333, 58, 82, 24] {
            // 模拟页面安全区回调先捕获位置，再提交顶部导航栏的中间高度。
            conversation.prepareForViewportChange()
            conversation.updateViewportInsets(UIEdgeInsets(top: top, left: safe.left,
                                                          bottom: bottom, right: safe.right))
            list.layoutIfNeeded()
            let frame = try #require(list.layoutAttributesForItem(at: anchor.indexPath)?.frame)
            // estimated 行在物化后会修正前方内容高度；UIKit 可同步补偿 contentOffset。
            // 要求同一消息在屏幕上保持原位，不能把合法的几何补偿误判成导航栏抢滚动。
            #expect(abs((frame.minY - list.contentOffset.y) - (originalFrame.minY - originalOffset.y)) < 0.5,
                    "top=\(top), before=\(originalOffset), after=\(list.contentOffset), rowDelta=\(frame.minY - originalFrame.minY)")
            #expect(abs(list.contentInset.top - top) < 0.5)
            #expect(abs(list.verticalScrollIndicatorInsets.top - top) < 0.5)
        }
    }

    /// 折叠、旋转及不对称安全区变化不能给纵向时间线增加横向滚动范围。
    @Test(arguments: [false, true], [0, 1, 60])
    func horizontalRangeRemainsEmptyAcrossViewportChanges(rtl: Bool, messageCount: Int) async throws {
        guard #available(iOS 26.0, *) else { return }
        let fixture = try Fixture(messageCount: messageCount)
        defer { fixture.close() }
        let page = fixture.page
        let list = page.conversationView.collectionView
        page.conversationView.applyLayoutDirection(rtl ? .rightToLeft : .leftToRight)
        #expect(await eventually { page.conversationView.initialPresentation.isPresented })
        for size in [CGSize(width: 740, height: 420), CGSize(width: 390, height: 740),
                     CGSize(width: 653, height: 740)] {
            for sideInsets in [(CGFloat(0), CGFloat(90)), (60, 0), (30, 30), (0, 0)] {
                page.conversationView.prepareForViewportChange()
                page.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: sideInsets.0,
                                                            bottom: 0, right: sideInsets.1)
                fixture.window.frame.size = size
                fixture.window.setNeedsLayout()
                fixture.window.layoutIfNeeded()
                page.view.layoutIfNeeded()
                page.layoutChatContent()
                list.layoutIfNeeded()
                let inset = list.adjustedContentInset
                #expect(list.contentSize.width + inset.left + inset.right <= list.bounds.width + 1)
                #expect(abs(list.contentOffset.x + inset.left) < 1)
                let safeFrame = page.view.convert(page.view.safeAreaLayoutGuide.layoutFrame, to: list)
                for index in list.indexPathsForVisibleItems {
                    let frame = try #require(list.layoutAttributesForItem(at: index)?.frame)
                    #expect(frame.minX >= safeFrame.minX - 1,
                            "row=\(frame), safe=\(safeFrame), size=\(size), rtl=\(rtl), list=\(list.convert(list.bounds, to: page.view)), composer=\(page.composerView.convert(page.composerView.bounds, to: page.view)), page=\(page.view.bounds), obstruction=\(page.bottomObstruction)")
                    #expect(frame.maxX <= safeFrame.maxX + 1,
                            "row=\(frame), safe=\(safeFrame), size=\(size), rtl=\(rtl), list=\(list.convert(list.bounds, to: page.view)), composer=\(page.composerView.convert(page.composerView.bounds, to: page.view)), page=\(page.view.bounds), obstruction=\(page.bottomObstruction)")
                }
            }
        }
    }

    @Test(arguments: [0, 1, 60])
    func listFillsPageWhileComposerAndObstructionsChange(messageCount: Int) async throws {
        guard #available(iOS 26.0, *) else { return }
        let fixture = try Fixture(messageCount: messageCount)
        defer { fixture.close() }
        let page = fixture.page
        let list = page.conversationView.collectionView
        #expect(await eventually { page.conversationView.initialPresentation.isPresented })
        fixture.expectGeometry()
        for obstruction: CGFloat in [280, 340, 120, 0] {
            page.conversationView.prepareForViewportChange()
            page.bottomObstruction = obstruction
            page.setNeedsQuickLayout()
            page.layoutChatContent()
            fixture.expectGeometry()
            #expect(abs(page.composerView.convert(page.composerView.bounds, to: page.view).maxY - (page.view.bounds.maxY
                - page.view.safeAreaInsets.bottom - obstruction)) < 1)
            #expect(page.conversationView.isNearBottom)
        }
        let originalHeight = page.composerView.bounds.height
        page.composerView.textView.text = "One\nTwo\nThree\nFour"
        UIView.performWithoutAnimation {
            page.composerView.textViewDidChange(page.composerView.textView)
        }
        fixture.expectGeometry()
        #expect(page.composerView.bounds.height > originalHeight)
        page.composerView.applyState(.recording(elapsed: 1, waveform: [0.2, 0.5]))
        fixture.expectGeometry()
        if messageCount > 0 {
            let last = try #require(list.layoutAttributesForItem(
                at: IndexPath(item: list.numberOfItems(inSection: 0) - 1, section: 0)))
            #expect(last.frame.maxY <= list.bounds.maxY - list.contentInset.bottom + 1)
        }
    }

    @Test func readingAnchorSurvivesInsetsAndWidthChanges() async throws {
        guard #available(iOS 26.0, *) else { return }
        let fixture = try Fixture(messageCount: 60)
        defer { fixture.close() }
        let page = fixture.page
        let list = page.conversationView.collectionView
        #expect(await eventually { page.conversationView.initialPresentation.isPresented })
        list.scrollToItem(at: IndexPath(item: 25, section: 0), at: .top, animated: false)
        let anchor = try #require(list.captureLocalizationAnchor())
        for obstruction: CGFloat in [300, 100, 0] {
            page.conversationView.prepareForViewportChange()
            page.bottomObstruction = obstruction
            page.setNeedsQuickLayout()
            page.layoutChatContent()
            let updated = try #require(list.captureLocalizationAnchor())
            #expect(updated.indexPath == anchor.indexPath)
            #expect(abs(updated.offsetFromViewportTop - anchor.offsetFromViewportTop) < 1)
            #expect(!page.conversationView.isNearBottom)
        }
        page.conversationView.prepareForViewportChange()
        page.additionalSafeAreaInsets = UIEdgeInsets(top: 18, left: 30, bottom: 0, right: 30)
        page.view.setNeedsLayout()
        page.view.layoutIfNeeded()
        page.layoutChatContent()
        fixture.expectGeometry()
        let resized = try #require(list.captureLocalizationAnchor())
        #expect(resized.indexPath == anchor.indexPath)
        #expect(abs(resized.offsetFromViewportTop - anchor.offsetFromViewportTop) < 1)
        #expect(list.contentInset.left == 0 && list.contentInset.right == 0)
        let cell = try #require(list.layoutAttributesForItem(at: resized.indexPath))
        let safeFrame = page.view.convert(page.view.safeAreaLayoutGuide.layoutFrame, to: list)
        #expect(cell.frame.minX >= safeFrame.minX - 1)
        #expect(cell.frame.maxX <= safeFrame.maxX + 1)
    }

    @Test func obscuredPreviewSourcesAndTransparentComposerMargins() async throws {
        guard #available(iOS 26.0, *) else { return }
        let fixture = try Fixture(messageCount: 60)
        defer { fixture.close() }
        let page = fixture.page
        let conversation = page.conversationView
        let list = conversation.collectionView
        #expect(await eventually { conversation.initialPresentation.isPresented })
        let source = UIView(frame: CGRect(x: 30, y: 0, width: 40, height: 40))
        list.addSubview(source)
        let visibleTop = list.bounds.minY + list.contentInset.top
        source.frame.origin.y = visibleTop + 10
        #expect(conversation.isUnobscuredPreviewSource(source))
        source.frame.origin.y = visibleTop - 20
        #expect(!conversation.isUnobscuredPreviewSource(source))
        source.frame.origin.y = list.bounds.maxY - list.contentInset.bottom - 20
        #expect(!conversation.isUnobscuredPreviewSource(source))
        let composer = page.composerView
        #expect(composer.hitTest(CGPoint(x: 1, y: 1), with: nil) == nil)
        let editorPoint = composer.textView.convert(CGPoint(x: 10, y: 10), to: composer)
        #expect(composer.hitTest(editorPoint, with: nil) != nil)
        let margin = composer.convert(CGPoint(x: 1, y: 1), to: page.view)
        let target = try #require(page.view.hitTest(margin, with: nil))
        #expect(target === list || target.isDescendant(of: list))
    }

    @Test func containerResizePreservesBottomAndReadingPosition() async throws {
        guard #available(iOS 26.0, *) else { return }
        let fixture = try Fixture(messageCount: 60)
        defer { fixture.close() }
        let page = fixture.page
        let conversation = page.conversationView
        let list = conversation.collectionView
        #expect(await eventually { conversation.initialPresentation.isPresented })
        for readingHistory in [false, true] {
            if readingHistory {
                list.scrollToItem(at: IndexPath(item: 25, section: 0), at: .top, animated: false)
            }
            let anchor = try #require(list.captureLocalizationAnchor())
            for size in [CGSize(width: 740, height: 420), CGSize(width: 420, height: 740)] {
                conversation.prepareForViewportChange()
                fixture.window.frame.size = size
                fixture.window.setNeedsLayout()
                fixture.window.layoutIfNeeded()
                page.view.layoutIfNeeded()
                page.layoutChatContent()
                fixture.expectGeometry()
                #expect(abs(page.view.bounds.width - size.width) < 1)
                #expect(abs(page.view.bounds.height - size.height) < 1)
                if readingHistory {
                    let resized = try #require(list.captureLocalizationAnchor())
                    #expect(resized.indexPath == anchor.indexPath, "size=\(size), old=\(anchor), new=\(resized)")
                    #expect(abs(resized.offsetFromViewportTop - anchor.offsetFromViewportTop) < 1,
                            "size=\(size), old=\(anchor), new=\(resized)")
                } else {
                    #expect(conversation.isNearBottom)
                }
            }
        }
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @available(iOS 26.0, *)
    @MainActor
    private final class Fixture {
        let window: UIWindow
        let previous: UIWindow?
        let page: ChatViewController

        init(messageCount: Int) throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            previous = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            let model = ChatViewModel()
            if messageCount > 0 {
                model.insertInitialHistory((0..<messageCount).map {
                    .init(direction: .incoming, content: .userText("Message \($0)\nA second line for measurement"))
                })
            }
            page = ChatViewController(viewModel: model)
            window.rootViewController = UINavigationController(rootViewController: page)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            page.view.layoutIfNeeded()
        }

        func expectGeometry() {
            let list = page.conversationView.collectionView
            let frame = list.convert(list.bounds, to: page.view)
            #expect(abs(frame.minX - page.view.bounds.minX) < 0.5)
            #expect(abs(frame.minY - page.view.bounds.minY) < 0.5)
            #expect(abs(frame.width - page.view.bounds.width) < 0.5)
            #expect(abs(frame.height - page.view.bounds.height) < 0.5)
            #expect(list.contentInsetAdjustmentBehavior == .never)
            #expect(!list.automaticallyAdjustsScrollIndicatorInsets)
            #expect(list.verticalScrollIndicatorInsets.top == list.contentInset.top)
            #expect(list.verticalScrollIndicatorInsets.bottom == list.contentInset.bottom)
            #expect(abs(list.contentInset.top - page.view.safeAreaInsets.top) < 1)
            #expect(abs(list.contentInset.bottom - (page.view.bounds.maxY - page.composerView.convert(page.composerView.bounds, to: page.view).minY)) < 1)
        }

        func close() {
            page.viewModel.cancelPendingReply()
            page.audioTranscription.cancelAll()
            page.audioController.stopAll()
            page.bottomObstructionCoordinator.stop()
            page.attachmentStore.removeAll()
            window.isHidden = true
            previous?.makeKeyAndVisible()
        }
    }
}
