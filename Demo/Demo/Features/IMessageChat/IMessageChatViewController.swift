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

    /// 聊天演示页面标题使用的本地化资源键。
    override var localizedTitleKey: String? { "demo.imessage.title" }

    /// 保存消息并生成时间线展示状态的视图模型。
    let viewModel: IMessageChatViewModel
    /// 呈现消息时间线和单元格交互的会话视图。
    let conversationView = IMessageConversationView()
    /// 承载文本、听写和附件草稿输入的视图。
    let composerView = IMessageChatComposerView()
    /// 导航栏中显示联系人头像和副标题的视图。
    let contactTitleView = IMessageContactTitleView(frame: .zero)
    /// 协调页面录音、音频播放和实时听写的控制器。
    let audioController: IMessageChatAudioController
    /// 负责内联文件、链接及混合粘贴草稿的控制器。
    let documentController: IMessageChatDocumentController
    /// 负责照片面板展示和媒体组导入的控制器。
    let photoController: IMessageChatPhotoPickerController
    /// 由页面所有附件功能共享的文件存储。
    let attachmentStore: any IMessageChatAttachmentStoring

    /// 识别已提交音频文件的服务，与输入栏实时听写分开运行。
    private var audioFileTranscriber: any IMessageChatAudioFileTranscribing = IMessageChatAudioFileTranscriber()

    /// 文件转写独立于录音/播放；异步启动保证发送调用栈先完成附件提交。
    private lazy var audioTranscription = IMessageChatAudioTranscriptionCoordinator(
        transcriber: audioFileTranscriber
    ) { [weak self] messageID, attachmentID, text in
        self?.viewModel.updateAudioTranscript(text, messageID: messageID, attachmentID: attachmentID)
    }

    /// 提供系统键盘可见性、几何和动画上下文的观察对象。
    private let keyboardObserver = QuickLayoutKeyboardObserver()
    /// 页面持有的 Combine 订阅，释放时自动取消。
    private var cancellables: Set<AnyCancellable> = []
    /// 当前输入栏需要避让的底部内容遮挡高度，单位为点。
    private var bottomObstruction: CGFloat = 0
    /// 模态菜单暂时接管焦点时，保存编辑器的目标选区。
    private var documentMenuSelection: NSRange?
    /// 以页面视图为坐标基准协调键盘与照片面板交接的对象。
    private lazy var bottomObstructionCoordinator =
        IMessageChatBottomObstructionCoordinator(hostView: view)

    /// 创建共享同一附件目录、使用系统媒体协作者的聊天页面。
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
        audioController: IMessageChatAudioController,
        audioFileTranscriber: (any IMessageChatAudioFileTranscribing)? = nil
    ) {
        let attachmentStore = audioController.attachmentStore
        self.viewModel = viewModel
        self.audioFileTranscriber = audioFileTranscriber ?? IMessageChatAudioFileTranscriber()
        self.audioController = audioController
        self.attachmentStore = attachmentStore
        documentController = IMessageChatDocumentController(store: attachmentStore)
        photoController = IMessageChatPhotoPickerController(
            attachmentStore: attachmentStore
        )
        super.init(nibName: nil, bundle: nil)
    }

    /// 使用指定消息模型、音频控制器和附件存储组装页面依赖。
    private init(
        viewModel: IMessageChatViewModel,
        audioController: IMessageChatAudioController,
        attachmentStore: any IMessageChatAttachmentStoring
    ) {
        self.viewModel = viewModel
        self.audioController = audioController
        self.attachmentStore = attachmentStore
        documentController = IMessageChatDocumentController(store: attachmentStore)
        photoController = IMessageChatPhotoPickerController(
            attachmentStore: attachmentStore
        )
        super.init(nibName: nil, bundle: nil)
    }

    /// 不支持从归档创建 `IMessageChatViewController`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        let audioController = IMessageChatAudioController()
        self.audioController = audioController
        let attachmentStore = audioController.attachmentStore
        self.attachmentStore = attachmentStore
        documentController = IMessageChatDocumentController(store: attachmentStore)
        photoController = IMessageChatPhotoPickerController(
            attachmentStore: attachmentStore
        )
        viewModel = IMessageChatViewModel(
            replyAudioSynthesizer: audioController
        )
        super.init(coder: coder)
    }

    /// 定义 `IMessageChatViewController` 的布局层级、间距和对齐方式。
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

    /// 配置导航标题、保存状态与交互绑定，并开始观察消息和底部遮挡变化。
    override func viewDidLoad() {
        quickLayoutKeyboardSafeAreaBehavior = .disabled
        super.viewDidLoad()

        contactTitleView.sizeToFit()
        navigationItem.titleView = contactTitleView
        view.backgroundColor = .systemBackground
        conversationView.attachmentSaveState = { [weak self] key in
            self?.attachmentSaveCoordinator.state(for: key) ?? .available
        }
        attachmentSaveCoordinator.stateDidChange = { [weak self] key, state in
            self?.conversationView.updateSaveState(state, for: key)
            if state == .completed {
                UIAccessibility.post(notification: .announcement, argument: DemoLocalization.text("imessage.save.completed"))
            }
        }
        attachmentSaveCoordinator.failed = { [weak self] error in self?.presentAttachmentSaveFailure(error) }
        configureInteractions()
        #if DEBUG
        if let fixture = try? IMessageChatSavePreviewFixtures.attachment(store: attachmentStore) {
            viewModel.appendSavePreviewAttachment(fixture)
        }
        #endif
        bindViewModel()
        observeKeyboard()
        configureBottomObstruction()
    }

    /// 在页面布局完成后重新采样键盘与照片面板的遮挡几何。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        bottomObstructionCoordinator.refreshGeometry()
    }

    /// 管理附件保存操作、状态反馈和页面退出失效的协调器。
    private let attachmentSaveCoordinator = IMessageChatAttachmentSaveCoordinator()
    /// 指示页面或其父容器正在退出聊天层级的布尔值。
    private var isLeavingChat = false
    /// 指示页面退出清理已经执行的布尔值，防止重复取消和删除资源。
    private var hasCleanedUpChat = false

    /// 在页面即将出现时重置退出标记，使取消返回手势后仍可继续使用。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isLeavingChat = false
    }

    /// 停止当前音频播放，并沿父控制器层级判断是否正在退出聊天。
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        audioController.stopPlayback()
        // 同时覆盖聊天页自身退出和导航/Tab 等父容器被关闭。
        var ancestor: UIViewController? = self
        while let controller = ancestor {
            if controller.isMovingFromParent || controller.isBeingDismissed {
                isLeavingChat = true
                break
            }
            ancestor = controller.parent
        }
    }

    /// 在页面确实退出且转场未取消时统一清理任务、草稿、面板与附件目录。
    ///
    /// 临时被其他界面覆盖不触发整页资源清理。
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // 临时覆盖只停播放；交互式返回取消后仍需要这些附件和页面任务。
        guard isLeavingChat, transitionCoordinator?.isCancelled != true,
              !hasCleanedUpChat else { return }
        hasCleanedUpChat = true
        attachmentSaveCoordinator.invalidate()
        composerView.dismissRecordingUnavailableHint()
        composerView.pasteCoordinator.invalidate()
        audioTranscription.cancelAll()
        viewModel.cancelPendingReply()
        audioController.stopAll()
        audioController.cancelRecordingOrPreview()
        photoController.dismissPicker(animated: false)
        photoController.discardDraft()
        documentController.discardAll()
        bottomObstructionCoordinator.stop()
        attachmentStore.removeAll()
    }

    /// 刷新联系人、输入栏、媒体动作和时间线使用的本地化内容。
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
                pauseAudio: DemoLocalization.text("imessage.audio.pause"),
                recordingRequiresEmptyDraft: DemoLocalization.text(
                    "imessage.audio.record.requiresEmptyDraft"
                ),
                file: DemoLocalization.text("imessage.attachment.file"),
                link: DemoLocalization.text("imessage.attachment.link")
            ),
            mediaStrings: mediaStrings
        )
        conversationView.configureMediaStrings(mediaStrings)
        viewModel.refreshLocalizedContent()
    }

    /// 将应用布局方向同步到输入栏、联系人标题和消息时间线。
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

    /// 连接输入栏动作、媒体状态、文档插入和消息交互到页面控制器。
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
        documentController.willInsert = { [weak self] in
            guard let self else { return }
            if let selection = documentMenuSelection {
                documentMenuSelection = nil
                if NSMaxRange(selection) <= composerView.textView.textStorage.length {
                    composerView.textView.selectedRange = selection
                }
            }
            prepareForDocumentSelection()
        }
        documentController.pickerCancelled = { [weak self] in self?.documentMenuSelection = nil }
        composerView.pasteAttachments = { [weak self] sources in self?.documentController.insertPasted(sources) }
        documentController.contentsInserted = { [weak self] contents in self?.composerView.insertContents(contents) }
        documentController.draftInserted = { [weak self] draft in
            self?.composerView.insertDocument(draft)
        }
        documentController.draftUpdated = { [weak self] draft in
            self?.composerView.updateDocument(draft)
        }
        photoController.stateDidChange = { [weak self] draft in
            guard let self else { return }
            if let draft, !draft.items.isEmpty {
                prepareForDocumentSelection()
            }
            composerView.applyMediaDraft(draft)
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
        case .sendText(let text), .sendMediaDraft(let text):
            return sendComposerDraft(segments: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.text(text)])
        case .sendDocuments(let segments):
            return sendComposerDraft(segments: segments)
        case .removeDocument(let id):
            documentController.remove(id)
            return true
        case .openDocument(let id):
            guard let draft = documentController.drafts[id], draft.status == .ready else { return false }
            audioController.stopPlayback()
            documentController.open(draft.attachment, from: presentedViewController ?? self)
            return true
        case .insertLink(let url):
            return documentController.insertLink(url)

        case .removeMediaDraftItem(let id):
            photoController.removeItem(id: id)
            return true

        case .requestAttachment(let kind):
            switch kind {
            case .photo:
                audioController.stopPlayback()
                photoController.present(
                    from: self,
                    keyboardHeight: bottomObstructionCoordinator
                        .storedKeyboardContentHeight
                )
                return true
            case .file:
                audioController.stopPlayback()
                documentMenuSelection = composerView.textView.selectedRange
                documentController.presentPicker(from: presentedViewController ?? self)
                return true
            case .link:
                documentMenuSelection = composerView.textView.selectedRange
                presentLinkEntry()
                return true
            case .audio:
                guard composerView.validateAudioRecordingRequest() else {
                    return false
                }
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
            guard composerView.canSendAudioDraft, photoController.draft == nil, documentController.drafts.isEmpty else { return false }
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

    /// 选择项目才改变音频状态；打开或关闭面板不触发此方法。
    private func prepareForDocumentSelection() {
        switch audioController.state {
        case .recording:
            audioController.cancelRecordingOrPreview()
        case .audioPreview:
            if let audio = audioController.takePreviewForFileAttachment() {
                documentController.adoptRecording(audio)
            }
        case .preparingSpeech, .dictating: audioController.stopDictation()
        case .idle: break
        }
    }

    /// 解析并核对完整文档快照，照片面板在先，编辑器片段保持原位置。
    private func sendComposerDraft(segments: [IMessageChatDraftSegment]) -> Bool {
        let ids = segments.compactMap { segment -> UUID? in
            if case .attachment(let id) = segment { return id }; return nil
        }
        guard !composerView.isShowingRecordingUnavailableHint,
              composerView.mediaDraft?.canSend != false,
              segments == composerView.draftSegments,
              let documents = documentController.attachments(for: ids) else { return false }
        let documentsByID = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        var contents: [IMessageChatMessageContent] = []
        if let draft = photoController.draft {
            guard let media = draft.attachment else { return false }
            contents.append(.attachment(.mediaGroup(media)))
        }
        for segment in segments {
            switch segment {
            case .attachment(let id):
                guard let attachment = documentsByID[id] else { return false }
                contents.append(.attachment(attachment))
            case .text(let text):
                if let url = IMessageChatPasteSource.webURL(in: text) {
                    contents.append(.attachment(.link(.init(url: url))))
                } else {
                    contents.append(.userText(text))
                }
            }
        }
        guard viewModel.sendContents(contents) else {
            presentMediaFailure(.mediaInvalid)
            return false
        }
        documentController.commit(ids)
        if photoController.draft != nil { _ = photoController.commitDraft() }
        photoController.dismissPicker(animated: true)
        return true
    }

    /// 展示网页地址输入框，并将有效 URL 交给文档草稿控制器。
    private func presentLinkEntry() {
        let alert = UIAlertController(title: DemoLocalization.text("imessage.attachment.link"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://example.com"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: DemoLocalization.text("imessage.action.cancel"), style: .cancel) { [weak self] _ in
            self?.documentMenuSelection = nil
        })
        let add = UIAlertAction(title: DemoLocalization.text("imessage.attachment.add"), style: .default) { [weak self, weak alert] _ in
            guard let self, let value = alert?.textFields?.first?.text,
                  let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            _ = documentController.insertLink(url)
        }
        add.isEnabled = false
        alert.textFields?.first?.addAction(UIAction { [weak alert, weak add] _ in
            let value = alert?.textFields?.first?.text ?? ""
            add?.isEnabled = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)).map(IMessageChatLinkAttachment.accepts) ?? false
        }, for: .editingChanged)
        alert.addAction(add)
        (presentedViewController ?? self).present(alert, animated: true)
    }

    /// 根据附件保存错误显示本地化提示，并按需提供系统设置入口。
    private func presentAttachmentSaveFailure(_ error: Error) {
        guard !hasCleanedUpChat, viewIfLoaded?.window != nil, presentedViewController == nil else { return }
        let denied = (error as? IMessageChatAttachmentSaveError) == .photoPermissionDenied
        let alert = UIAlertController(title: DemoLocalization.text("imessage.error.title"),
            message: DemoLocalization.text(denied ? "imessage.save.permissionDenied" : "imessage.save.failed"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: DemoLocalization.text("imessage.action.ok"), style: .cancel))
        if denied {
            alert.addAction(UIAlertAction(title: DemoLocalization.text("imessage.action.settings"), style: .default) { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
        }
        present(alert, animated: true)
    }

    /// 把时间线消息操作路由到类型专属的页面协调器。
    ///
    /// - Parameter action: Cell 发出的值类型操作。
    private func handleMessageAction(_ action: IMessageChatMessageAction) {
        switch action {
        case .retryMessage(let messageID):
            viewModel.retryMessage(id: messageID)
        case .saveAttachment(let messageID, let attachment):
            guard let message = viewModel.state.timeline.compactMap({ item -> IMessageChatMessagePresentation? in
                guard case .message(let message) = item.content else { return nil }
                return message
            }).first(where: { $0.id == messageID && $0.content == .attachment(attachment) }) else { return }
            attachmentSaveCoordinator.save(message: message, from: self)
        case .openDocument(let attachment):
            audioController.stopPlayback()
            documentController.open(attachment, from: presentedViewController ?? self)
        case .toggleAudioPlayback(let messageID, let attachment):
            audioController.toggleMessagePlayback(
                messageID: messageID,
                attachment: attachment
            )
        case .openMediaGroup(_, let attachment, let index):
            audioController.stopPlayback()
            let preview = IMessageChatMediaPreviewController(
                group: attachment,
                initialIndex: index,
                strings: makeMediaStrings(),
                playbackCoordinator: audioController.playbackCoordinator
            )
            present(preview, animated: true)
        }
    }

    /// 绑定视图模型更新，将新状态渲染到时间线并提交待转写的音频文件。
    private func bindViewModel() {
        viewModel.bind { [weak self] state, reason in
            guard let self else { return }
            conversationView.render(state, reason: reason)
            audioTranscription.enqueue(state, locale: IMessageChatSpeechConfiguration.recognitionLocale(
                for: DemoLocalization.localizationController.currentLocale.locale
            ))
        }
    }

    /// 观察键盘事件，更新照片面板高度缓存并按遮挡协调结果决定是否跟随滚动。
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

    /// 绑定有效遮挡高度变化，按动画来源更新输入栏位置并保留历史消息阅读位置。
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

    /// 按当前应用语言生成媒体界面共用的文字集合。
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
/// 创建使用固定时钟与示例依赖的完整聊天页面预览。
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
