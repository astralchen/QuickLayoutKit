//
//  IMessageChatCells.swift
//  Demo
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 根据消息方向显示文本与圆角气泡轮廓的视图。
final class IMessageBubbleView: QuickLayoutView {

    /// 显示消息正文并支持动态字体的标签。
    let messageLabel = UILabel()
    /// 按消息方向裁剪气泡圆角的形状遮罩。
    private let maskLayer = CAShapeLayer()
    /// 当前消息的接收或发出方向，用于确定气泡外观与语义对齐。
    private var direction: IMessageChatDirection = .incoming

    /// 定义 `IMessageBubbleView` 的布局层级、间距和对齐方式。
    override var body: Layout {
        messageLabel
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    /// 使用指定初始边框创建 `IMessageBubbleView`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .natural
        layer.mask = maskLayer
        isAccessibilityElement = true
    }

    /// 不支持从归档创建 `IMessageBubbleView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 根据当前边界更新 `IMessageBubbleView` 的子视图布局与图层几何。
    override func layoutSubviews() {
        super.layoutSubviews()
        updateBubbleMask()
    }

    /// 应用消息文本、收发方向和辅助功能信息，并请求重新布局。
    func configure(_ message: IMessageChatMessagePresentation) {
        direction = message.direction
        messageLabel.text = message.text
        switch message.direction {
        case .incoming:
            backgroundColor = .secondarySystemFill
            messageLabel.textColor = .label
        case .outgoing:
            backgroundColor = .systemBlue
            messageLabel.textColor = .white
        }
        accessibilityLabel = message.text
        setNeedsQuickLayout()
        setNeedsLayout()
    }

    /// 清空文本与辅助功能信息，恢复未配置的气泡状态。
    func reset() {
        direction = .incoming
        messageLabel.text = nil
        accessibilityLabel = nil
        backgroundColor = .clear
        maskLayer.path = nil
        setNeedsQuickLayout()
    }

    /// 根据当前边界和收发方向更新气泡遮罩路径。
    private func updateBubbleMask() {
        guard bounds.width > 0, bounds.height > 0 else {
            maskLayer.path = nil
            return
        }
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let compactBottomLeft = direction == .incoming ? !isRTL : isRTL
        let compactBottomRight = !compactBottomLeft
        maskLayer.frame = bounds
        maskLayer.path = Self.roundedPath(
            in: bounds,
            topLeft: 18,
            topRight: 18,
            bottomLeft: compactBottomLeft ? 5 : 18,
            bottomRight: compactBottomRight ? 5 : 18
        )
    }

    /// 返回分别指定四个圆角半径的闭合矩形路径。
    ///
    /// - Parameters:
    ///   - rect: 需要绘制的矩形区域。
    ///   - topLeft: 左上角半径，单位为点。
    ///   - topRight: 右上角半径，单位为点。
    ///   - bottomLeft: 左下角半径，单位为点。
    ///   - bottomRight: 右下角半径，单位为点。
    /// - Returns: 用于气泡遮罩的闭合路径。
    private static func roundedPath(
        in rect: CGRect,
        topLeft: CGFloat,
        topRight: CGFloat,
        bottomLeft: CGFloat,
        bottomRight: CGFloat
    ) -> CGPath {
        let maximumRadius = min(rect.width, rect.height) / 2
        let tl = min(topLeft, maximumRadius)
        let tr = min(topRight, maximumRadius)
        let bl = min(bottomLeft, maximumRadius)
        let br = min(bottomRight, maximumRadius)
        let path = UIBezierPath()

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
            radius: tr,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
            radius: br,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(
            withCenter: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
            radius: bl,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(
            withCenter: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
            radius: tl,
            startAngle: .pi,
            endAngle: .pi * 1.5,
            clockwise: true
        )
        path.close()
        return path.cgPath
    }
}

/// 在时间线中显示文本气泡和发送状态的自适应单元格。
final class IMessageBubbleCell: QuickLayoutCollectionViewCell {

    /// 呈现消息正文与收发方向外观的文本气泡视图。
    let bubbleView = IMessageBubbleView(frame: .zero)
    /// 显示发送进度、失败入口及送达文本的状态视图。
    let deliveryStatusView = IMessageChatDeliveryStatusView()
    /// 状态视图中用于显示本地化送达文本的标签。
    var deliveryLabel: UILabel { deliveryStatusView.label }
    /// 当前绑定的消息展示模型；未配置或复用清理后为 `nil`。
    private var message: IMessageChatMessagePresentation?
    /// 当前布局允许的消息气泡最大宽度，单位为点。
    private var maximumBubbleWidth: CGFloat = 280

    /// 需要随单元格同步更新布局方向的内容视图。
    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [bubbleView]
    }

    /// 定义 `IMessageBubbleCell` 的布局层级、间距和对齐方式。
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
                bubbleView
                    .frame(
                        maxWidth: maximumBubbleWidth,
                        alignment: message?.direction == .outgoing
                            ? .trailing
                            : .leading
                    )
                if message?.deliveryText != nil {
                    deliveryStatusView
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

    /// 使用指定初始边框创建 `IMessageBubbleCell`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
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

    /// 不支持从归档创建 `IMessageBubbleCell`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 根据列表提供的宽度更新内容宽度限制，并返回自适应高度的布局属性。
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let resolvedWidth = max(140, layoutAttributes.size.width * 0.75)
        if abs(resolvedWidth - maximumBubbleWidth) > 0.5 {
            maximumBubbleWidth = resolvedWidth
            setNeedsQuickLayout()
        }
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    /// 绑定文本消息，更新气泡、发送状态和单元格布局。
    func configure(_ message: IMessageChatMessagePresentation) {
        self.message = message
        bubbleView.configure(message)
        deliveryStatusView.configure(message)
        deliveryLabel.text = message.deliveryText
        deliveryLabel.accessibilityLabel = message.deliveryText
        setNeedsQuickLayout()
    }

    /// 为复用清理 `IMessageBubbleCell` 的内容与临时状态。
    override func prepareForReuse() {
        super.prepareForReuse()
        message = nil
        bubbleView.reset()
        deliveryStatusView.configure(nil)
        deliveryStatusView.retryRequested = nil
        deliveryLabel.text = nil
        deliveryLabel.accessibilityLabel = nil
        setNeedsQuickLayout()
    }
}

/// 在时间线中显示本地化时间分隔文本的单元格。
final class IMessageTimestampCell: QuickLayoutCollectionViewCell {

    /// 显示消息组时间的居中标签。
    let timestampLabel = UILabel()

    /// 定义 `IMessageTimestampCell` 的布局层级、间距和对齐方式。
    override var body: Layout {
        timestampLabel
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    /// 使用指定初始边框创建 `IMessageTimestampCell`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
        timestampLabel.font = .preferredFont(forTextStyle: .caption1)
        timestampLabel.adjustsFontForContentSizeCategory = true
        timestampLabel.textColor = .secondaryLabel
        timestampLabel.textAlignment = .center
        timestampLabel.numberOfLines = 0
        timestampLabel.isAccessibilityElement = true
    }

    /// 不支持从归档创建 `IMessageTimestampCell`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 应用时间分隔文本，并同步可访问标签与布局。
    func configure(_ timestamp: IMessageChatTimestampPresentation) {
        timestampLabel.text = timestamp.text
        timestampLabel.accessibilityLabel = timestamp.text
        setNeedsQuickLayout()
    }

    /// 为复用清理 `IMessageTimestampCell` 的内容与临时状态。
    override func prepareForReuse() {
        super.prepareForReuse()
        timestampLabel.text = nil
        timestampLabel.accessibilityLabel = nil
    }
}

/// 以三个圆点动画表示对方正在输入的气泡视图。
final class IMessageTypingBubbleView: QuickLayoutView {

    /// 按显示顺序排列的三个输入状态圆点。
    let dots: [UIView] = (0..<3).map { _ in UIView() }

    /// 定义 `IMessageTypingBubbleView` 的布局层级、间距和对齐方式。
    override var body: Layout {
        HStack(spacing: 4) {
            ForEach(dots) { dot in
                dot.frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

    /// 使用指定初始边框创建 `IMessageTypingBubbleView`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemFill
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        for dot in dots {
            dot.backgroundColor = .secondaryLabel
            dot.layer.cornerRadius = 3.5
        }
        isAccessibilityElement = true
    }

    /// 不支持从归档创建 `IMessageTypingBubbleView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 进入窗口时按需启动圆点动画，离开窗口时移除动画。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            dots.forEach { $0.layer.removeAllAnimations() }
        } else {
            startAnimatingIfNeeded()
        }
    }

    /// 更新输入状态的辅助功能描述，并按需启动圆点动画。
    func configure(accessibilityLabel: String) {
        self.accessibilityLabel = accessibilityLabel
        startAnimatingIfNeeded()
    }

    /// 仅在视图可见且未启用减弱动态效果时启动错峰圆点动画。
    private func startAnimatingIfNeeded() {
        guard window != nil, !UIAccessibility.isReduceMotionEnabled else {
            dots.forEach {
                $0.layer.removeAllAnimations()
                $0.alpha = 1
            }
            return
        }
        for (index, dot) in dots.enumerated() {
            guard dot.layer.animation(forKey: "imessage.typing") == nil else {
                continue
            }
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [0.35, 1, 0.35]
            animation.keyTimes = [0, 0.5, 1]
            animation.duration = 0.9
            animation.beginTime = CACurrentMediaTime() + Double(index) * 0.15
            animation.repeatCount = .infinity
            dot.layer.add(animation, forKey: "imessage.typing")
        }
    }
}

/// 在时间线语义起始侧显示输入状态气泡的单元格。
final class IMessageTypingCell: QuickLayoutCollectionViewCell {

    /// 显示三个圆点及辅助功能输入状态的气泡视图。
    let typingView = IMessageTypingBubbleView(frame: .zero)

    /// 需要随单元格同步更新布局方向的内容视图。
    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [typingView]
    }

    /// 定义 `IMessageTypingCell` 的布局层级、间距和对齐方式。
    override var body: Layout {
        HStack(spacing: 0) {
            typingView
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    /// 使用指定初始边框创建 `IMessageTypingCell`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
    }

    /// 不支持从归档创建 `IMessageTypingCell`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 更新输入状态气泡的辅助功能描述，并使布局失效。
    func configure(accessibilityLabel: String) {
        typingView.configure(accessibilityLabel: accessibilityLabel)
        setNeedsQuickLayout()
    }
}

#if DEBUG
/// 创建承载指定消息文本气泡的独立预览控制器。
@MainActor
private func makeIMessageBubbleViewPreview(
    _ message: IMessageChatMessagePresentation
) -> UIViewController {
    let backgroundView = UIView()
    backgroundView.backgroundColor = .systemBackground
    let bubbleView = IMessageBubbleView(frame: .zero)
    bubbleView.configure(message)
    return QuickLayoutHostingController {
        ZStack {
            backgroundView.resizable()
            bubbleView
        }
        .frame(width: 330, height: 110)
    }
}

/// 创建承载指定文本消息单元格的独立预览控制器。
@MainActor
private func makeIMessageBubbleCellPreview(
    _ message: IMessageChatMessagePresentation
) -> UIViewController {
    let backgroundView = UIView()
    backgroundView.backgroundColor = .systemBackground
    let cell = IMessageBubbleCell(frame: .zero)
    cell.configure(message)
    return QuickLayoutHostingController {
        ZStack {
            backgroundView.resizable()
            cell.resizable().frame(width: 390, height: 86)
        }
    }
}

/// 创建使用固定示例时间的时间分隔单元格预览。
@MainActor
private func makeIMessageTimestampCellPreview() -> UIViewController {
    let cell = IMessageTimestampCell(frame: .zero)
    cell.configure(IMessageChatPreviewData.timestamp)
    return QuickLayoutHostingController {
        cell.resizable().frame(width: 390, height: 52)
    }
}

/// 创建用于检查输入圆点动画及外观的气泡视图预览。
@MainActor
private func makeIMessageTypingBubbleViewPreview() -> UIViewController {
    let backgroundView = UIView()
    backgroundView.backgroundColor = .systemBackground
    let typingView = IMessageTypingBubbleView(frame: .zero)
    typingView.configure(
        accessibilityLabel: IMessageChatPreviewData
            .typingAccessibilityLabel
    )
    return QuickLayoutHostingController {
        ZStack {
            backgroundView.resizable()
            typingView
        }
        .frame(width: 160, height: 90)
    }
}

/// 创建用于检查时间线输入状态布局的单元格预览。
@MainActor
private func makeIMessageTypingCellPreview() -> UIViewController {
    let cell = IMessageTypingCell(frame: .zero)
    cell.configure(
        accessibilityLabel: IMessageChatPreviewData
            .typingAccessibilityLabel
    )
    return QuickLayoutHostingController {
        cell.resizable().frame(width: 390, height: 62)
    }
}

#Preview("消息气泡 View · 收到") {
    makeIMessageBubbleViewPreview(IMessageChatPreviewData.incomingMessage)
}

#Preview("消息气泡 View · 发出") {
    makeIMessageBubbleViewPreview(IMessageChatPreviewData.outgoingMessage)
}

#Preview("消息气泡 Cell · 收到") {
    makeIMessageBubbleCellPreview(IMessageChatPreviewData.incomingMessage)
}

#Preview("消息气泡 Cell · 发出") {
    makeIMessageBubbleCellPreview(IMessageChatPreviewData.outgoingMessage)
}

#Preview("消息时间 Cell") {
    makeIMessageTimestampCellPreview()
}

#Preview("输入中气泡 View") {
    makeIMessageTypingBubbleViewPreview()
}

#Preview("输入中 Cell") {
    makeIMessageTypingCellPreview()
}
#endif
