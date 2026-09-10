import UIKit

/// 所有消息类型共用的状态栏。失败状态整体可重试，点击区至少 44 × 44 pt。
final class IMessageChatDeliveryStatusView: UIControl {
    /// 显示本地化送达或已读文本的标签。
    let label = UILabel()
    /// 消息正在发送时显示的活动指示器。
    let progress = UIActivityIndicatorView(style: .medium)
    /// 发送失败时显示的重试符号图像视图。
    private let failureImage = UIImageView(image: UIImage(systemName: "exclamationmark.circle.fill"))
    /// 当前状态对应的消息标识符，用于发送重试请求。
    private var messageID: Int?
    /// 当前展示的发送状态；未绑定消息时为 `nil`。
    private var status: IMessageChatDeliveryState?
    /// 用户点击失败入口时调用的闭包，参数为待重试的消息身份。
    var retryRequested: ((Int) -> Void)?

    /// 使用指定初始边框创建 `IMessageChatDeliveryStatusView`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
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

    /// 不支持从归档创建 `IMessageChatDeliveryStatusView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 绑定消息发送状态，并更新文字、进度、失败入口与可交互性。
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
        accessibilityHint = status == .failed ? Localization.text("imessage.status.retry.hint") : nil
        accessibilityTraits = status == .failed ? .button : .staticText
        accessibilityIdentifier = status == .failed ? "imessage.message.retry" : "imessage.message.status"
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    /// 当前发送状态图标占用的宽度，单位为点。
    private var iconWidth: CGFloat { status == .sending || status == .failed ? 26 : 0 }
    /// `IMessageChatDeliveryStatusView` 在当前内容与布局约束下的固有尺寸。
    override var intrinsicContentSize: CGSize { sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)) }
    /// 返回 `IMessageChatDeliveryStatusView` 在指定建议尺寸下所需的大小。
    ///
    /// - Parameter size: 父视图提供的建议尺寸。
    /// - Returns: 当前内容对应的适配尺寸。
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let textSize = label.sizeThatFits(CGSize(width: max(1, size.width - iconWidth), height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: min(size.width, max(status == .failed ? 44 : 0, textSize.width + iconWidth)),
                      height: max(status == .failed ? 44 : (status == .sending ? 20 : 0), textSize.height))
    }
    /// 根据当前边界更新 `IMessageChatDeliveryStatusView` 的子视图布局与图层几何。
    override func layoutSubviews() {
        super.layoutSubviews()
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let iconX = rtl ? bounds.width - 20 : 0
        progress.frame = CGRect(x: iconX, y: (bounds.height - 20) / 2, width: 20, height: 20)
        failureImage.frame = progress.frame
        label.frame = CGRect(x: rtl ? 0 : iconWidth, y: 0, width: max(0, bounds.width - iconWidth), height: bounds.height)
    }
}
