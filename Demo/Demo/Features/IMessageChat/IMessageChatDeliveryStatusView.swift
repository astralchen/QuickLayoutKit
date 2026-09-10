import UIKit

/// 所有消息类型共用的状态栏。失败状态整体可重试，点击区至少 44 × 44 pt。
final class IMessageChatDeliveryStatusView: UIControl {
    let label = UILabel()
    let progress = UIActivityIndicatorView(style: .medium)
    private let failureImage = UIImageView(image: UIImage(systemName: "exclamationmark.circle.fill"))
    private var messageID: Int?
    private var status: IMessageChatDeliveryState?
    var retryRequested: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        failureImage.tintColor = .systemRed
        for view in [label, progress, failureImage] { addSubview(view) }
        isAccessibilityElement = true
        addAction(UIAction { [weak self] _ in
            guard let self, status == .failed, let messageID else { return }
            retryRequested?(messageID)
        }, for: .touchUpInside)
        configure(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ message: IMessageChatMessagePresentation?) {
        messageID = message?.id
        status = message?.deliveryState
        label.text = message?.deliveryText
        label.textColor = status == .failed ? .systemRed : .secondaryLabel
        progress.isHidden = status != .sending
        if status == .sending { progress.startAnimating() } else { progress.stopAnimating() }
        failureImage.isHidden = status != .failed
        isUserInteractionEnabled = status == .failed
        accessibilityLabel = message?.deliveryText
        accessibilityHint = status == .failed ? DemoLocalization.text("imessage.status.retry.hint") : nil
        accessibilityTraits = status == .failed ? .button : .staticText
        accessibilityIdentifier = status == .failed ? "imessage.message.retry" : "imessage.message.status"
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private var iconWidth: CGFloat { status == .sending || status == .failed ? 26 : 0 }
    override var intrinsicContentSize: CGSize { sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)) }
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let textSize = label.sizeThatFits(CGSize(width: max(1, size.width - iconWidth), height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: min(size.width, max(status == .failed ? 44 : 0, textSize.width + iconWidth)),
                      height: max(status == .failed ? 44 : (status == .sending ? 20 : 0), textSize.height))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let iconX = rtl ? bounds.width - 20 : 0
        progress.frame = CGRect(x: iconX, y: (bounds.height - 20) / 2, width: 20, height: 20)
        failureImage.frame = progress.frame
        label.frame = CGRect(x: rtl ? 0 : iconWidth, y: 0, width: max(0, bounds.width - iconWidth), height: bounds.height)
    }
}
