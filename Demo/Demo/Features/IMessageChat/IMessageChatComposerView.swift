//
//  IMessageChatComposerView.swift
//  Demo
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 在临时提示期间冻结键盘和输入法修改，同时保留第一响应者与组合文本。
@available(iOS 26.0, *)
final class IMessageChatTextView: UITextView {
    /// 只拦截编辑，不修改 `isEditable` 或第一响应者状态。
    var isInputSuspended = false
    /// 允许粘贴时、执行系统粘贴之前调用的闭包。
    var willPaste: (() -> Void)?

    /// 在输入未暂停时通知粘贴准备回调，并执行系统粘贴。
    override func paste(_ sender: Any?) {
        guard !isInputSuspended else { return }
        willPaste?()
        super.paste(sender)
    }

    /// 在输入未暂停时将文字交给系统文本输入实现。
    override func insertText(_ text: String) {
        guard !isInputSuspended else { return }
        super.insertText(text)
    }

    /// 在输入未暂停时执行系统向后删除操作。
    override func deleteBackward() {
        guard !isInputSuspended else { return }
        super.deleteBackward()
    }

    /// 在输入未暂停时更新输入法组合文本及其内部选区。
    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        guard !isInputSuspended else { return }
        super.setMarkedText(markedText, selectedRange: selectedRange)
    }

    /// 在输入未暂停时提交当前输入法组合文本。
    override func unmarkText() {
        guard !isInputSuspended else { return }
        super.unmarkText()
    }

    /// 在输入未暂停时使用系统文本输入接口替换指定范围。
    override func replace(_ range: UITextRange, withText text: String) {
        guard !isInputSuspended else { return }
        super.replace(range, withText: text)
    }

    /// 返回当前编辑动作是否可用；输入暂停期间禁用编辑菜单动作。
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        !isInputSuspended && super.canPerformAction(action, withSender: sender)
    }
}

/// 保持设计尺寸并把实际命中区域扩展到最小触控尺寸的按钮。
///
/// 视觉尺寸可以小于 44 点；命中测试会围绕按钮中心对称扩展，但不会改变
/// Auto Layout、QuickLayout 或辅助功能报告的视觉边界。
@available(iOS 26.0, *)
final class IMessageChatComposerHitButton: UIButton {

    /// 按钮响应触控所使用的最小尺寸。
    var minimumHitSize = CGSize(width: 44, height: 44)

    /// 返回指定触点是否位于扩展后的最小触控区域。
    ///
    /// 隐藏、透明或禁止交互时不响应命中；扩展区域不改变视觉边框。
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

/// 照片和内联附件共用的删除按钮。按 iPhone 16 Pro @3x 参考图，
/// 圆形视觉直径为 18 点；照片默认右上内缩 4 点，大圆角附件卡片可增加留白。
/// 44 点控件区域向卡片内部延伸，不随视觉边距变化。
@available(iOS 26.0, *)
final class IMessageChatDraftRemoveButton: UIButton {
    /// 删除符号相对卡片边缘的视觉内缩量，单位为点。
    var visualInset: CGFloat = 4 {
        didSet { setNeedsLayout() }
    }
    /// 承载删除符号的圆形背景视图。
    private let circleView = UIView()
    /// 显示删除叉号的图像视图。
    private let crossView = UIImageView(image: UIImage(
        systemName: "xmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
    ))

    /// 使用指定初始边框创建 `IMessageChatDraftRemoveButton`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        circleView.backgroundColor = UIColor(white: 0.45, alpha: 0.85)
        circleView.layer.cornerRadius = 9
        circleView.isUserInteractionEnabled = false
        crossView.tintColor = .white
        crossView.contentMode = .scaleAspectFit
        circleView.addSubview(crossView)
        addSubview(circleView)
    }

    /// 不支持从归档创建 `IMessageChatDraftRemoveButton`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 按钮的高亮状态；变化时同步调整圆形背景的反馈外观。
    override var isHighlighted: Bool {
        didSet { circleView.alpha = isHighlighted ? 0.6 : 1 }
    }

    /// 根据当前边界更新 `IMessageChatDraftRemoveButton` 的子视图布局与图层几何。
    override func layoutSubviews() {
        super.layoutSubviews()
        circleView.frame = CGRect(
            x: bounds.maxX - visualInset - 18, y: visualInset, width: 18, height: 18
        )
        crossView.frame = circleView.bounds.insetBy(dx: 4, dy: 4)
    }
}

/// ``IMessageChatComposerView`` 使用的本地化字符串。
nonisolated struct IMessageChatComposerStrings: Equatable, Sendable {
    /// 空文本草稿显示的占位文字。
    let placeholder: String
    /// 发送按钮的本地化辅助功能标签。
    let send: String
    /// 附件菜单入口的本地化标签。
    let addAttachment: String
    /// 音频录制菜单项的本地化标题。
    let audio: String
    /// 开始听写操作的本地化标签。
    let dictate: String
    /// 停止听写操作的本地化标签。
    let stopDictation: String
    /// 停止录音操作的本地化标签。
    let stopRecording: String
    /// 取消音频草稿操作的本地化标签。
    let cancelAudio: String
    /// 播放音频操作的本地化标签。
    let playAudio: String
    /// 暂停音频操作的本地化标签。
    let pauseAudio: String
    /// 草稿非空、无法开始录音时显示的提示文字。
    let recordingRequiresEmptyDraft: String
    /// 文件选择菜单项的本地化标题；默认值为 `Files`。
    var file: String = "Files"
    /// 链接插入菜单项的本地化标题；默认值为 `Link`。
    var link: String = "Link"
}

/// 输入栏当前可以请求的附件类型。
///
/// 菜单只能展示已经接入完整选择、预览、发送和清理流程的类型，并由
/// ViewController 选择对应协调器；Composer 不直接呈现
/// `PHPickerViewController`、播放器或相机界面。
nonisolated enum IMessageChatAttachmentKind: Equatable, Sendable {
    /// 从照片图库选择图片或视频。
    case photo
    /// 录制音频附件。
    case audio
    /// 从系统文件选择器导入文件。
    case file
    /// 输入网页 URL 并创建链接附件。
    case link
}

/// 按 TextKit 文档位置排列的发送片段，不携带文件所有权。
nonisolated enum IMessageChatDraftSegment: Equatable, Sendable {
    /// 编辑器中保留原始空格与换行的文字段。
    case text(String)
    /// 按稳定标识符引用的内联附件段。
    case attachment(UUID)
}

/// 一次编辑事务中的正文和附件占位，顺序与用户插入内容一致。
nonisolated enum IMessageChatEditorInsertion {
    /// 在当前选区插入的纯文本内容。
    case text(String)
    /// 在当前选区插入的文档附件草稿。
    case attachment(IMessageChatDocumentDraft)
}

/// 用户从消息输入栏发起的操作。
///
/// 单一动作入口防止每增加一种附件就继续增加多组可选闭包。返回值只表示动作是否
/// 被业务层接受；文本仅在 `.sendText` 返回 `true` 后清空，附件草稿也只在发送
/// 成功后由其所有者提交。
nonisolated enum IMessageChatComposerAction: Equatable, Sendable {
    /// 按编辑器顺序发送文字段与文档附件引用。
    case sendDocuments([IMessageChatDraftSegment])
    /// 删除指定稳定身份的文档草稿。
    case removeDocument(UUID)
    /// 打开指定稳定身份的文档草稿预览。
    case openDocument(UUID)
    /// 将有效网页 URL 插入为链接草稿。
    case insertLink(URL)
    /// 发送指定文本草稿。
    case sendText(String)
    /// 发送当前媒体组草稿及附带的文本。
    case sendMediaDraft(String)
    /// 从媒体草稿中删除指定项目。
    case removeMediaDraftItem(UUID)
    /// 请求显示指定种类的附件输入入口。
    case requestAttachment(kind: IMessageChatAttachmentKind)
    /// 停止当前录音并保留有效音频供预览。
    case stopAudioRecording
    /// 取消当前附件草稿。
    case cancelAttachmentDraft
    /// 发送当前音频附件草稿。
    case sendAttachmentDraft
    /// 切换音频草稿的播放与暂停状态。
    case toggleAudioPreviewPlayback
    /// 请求开始麦克风听写。
    case startDictation
    /// 请求结束当前听写。
    case stopDictation
    /// 报告听写期间发生的手动编辑，使上层停止覆盖文本。
    case manualEditDuringDictation
}

/// 消息输入栏渲染的互斥展示状态。
///
/// 状态只包含 View 所需的值类型数据，不持有录音器、播放器或语音识别任务。
/// 媒体预览只传递值类型草稿，不把资源选择器或播放器对象放入输入栏状态。
nonisolated enum IMessageChatComposerState: Equatable, Sendable {
    /// 没有活动录音或听写的常规文本编辑状态。
    case idle
    /// 正在请求权限或准备语音识别资源。
    case preparingSpeech
    /// 正在听写，并携带当前累计识别文本。
    case dictating(text: String)
    /// 正在录音，并携带已录制秒数与归一化波形。
    case recording(elapsed: TimeInterval, waveform: [Float])
    /// 预览已录制音频，并携带播放状态与 `0...1` 范围的进度。
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
        /// 显示常规文本输入与附件入口。
        case idle
        /// 显示语音识别准备状态。
        case preparingSpeech
        /// 显示活动听写状态。
        case dictating
        /// 显示录音波形、时长与停止操作。
        case recording
        /// 显示音频草稿预览与发送操作。
        case preview
        /// 显示照片或视频草稿条带。
        case mediaDraft
        /// 显示草稿非空时的短暂录音不可用提示。
        case recordingUnavailable
        /// 显示包含内联文档卡片的文本编辑器。
        case documentAttachments
    }

    /// 输入栏各状态共用的布局尺寸，长度单位均为点。
    private enum Metrics {
        /// 输入栏内容相对页面左右边缘的内边距。
        static let horizontalPadding: CGFloat = 16
        /// 输入栏内容相对上下边缘的内边距。
        static let verticalPadding: CGFloat = 8
        /// 单行文本输入区域的基准高度。
        static let textInputHeight: CGFloat = 44
        /// 文本操作区域为发送或听写按钮保留的宽度。
        static let textActionWidth: CGFloat = 44

        /// 文本和音频预览发送按钮共用的横向胶囊视觉尺寸。
        ///
        /// 该尺寸来自 iPhone 16 Pro 设计图的 @3x 像素测量；按钮命中区域
        /// 仍由 ``IMessageChatComposerHitButton`` 扩展到 44 × 44 点。
        static let sendButtonWidth: CGFloat = 38
        /// 发送按钮的视觉高度。
        static let sendButtonHeight: CGFloat = 28
        /// 文本听写按钮的布局高度。
        static let textDictationButtonHeight: CGFloat = 40
        /// 文本操作控件之间的间距。
        static let textActionSpacing: CGFloat = 4
        /// 文本操作区域语义起始侧的额外内边距。
        static let textLeadingPadding: CGFloat = 4
        /// 文本操作区域语义结束侧的额外内边距。
        static let textTrailingPadding: CGFloat = 6

        /// 文本发送按钮与输入玻璃底边之间的设计间距。
        ///
        /// 此值只用于文本输入玻璃；录音面板继续使用独立的 64 点胶囊布局。
        static let textSendBottomPadding: CGFloat = 6

        /// 麦克风按钮用于保持与文本发送按钮相同的尾部布局高度。
        static let textDictationBottomPadding: CGFloat = 2
        /// 录音和音频预览胶囊的高度。
        static let mediaInputHeight: CGFloat = 64
        /// 录音波形与控制区域之间的水平间距。
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
        /// 媒体控制按钮的视觉尺寸。
        static let mediaControlSize: CGFloat = 36
        /// 媒体控制按钮的最小布局触控尺寸。
        static let mediaControlHitSize: CGFloat = 44
        /// 音频预览控件之间的水平间距。
        static let previewHorizontalSpacing: CGFloat = 8
        /// 照片和视频草稿条带的固定高度。
        static let mediaDraftHeight: CGFloat = 120
        /// 媒体草稿条带与其余输入内容之间的间距。
        static let mediaDraftSpacing: CGFloat = 8
    }

    /// 启用 TextKit 2、承载文字与内联附件的文本编辑器。
    let textView = IMessageChatTextView(usingTextLayoutManager: true)
    private lazy var inputBinding = Localization.inputContext(for: self)
        .makeTextInputBinding(to: textView)

    /// 接管系统粘贴并保留文字与附件顺序的协调器。
    lazy var pasteCoordinator = IMessageChatPasteCoordinator(textView: textView)
    /// 粘贴解析出待导入来源后调用的闭包。
    var pasteAttachments: (([IMessageChatPasteSource]) -> Void)?
    /// 编辑器为空时显示提示文字的标签。
    let placeholderLabel = UILabel()
    /// 草稿阻止录音时显示的短暂说明。
    let recordingUnavailableLabel = UILabel()
    /// 展开照片、录音、文件和链接菜单的按钮。
    let attachmentButton = UIButton(type: .system)
    /// 发送当前文字或混合草稿的按钮。
    let sendButton = IMessageChatComposerHitButton(type: .system)
    /// 开始或停止实时听写的按钮。
    let dictationButton = UIButton(type: .system)
    /// 停止录音并保留有效草稿的按钮。
    let recordingStopButton = IMessageChatComposerHitButton(type: .system)
    /// 丢弃当前音频草稿的按钮。
    let audioCancelButton = UIButton(type: .system)
    /// 切换音频草稿播放与暂停的按钮。
    let audioPlayButton = IMessageChatComposerHitButton(type: .system)
    /// 发送当前音频草稿的按钮。
    let audioSendButton = IMessageChatComposerHitButton(type: .system)
    /// 显示实时录音音量的固定槽位波形视图。
    let recordingWaveformView = IMessageWaveformView()
    /// 显示音频草稿波形和播放位置的视图。
    let previewWaveformView = IMessageWaveformView()
    /// 显示当前已录制时长的标签。
    let recordingDurationLabel = UILabel()
    /// 显示音频预览时长或播放时间的标签。
    let previewDurationLabel = UILabel()
    /// 按选择顺序显示照片和视频草稿的横向条带。
    let mediaDraftStripView = IMessageChatMediaDraftStripView()
    /// 分隔媒体草稿与文本操作区域的视图。
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

    /// 当前输入栏使用的本地化文字集合。
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
        pauseAudio: "Pause audio",
        recordingRequiresEmptyDraft: "To record audio, clear the input field."
    )
    /// 驱动录音、听写和预览控件显示的媒体状态。
    private var composerState: IMessageChatComposerState = .idle
    /// 当前有序媒体草稿；提示只改变展示，导入结果继续通过 `applyMediaDraft` 更新。
    private(set) var mediaDraft: IMessageChatMediaDraftPresentation?
    /// 媒体草稿及预览操作使用的本地化文字集合。
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
    /// 最近一次测量得到的文本输入高度，单位为点。
    private var currentInputHeight = Metrics.textInputHeight
    /// 指示正在回填识别文本的布尔值，避免将更新误判为手动输入。
    private var isApplyingTranscription = false
    /// 按稳定身份保存的活跃 TextKit 附件对象。
    private(set) var textAttachments: [UUID: IMessageChatTextAttachment] = [:]
    /// 指示正在核对编辑器附件身份的布尔值，用于阻止递归核对。
    private var isReconcilingAttachments = false
    /// 指示混合内容替换事务尚未结束的布尔值，用于忽略中间编辑回调。
    private var isInsertingContents = false

    /// 提示属于输入栏展示状态，不占用音频控制器或麦克风。
    private(set) var isShowingRecordingUnavailableHint = false
    /// 可注入的等待操作，让测试无需真实等待两秒。
    var recordingHintSleeper: @MainActor @Sendable (Duration) async throws -> Void = {
        try await Task.sleep(for: $0)
    }
    /// 控制录音不可用提示自动结束的延时任务。
    private var recordingHintTask: Task<Void, Never>?
    /// 录音提示操作的递增版本，用于忽略旧任务的完成回调。
    private var recordingHintGeneration = 0
    /// 提示期间保留的文本滚动偏移，在恢复布局后应用。
    private var retainedTextContentOffset: CGPoint?

    /// 附件菜单按钮使用的玻璃背景容器。
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

    /// 组织文本编辑器、媒体草稿与操作区域的布局容器。
    private lazy var editorContainer: QuickLayoutView = QuickLayoutView { [self] in
        ZStack(alignment: .topLeading) { [unowned self] in
            self.textView.resizable()
            self.placeholderLabel
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
                .padding(.horizontal, 8)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )
            self.recordingUnavailableLabel
                .resizable()
                .padding(.horizontal, 8)
        }
    }

    /// 常规文本输入区域使用的玻璃背景容器。
    private lazy var inputGlassView: QuickLayoutVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return QuickLayoutVisualEffectView(effect: effect) { [unowned self] in
            VStack(spacing: 0) {
                if mediaDraft != nil && !isShowingRecordingUnavailableHint {
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
                VStack(spacing: 0) {
                    if documentActionHeight > 0 {
                        // 附件占用完整编辑宽度，发送操作只占下方一行。
                        textEditorLayout
                        textActionLayout.frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        HStack(alignment: .bottom, spacing: Metrics.textActionSpacing) {
                            textEditorLayout
                            textActionLayout
                        }
                    }
                }
                .padding(.leading, Metrics.textLeadingPadding)
                .padding(.trailing, Metrics.textTrailingPadding)
            }
        }
    }()

    /// 固定当前编辑高度并观察可用宽度变化的文本编辑区域布局。
    @LayoutBuilder
    private var textEditorLayout: Layout {
        editorContainer
            .resizable(axis: .horizontal)
            .frame(height: isShowingRecordingUnavailableHint ? Metrics.textInputHeight : currentInputHeight)
            .onGeometryChange(
                for: CGFloat.self,
                of: { max(0, $0.size.width - 8) },
                action: { [weak self] width in self?.updateTextHeight(availableWidth: width) }
            )
    }

    /// 内联附件模式下独立操作行的高度，单位为点。
    private var documentActionHeight: CGFloat {
        guard !textAttachments.isEmpty && !isShowingRecordingUnavailableHint else { return 0 }
        switch composerState {
        case .preparingSpeech, .dictating:
            return Metrics.textDictationButtonHeight + Metrics.textDictationBottomPadding
        case .idle, .recording, .audioPreview:
            return Metrics.sendButtonHeight + Metrics.textSendBottomPadding
        }
    }

    /// 录音状态使用的玻璃背景容器。
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

    /// 音频预览状态使用的玻璃背景容器。
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

    /// 音频取消按钮使用的独立玻璃背景容器。
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

    /// 固定音频预览时长标签布局的容器。
    private lazy var previewDurationContainer = QuickLayoutView { [unowned self] in
        self.previewDurationLabel
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    /// 根据可发送内容与听写状态选择发送或听写按钮的布局。
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
            if isShowingRecordingUnavailableHint || !textAttachments.isEmpty || hasSendableContent {
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
                    .padding(.bottom, sendButtonBottomPadding)
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

    /// 单行输入及临时提示中，发送按钮在输入胶囊内上下等距。
    private var sendButtonBottomPadding: CGFloat {
        if isShowingRecordingUnavailableHint {
            return (Metrics.textInputHeight - Metrics.sendButtonHeight) / 2
        }
        if !textAttachments.isEmpty { return Metrics.textSendBottomPadding }
        let font = textView.font ?? .preferredFont(forTextStyle: .body)
        let singleLineHeight = max(
            Metrics.textInputHeight,
            ceil(font.lineHeight) + textView.textContainerInset.top
                + textView.textContainerInset.bottom
        )
        return currentInputHeight <= singleLineHeight + 0.5
            ? (currentInputHeight - Metrics.sendButtonHeight) / 2
            : Metrics.textSendBottomPadding
    }

    /// 定义 `IMessageChatComposerView` 的布局层级、间距和对齐方式。
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

            case .audioPreview where textAttachments.isEmpty:
                HStack(alignment: .center, spacing: 8) {
                    audioCancelGlassView.frame(
                        width: Metrics.mediaControlHitSize,
                        height: Metrics.mediaControlHitSize
                    )
                    previewGlassView
                        .resizable(axis: .horizontal)
                        .frame(height: Metrics.mediaInputHeight)
                }

            case .idle, .preparingSpeech, .dictating, .audioPreview:
                Spacer().frame(width: 0, height: 0)
            }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
    }

    /// 使用指定初始边框创建 `IMessageChatComposerView`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 不支持从归档创建 `IMessageChatComposerView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 在输入栏释放时取消录音提示的延时任务。
    deinit {
        recordingHintTask?.cancel()
    }

    /// 进入窗口后重新测量文本；离开窗口时使粘贴任务和录音提示失效。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            pasteCoordinator.invalidate()
            dismissRecordingUnavailableHint()
            return
        }
        inputBinding.refresh()
        DispatchQueue.main.async { [weak self] in
            self?.updateTextHeight()
        }
    }

    /// 根据当前边界更新 `IMessageChatComposerView` 的子视图布局与图层几何。
    override func layoutSubviews() {
        super.layoutSubviews()
        if !isShowingRecordingUnavailableHint, let retainedTextContentOffset {
            textView.setContentOffset(retainedTextContentOffset, animated: false)
            self.retainedTextContentOffset = nil
        }
    }

    /// 检查录音入口；非空草稿只展示提示，不应继续请求权限或启动音频服务。
    ///
    /// 空格、换行以及正在导入的媒体也属于草稿。重复请求不会延长当前提示。
    /// - Returns: 只有空闲且输入栏完全为空时返回 `true`。
    func validateAudioRecordingRequest() -> Bool {
        guard composerState == .idle, !isShowingRecordingUnavailableHint else {
            return false
        }
        guard !(textView.text ?? "").isEmpty || mediaDraft != nil else {
            return true
        }
        retainedTextContentOffset = textView.contentOffset
        pasteCoordinator.invalidate()
        isShowingRecordingUnavailableHint = true
        recordingHintGeneration += 1
        let generation = recordingHintGeneration
        refreshRecordingHintLayout()
        UIAccessibility.post(
            notification: .announcement,
            argument: strings.recordingRequiresEmptyDraft
        )
        let sleeper = recordingHintSleeper
        recordingHintTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            do {
                try await sleeper(.seconds(2))
            } catch {
                // 主动取消由调用方同步清理；等待失败也不能使输入栏永久禁用。
            }
            guard !Task.isCancelled, let self,
                  recordingHintGeneration == generation else { return }
            dismissRecordingUnavailableHint()
        }
        return false
    }

    /// 取消临时提示并按最新草稿恢复输入栏，保留用户当前的键盘选择。
    func dismissRecordingUnavailableHint() {
        recordingHintGeneration += 1
        recordingHintTask?.cancel()
        recordingHintTask = nil
        guard isShowingRecordingUnavailableHint else { return }
        isShowingRecordingUnavailableHint = false
        refreshRecordingHintLayout()
        updateTextHeight()
    }

    /// 使用与媒体状态切换相同的高度通知，使页面继续遵守原有滚动规则。
    private func refreshRecordingHintLayout() {
        updateComposerState()
        inputGlassView.setNeedsQuickLayout()
        editorContainer.setNeedsQuickLayout()
        setNeedsQuickLayout()
        invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
        heightDidChange?()
    }

    /// 在动态字体类别变化后刷新附件尺寸、TextKit 布局与输入高度。
    override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory
                != traitCollection.preferredContentSizeCategory else {
            return
        }
        refreshTextAttachments()
        if let manager = textView.textLayoutManager, let content = manager.textContentManager {
            manager.invalidateLayout(for: content.documentRange)
        }
        updateTextHeight()
    }

    /// `IMessageChatComposerView` 在当前内容与布局约束下的固有尺寸。
    override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: resolvedContentHeight + Metrics.verticalPadding * 2
        )
    }

    /// 返回 `IMessageChatComposerView` 在指定建议尺寸下所需的大小。
    ///
    /// - Parameter size: 父视图提供的建议尺寸。
    /// - Returns: 当前内容对应的适配尺寸。
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width,
            height: resolvedContentHeight + Metrics.verticalPadding * 2
        )
    }

    /// 仅去除附件标记及系统生成的分段；用户输入的空格、换行都保留。
    var plainDraftText: String {
        let text = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString(string: ""))
        var ranges: [NSRange] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            if attrs[.attachment] != nil || attrs[IMessageChatTextAttachment.separatorKey] != nil {
                ranges.append(range)
            }
        }
        for range in ranges.reversed() { text.deleteCharacters(in: range) }
        return text.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    /// 指示当前是否可以直接发送音频预览草稿的布尔值。
    ///
    /// 要求处于音频预览、没有媒体组及普通文本，并且未显示录音不可用提示。
    var canSendAudioDraft: Bool {
        guard case .audioPreview = composerState else { return false }
        return mediaDraft == nil && plainDraftText.isEmpty && !isShowingRecordingUnavailableHint
    }

    /// 将整批内容替换到当前选区；附件异步更新不会再改变插入位置。
    func insertContents(_ items: [IMessageChatEditorInsertion]) {
        guard !isShowingRecordingUnavailableHint else { return }
        let selection = textView.selectedRange
        guard selection.location != NSNotFound, NSMaxRange(selection) <= textView.textStorage.length else { return }
        // 结束组合输入可能同步触发编辑回调；必须在注册新附件之前完成，
        // 否则身份核对会把尚未写入 textStorage 的新卡片当作已删除对象。
        if textView.markedTextRange != nil { textView.unmarkText() }
        let content = NSMutableAttributedString(string: "")
        var preceding = selection.location > 0
            ? (textView.textStorage.string as NSString).substring(with: NSRange(location: selection.location - 1, length: 1)) : ""
        for item in items {
            switch item {
            case .text(let text):
                content.append(NSAttributedString(string: text, attributes: [
                    .font: textView.font ?? UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: UIColor.label,
                ]))
                if !text.isEmpty { preceding = String(text.suffix(1)) }
            case .attachment(let draft):
                guard textAttachments[draft.id] == nil else { updateDocument(draft); continue }
                if !preceding.isEmpty, preceding != "\n" { content.append(documentSeparator(draft.id)) }
                content.append(NSAttributedString(attachment: makeTextAttachment(draft)))
                content.append(documentSeparator(draft.id))
                preceding = "\n"
            }
        }
        guard content.length > 0 else { return }
        // attributedString 替换和光标更新属于同一事务；UIKit 的中间回调不能
        // 以尚未完成属性写入的文本判断附件已被删除。
        guard let start = textView.position(from: textView.beginningOfDocument, offset: selection.location),
              let end = textView.position(from: start, offset: selection.length),
              let range = textView.textRange(from: start, to: end) else { return }
        isInsertingContents = true
        // 先通过 UITextInput 同步替换字符和输入法上下文，再仅写入附件属性。
        // 直接替换 textStorage 的字符会留下旧的键盘上下文，随后将光标附近
        // 的附件改写为旧字符（尤其是 UTF-16 多码元字符后的原生混合粘贴）。
        textView.replace(range, withText: content.string)
        textView.textStorage.beginEditing()
        content.enumerateAttributes(in: NSRange(location: 0, length: content.length)) { attributes, range, _ in
            textView.textStorage.setAttributes(attributes, range: NSRange(location: selection.location + range.location, length: range.length))
        }
        textView.textStorage.endEditing()
        textView.selectedRange = NSRange(location: selection.location + content.length, length: 0)
        isInsertingContents = false
        reconcileTextAttachments()
        resetTypingAttributes()
        updateTextHeight()
        refreshTextAttachments()
        refreshRecordingHintLayout()
    }

    /// 菜单单项导入和录音移交同样遵循当前光标的替换语义。
    func insertDocument(_ draft: IMessageChatDocumentDraft) {
        insertContents([.attachment(draft)])
    }

    /// 在附件边界结束文字段，仅忽略由编辑器生成的排版字符。
    var draftSegments: [IMessageChatDraftSegment] {
        var result: [IMessageChatDraftSegment] = []
        var body = ""
        /// 将当前累计的非空文字追加为草稿段，并清空文字缓冲区。
        func flush() {
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.text(body)) }
            body = ""
        }
        let storage = textView.textStorage
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
            if let attachment = attributes[.attachment] as? IMessageChatTextAttachment {
                flush()
                if textAttachments[attachment.draft.id] === attachment { result.append(.attachment(attachment.draft.id)) }
            } else if attributes[.attachment] != nil {
                flush()
            } else if attributes[IMessageChatTextAttachment.separatorKey] == nil {
                body += (storage.string as NSString).substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
            }
        }
        flush()
        return result
    }

    /// 创建带附件身份标记的分隔换行，使发送时可排除编辑器生成的排版字符。
    private func documentSeparator(_ id: UUID) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [
            IMessageChatTextAttachment.separatorKey: id.uuidString,
            .font: textView.font ?? UIFont.preferredFont(forTextStyle: .body),
        ])
    }

    /// 创建并登记内联附件，绑定尺寸变化、打开与删除回调。
    private func makeTextAttachment(_ draft: IMessageChatDocumentDraft) -> IMessageChatTextAttachment {
        let attachment = IMessageChatTextAttachment(draft: draft)
        textAttachments[draft.id] = attachment
        attachment.sizeDidChange = { [weak self, weak attachment] in
            guard let self, let attachment, textAttachments[draft.id] === attachment else { return }
            updateTextHeight()
            textView.setNeedsLayout()
        }
        attachment.open = { [weak self] in
            guard let self, !isShowingRecordingUnavailableHint else { return }
            _ = actionRequested?(.openDocument(draft.id))
        }
        attachment.remove = { [weak self] in
            guard let self, !isShowingRecordingUnavailableHint else { return }
            removeDocument(draft.id, notify: true)
        }
        return attachment
    }

    /// 更新同一身份附件的草稿内容，并刷新卡片与输入栏状态。
    func updateDocument(_ draft: IMessageChatDocumentDraft) {
        guard let attachment = textAttachments[draft.id] else { return }
        attachment.draft = draft
        attachment.refresh()
        updateComposerState()
    }

    /// 按编辑器中的实际排列顺序返回活跃文档附件标识符。
    var orderedDocumentIDs: [UUID] {
        var ids: [UUID] = []
        textView.textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textView.textStorage.length)) { value, _, _ in
            if let attachment = value as? IMessageChatTextAttachment,
               textAttachments[attachment.draft.id] === attachment { ids.append(attachment.draft.id) }
        }
        return ids
    }

    /// 恢复普通文字的字体与颜色，防止继续输入时继承附件属性。
    private func resetTypingAttributes() {
        guard textView.markedTextRange == nil else { return }
        textView.typingAttributes = [
            .font: textView.font ?? UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ]
        inputBinding.refresh()
    }

    /// 将当前布局方向应用到全部内联附件，并刷新其视图和测量。
    private func refreshTextAttachments() {
        for attachment in textAttachments.values {
            attachment.direction = textView.effectiveUserInterfaceLayoutDirection
            attachment.refresh()
        }
    }

    /// 逆序修改 textStorage，保持光标位置；不更换编辑器，不重新取得焦点。
    private func removeEditorRanges(_ ranges: [NSRange]) {
        // 普通输入没有附件删除时，不触碰选区，避免打断输入法的组合文本。
        guard !ranges.isEmpty else { return }
        var selection = textView.selectedRange
        textView.textStorage.beginEditing()
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            let start = selection.location - min(range.length, max(0, selection.location - range.location))
            let end = NSMaxRange(selection) - min(range.length, max(0, NSMaxRange(selection) - range.location))
            textView.textStorage.deleteCharacters(in: range)
            selection = NSRange(location: start, length: end - start)
        }
        textView.textStorage.endEditing()
        textView.selectedRange = selection
    }

    /// 移除指定附件的活跃身份及回调，并清理编辑器中的失效引用。
    ///
    /// - Parameters:
    ///   - id: 要移除的附件稳定标识符。
    ///   - notify: 是否向上层发送文档删除动作。
    func removeDocument(_ id: UUID, notify: Bool) {
        guard let attachment = textAttachments.removeValue(forKey: id) else { return }
        attachment.open = nil
        attachment.remove = nil
        reconcileTextAttachments()
        if notify { _ = actionRequested?(.removeDocument(id)) }
        updateTextHeight()
        refreshRecordingHintLayout()
    }

    /// 删除、剪切和撤销核对所有活跃身份；失效对象与重复粘贴不能恢复已删除文件。
    private func reconcileTextAttachments() {
        guard !isReconcilingAttachments else { return }
        isReconcilingAttachments = true
        defer { isReconcilingAttachments = false }
        let storage = textView.textStorage
        var found: Set<UUID> = []
        var invalid: [NSRange] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let value else { return }
            guard let attachment = value as? IMessageChatTextAttachment else { invalid.append(range); return }
            let id = attachment.draft.id
            if textAttachments[id] === attachment, found.insert(id).inserted {} else { invalid.append(range) }
        }
        storage.enumerateAttribute(IMessageChatTextAttachment.separatorKey, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let value = value as? String, let id = UUID(uuidString: value), !found.contains(id) { invalid.append(range) }
        }
        removeEditorRanges(invalid)
        for id in Set(textAttachments.keys).subtracting(found) {
            let attachment = textAttachments.removeValue(forKey: id)
            attachment?.open = nil
            attachment?.remove = nil
            _ = actionRequested?(.removeDocument(id))
        }
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
        recordingUnavailableLabel.text = strings.recordingRequiresEmptyDraft
        textView.accessibilityLabel = strings.placeholder
        sendButton.accessibilityLabel = strings.send
        attachmentButton.accessibilityLabel = strings.addAttachment
        recordingStopButton.accessibilityLabel = strings.stopRecording
        audioCancelButton.accessibilityLabel = strings.cancelAudio
        audioSendButton.accessibilityLabel = strings.send
        updateAttachmentMenu()
        updateComposerState()
        mediaDraftStripView.configure(mediaDraft, strings: self.mediaStrings)
        refreshTextAttachments()
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
        if state != .idle {
            dismissRecordingUnavailableHint()
        }
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
            if textAttachments.isEmpty { textView.text = text } else {
                let body = NSMutableAttributedString(string: "")
                for id in orderedDocumentIDs {
                    guard let attachment = textAttachments[id] else { continue }
                    body.append(NSAttributedString(attachment: attachment))
                    body.append(NSAttributedString(string: "\n", attributes: [IMessageChatTextAttachment.separatorKey: id.uuidString]))
                }
                body.append(NSAttributedString(string: text, attributes: textView.typingAttributes))
                textView.textStorage.setAttributedString(body)
            }
            isApplyingTranscription = false
            inputBinding.refresh()
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
                attachment.duration, paddedMinutes: true
            )
            let elapsedText = IMessageAudioBubbleView.playbackTimeText(
                duration: attachment.duration, progress: progress, isPlaying: true, paddedMinutes: true
            )
            previewDurationLabel.text = IMessageAudioBubbleView.playbackTimeText(
                duration: attachment.duration, progress: progress, isPlaying: isPlaying, paddedMinutes: true
            )
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
        inputBinding.refresh()
        placeholderLabel.semanticContentAttribute = semanticAttribute
        placeholderLabel.textAlignment = textView.textAlignment
        recordingUnavailableLabel.semanticContentAttribute = semanticAttribute
        refreshTextAttachments()
        setNeedsQuickLayout()
    }

    /// 响应文本变化，核对附件身份并更新输入属性、发送状态与输入高度。
    func textViewDidChange(_ textView: UITextView) {
        guard !isInsertingContents else { return }
        reconcileTextAttachments()
        resetTypingAttributes()
        placeholderLabel.textAlignment = textView.textAlignment
        updateComposerState()
        updateTextHeight()
    }

    /// 将开始编辑事件转发给页面，由页面协调照片面板到键盘的交接。
    func textViewDidBeginEditing(_ textView: UITextView) {
        inputBinding.refresh()
        textInputDidBeginEditing?()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        inputBinding.refresh()
    }

    /// 在 UIKit 应用手动文本编辑前停止正在进行的语音转写。
    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard !isShowingRecordingUnavailableHint else { return false }
        resetTypingAttributes()
        if case .dictating = composerState, !isApplyingTranscription {
            _ = actionRequested?(.manualEditDuringDictation)
        }
        return true
    }

    /// 根据录音、预览、提示及媒体草稿状态解析的内容高度。
    private var resolvedContentHeight: CGFloat {
        // 提示临时覆盖附件展示；外层高度必须与内部的单行提示保持一致。
        if isShowingRecordingUnavailableHint { return Metrics.textInputHeight }
        if !textAttachments.isEmpty { return currentInputHeight + mediaDraftAdditionalHeight + documentActionHeight }
        return switch composerState {
        case .idle, .preparingSpeech, .dictating:
            currentInputHeight + mediaDraftAdditionalHeight
        case .recording, .audioPreview:
            Metrics.mediaInputHeight
        }
    }

    /// 返回当前媒体状态对应的稳定布局模式。
    private var layoutMode: LayoutMode {
        if isShowingRecordingUnavailableHint { return .recordingUnavailable }
        if !textAttachments.isEmpty { return .documentAttachments }
        return switch composerState {
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

    /// 常规输入层保留的高度，用于在媒体状态切换期间稳定布局。
    private var retainedTextInputHeight: CGFloat {
        if isShowingRecordingUnavailableHint { return Metrics.textInputHeight }
        if !textAttachments.isEmpty { return currentInputHeight + mediaDraftAdditionalHeight + documentActionHeight }
        return switch composerState {
        case .idle, .preparingSpeech, .dictating:
            currentInputHeight + mediaDraftAdditionalHeight
        case .recording, .audioPreview:
            Metrics.textInputHeight
        }
    }

    /// 指示当前纯文本移除首尾空白后是否可发送的布尔值。
    private var hasSendableText: Bool {
        !plainDraftText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    /// 指示当前文字、内联附件或媒体草稿是否满足发送条件的布尔值。
    private var hasSendableContent: Bool {
        if textAttachments.values.contains(where: { $0.draft.status != .ready }) { return false }
        if let mediaDraft {
            return mediaDraft.canSend
        }
        return !textAttachments.isEmpty || hasSendableText
    }

    /// 媒体草稿存在时需要额外预留的条带与间距高度。
    private var mediaDraftAdditionalHeight: CGFloat {
        mediaDraft == nil
            ? 0
            : Metrics.mediaDraftHeight + Metrics.mediaDraftSpacing + 4
    }

    /// 当前显示环境的单个物理像素，避免 iOS 26 已弃用的全局屏幕查询。
    private var hairlineHeight: CGFloat {
        1 / max(1, traitCollection.displayScale)
    }

    /// 配置输入控件、动态字体、辅助功能标识和操作回调。
    private func configureViews() {
        pasteCoordinator.insertAttachments = { [weak self] sources in
            guard let self, !isShowingRecordingUnavailableHint else { return }
            pasteAttachments?(sources)
        }
        pasteCoordinator.textDidChange = { [weak self] in
            guard let self else { return }
            textViewDidChange(textView)
        }
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
        inputBinding.refresh()
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

        // 提示始终只有 44 点高；限制字号后再按宽度缩放，避免辅助功能字号
        // 下截断“清除输入栏”这一关键说明。VoiceOver 始终读取完整文案。
        recordingUnavailableLabel.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 15), maximumPointSize: 20)
        recordingUnavailableLabel.adjustsFontForContentSizeCategory = true
        recordingUnavailableLabel.textColor = .secondaryLabel
        recordingUnavailableLabel.textAlignment = .center
        recordingUnavailableLabel.numberOfLines = 1
        recordingUnavailableLabel.adjustsFontSizeToFitWidth = true
        recordingUnavailableLabel.minimumScaleFactor = 0.5
        recordingUnavailableLabel.text = strings.recordingRequiresEmptyDraft
        recordingUnavailableLabel.accessibilityIdentifier = "imessage.composer.recordingUnavailable"

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
            guard let self, !isShowingRecordingUnavailableHint else { return }
            _ = actionRequested?(.removeMediaDraftItem(id))
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

    /// 配置带强调背景的符号按钮，并绑定辅助功能标识与目标动作。
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

    /// 使用当前本地化文字重建附件菜单，并在提示期间忽略菜单操作。
    private func updateAttachmentMenu() {
        let photoAction = UIAction(
            title: mediaStrings.photo,
            image: UIImage(systemName: "photo.on.rectangle")
        ) { [weak self] _ in
            guard let self, !isShowingRecordingUnavailableHint else { return }
            _ = actionRequested?(
                .requestAttachment(kind: .photo)
            )
        }
        let audioAction = UIAction(
            title: strings.audio,
            image: UIImage(systemName: "waveform")
        ) { [weak self] _ in
            guard let self, !isShowingRecordingUnavailableHint else { return }
            _ = actionRequested?(
                .requestAttachment(kind: .audio)
            )
        }
        let fileAction = UIAction(title: strings.file, image: UIImage(systemName: "folder")) { [weak self] _ in
            guard let self, !isShowingRecordingUnavailableHint else { return }
            _ = actionRequested?(.requestAttachment(kind: .file))
        }
        let linkAction = UIAction(title: strings.link, image: UIImage(systemName: "link")) { [weak self] _ in
            guard let self, !isShowingRecordingUnavailableHint else { return }
            _ = actionRequested?(.requestAttachment(kind: .link))
        }
        attachmentButton.menu = UIMenu(children: [photoAction, audioAction, fileAction, linkAction])
    }

    /// 按草稿内容类型转发发送动作，并在上层受理后清空对应内容。
    @objc private func sendButtonDidTap() {
        guard !isShowingRecordingUnavailableHint, hasSendableContent else { return }
        let text = plainDraftText
        let accepted: Bool
        if !textAttachments.isEmpty {
            accepted = actionRequested?(.sendDocuments(draftSegments)) == true
        } else if mediaDraft != nil {
            accepted = actionRequested?(.sendMediaDraft(text)) == true
        } else {
            accepted = actionRequested?(.sendText(text)) == true
        }
        guard accepted else { return }
        for attachment in textAttachments.values { attachment.open = nil; attachment.remove = nil }
        textAttachments.removeAll()
        textView.text = nil
        resetTypingAttributes()
        updateComposerState()
        updateTextHeight()
    }

    /// 根据当前听写状态转发开始或停止听写动作。
    @objc private func dictationButtonDidTap() {
        guard !isShowingRecordingUnavailableHint else { return }
        switch composerState {
        case .preparingSpeech, .dictating:
            _ = actionRequested?(.stopDictation)
        case .idle, .recording, .audioPreview:
            _ = actionRequested?(.startDictation)
        }
    }

    /// 转发停止录音动作。
    @objc private func recordingStopButtonDidTap() {
        _ = actionRequested?(.stopAudioRecording)
    }

    /// 转发取消当前音频草稿的动作。
    @objc private func audioCancelButtonDidTap() {
        _ = actionRequested?(.cancelAttachmentDraft)
    }

    /// 转发音频预览播放或暂停动作。
    @objc private func audioPlayButtonDidTap() {
        _ = actionRequested?(.toggleAudioPreviewPlayback)
    }

    /// 在音频草稿可发送时转发发送动作。
    @objc private func audioSendButtonDidTap() {
        guard canSendAudioDraft else { return }
        _ = actionRequested?(.sendAttachmentDraft)
    }

    /// 根据当前输入与媒体状态同步控件显示、交互、辅助功能标签及波形。
    private func updateComposerState() {
        let showsTextInput: Bool
        switch composerState {
        case .idle, .preparingSpeech, .dictating:
            showsTextInput = true
        case .recording, .audioPreview:
            showsTextInput = !textAttachments.isEmpty
        }
        attachmentGlassView.alpha = showsTextInput ? 1 : 0
        inputGlassView.alpha = showsTextInput ? 1 : 0
        attachmentGlassView.isUserInteractionEnabled = showsTextInput
        // 不禁用文本编辑器的祖先视图，否则 UIKit 会结束当前编辑并收起键盘。
        // alpha 为 0 时容器不参与触摸命中；只隐藏外观即可保留用户已有的焦点。
        attachmentGlassView.accessibilityElementsHidden = !showsTextInput
        inputGlassView.accessibilityElementsHidden = !showsTextInput
        textView.alpha = isShowingRecordingUnavailableHint ? 0 : 1
        textView.isInputSuspended = isShowingRecordingUnavailableHint
        textView.accessibilityElementsHidden = isShowingRecordingUnavailableHint
        textView.isAccessibilityElement = !isShowingRecordingUnavailableHint
        placeholderLabel.isHidden = isShowingRecordingUnavailableHint
            || !(textView.text ?? "").isEmpty
        recordingUnavailableLabel.isHidden = !isShowingRecordingUnavailableHint
        sendButton.isEnabled = !isShowingRecordingUnavailableHint && hasSendableContent
        sendButton.accessibilityHint = nil
        audioSendButton.isEnabled = canSendAudioDraft
        attachmentButton.isEnabled = !isShowingRecordingUnavailableHint
            && (composerState == .idle || !textAttachments.isEmpty)
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
        if isShowingRecordingUnavailableHint {
            dictationButton.isEnabled = false
        }
        inputGlassView.setNeedsQuickLayout()
    }

    /// 按可用宽度测量文本内容，并在有效高度变化时通知页面更新布局。
    private func updateTextHeight(availableWidth: CGFloat? = nil) {
        guard !isShowingRecordingUnavailableHint else { return }
        let font = textView.font ?? .preferredFont(forTextStyle: .body)
        let width = max(1, availableWidth ?? textView.bounds.width)
        let previousInsets = textView.textContainerInset
        let measuredContentHeight = max(0, textView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height - previousInsets.top - previousInsets.bottom)
        // 44 点胶囊比单行排版高，把剩余高度平分到上下；多行仍使用 8 点。
        // 先扣除旧内边距，避免连续测量把上一轮居中留白重复计入高度。
        let verticalInset = max(8, (Metrics.textInputHeight - measuredContentHeight) / 2)
        if abs(previousInsets.top - verticalInset) > 0.01
            || abs(previousInsets.bottom - verticalInset) > 0.01 {
            textView.textContainerInset = UIEdgeInsets(
                top: verticalInset, left: previousInsets.left,
                bottom: verticalInset, right: previousInsets.right
            )
            editorContainer.setNeedsQuickLayout()
        }
        let attachmentWidth = max(1, width - textView.textContainerInset.left
            - textView.textContainerInset.right - textView.textContainer.lineFragmentPadding * 2)
        let attachmentHeight = textAttachments.values.reduce(CGFloat.zero) { total, attachment in
            total + attachment.preferredSize(maximumWidth: attachmentWidth,
                layoutManager: textView.textLayoutManager).height + ceil(font.lineHeight)
        }
        let contentLimit = attachmentHeight + ceil(font.lineHeight * 5)
            + textView.textContainerInset.top
            + textView.textContainerInset.bottom
        // 多附件不能把整页推出窗口；超过可见预算后仍由原 UITextView 滚动编辑。
        let viewportLimit = textAttachments.isEmpty ? contentLimit
            : max(180, (window?.bounds.height ?? 874) * 0.42) - documentActionHeight
        let maximumHeight = min(contentLimit, viewportLimit)
        let measuredHeight = measuredContentHeight + verticalInset * 2
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
/// 创建指定草稿、媒体状态和布局方向的输入栏预览，可选择显示录音不可用提示。
@MainActor
private func makeIMessageChatComposerPreview(
    text: String,
    state: IMessageChatComposerState,
    direction: UIUserInterfaceLayoutDirection,
    showsRecordingHint: Bool = false
) -> UIViewController {
    let backgroundView = UIView()
    backgroundView.backgroundColor = .systemBackground
    let composerView = IMessageChatComposerView(frame: .zero)
    composerView.configure(strings: IMessageChatPreviewData.composerStrings)
    composerView.applyLayoutDirection(direction)
    composerView.textView.text = text
    composerView.textViewDidChange(composerView.textView)
    composerView.applyState(state)
    if showsRecordingHint {
        // Canvas 保持提示外观；真实页面仍使用默认两秒等待。
        composerView.recordingHintSleeper = { _ in
            try await Task.sleep(for: .seconds(3_600))
        }
        _ = composerView.validateAudioRecordingRequest()
    }
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

#Preview("消息输入栏 · 录音前清空提示") {
    makeIMessageChatComposerPreview(
        text: IMessageChatPreviewData.composerMultilineText,
        state: .idle,
        direction: .leftToRight,
        showsRecordingHint: true
    )
}

#Preview("消息输入栏 · 录音前清空提示 RTL") {
    makeIMessageChatComposerPreview(
        text: IMessageChatPreviewData.composerRTLText,
        state: .idle,
        direction: .rightToLeft,
        showsRecordingHint: true
    )
}
#endif
