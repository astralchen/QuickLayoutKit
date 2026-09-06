//
//  IMessageChatComposerView.swift
//  Demo
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 保持设计尺寸并把实际命中区域扩展到最小触控尺寸的按钮。
///
/// 视觉尺寸可以小于 44 点；命中测试会围绕按钮中心对称扩展，但不会改变
/// Auto Layout、QuickLayout 或辅助功能报告的视觉边界。
@available(iOS 26.0, *)
final class IMessageChatComposerHitButton: UIButton {

    /// 按钮响应触控所使用的最小尺寸。
    var minimumHitSize = CGSize(width: 44, height: 44)

    override func point(
        inside point: CGPoint,
        with event: UIEvent?
    ) -> Bool {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else {
            return false
        }
        let horizontalInset = min(
            0,
            (bounds.width - minimumHitSize.width) / 2
        )
        let verticalInset = min(
            0,
            (bounds.height - minimumHitSize.height) / 2
        )
        return bounds.insetBy(
            dx: horizontalInset,
            dy: verticalInset
        ).contains(point)
    }
}

/// ``IMessageChatComposerView`` 使用的本地化字符串。
nonisolated struct IMessageChatComposerStrings: Equatable, Sendable {
    let placeholder: String
    let send: String
    let addAttachment: String
    let audio: String
    let dictate: String
    let stopDictation: String
    let stopRecording: String
    let cancelAudio: String
    let playAudio: String
    let pauseAudio: String
}

/// 输入栏当前可以请求的附件类型。
///
/// 菜单只能展示已经接入完整选择、预览、发送和清理流程的类型，并由
/// ViewController 选择对应协调器；Composer 不直接呈现
/// `PHPickerViewController`、播放器或相机界面。
nonisolated enum IMessageChatAttachmentKind: Equatable, Sendable {
    case photo
    case audio
}

/// 用户从消息输入栏发起的操作。
///
/// 单一动作入口防止每增加一种附件就继续增加多组可选闭包。返回值只表示动作是否
/// 被业务层接受；文本仅在 `.sendText` 返回 `true` 后清空，附件草稿也只在发送
/// 成功后由其所有者提交。
nonisolated enum IMessageChatComposerAction: Equatable, Sendable {
    case sendText(String)
    case sendMediaDraft(String)
    case removeMediaDraftItem(UUID)
    case requestAttachment(kind: IMessageChatAttachmentKind)
    case stopAudioRecording
    case cancelAttachmentDraft
    case sendAttachmentDraft
    case toggleAudioPreviewPlayback
    case startDictation
    case stopDictation
    case manualEditDuringDictation
}

/// 消息输入栏渲染的互斥展示状态。
///
/// 状态只包含 View 所需的值类型数据，不持有录音器、播放器或语音识别任务。
/// 媒体预览只传递值类型草稿，不把资源选择器或播放器对象放入输入栏状态。
nonisolated enum IMessageChatComposerState: Equatable, Sendable {
    case idle
    case preparingSpeech
    case dictating(text: String)
    case recording(elapsed: TimeInterval, waveform: [Float])
    case audioPreview(
        attachment: IMessageChatAudioAttachment,
        isPlaying: Bool,
        progress: Double
    )
}

/// 支持文本、照片/视频草稿、语音转写文本和音频消息的 Liquid Glass 输入栏。
///
/// 此视图渲染页面媒体控制器提供的状态，不持有录音器、播放器或语音识别任务。
@available(iOS 26.0, *)
final class IMessageChatComposerView: QuickLayoutView, UITextViewDelegate {

    /// 会改变输入栏视图层级或固有高度的展示模式。
    ///
    /// 录音计量和播放进度属于同一模式内的数据更新，不应触发 Composer
    /// 重新布局，否则高频刷新会使玻璃背景和固定内边距产生视觉抖动。
    private enum LayoutMode: Equatable {
        case idle
        case preparingSpeech
        case dictating
        case recording
        case preview
        case mediaDraft
    }

    private enum Metrics {
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 8
        static let textInputHeight: CGFloat = 44
        static let textActionWidth: CGFloat = 44

        /// 文本和音频预览发送按钮共用的横向胶囊视觉尺寸。
        ///
        /// 该尺寸来自 iPhone 16 Pro 设计图的 @3x 像素测量；按钮命中区域
        /// 仍由 ``IMessageChatComposerHitButton`` 扩展到 44 × 44 点。
        static let sendButtonWidth: CGFloat = 38
        static let sendButtonHeight: CGFloat = 28
        static let textDictationButtonHeight: CGFloat = 40
        static let textActionSpacing: CGFloat = 4
        static let textLeadingPadding: CGFloat = 4
        static let textTrailingPadding: CGFloat = 6

        /// 文本发送按钮与输入玻璃底边之间的设计间距。
        ///
        /// 此值只用于文本输入玻璃；录音面板继续使用独立的 64 点胶囊布局。
        static let textSendBottomPadding: CGFloat = 6

        /// 麦克风按钮用于保持与文本发送按钮相同的尾部布局高度。
        static let textDictationBottomPadding: CGFloat = 2
        static let mediaInputHeight: CGFloat = 64
        static let recordingHorizontalSpacing: CGFloat = 12

        /// 录音和预览玻璃内所有内容共用的四边基础内边距。
        ///
        /// 两种媒体状态必须从相同的内容边界开始布局，避免状态切换时玻璃内
        /// 控件产生水平或垂直跳动。
        static let mediaContentPadding: CGFloat = 14

        /// 实时录音波形在共享内容边界内使用的额外起始留白。
        ///
        /// 该留白用于匹配设计图中没有前置播放按钮时的波形视觉起点；停止按钮
        /// 仍然只使用共享的 14 点结束内边距。
        static let recordingWaveformLeadingInset: CGFloat = 14
        static let mediaControlSize: CGFloat = 36
        static let mediaControlHitSize: CGFloat = 44
        static let previewHorizontalSpacing: CGFloat = 8
        static let mediaDraftHeight: CGFloat = 120
        static let mediaDraftSpacing: CGFloat = 8
    }

    let textView = UITextView()
    let placeholderLabel = UILabel()
    let attachmentButton = UIButton(type: .system)
    let sendButton = IMessageChatComposerHitButton(type: .system)
    let dictationButton = UIButton(type: .system)
    let recordingStopButton = IMessageChatComposerHitButton(type: .system)
    let audioCancelButton = UIButton(type: .system)
    let audioPlayButton = IMessageChatComposerHitButton(type: .system)
    let audioSendButton = IMessageChatComposerHitButton(type: .system)
    let recordingWaveformView = IMessageWaveformView()
    let previewWaveformView = IMessageWaveformView()
    let recordingDurationLabel = UILabel()
    let previewDurationLabel = UILabel()
    let mediaDraftStripView = IMessageChatMediaDraftStripView()
    let mediaDraftSeparatorView = UIView()

    /// 用户在输入栏中发起操作时调用。
    ///
    /// 处理方应对成功接受的动作返回 `true`。发送动作返回 `false` 时，Composer
    /// 会保留当前文本或附件预览，避免验证、导入或文件失效导致草稿丢失。
    var actionRequested: ((IMessageChatComposerAction) -> Bool)?

    /// 输入栏固有高度发生变化时调用。
    var heightDidChange: (() -> Void)?

    /// 文本编辑器取得第一响应者时调用，用于完成照片 Sheet 到键盘的交接。
    var textInputDidBeginEditing: (() -> Void)?

    private var strings = IMessageChatComposerStrings(
        placeholder: "iMessage",
        send: "Send",
        addAttachment: "Add attachment",
        audio: "Audio",
        dictate: "Dictate",
        stopDictation: "Stop dictation",
        stopRecording: "Stop recording",
        cancelAudio: "Cancel audio",
        playAudio: "Play audio",
        pauseAudio: "Pause audio"
    )
    private var composerState: IMessageChatComposerState = .idle
    private var mediaDraft: IMessageChatMediaDraftPresentation?
    private var mediaStrings = IMessageChatMediaStrings(
        photo: "Photos",
        itemsFormat: "%d items",
        image: "Image",
        animatedImage: "Animated image",
        video: "Video",
        videoDurationFormat: "Video, duration %@",
        importing: "Importing",
        remove: "Remove",
        play: "Play",
        openPreview: "Open preview",
        close: "Close",
        firstItem: "First item",
        lastItem: "Last item",
        positionFormat: "%d of %d"
    )
    private var currentInputHeight = Metrics.textInputHeight
    private var isApplyingTranscription = false

    private lazy var attachmentGlassView: QuickLayoutVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let glassView = QuickLayoutVisualEffectView(
            effect: effect
        ) { [unowned self] in
            attachmentButton.resizable().frame(width: 44, height: 44)
        }
        glassView.cornerConfiguration = .capsule()
        return glassView
    }()

    private lazy var editorContainer: QuickLayoutView = QuickLayoutView { [self] in
        ZStack(alignment: .topLeading) { [unowned self] in
            self.textView.resizable()
            self.placeholderLabel
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        }
    }

    private lazy var inputGlassView: QuickLayoutVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return QuickLayoutVisualEffectView(effect: effect) { [unowned self] in
            VStack(spacing: 0) {
                if mediaDraft != nil {
                    mediaDraftStripView
                        .resizable(axis: .horizontal)
                        .frame(height: Metrics.mediaDraftHeight)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    mediaDraftSeparatorView
                        .resizable(axis: .horizontal)
                        .frame(height: hairlineHeight)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(
                            .bottom,
                            Metrics.mediaDraftSpacing
                                - 4
                                - hairlineHeight
                        )
                }
                HStack(
                    alignment: .bottom,
                    spacing: Metrics.textActionSpacing
                ) {
                    editorContainer
                        .resizable(axis: .horizontal)
                        .frame(height: currentInputHeight)
                        .onGeometryChange(
                            for: CGFloat.self,
                            of: { max(0, $0.size.width - 8) },
                            action: { [weak self] width in
                                self?.updateTextHeight(availableWidth: width)
                            }
                        )
                    textActionLayout
                }
                .padding(.leading, Metrics.textLeadingPadding)
                .padding(.trailing, Metrics.textTrailingPadding)
            }
        }
    }()

    private lazy var recordingGlassView: QuickLayoutVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let glassView = QuickLayoutVisualEffectView(
            effect: effect
        ) { [unowned self] in
            HStack(
                alignment: .center,
                spacing: Metrics.recordingHorizontalSpacing
            ) {
                recordingWaveformView
                    .resizable(axis: .horizontal)
                    .frame(height: 30)
                    .padding(
                        .leading,
                        Metrics.recordingWaveformLeadingInset
                    )
                recordingDurationLabel.fixedSize()
                recordingStopButton
                    .resizable()
                    .frame(
                        width: Metrics.mediaControlSize,
                        height: Metrics.mediaControlSize
                    )
            }
            .padding(Metrics.mediaContentPadding)
        }
        glassView.cornerConfiguration = .capsule()
        return glassView
    }()

    private lazy var previewGlassView: QuickLayoutVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let glassView = QuickLayoutVisualEffectView(
            effect: effect
        ) { [unowned self] in
            HStack(spacing: Metrics.previewHorizontalSpacing) {
                audioPlayButton
                    .resizable()
                    .frame(
                        width: Metrics.mediaControlSize,
                        height: Metrics.mediaControlSize
                    )
                previewWaveformView
                    .resizable(axis: .horizontal)
                    .frame(height: 30)
                previewDurationContainer.fixedSize()
                audioSendButton
                    .resizable()
                    .frame(
                        width: Metrics.sendButtonWidth,
                        height: Metrics.sendButtonHeight
                    )
            }
            .padding(Metrics.mediaContentPadding)
        }
        glassView.cornerConfiguration = .capsule()
        return glassView
    }()

    private lazy var audioCancelGlassView: QuickLayoutVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let glassView = QuickLayoutVisualEffectView(
            effect: effect
        ) { [unowned self] in
            audioCancelButton
                .resizable()
                .frame(
                    width: Metrics.mediaControlHitSize,
                    height: Metrics.mediaControlHitSize
                )
        }
        glassView.cornerConfiguration = .capsule()
        return glassView
    }()

    private lazy var previewDurationContainer = QuickLayoutView { [unowned self] in
        self.previewDurationLabel
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    @LayoutBuilder
    private var textActionLayout: Layout {
        switch composerState {
        case .preparingSpeech, .dictating:
            dictationButton
                .resizable()
                .frame(
                    width: Metrics.textActionWidth,
                    height: Metrics.textDictationButtonHeight
                )
                .padding(.bottom, Metrics.textDictationBottomPadding)
        case .idle, .recording, .audioPreview:
            if hasSendableContent {
                sendButton
                    .resizable()
                    .frame(
                        width: Metrics.sendButtonWidth,
                        height: Metrics.sendButtonHeight
                    )
                    .frame(
                        width: Metrics.textActionWidth,
                        alignment: .trailing
                    )
                    .padding(.bottom, Metrics.textSendBottomPadding)
            } else {
                dictationButton
                    .resizable()
                    .frame(
                        width: Metrics.textActionWidth,
                        height: Metrics.textDictationButtonHeight
                    )
                    .padding(.bottom, Metrics.textDictationBottomPadding)
            }
        }
    }

    @LayoutBuilder
    override var body: Layout {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 8) {
                attachmentGlassView.frame(width: 44, height: 44)
                inputGlassView
                    .resizable(axis: .horizontal)
                    .frame(height: retainedTextInputHeight)
            }

            switch composerState {
            case .recording:
                recordingGlassView
                    .resizable(axis: .horizontal)
                    .frame(height: Metrics.mediaInputHeight)

            case .audioPreview:
                HStack(alignment: .center, spacing: 8) {
                    audioCancelGlassView.frame(
                        width: Metrics.mediaControlHitSize,
                        height: Metrics.mediaControlHitSize
                    )
                    previewGlassView
                        .resizable(axis: .horizontal)
                        .frame(height: Metrics.mediaInputHeight)
                }

            case .idle, .preparingSpeech, .dictating:
                Spacer().frame(width: 0, height: 0)
            }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updateTextHeight()
        }
    }

    override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory
                != traitCollection.preferredContentSizeCategory else {
            return
        }
        updateTextHeight()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: resolvedContentHeight + Metrics.verticalPadding * 2
        )
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width,
            height: resolvedContentHeight + Metrics.verticalPadding * 2
        )
    }

    /// 应用输入栏显示的本地化字符串。
    ///
    /// - Parameter strings: 输入栏当前及后续状态所需的完整字符串集合。
    func configure(
        strings: IMessageChatComposerStrings,
        mediaStrings: IMessageChatMediaStrings? = nil
    ) {
        self.strings = strings
        if let mediaStrings {
            self.mediaStrings = mediaStrings
        }
        placeholderLabel.text = strings.placeholder
        textView.accessibilityLabel = strings.placeholder
        sendButton.accessibilityLabel = strings.send
        attachmentButton.accessibilityLabel = strings.addAttachment
        recordingStopButton.accessibilityLabel = strings.stopRecording
        audioCancelButton.accessibilityLabel = strings.cancelAudio
        audioSendButton.accessibilityLabel = strings.send
        updateAttachmentMenu()
        updateComposerState()
        mediaDraftStripView.configure(mediaDraft, strings: self.mediaStrings)
        if case .audioPreview(_, let isPlaying, _) = composerState {
            audioPlayButton.accessibilityLabel = isPlaying
                ? strings.pauseAudio
                : strings.playAudio
        }
    }

    /// 应用照片选择器产生的有序媒体草稿。
    func applyMediaDraft(_ draft: IMessageChatMediaDraftPresentation?) {
        let previousLayoutMode = layoutMode
        let previousContentHeight = resolvedContentHeight
        mediaDraft = draft
        mediaDraftStripView.configure(draft, strings: mediaStrings)
        updateAttachmentMenu()
        updateComposerState()
        inputGlassView.setNeedsQuickLayout()
        setNeedsQuickLayout()
        let layoutChanged = previousLayoutMode != layoutMode
            || abs(previousContentHeight - resolvedContentHeight) > 0.5
        if layoutChanged {
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
            heightDidChange?()
        }
    }

    /// 渲染页面协调器生成的输入栏状态。
    ///
    /// - Parameter state: 当前音频录制、预览或语音转写状态。传入
    ///   ``IMessageChatComposerState/idle`` 会恢复普通文本输入栏，但不会
    ///   修改其中的草稿。
    func applyState(_ state: IMessageChatComposerState) {
        let previousLayoutMode = layoutMode
        let previousContentHeight = resolvedContentHeight
        composerState = state
        switch state {
        case .idle:
            break
        case .preparingSpeech:
            dictationButton.isEnabled = false
        case .dictating(let text):
            dictationButton.isEnabled = true
            isApplyingTranscription = true
            textView.text = text
            isApplyingTranscription = false
            updateTextHeight()
        case .recording(let elapsed, let waveform):
            recordingWaveformView.samples = waveform
            recordingWaveformView.progress = 1
            let durationText = IMessageAudioBubbleView.durationText(elapsed)
            recordingDurationLabel.text = durationText
            recordingStopButton.accessibilityValue = durationText
        case .audioPreview(let attachment, let isPlaying, let progress):
            previewWaveformView.samples = attachment.waveform
            previewWaveformView.progress = progress
            let durationText = IMessageAudioBubbleView.durationText(
                attachment.duration
            )
            let elapsedText = IMessageAudioBubbleView.durationText(
                attachment.duration * progress
            )
            previewDurationLabel.text = "+ \(durationText)"
            audioPlayButton.configuration?.image = UIImage(
                systemName: isPlaying ? "pause.fill" : "play.fill"
            )
            audioPlayButton.accessibilityLabel = isPlaying
                ? strings.pauseAudio
                : strings.playAudio
            audioPlayButton.accessibilityValue = "\(elapsedText) / \(durationText)"
        }

        let layoutModeChanged = previousLayoutMode != layoutMode
        let contentHeightChanged = abs(
            previousContentHeight - resolvedContentHeight
        ) > 0.5

        // 转写文本会改变占位符、可发送状态和文本高度；录音计量及播放进度
        // 只更新现有视图内容，保持媒体胶囊的几何与内边距不变。
        if layoutModeChanged || layoutMode == .dictating {
            updateComposerState()
        }
        if layoutModeChanged {
            inputGlassView.setNeedsQuickLayout()
            setNeedsQuickLayout()
            superview?.setNeedsLayout()
        }
        if contentHeightChanged {
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
            heightDidChange?()
        }
    }

    /// 应用输入栏所有控件所使用的语义方向。
    func applyLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        let semanticAttribute = direction.appLayoutDirection
            .semanticContentAttribute
        semanticContentAttribute = semanticAttribute
        attachmentGlassView.semanticContentAttribute = semanticAttribute
        inputGlassView.semanticContentAttribute = semanticAttribute
        recordingGlassView.semanticContentAttribute = semanticAttribute
        previewGlassView.semanticContentAttribute = semanticAttribute
        audioCancelGlassView.semanticContentAttribute = semanticAttribute
        previewDurationContainer.semanticContentAttribute = semanticAttribute
        mediaDraftStripView.semanticContentAttribute = semanticAttribute
        mediaDraftSeparatorView.semanticContentAttribute = semanticAttribute
        textView.semanticContentAttribute = semanticAttribute
        textView.textAlignment = .natural
        placeholderLabel.semanticContentAttribute = semanticAttribute
        placeholderLabel.textAlignment = .natural
        setNeedsQuickLayout()
    }

    func textViewDidChange(_ textView: UITextView) {
        updateComposerState()
        updateTextHeight()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        textInputDidBeginEditing?()
    }

    /// 在 UIKit 应用手动文本编辑前停止正在进行的语音转写。
    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        if case .dictating = composerState, !isApplyingTranscription {
            _ = actionRequested?(.manualEditDuringDictation)
        }
        return true
    }

    private var resolvedContentHeight: CGFloat {
        switch composerState {
        case .idle, .preparingSpeech, .dictating:
            currentInputHeight + mediaDraftAdditionalHeight
        case .recording, .audioPreview:
            Metrics.mediaInputHeight
        }
    }

    /// 返回当前媒体状态对应的稳定布局模式。
    private var layoutMode: LayoutMode {
        switch composerState {
        case .idle:
            mediaDraft == nil ? .idle : .mediaDraft
        case .preparingSpeech:
            .preparingSpeech
        case .dictating:
            .dictating
        case .recording:
            .recording
        case .audioPreview:
            .preview
        }
    }

    private var retainedTextInputHeight: CGFloat {
        switch composerState {
        case .idle, .preparingSpeech, .dictating:
            currentInputHeight + mediaDraftAdditionalHeight
        case .recording, .audioPreview:
            Metrics.textInputHeight
        }
    }

    private var hasSendableText: Bool {
        !(textView.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var hasSendableContent: Bool {
        if let mediaDraft {
            return mediaDraft.canSend
        }
        return hasSendableText
    }

    private var mediaDraftAdditionalHeight: CGFloat {
        mediaDraft == nil
            ? 0
            : Metrics.mediaDraftHeight + Metrics.mediaDraftSpacing + 4
    }

    /// 当前显示环境的单个物理像素，避免 iOS 26 已弃用的全局屏幕查询。
    private var hairlineHeight: CGFloat {
        1 / max(1, traitCollection.displayScale)
    }

    private func configureViews() {
        accessibilityIdentifier = "imessage.composer"
        backgroundColor = .clear
        quickLayoutHorizontalFlexibility = .fullyFlexible
        quickLayoutVerticalFlexibility = .fixedSize

        mediaDraftSeparatorView.backgroundColor = .separator
        mediaDraftSeparatorView.isAccessibilityElement = false

        for glassView in [
            attachmentGlassView,
            inputGlassView,
            recordingGlassView,
            previewGlassView,
            audioCancelGlassView,
        ] {
            glassView.backgroundColor = .clear
            glassView.clipsToBounds = true
            glassView.layer.cornerCurve = .continuous
            glassView.layer.cornerRadius = 22
        }
        recordingGlassView.layer.cornerRadius = Metrics.mediaInputHeight / 2
        previewGlassView.layer.cornerRadius = Metrics.mediaInputHeight / 2
        audioCancelGlassView.layer.cornerRadius = Metrics.mediaControlHitSize / 2

        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.textAlignment = .natural
        textView.textContainerInset = UIEdgeInsets(
            top: 8,
            left: 8,
            bottom: 8,
            right: 4
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardDismissMode = .interactive
        textView.delegate = self
        textView.accessibilityIdentifier = "imessage.composer.text"

        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.isAccessibilityElement = false

        configurePlainButton(
            attachmentButton,
            symbolName: "plus",
            identifier: "imessage.composer.attachment",
            action: nil
        )
        attachmentButton.cornerConfiguration = .capsule()
        attachmentButton.showsMenuAsPrimaryAction = true

        configureProminentButton(
            sendButton,
            symbolName: "arrow.up",
            color: .systemBlue,
            identifier: "imessage.composer.send",
            action: #selector(sendButtonDidTap)
        )
        configurePlainButton(
            dictationButton,
            symbolName: "mic.fill",
            identifier: "imessage.composer.dictation",
            action: #selector(dictationButtonDidTap)
        )
        configureTintedButton(
            recordingStopButton,
            symbolName: "stop.fill",
            color: .systemRed,
            identifier: "imessage.composer.recording.stop",
            action: #selector(recordingStopButtonDidTap)
        )
        configurePlainButton(
            audioCancelButton,
            symbolName: "xmark",
            identifier: "imessage.composer.audio.cancel",
            action: #selector(audioCancelButtonDidTap)
        )
        configureGrayButton(
            audioPlayButton,
            symbolName: "play.fill",
            identifier: "imessage.composer.audio.play",
            action: #selector(audioPlayButtonDidTap)
        )
        configureProminentButton(
            audioSendButton,
            symbolName: "arrow.up",
            color: .systemBlue,
            identifier: "imessage.composer.audio.send",
            action: #selector(audioSendButtonDidTap)
        )

        recordingWaveformView.playedColor = .systemRed
        recordingWaveformView.unplayedColor = UIColor.systemRed
            .withAlphaComponent(0.3)
        recordingWaveformView.minimumBarHeight = 2
        recordingWaveformView.maximumBarHeight = 12
        recordingWaveformView.barWidth = 2
        recordingWaveformView.barSpacing = 2
        recordingWaveformView.fadedLeadingFraction = 0.28
        previewWaveformView.playedColor = .label
        previewWaveformView.unplayedColor = .tertiaryLabel
        previewWaveformView.minimumBarHeight = 2
        previewWaveformView.maximumBarHeight = 12
        previewWaveformView.barWidth = 2
        previewWaveformView.barSpacing = 2

        previewDurationContainer.backgroundColor = .secondarySystemFill
        previewDurationContainer.clipsToBounds = true
        previewDurationContainer.layer.cornerCurve = .continuous
        previewDurationContainer.layer.cornerRadius = 14

        configureDurationLabel(recordingDurationLabel)
        configureDurationLabel(previewDurationLabel)
        recordingDurationLabel.textColor = .systemRed
        previewDurationLabel.textColor = .label
        for button in [
            sendButton,
            recordingStopButton,
            audioPlayButton,
            audioSendButton,
        ] {
            button.minimumHitSize = CGSize(
                width: Metrics.mediaControlHitSize,
                height: Metrics.mediaControlHitSize
            )
        }
        mediaDraftStripView.removeRequested = { [weak self] id in
            _ = self?.actionRequested?(.removeMediaDraftItem(id))
        }
        updateComposerState()
    }

    /// 配置固定高度媒体面板中显示的时钟标签。
    ///
    /// 字体随 Dynamic Type 缩放，但最大字号限制为 24 点，避免辅助功能字号
    /// 完全挤占波形；时长仍保持单行并优先获得完整的水平空间。
    private func configureDurationLabel(_ label: UILabel) {
        let baseFont = UIFont.monospacedDigitSystemFont(
            ofSize: 17,
            weight: .regular
        )
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: baseFont,
            maximumPointSize: 24
        )
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        label.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
    }

    /// 配置在普通态、按下态和菜单高亮态均保持胶囊形状的图标按钮。
    private func configurePlainButton(
        _ button: UIButton,
        symbolName: String,
        identifier: String,
        action: Selector?
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbolName)
        configuration.contentInsets = .zero
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        button.tintColor = .label
        button.accessibilityIdentifier = identifier
        if let action {
            button.addTarget(self, action: action, for: .touchUpInside)
        }
    }

    private func configureProminentButton(
        _ button: UIButton,
        symbolName: String,
        color: UIColor,
        identifier: String,
        action: Selector
    ) {
        var configuration = UIButton.Configuration.prominentGlass()
        configuration.image = UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 17,
                weight: .bold
            )
        )
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        button.configuration = configuration
        button.cornerConfiguration = .capsule()
        button.tintColor = color
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    /// 配置使用浅色强调背景的媒体控制按钮。
    private func configureTintedButton(
        _ button: UIButton,
        symbolName: String,
        color: UIColor,
        identifier: String,
        action: Selector
    ) {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13,
                weight: .bold
            )
        )
        configuration.contentInsets = .zero
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = color
        configuration.baseBackgroundColor = color
        button.configuration = configuration
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    /// 配置使用系统次级填充背景的媒体控制按钮。
    private func configureGrayButton(
        _ button: UIButton,
        symbolName: String,
        identifier: String,
        action: Selector
    ) {
        var configuration = UIButton.Configuration.gray()
        configuration.image = UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13,
                weight: .bold
            )
        )
        configuration.contentInsets = .zero
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .label
        button.configuration = configuration
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func updateAttachmentMenu() {
        let photoAction = UIAction(
            title: mediaStrings.photo,
            image: UIImage(systemName: "photo.on.rectangle")
        ) { [weak self] _ in
            guard let self else { return }
            _ = actionRequested?(
                .requestAttachment(kind: .photo)
            )
        }
        let audioAction = UIAction(
            title: strings.audio,
            image: UIImage(systemName: "waveform")
        ) { [weak self] _ in
            guard let self else { return }
            _ = actionRequested?(
                .requestAttachment(kind: .audio)
            )
        }
        if mediaDraft != nil {
            audioAction.attributes = [.disabled]
        }
        attachmentButton.menu = UIMenu(children: [photoAction, audioAction])
    }

    @objc private func sendButtonDidTap() {
        let text = textView.text ?? ""
        let accepted: Bool
        if mediaDraft != nil {
            accepted = actionRequested?(.sendMediaDraft(text)) == true
        } else {
            accepted = actionRequested?(.sendText(text)) == true
        }
        guard accepted else { return }
        textView.text = nil
        updateComposerState()
        updateTextHeight()
    }

    @objc private func dictationButtonDidTap() {
        switch composerState {
        case .preparingSpeech, .dictating:
            _ = actionRequested?(.stopDictation)
        case .idle, .recording, .audioPreview:
            _ = actionRequested?(.startDictation)
        }
    }

    @objc private func recordingStopButtonDidTap() {
        _ = actionRequested?(.stopAudioRecording)
    }

    @objc private func audioCancelButtonDidTap() {
        _ = actionRequested?(.cancelAttachmentDraft)
    }

    @objc private func audioPlayButtonDidTap() {
        _ = actionRequested?(.toggleAudioPreviewPlayback)
    }

    @objc private func audioSendButtonDidTap() {
        _ = actionRequested?(.sendAttachmentDraft)
    }

    private func updateComposerState() {
        let showsTextInput: Bool
        switch composerState {
        case .idle, .preparingSpeech, .dictating:
            showsTextInput = true
        case .recording, .audioPreview:
            showsTextInput = false
        }
        attachmentGlassView.alpha = showsTextInput ? 1 : 0
        inputGlassView.alpha = showsTextInput ? 1 : 0
        attachmentGlassView.isUserInteractionEnabled = showsTextInput
        // 不禁用文本编辑器的祖先视图，否则 UIKit 会结束当前编辑并收起键盘。
        // alpha 为 0 时容器不参与触摸命中；只隐藏外观即可保留用户已有的焦点。
        attachmentGlassView.accessibilityElementsHidden = !showsTextInput
        inputGlassView.accessibilityElementsHidden = !showsTextInput
        placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
        sendButton.isEnabled = hasSendableContent
        attachmentButton.isEnabled = composerState == .idle
        switch composerState {
        case .preparingSpeech:
            dictationButton.isEnabled = false
            dictationButton.configuration?.showsActivityIndicator = true
            dictationButton.accessibilityLabel = strings.stopDictation
        case .dictating:
            dictationButton.isEnabled = true
            dictationButton.configuration?.showsActivityIndicator = false
            dictationButton.configuration?.image = UIImage(systemName: "stop.fill")
            dictationButton.tintColor = .systemRed
            dictationButton.accessibilityLabel = strings.stopDictation
        case .idle, .recording, .audioPreview:
            dictationButton.isEnabled = true
            dictationButton.configuration?.showsActivityIndicator = false
            dictationButton.configuration?.image = UIImage(systemName: "mic.fill")
            dictationButton.tintColor = .label
            dictationButton.accessibilityLabel = strings.dictate
        }
        inputGlassView.setNeedsQuickLayout()
    }

    private func updateTextHeight(availableWidth: CGFloat? = nil) {
        let font = textView.font ?? .preferredFont(forTextStyle: .body)
        let maximumHeight = ceil(font.lineHeight * 5)
            + textView.textContainerInset.top
            + textView.textContainerInset.bottom
        let width = max(1, availableWidth ?? textView.bounds.width)
        let measuredHeight = textView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
        let resolvedHeight = min(max(44, ceil(measuredHeight)), maximumHeight)
        textView.isScrollEnabled = measuredHeight > maximumHeight + 0.5

        guard abs(resolvedHeight - currentInputHeight) > 0.5 else { return }
        currentInputHeight = resolvedHeight
        inputGlassView.setNeedsQuickLayout()
        setNeedsQuickLayout()
        invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
        heightDidChange?()
    }
}

#if DEBUG
@MainActor
private func makeIMessageChatComposerPreview(
    text: String,
    state: IMessageChatComposerState,
    direction: UIUserInterfaceLayoutDirection
) -> UIViewController {
    let backgroundView = UIView()
    backgroundView.backgroundColor = .systemBackground
    let composerView = IMessageChatComposerView(frame: .zero)
    composerView.configure(strings: IMessageChatPreviewData.composerStrings)
    composerView.applyLayoutDirection(direction)
    composerView.textView.text = text
    composerView.textViewDidChange(composerView.textView)
    composerView.applyState(state)
    return QuickLayoutHostingController {
        ZStack(alignment: .bottom) {
            backgroundView.resizable()
            composerView
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
        }
        .frame(width: 390, height: 170)
    }
}

#Preview("消息输入栏 · 空白") {
    makeIMessageChatComposerPreview(
        text: "",
        state: .idle,
        direction: .leftToRight
    )
}

#Preview("消息输入栏 · 多行") {
    makeIMessageChatComposerPreview(
        text: IMessageChatPreviewData.composerMultilineText,
        state: .idle,
        direction: .leftToRight
    )
}

#Preview("消息输入栏 · 录音") {
    makeIMessageChatComposerPreview(
        text: "",
        state: .recording(
            elapsed: 3,
            waveform: IMessageChatPreviewData.recordingWaveform
        ),
        direction: .leftToRight
    )
}

#Preview("消息输入栏 · 音频预览") {
    makeIMessageChatComposerPreview(
        text: "",
        state: .audioPreview(
            attachment: IMessageChatPreviewData.audioAttachment,
            isPlaying: false,
            progress: 0
        ),
        direction: .leftToRight
    )
}

#Preview("消息输入栏 · RTL") {
    makeIMessageChatComposerPreview(
        text: IMessageChatPreviewData.composerRTLText,
        state: .idle,
        direction: .rightToLeft
    )
}
#endif
