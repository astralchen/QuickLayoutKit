//
//  IMessageChatCells.swift
//  Demo
//

import QuickLayout
import QuickLayoutKit
import UIKit

final class IMessageBubbleView: QuickLayoutView {

    let messageLabel = UILabel()
    private let maskLayer = CAShapeLayer()
    private var direction: IMessageChatDirection = .incoming

    override var body: Layout {
        messageLabel
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .natural
        layer.mask = maskLayer
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateBubbleMask()
    }

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

    func reset() {
        direction = .incoming
        messageLabel.text = nil
        accessibilityLabel = nil
        backgroundColor = .clear
        maskLayer.path = nil
        setNeedsQuickLayout()
    }

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

final class IMessageBubbleCell: QuickLayoutCollectionViewCell {

    let bubbleView = IMessageBubbleView(frame: .zero)
    let deliveryLabel = UILabel()
    private var message: IMessageChatMessagePresentation?
    private var maximumBubbleWidth: CGFloat = 280

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
                bubbleView
                    .frame(
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
        let resolvedWidth = max(140, layoutAttributes.size.width * 0.75)
        if abs(resolvedWidth - maximumBubbleWidth) > 0.5 {
            maximumBubbleWidth = resolvedWidth
            setNeedsQuickLayout()
        }
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    func configure(_ message: IMessageChatMessagePresentation) {
        self.message = message
        bubbleView.configure(message)
        deliveryLabel.text = message.deliveryText
        deliveryLabel.accessibilityLabel = message.deliveryText
        setNeedsQuickLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        message = nil
        bubbleView.reset()
        deliveryLabel.text = nil
        deliveryLabel.accessibilityLabel = nil
        setNeedsQuickLayout()
    }
}

final class IMessageTimestampCell: QuickLayoutCollectionViewCell {

    let timestampLabel = UILabel()

    override var body: Layout {
        timestampLabel
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ timestamp: IMessageChatTimestampPresentation) {
        timestampLabel.text = timestamp.text
        timestampLabel.accessibilityLabel = timestamp.text
        setNeedsQuickLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        timestampLabel.text = nil
        timestampLabel.accessibilityLabel = nil
    }
}

final class IMessageTypingBubbleView: QuickLayoutView {

    let dots: [UIView] = (0..<3).map { _ in UIView() }

    override var body: Layout {
        HStack(spacing: 4) {
            ForEach(dots) { dot in
                dot.frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            dots.forEach { $0.layer.removeAllAnimations() }
        } else {
            startAnimatingIfNeeded()
        }
    }

    func configure(accessibilityLabel: String) {
        self.accessibilityLabel = accessibilityLabel
        startAnimatingIfNeeded()
    }

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

final class IMessageTypingCell: QuickLayoutCollectionViewCell {

    let typingView = IMessageTypingBubbleView(frame: .zero)

    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [typingView]
    }

    override var body: Layout {
        HStack(spacing: 0) {
            typingView
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(accessibilityLabel: String) {
        typingView.configure(accessibilityLabel: accessibilityLabel)
        setNeedsQuickLayout()
    }
}
