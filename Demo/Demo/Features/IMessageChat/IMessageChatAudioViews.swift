//
//  IMessageChatAudioViews.swift
//  Demo
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 用紧凑柱形区分已播放和未播放采样的波形视图。
///
/// 此视图仅用于装饰。所属的播放控件为对应音频附件提供 VoiceOver 标签和值。
final class IMessageWaveformView: UIView {

    /// 波形柱的首选宽度。
    ///
    /// 当所有柱形无法在当前边界内完整显示时，视图会等比收窄柱形；当采样数量
    /// 较少时不会横向拉伸柱形，而是将完整波形居中显示。
    var barWidth: CGFloat = 2 {
        didSet { setNeedsDisplay() }
    }

    /// 相邻波形柱之间的首选间距。
    ///
    /// 当当前边界不足时，视图会先收窄间距，再收窄柱形。
    var barSpacing: CGFloat = 2 {
        didSet { setNeedsDisplay() }
    }

    /// 位于语义起始侧、使用未播放颜色绘制的波形比例。
    ///
    /// 值会被限制在 `0...1`。录音面板使用此属性表达设计图中的旧采样渐隐区；
    /// 播放波形应保留默认值 `0`，继续仅由 ``progress`` 区分播放进度。
    var fadedLeadingFraction: CGFloat = 0 {
        didSet { setNeedsDisplay() }
    }

    /// 波形柱允许显示的最小高度。
    ///
    /// 默认值适用于消息气泡；Composer 可以使用更紧凑的设计尺寸。
    var minimumBarHeight: CGFloat = 3 {
        didSet { setNeedsDisplay() }
    }

    /// 波形柱允许显示的最大高度。
    ///
    /// 值为 `nil` 时使用视图的完整高度。设置该值只约束柱形绘制，
    /// 不改变视图参与布局和垂直居中的边界。
    var maximumBarHeight: CGFloat? {
        didSet { setNeedsDisplay() }
    }

    /// 位于 `0...1` 范围内的归一化波形采样。
    var samples: [Float] = [] {
        didSet { setNeedsDisplay() }
    }

    /// 位于 `0...1` 范围内的归一化播放位置。
    var progress: Double = 0 {
        didSet { setNeedsDisplay() }
    }

    /// 播放位置之后的波形采样所使用的颜色。
    var unplayedColor: UIColor = .secondaryLabel {
        didSet { setNeedsDisplay() }
    }

    /// 播放位置之前的波形采样所使用的颜色。
    var playedColor: UIColor = .label {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !samples.isEmpty else {
            return
        }
        let count = samples.count
        let preferredBarWidth = max(0.5, barWidth)
        let preferredSpacing = max(0, barSpacing)
        let resolvedSpacing: CGFloat
        if count > 1 {
            resolvedSpacing = min(
                preferredSpacing,
                max(
                    0,
                    (rect.width - preferredBarWidth * CGFloat(count))
                        / CGFloat(count - 1)
                )
            )
        } else {
            resolvedSpacing = 0
        }
        let availableWidth = max(
            0.5,
            rect.width - resolvedSpacing * CGFloat(count - 1)
        )
        let resolvedBarWidth = min(
            preferredBarWidth,
            availableWidth / CGFloat(count)
        )
        let contentWidth = resolvedBarWidth * CGFloat(count)
            + resolvedSpacing * CGFloat(count - 1)
        let leadingX = rect.midX - contentWidth / 2
        let isRightToLeft = effectiveUserInterfaceLayoutDirection
            == .rightToLeft
        let resolvedProgress = min(1, max(0, progress))
        let resolvedFadedFraction = min(1, max(0, fadedLeadingFraction))

        context.saveGState()
        context.setLineCap(.round)
        context.setLineWidth(resolvedBarWidth)
        for (index, sample) in samples.enumerated() {
            let displayIndex = isRightToLeft ? count - index - 1 : index
            let x = leadingX + resolvedBarWidth / 2
                + CGFloat(displayIndex)
                    * (resolvedBarWidth + resolvedSpacing)
            let maximumHeight = min(
                rect.height,
                max(0, maximumBarHeight ?? rect.height)
            )
            let minimumHeight = min(
                maximumHeight,
                max(0, minimumBarHeight)
            )
            let height = max(
                minimumHeight,
                maximumHeight * CGFloat(min(1, max(0.08, sample)))
            )
            let normalizedIndex = count == 1
                ? 0
                : Double(index) / Double(count - 1)
            let usesFadedLeadingColor = CGFloat(normalizedIndex)
                < resolvedFadedFraction
            let color: UIColor
            if usesFadedLeadingColor {
                color = unplayedColor
            } else {
                color = Self.isSamplePlayed(
                    at: index,
                    count: count,
                    progress: resolvedProgress
                )
                    ? playedColor
                    : unplayedColor
            }
            context.setStrokeColor(color.cgColor)
            context.move(to: CGPoint(x: x, y: rect.midY - height / 2))
            context.addLine(to: CGPoint(x: x, y: rect.midY + height / 2))
            context.strokePath()
        }
        context.restoreGState()
    }

    /// 返回指定波形柱在当前进度下是否已经播放。
    ///
    /// 使用柱形中心点判断播放进度，确保零进度不会提前高亮第一根柱形，
    /// 完整进度仍会覆盖全部柱形。
    ///
    /// - Parameters:
    ///   - index: 波形柱在采样数组中的索引。
    ///   - count: 波形柱总数。
    ///   - progress: 位于 `0...1` 范围内的播放位置。
    /// - Returns: 当前波形柱已经越过播放位置时返回 `true`。
    static func isSamplePlayed(
        at index: Int,
        count: Int,
        progress: Double
    ) -> Bool {
        guard count > 0, index >= 0, index < count else {
            return false
        }
        let resolvedProgress = min(1, max(0, progress))
        guard resolvedProgress > 0 else {
            return false
        }
        guard resolvedProgress < 1 else {
            return true
        }
        let sampleCenter = (Double(index) + 0.5) / Double(count)
        return sampleCenter <= resolvedProgress
    }
}

/// 显示播放、波形和时长控件的消息气泡。
final class IMessageAudioBubbleView: QuickLayoutView {

    let playButton = UIButton(type: .system)
    let waveformView = IMessageWaveformView()
    let durationLabel = UILabel()

    var playbackRequested: (() -> Void)?

    private var attachment: IMessageChatAudioAttachment?
    private var direction: IMessageChatDirection = .incoming

    override var body: Layout {
        HStack(spacing: 8) {
            playButton.resizable().frame(width: 32, height: 32)
            waveformView.resizable().frame(width: 132, height: 30)
            durationLabel.fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        clipsToBounds = true

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "play.fill")
        configuration.contentInsets = .zero
        playButton.configuration = configuration
        playButton.accessibilityIdentifier = "imessage.audio.play"
        playButton.addTarget(
            self,
            action: #selector(playButtonDidTap),
            for: .touchUpInside
        )

        durationLabel.font = .preferredFont(forTextStyle: .caption1)
        durationLabel.adjustsFontForContentSizeCategory = true
        durationLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 使用音频附件和播放状态配置气泡。
    ///
    /// - Parameters:
    ///   - attachment: 气泡所表示的附件。
    ///   - direction: 语义化的接收或发出消息方向。
    ///   - playback: 页面级播放状态。
    ///   - playAccessibilityLabel: 本地化的“播放”操作。
    ///   - pauseAccessibilityLabel: 本地化的“暂停”操作。
    func configure(
        attachment: IMessageChatAudioAttachment,
        direction: IMessageChatDirection,
        playback: IMessageChatPlaybackState,
        playAccessibilityLabel: String,
        pauseAccessibilityLabel: String
    ) {
        self.attachment = attachment
        self.direction = direction
        let isCurrent = playback.attachmentID == attachment.id
        let isPlaying = isCurrent && playback.isPlaying
        let progress = isCurrent ? playback.progress : 0
        waveformView.samples = attachment.waveform
        waveformView.progress = progress
        durationLabel.text = Self.durationText(attachment.duration)
        playButton.configuration?.image = UIImage(
            systemName: isPlaying ? "pause.fill" : "play.fill"
        )
        playButton.accessibilityLabel = isPlaying
            ? pauseAccessibilityLabel
            : playAccessibilityLabel
        let elapsedText = Self.durationText(
            attachment.duration * progress
        )
        playButton.accessibilityValue = "\(elapsedText) / \(durationLabel.text ?? "")"

        switch direction {
        case .incoming:
            backgroundColor = .secondarySystemFill
            playButton.tintColor = .label
            durationLabel.textColor = .secondaryLabel
            waveformView.playedColor = .label
            waveformView.unplayedColor = .tertiaryLabel
        case .outgoing:
            backgroundColor = .systemBlue
            playButton.tintColor = .white
            durationLabel.textColor = UIColor.white.withAlphaComponent(0.82)
            waveformView.playedColor = .white
            waveformView.unplayedColor = UIColor.white.withAlphaComponent(0.42)
        }
        accessibilityLabel = "\(playButton.accessibilityLabel ?? ""), \(durationLabel.text ?? "")"
        setNeedsQuickLayout()
    }

    /// 在所属 Cell 复用前移除消息特定状态。
    func reset() {
        attachment = nil
        direction = .incoming
        playbackRequested = nil
        waveformView.samples = []
        waveformView.progress = 0
        durationLabel.text = nil
        playButton.accessibilityLabel = nil
        playButton.accessibilityValue = nil
        accessibilityLabel = nil
    }

    @objc private func playButtonDidTap() {
        playbackRequested?()
    }

    /// 返回时钟样式的音频时长文本。
    ///
    /// - Parameter duration: 音频时长，单位为秒。
    /// - Returns: 格式为 `m:ss` 的字符串。
    static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// 承载音频消息气泡的可复用时间线 Cell。
final class IMessageAudioBubbleCell: QuickLayoutCollectionViewCell {

    let bubbleView = IMessageAudioBubbleView(frame: .zero)
    let deliveryLabel = UILabel()

    var playbackRequested: ((Int, IMessageChatAudioAttachment) -> Void)?

    private var message: IMessageChatMessagePresentation?
    private var maximumBubbleWidth: CGFloat = 300

    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [bubbleView]
    }

    @LayoutBuilder
    override var body: Layout {
        HStack(spacing: 0) {
            if message?.direction == .outgoing {
                Spacer()
            }
            VStack(
                alignment: message?.direction == .outgoing
                    ? .trailing
                    : .leading,
                spacing: 3
            ) {
                // 音频气泡与文本气泡共用同一条语义边缘。最大宽度框可能宽于
                // 音频内容的固有宽度，因此必须显式指定框内对齐方向，避免气泡
                // 使用默认居中后在发出消息的尾部留下额外空白。
                bubbleView.frame(
                    maxWidth: maximumBubbleWidth,
                    alignment: message?.direction == .outgoing
                        ? .trailing
                        : .leading
                )
                if message?.deliveryText != nil {
                    deliveryLabel
                }
            }
            if message?.direction != .outgoing {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        deliveryLabel.font = .preferredFont(forTextStyle: .caption2)
        deliveryLabel.adjustsFontForContentSizeCategory = true
        deliveryLabel.textColor = .secondaryLabel
        deliveryLabel.textAlignment = .natural
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let resolvedWidth = max(230, layoutAttributes.size.width * 0.75)
        if abs(resolvedWidth - maximumBubbleWidth) > 0.5 {
            maximumBubbleWidth = resolvedWidth
            setNeedsQuickLayout()
        }
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    /// 使用音频消息配置 Cell。
    ///
    /// - Parameters:
    ///   - message: 音频消息展示模型。
    ///   - playback: 页面级播放状态。
    ///   - playAccessibilityLabel: 本地化的“播放”操作。
    ///   - pauseAccessibilityLabel: 本地化的“暂停”操作。
    func configure(
        _ message: IMessageChatMessagePresentation,
        playback: IMessageChatPlaybackState,
        playAccessibilityLabel: String,
        pauseAccessibilityLabel: String
    ) {
        guard let attachment = message.audio else { return }
        self.message = message
        bubbleView.configure(
            attachment: attachment,
            direction: message.direction,
            playback: playback,
            playAccessibilityLabel: playAccessibilityLabel,
            pauseAccessibilityLabel: pauseAccessibilityLabel
        )
        bubbleView.playbackRequested = { [weak self] in
            guard let self,
                  let message = self.message,
                  let attachment = message.audio else { return }
            self.playbackRequested?(message.id, attachment)
        }
        deliveryLabel.text = message.deliveryText
        deliveryLabel.accessibilityLabel = message.deliveryText
        setNeedsQuickLayout()
    }

    /// 在不改变 Cell 消息身份的情况下更新播放进度。
    ///
    /// - Parameters:
    ///   - playback: 页面级播放状态。
    ///   - playAccessibilityLabel: 本地化的“播放”操作。
    ///   - pauseAccessibilityLabel: 本地化的“暂停”操作。
    func updatePlayback(
        _ playback: IMessageChatPlaybackState,
        playAccessibilityLabel: String,
        pauseAccessibilityLabel: String
    ) {
        guard let message, let attachment = message.audio else { return }
        bubbleView.configure(
            attachment: attachment,
            direction: message.direction,
            playback: playback,
            playAccessibilityLabel: playAccessibilityLabel,
            pauseAccessibilityLabel: pauseAccessibilityLabel
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        message = nil
        playbackRequested = nil
        bubbleView.reset()
        deliveryLabel.text = nil
        deliveryLabel.accessibilityLabel = nil
        setNeedsQuickLayout()
    }
}

#if DEBUG
@MainActor
private func makeIMessageAudioBubblePreview(
    direction: IMessageChatDirection
) -> UIViewController {
    let message = direction == .outgoing
        ? IMessageChatPreviewData.outgoingAudioMessage
        : IMessageChatPreviewData.incomingAudioMessage
    let cell = IMessageAudioBubbleCell(frame: .zero)
    cell.configure(
        message,
        playback: .idle,
        playAccessibilityLabel: "播放音频",
        pauseAccessibilityLabel: "暂停音频"
    )
    return QuickLayoutHostingController {
        cell.resizable().frame(width: 390, height: 84)
    }
}

#Preview("音频消息 · 收到") {
    makeIMessageAudioBubblePreview(direction: .incoming)
}

#Preview("音频消息 · 发出") {
    makeIMessageAudioBubblePreview(direction: .outgoing)
}
#endif
