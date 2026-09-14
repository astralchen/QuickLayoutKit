import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func voiceRoomMessageButtonSendsScrollsAndRemovesComposer() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let viewController = VoiceRoomViewController()
        viewController.configureQuickLayoutKeyboardSafeAreaForTesting(
            notificationCenter: .default
        ) { _, _ in true }
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 402, height: 874)
        )
        defer { window.isHidden = true }
        viewController.overrideUserInterfaceStyle = .dark

        layout(viewController, in: navigationController)
        let initialLatestMessage = viewController.latestPublicChatMessage
        let actionBarView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.actionBar"
            }
        )
        let defaultActionBarHeight = actionBarView.bounds.height
        #expect(
            viewController.publicChatScrollView.keyboardDismissMode
                == .interactive
        )
        if #available(iOS 17.0, *) {
            #expect(
                abs(
                    viewController.quickLayoutKeyboardDismissPadding
                        - defaultActionBarHeight
                ) < 1
            )
        }
        let defaultControlIdentifiers: Set<String> = [
            "liveRoom.message.button",
            "liveRoom.microphone.button",
            "liveRoom.gift.button",
            "liveRoom.more.button",
        ]
        let defaultControlViews = viewController.view
            .allSubviews(of: UIControl.self)
            .filter {
                guard let identifier = $0.accessibilityIdentifier else {
                    return false
                }
                return defaultControlIdentifiers.contains(identifier)
            }
        #expect(defaultControlViews.count == defaultControlIdentifiers.count)
        #expect(
            defaultControlViews.allSatisfy {
                abs($0.bounds.height - 35) < 1
            }
        )
        let hostSeatView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.seat.0"
            }
        )
        let messageButton = try #require(
            viewController.view
                .allSubviews(of: IconTitleButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.message.button"
            }
        )
        activate(messageButton)
        layout(viewController, in: navigationController)

        #expect(viewController.isShowingMessageComposer)
        #expect(abs(actionBarView.bounds.height - defaultActionBarHeight) < 1)
        if #available(iOS 17.0, *) {
            #expect(
                abs(
                    viewController.quickLayoutKeyboardDismissPadding
                        - actionBarView.bounds.height
                ) < 1
            )
        }
        let hostSeatWidthBeforeKeyboard = hostSeatView.bounds.width
        let seatStageHeightBeforeKeyboard = viewController
            .seatStageView.bounds.height
        let messagesHeightBeforeKeyboard = viewController
            .messagesView.bounds.height
        let textField = try #require(
            viewController.view.allSubviews(of: UITextField.self).first {
                $0.accessibilityIdentifier == "liveRoom.message.input"
            }
        )
        let inputContainer = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.message.input.container"
            }
        )
        let sendButton = try #require(
            viewController.view
                .allSubviews(of: CapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.message.send"
            }
        )
        let cancelButton = try #require(
            viewController.view
                .allSubviews(of: SymbolButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.message.cancel"
            }
        )

        let keyboardFrameInWindow = CGRect(
            x: 0,
            y: 534,
            width: window.bounds.width,
            height: window.bounds.height - 534
        )
        let keyboardFrameInScreen = window.convert(
            keyboardFrameInWindow,
            to: nil
        )
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameBeginUserInfoKey: CGRect(
                    x: 0,
                    y: window.bounds.maxY,
                    width: window.bounds.width,
                    height: 0
                ),
                UIResponder.keyboardFrameEndUserInfoKey: keyboardFrameInScreen,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.0,
                UIResponder.keyboardAnimationCurveUserInfoKey:
                    UInt(UIView.AnimationCurve.easeInOut.rawValue),
            ]
        )
        layout(viewController, in: navigationController)

        let textFieldFrame = textField.convert(
            textField.bounds,
            to: viewController.view
        )
        let inputContainerFrame = inputContainer.convert(
            inputContainer.bounds,
            to: viewController.view
        )
        let sendButtonFrame = sendButton.convert(
            sendButton.bounds,
            to: viewController.view
        )
        let cancelButtonFrame = cancelButton.convert(
            cancelButton.bounds,
            to: viewController.view
        )
        let keyboardTop = viewController.view.convert(
            keyboardFrameInScreen,
            from: nil
        ).minY
        let actionBarFrame = actionBarView.convert(
            actionBarView.bounds,
            to: viewController.view
        )

        #expect(textField.borderStyle == .none)
        #expect(textField.backgroundColor == .clear)
        #expect(textField.textColor == .white)
        #expect(textField.keyboardAppearance == .dark)
        #expect(abs(inputContainer.layer.cornerRadius - 8) < 0.5)
        #expect(
            inputContainer.layer.cornerRadius
                < inputContainerFrame.height / 2
        )
        #expect(inputContainer.clipsToBounds)
        #expect(inputContainerFrame.height >= 35)
        #expect(
            abs(textFieldFrame.height - inputContainerFrame.height) < 1
        )
        #expect(abs(sendButtonFrame.height - 35) < 1)
        #expect(abs(cancelButtonFrame.height - 35) < 1)
        #expect(abs(sendButton.layer.cornerRadius - 17.5) < 0.5)
        #expect(textFieldFrame.width >= 96)
        #expect(sendButtonFrame.minX - textFieldFrame.maxX >= 7)
        #expect(cancelButtonFrame.minX - sendButtonFrame.maxX >= 7)
        #expect(abs(textFieldFrame.midY - sendButtonFrame.midY) < 1)
        #expect(abs(sendButtonFrame.midY - cancelButtonFrame.midY) < 1)
        #expect(cancelButtonFrame.maxY <= keyboardTop - 7)
        #expect(abs(actionBarFrame.maxY - keyboardTop) < 1)
        #expect(actionBarView.transform == .identity)
        #expect(
            abs(hostSeatView.bounds.width - hostSeatWidthBeforeKeyboard) < 1
        )
        #expect(
            abs(
                viewController.seatStageView.bounds.height
                    - seatStageHeightBeforeKeyboard
            ) < 1
        )
        #expect(
            abs(
                viewController.messagesView.bounds.height
                    - messagesHeightBeforeKeyboard
            ) < 1
        )
        #expect(!sendButton.isEnabled)
        #expect(sendButton.layer.borderWidth == 1)
        #expect((sendButton.backgroundColor?.cgColor.alpha ?? 0) >= 0.1)

        textField.text = "   "
        textField.sendActions(for: .editingChanged)
        #expect(!sendButton.isEnabled)
        activate(sendButton)
        layout(viewController, in: navigationController)
        #expect(viewController.isShowingMessageComposer)
        #expect(viewController.latestPublicChatMessage == initialLatestMessage)

        textField.text = "  新消息已发送  "
        textField.sendActions(for: .editingChanged)
        #expect(sendButton.isEnabled)
        #expect((sendButton.backgroundColor?.cgColor.alpha ?? 0) == 1)
        activate(sendButton)
        layout(viewController, in: navigationController)

        #expect(!viewController.isShowingMessageComposer)
        #expect(viewController.latestPublicChatMessage == "我：新消息已发送")
        #expect(
            !viewController.view.allSubviews(of: UITextField.self).contains {
                $0.accessibilityIdentifier == "liveRoom.message.input"
            }
        )
        #expect(
            viewController.view.allSubviews(of: QuickLayoutButton.self).contains {
                $0.accessibilityIdentifier == "liveRoom.message.button"
            }
        )

        let scrollView = viewController.publicChatScrollView
        let bottomOffset = max(
            -scrollView.contentInset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.contentInset.bottom
        )
        #expect(abs(scrollView.contentOffset.y - bottomOffset) < 1)
        #expect(
            viewController.view.allSubviews(of: UIScrollView.self)
                .filter(\.isScrollEnabled).count == 1
        )
    }

    @Test func voiceRoomActionBarUsesSafeAreaOrViewBottomWithoutExtraSpacing() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let viewController = VoiceRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 375, height: 667)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        let actionBarView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.actionBar"
            }
        )
        let chatView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.publicChat.container"
            }
        )
        let actionBarFrame = actionBarView.convert(
            actionBarView.bounds,
            to: viewController.view
        )
        let chatFrame = chatView.convert(
            chatView.bounds,
            to: viewController.view
        )
        let safeAreaBottom = viewController.view.bounds.maxY
            - viewController.view.safeAreaInsets.bottom
        let bottomSpacing = safeAreaBottom - actionBarFrame.maxY
        let screenBottomSpacing = viewController.view.bounds.maxY
            - actionBarFrame.maxY
        #expect(abs(bottomSpacing) < 1)
        #expect(
            abs(
                screenBottomSpacing
                    - viewController.view.safeAreaInsets.bottom
            ) < 1
        )
        #expect(abs(actionBarFrame.minY - chatFrame.maxY - 10) < 1)
        #expect(
            viewController.view.allSubviews(of: UIScrollView.self)
                .filter(\.isScrollEnabled).count == 1
        )
    }

    @Test func voiceRoomKeyboardDismissPaddingTracksActionBarLayoutChanges() throws {
        guard #available(iOS 17.0, *) else { return }

        let viewController = VoiceRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        func expectActionBarDismissPadding(
            sourceLocation: SourceLocation = #_sourceLocation
        ) {
            #expect(
                abs(
                    viewController.quickLayoutKeyboardDismissPadding
                        - viewController.actionBarView.bounds.height
                ) < 1,
                sourceLocation: sourceLocation
            )
        }

        layout(viewController, in: navigationController)
        expectActionBarDismissPadding()

        viewController.traitOverrides.preferredContentSizeCategory =
            .accessibilityExtraExtraExtraLarge
        layout(viewController, in: navigationController)
        expectActionBarDismissPadding()

        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        navigationController.view.frame = window.bounds
        layout(viewController, in: navigationController)
        expectActionBarDismissPadding()
        #expect(
            viewController.publicChatScrollView.keyboardDismissMode
                == .interactive
        )
    }

    @Test func voiceRoomActionBarIgnoresFloatingKeyboard() throws {
        let viewController = VoiceRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 768, height: 1024)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let actionBarView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.actionBar"
            }
        )
        let restingFrame = actionBarView.convert(
            actionBarView.bounds,
            to: viewController.view
        )
        let floatingFrameInScreen = window.convert(
            CGRect(x: 180, y: 470, width: 360, height: 240),
            to: nil
        )

        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    floatingFrameInScreen,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ]
        )
        layout(viewController, in: navigationController)

        let floatingKeyboardActionBarFrame = actionBarView.convert(
            actionBarView.bounds,
            to: viewController.view
        )
        #expect(
            abs(floatingKeyboardActionBarFrame.maxY - restingFrame.maxY) < 1
        )
        #expect(actionBarView.transform == .identity)
    }
}
