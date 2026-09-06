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
    let photoController: IMessageChatPhotoPickerController
    let attachmentStore: any IMessageChatAttachmentStoring

    private let keyboardObserver = QuickLayoutKeyboardObserver()
    private var cancellables: Set<AnyCancellable> = []
    private var bottomObstruction: CGFloat = 0
    private lazy var bottomObstructionCoordinator =
        IMessageChatBottomObstructionCoordinator(hostView: view)

    convenience init() {
        let attachmentStore = IMessageChatPageAttachmentStore()
        let audioController = IMessageChatAudioController(
            attachmentStore: attachmentStore
        )
        self.init(
            viewModel: IMessageChatViewModel(
                replyAudioSynthesizer: audioController
            ),
            audioController: audioController,
            attachmentStore: attachmentStore
        )
    }

    /// 使用指定的视图模型和真实媒体控制器创建聊天视图控制器。
    ///
    /// - Parameter viewModel: 管理消息时间线的视图模型。
    convenience init(viewModel: IMessageChatViewModel) {
        let attachmentStore = IMessageChatPageAttachmentStore()
        self.init(
            viewModel: viewModel,
            audioController: IMessageChatAudioController(
                attachmentStore: attachmentStore
            ),
            attachmentStore: attachmentStore
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
        let attachmentStore = IMessageChatPageAttachmentStore()
        self.viewModel = viewModel
        self.audioController = audioController
        self.attachmentStore = attachmentStore
        photoController = IMessageChatPhotoPickerController(
            attachmentStore: attachmentStore
        )
        super.init(nibName: nil, bundle: nil)
    }

    private init(
        viewModel: IMessageChatViewModel,
        audioController: IMessageChatAudioController,
        attachmentStore: any IMessageChatAttachmentStoring
    ) {
        self.viewModel = viewModel
        self.audioController = audioController
        self.attachmentStore = attachmentStore
        photoController = IMessageChatPhotoPickerController(
            attachmentStore: attachmentStore
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        let audioController = IMessageChatAudioController()
        self.audioController = audioController
        let attachmentStore = IMessageChatPageAttachmentStore()
        self.attachmentStore = attachmentStore
        photoController = IMessageChatPhotoPickerController(
            attachmentStore: attachmentStore
        )
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
        .padding(.bottom, bottomObstruction)
        .safeAreaPadding(.all, 0)
    }

    override func viewDidLoad() {
        quickLayoutKeyboardSafeAreaBehavior = .disabled
        super.viewDidLoad()

        contactTitleView.sizeToFit()
        navigationItem.titleView = contactTitleView
        view.backgroundColor = .systemBackground
        configureInteractions()
        bindViewModel()
        observeKeyboard()
        configureBottomObstruction()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        bottomObstructionCoordinator.refreshGeometry()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isMovingFromParent || isBeingDismissed else { return }
        viewModel.cancelPendingReply()
        audioController.stopAll()
        photoController.dismissPicker(animated: false)
        photoController.discardDraft()
        bottomObstructionCoordinator.stop()
        attachmentStore.removeAll()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        contactTitleView.configure(
            subtitle: DemoLocalization.text("imessage.contact.subtitle")
        )
        contactTitleView.sizeToFit()
        let mediaStrings = makeMediaStrings()
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
            ),
            mediaStrings: mediaStrings
        )
        conversationView.configureMediaStrings(mediaStrings)
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
        photoController.stateDidChange = { [weak self] draft in
            self?.composerView.applyMediaDraft(draft)
        }
        photoController.failureDidOccur = { [weak self] in
            self?.presentMediaFailure(.mediaImportFailed)
        }
        photoController.pickerDidPresent = { [weak self] picker in
            self?.bottomObstructionCoordinator.trackPicker(picker)
        }
        photoController.pickerDidFinishPresenting = { [weak self] picker in
            self?.bottomObstructionCoordinator.finishPickerPresentation(picker)
        }
        photoController.pickerDidDismiss = { [weak self] in
            self?.bottomObstructionCoordinator.stopTrackingPicker()
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
        composerView.applyMediaDraft(photoController.draft)
        composerView.textInputDidBeginEditing = { [weak self] in
            guard let self, photoController.isPresented else { return }
            // 先保存交接起点再关闭面板，否则面板向下退出时输入栏也会先下落再随键盘升起。
            bottomObstructionCoordinator.beginKeyboardHandoff()
            photoController.dismissPicker(animated: true)
        }
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

        case .sendMediaDraft(let text):
            guard let attachment = photoController.draftAttachment else {
                presentMediaFailure(.mediaInvalid)
                return false
            }
            guard viewModel.sendMediaGroup(
                attachment,
                followedByText: text
            ) else {
                presentMediaFailure(.mediaInvalid)
                return false
            }
            let committed = photoController.commitDraft()
            photoController.dismissPicker(animated: true)
            return committed

        case .removeMediaDraftItem(let id):
            photoController.removeItem(id: id)
            return true

        case .requestAttachment(let kind):
            switch kind {
            case .photo:
                photoController.present(
                    from: self,
                    keyboardHeight: bottomObstructionCoordinator
                        .storedKeyboardContentHeight
                )
                return true
            case .audio:
                // 录音动作只启动音频流程；文本焦点由用户操作决定，不能在菜单
                // 关闭后异步抢回焦点，否则会再次唤起键盘并带动输入栏移动。
                audioController.startRecording()
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
        case .openMediaGroup(_, let attachment, let index):
            let preview = IMessageChatMediaPreviewController(
                group: attachment,
                initialIndex: index,
                strings: makeMediaStrings()
            )
            present(preview, animated: true)
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
                let shouldApplyKeyboardLayout = bottomObstructionCoordinator.updateKeyboard(
                    context
                )
                // 已展示的面板保留原有档位；尤其不能在切回键盘的关闭动画中重算高度。
                // 更新下一次使用的缓存后，仍由协调器决定本次通知是否可驱动页面布局。
                photoController.updateKeyboardHeight(
                    bottomObstructionCoordinator.storedKeyboardContentHeight,
                    invalidatingPresentedDetent: !photoController.isPresented
                )
                guard shouldApplyKeyboardLayout else { return }
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

    private func configureBottomObstruction() {
        bottomObstructionCoordinator.heightDidChange = { [weak self] height, context in
            guard let self else { return }
            let wasNearBottom = conversationView.isNearBottom
            bottomObstruction = height
            setNeedsQuickLayout()
            let updates: () -> Void = { [weak self] in
                self?.quickLayoutIfNeeded()
            }
            if let context, context.animationDuration > 0 {
                // 只有键盘通知携带动画目标；beginFromCurrentState 允许新通知接续正在进行的动画。
                UIView.animate(
                    withDuration: context.animationDuration,
                    delay: 0,
                    options: context.animationOptions.union(.beginFromCurrentState),
                    animations: updates
                )
            } else {
                // 显示链接提供的是当前呈现位置，必须立即布局，不能逐帧叠加新动画导致滞后。
                updates()
            }
            // 用户正在阅读历史消息时保留当前位置；仅在变化前接近底部时继续跟随新布局。
            if wasNearBottom {
                conversationView.scrollToBottom(animated: false)
            }
        }
        bottomObstructionCoordinator.refreshGeometry()
    }

    private func makeMediaStrings() -> IMessageChatMediaStrings {
        IMessageChatMediaStrings(
            photo: DemoLocalization.text("imessage.attachment.photo"),
            itemsFormat: DemoLocalization.text("imessage.media.items"),
            image: DemoLocalization.text("imessage.media.image"),
            animatedImage: DemoLocalization.text(
                "imessage.media.animatedImage"
            ),
            video: DemoLocalization.text("imessage.media.video"),
            videoDurationFormat: DemoLocalization.text(
                "imessage.media.videoDuration"
            ),
            importing: DemoLocalization.text("imessage.media.importing"),
            remove: DemoLocalization.text("imessage.media.remove"),
            play: DemoLocalization.text("imessage.media.play"),
            openPreview: DemoLocalization.text("imessage.media.openPreview"),
            close: DemoLocalization.text("imessage.media.close"),
            firstItem: DemoLocalization.text("imessage.media.first"),
            lastItem: DemoLocalization.text("imessage.media.last"),
            positionFormat: DemoLocalization.text("imessage.media.position")
        )
    }

    /// 针对媒体操作失败呈现本地化的恢复信息。
    ///
    /// 权限失败包含前往“设置”的操作。其他失败均采用非破坏性处理，并完整保留当前
    /// 草稿。
    ///
    /// - Parameter failure: 媒体控制器报告的失败。
    private func presentMediaFailure(_ failure: IMessageChatMediaFailure) {
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
        case .mediaImportFailed:
            "imessage.error.mediaImportFailed"
        case .mediaInvalid:
            "imessage.error.mediaInvalid"
        }
        let alert = UIAlertController(
            title: DemoLocalization.text("imessage.error.title"),
            message: DemoLocalization.text(messageKey),
            preferredStyle: .alert
        )
        let presenter = presentedViewController ?? self
        guard !(presenter is UIAlertController),
              presenter.presentedViewController == nil else { return }
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
        presenter.present(alert, animated: true)
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
