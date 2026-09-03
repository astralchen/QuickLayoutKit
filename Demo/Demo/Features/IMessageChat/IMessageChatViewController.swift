//
//  IMessageChatViewController.swift
//  Demo
//

import Combine
import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 支持文本、录制音频和语音转写草稿的一对一聊天 Demo。
@available(iOS 26.0, *)
final class IMessageChatViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.imessage.title" }

    let viewModel: IMessageChatViewModel
    let conversationView = IMessageConversationView()
    let composerView = IMessageChatComposerView()
    let contactTitleView = IMessageContactTitleView(frame: .zero)
    let audioController: IMessageChatAudioController

    private let keyboardObserver = QuickLayoutKeyboardObserver()
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        let audioController = IMessageChatAudioController()
        self.init(
            viewModel: IMessageChatViewModel(
                replyAudioSynthesizer: audioController
            ),
            audioController: audioController
        )
    }

    /// 使用指定的视图模型和真实媒体控制器创建聊天视图控制器。
    ///
    /// - Parameter viewModel: 管理消息时间线的视图模型。
    convenience init(viewModel: IMessageChatViewModel) {
        self.init(
            viewModel: viewModel,
            audioController: IMessageChatAudioController()
        )
    }

    /// 使用可注入的时间线和媒体协作者创建聊天视图控制器。
    ///
    /// - Parameters:
    ///   - viewModel: 管理消息时间线的视图模型。
    ///   - audioController: 管理页面音频操作的控制器。
    init(
        viewModel: IMessageChatViewModel,
        audioController: IMessageChatAudioController
    ) {
        self.viewModel = viewModel
        self.audioController = audioController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        let audioController = IMessageChatAudioController()
        self.audioController = audioController
        viewModel = IMessageChatViewModel(
            replyAudioSynthesizer: audioController
        )
        super.init(coder: coder)
    }

    override var body: Layout {
        VStack(spacing: 0) {
            conversationView
                .resizable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            composerView
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
        }
        .safeAreaPadding(.all, 0)
    }

    override func viewDidLoad() {
        quickLayoutKeyboardSafeAreaBehavior = .docked(
            usesBottomSafeArea: true
        )
        super.viewDidLoad()

        contactTitleView.sizeToFit()
        navigationItem.titleView = contactTitleView
        view.backgroundColor = .systemBackground
        configureInteractions()
        bindViewModel()
        observeKeyboard()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isMovingFromParent || isBeingDismissed else { return }
        viewModel.cancelPendingReply()
        audioController.stopAll()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        contactTitleView.configure(
            subtitle: DemoLocalization.text("imessage.contact.subtitle")
        )
        contactTitleView.sizeToFit()
        composerView.configure(
            strings: IMessageChatComposerStrings(
                placeholder: DemoLocalization.text(
                    "imessage.composer.placeholder"
                ),
                send: DemoLocalization.text("imessage.composer.send"),
                addAttachment: DemoLocalization.text(
                    "imessage.attachment.add"
                ),
                audio: DemoLocalization.text("imessage.attachment.audio"),
                dictate: DemoLocalization.text("imessage.dictation.start"),
                stopDictation: DemoLocalization.text(
                    "imessage.dictation.stop"
                ),
                stopRecording: DemoLocalization.text(
                    "imessage.audio.record.stop"
                ),
                cancelAudio: DemoLocalization.text(
                    "imessage.audio.cancel"
                ),
                playAudio: DemoLocalization.text("imessage.audio.play"),
                pauseAudio: DemoLocalization.text("imessage.audio.pause")
            )
        )
        viewModel.refreshLocalizedContent()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        let semanticAttribute = direction.appLayoutDirection
            .semanticContentAttribute
        contactTitleView.semanticContentAttribute = semanticAttribute
        composerView.applyLayoutDirection(direction)
        conversationView.applyLayoutDirection(direction)
        setNeedsQuickLayout()
    }

    private func configureInteractions() {
        composerView.actionRequested = { [weak self] action in
            self?.handleComposerAction(action) ?? false
        }
        conversationView.actionRequested = { [weak self] action in
            self?.handleMessageAction(action)
        }
        audioController.stateDidChange = { [weak self] state in
            self?.composerView.applyState(state)
        }
        audioController.playbackDidChange = { [weak self] playback in
            self?.conversationView.updateAudioPlayback(playback)
        }
        audioController.failureDidOccur = { [weak self] failure in
            self?.presentMediaFailure(failure)
        }
        composerView.heightDidChange = { [weak self] in
            guard let self else { return }
            let shouldFollow = conversationView.isNearBottom
            setNeedsQuickLayout()
            quickLayoutIfNeeded()
            if shouldFollow {
                conversationView.scrollToBottom(animated: false)
            }
        }
        composerView.applyState(audioController.state)
    }

    /// 处理输入栏发出的统一用户动作。
    ///
    /// 附件发送先让 ViewModel 验证并追加消息，成功后才提交页面草稿。该顺序保证
    /// 文件失效或后续图片、视频验证失败时，预览仍然可以重试或取消。
    ///
    /// - Parameter action: 输入栏发出的值类型动作。
    /// - Returns: 动作已经被对应业务层接受时为 `true`。
    private func handleComposerAction(
        _ action: IMessageChatComposerAction
    ) -> Bool {
        switch action {
        case .sendText(let text):
            return viewModel.send(text)

        case .requestAttachment(let kind, let keyboardWasVisible):
            switch kind {
            case .audio:
                audioController.startRecording()
                if keyboardWasVisible {
                    composerView.restoreTextInputFocus()
                }
                return true
            }

        case .stopAudioRecording:
            audioController.stopRecording()
            return true

        case .cancelAttachmentDraft:
            audioController.cancelRecordingOrPreview()
            return true

        case .sendAttachmentDraft:
            guard let attachment = audioController.previewAttachment,
                  viewModel.sendAttachment(attachment) else {
                return false
            }
            return audioController.commitPreviewAttachment(id: attachment.id)

        case .toggleAudioPreviewPlayback:
            audioController.togglePreviewPlayback()
            return true

        case .startDictation:
            audioController.startDictation(
                locale: DemoLocalization.localizationController
                    .currentLocale.locale
            )
            return true

        case .stopDictation, .manualEditDuringDictation:
            audioController.stopDictation()
            return true
        }
    }

    /// 把时间线消息操作路由到类型专属的页面协调器。
    ///
    /// - Parameter action: Cell 发出的值类型操作。
    private func handleMessageAction(_ action: IMessageChatMessageAction) {
        switch action {
        case .toggleAudioPlayback(let messageID, let attachment):
            audioController.toggleMessagePlayback(
                messageID: messageID,
                attachment: attachment
            )
        }
    }

    private func bindViewModel() {
        viewModel.bind { [weak self] state, reason in
            self?.conversationView.render(state, reason: reason)
        }
    }

    private func observeKeyboard() {
        keyboardObserver.$context
            .dropFirst()
            .sink { [weak self] context in
                guard let self else { return }
                let shouldFollow = conversationView.isNearBottom
                DispatchQueue.main.async { [weak self] in
                    guard let self, shouldFollow else { return }
                    quickLayoutIfNeeded()
                    conversationView.scrollToBottom(
                        animated: context.animationDuration > 0
                    )
                }
            }
            .store(in: &cancellables)
    }

    /// 针对媒体操作失败呈现本地化的恢复信息。
    ///
    /// 权限失败包含前往“设置”的操作。其他失败均采用非破坏性处理，并完整保留当前
    /// 草稿。
    ///
    /// - Parameter failure: 媒体控制器报告的失败。
    private func presentMediaFailure(_ failure: IMessageChatMediaFailure) {
        guard presentedViewController == nil else { return }
        let messageKey: String = switch failure {
        case .microphonePermissionDenied:
            "imessage.error.microphonePermission"
        case .speechPermissionDenied:
            "imessage.error.speechPermission"
        case .recordingTooShort:
            "imessage.error.recordingTooShort"
        case .recordingFailed:
            "imessage.error.recordingFailed"
        case .playbackFailed:
            "imessage.error.playbackFailed"
        case .speechUnavailable:
            "imessage.error.speechUnavailable"
        case .speechFailed:
            "imessage.error.speechFailed"
        }
        let alert = UIAlertController(
            title: DemoLocalization.text("imessage.error.title"),
            message: DemoLocalization.text(messageKey),
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(
                title: DemoLocalization.text("imessage.action.ok"),
                style: .cancel
            )
        )
        if failure == .microphonePermissionDenied
            || failure == .speechPermissionDenied {
            alert.addAction(
                UIAlertAction(
                    title: DemoLocalization.text("imessage.action.settings"),
                    style: .default
                ) { _ in
                    guard let url = URL(
                        string: UIApplication.openSettingsURLString
                    ) else { return }
                    UIApplication.shared.open(url)
                }
            )
        }
        present(alert, animated: true)
    }
}

#if DEBUG
@MainActor
private func makeIMessageChatViewControllerPreview() -> UIViewController {
    let viewModel = IMessageChatViewModel(
        localizer: .live,
        clock: { IMessageChatPreviewData.fixedDate },
        sleeper: { duration in
            try await Task.sleep(for: duration)
        }
    )
    return UINavigationController(
        rootViewController: IMessageChatViewController(viewModel: viewModel)
    )
}

#Preview("iMessage 聊天页面") {
    makeIMessageChatViewControllerPreview()
}
#endif
