import UIKit

/// 非编辑、非滚动的消息正文，保留系统数据识别、文字选择和上下文菜单。
final class MessageBodyTextView: UITextView {
    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        dataDetectorTypes = [.phoneNumber, .link, .address]
        accessibilityIdentifier = "imessage.message.text"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// UITextView 默认占满建议宽度；正文按内容收窄，长文本才换行。
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let attributedText, attributedText.length > 0 else { return .zero }
        let width = max(1, size.width)
        let bounds = attributedText.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let fittingWidth = min(width, ceil(bounds.width))
        let fitting = super.sizeThatFits(CGSize(width: fittingWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: fittingWidth, height: ceil(fitting.height))
    }
}
