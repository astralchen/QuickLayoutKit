//
//  IMessageChatComposerView.swift
//  Demo
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

@available(iOS 26.0, *)
final class IMessageChatComposerView: QuickLayoutView, UITextViewDelegate {

    let textView = UITextView()
    let placeholderLabel = UILabel()
    let sendButton = UIButton(type: .system)

    var sendRequested: ((String) -> Bool)?
    var heightDidChange: (() -> Void)?

    private var currentInputHeight: CGFloat = 44

    private lazy var inputGlassView: QuickLayoutVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return QuickLayoutVisualEffectView(effect: effect) { [unowned self] in
            ZStack(alignment: .topLeading) {
                textView.resizable()
                placeholderLabel
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
            .padding(.horizontal, 4)
        }
    }()

    private lazy var glassContainerView: QuickLayoutVisualEffectView = {
        let effect = UIGlassContainerEffect()
        effect.spacing = 8
        return QuickLayoutVisualEffectView(effect: effect) { [unowned self] in
            HStack(alignment: .bottom, spacing: 8) {
                inputGlassView
                    .resizable(axis: .horizontal)
                    .frame(height: currentInputHeight)
                    .onGeometryChange(
                        for: CGFloat.self,
                        of: { max(0, $0.size.width - 8) },
                        action: { [weak self] width in
                            self?.updateTextHeight(availableWidth: width)
                        }
                    )
                sendButton.resizable().frame(width: 44, height: 44)
            }
        }
    }()

    override var body: Layout {
        glassContainerView
            .resizable()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: currentInputHeight + 16
        )
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: currentInputHeight + 16)
    }

    func configure(
        placeholder: String,
        sendAccessibilityLabel: String
    ) {
        placeholderLabel.text = placeholder
        textView.accessibilityLabel = placeholder
        sendButton.accessibilityLabel = sendAccessibilityLabel
        updateComposerState()
        inputGlassView.setNeedsQuickLayout()
    }

    func applyLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        let semanticAttribute = direction.appLayoutDirection
            .semanticContentAttribute
        semanticContentAttribute = semanticAttribute
        glassContainerView.semanticContentAttribute = semanticAttribute
        inputGlassView.semanticContentAttribute = semanticAttribute
        textView.semanticContentAttribute = semanticAttribute
        textView.textAlignment = .natural
        placeholderLabel.semanticContentAttribute = semanticAttribute
        placeholderLabel.textAlignment = .natural
        glassContainerView.setNeedsQuickLayout()
        inputGlassView.setNeedsQuickLayout()
        setNeedsQuickLayout()
    }

    func textViewDidChange(_ textView: UITextView) {
        updateComposerState()
        updateTextHeight()
    }

    private func configureViews() {
        accessibilityIdentifier = "imessage.composer"
        backgroundColor = .clear
        quickLayoutHorizontalFlexibility = .fullyFlexible
        quickLayoutVerticalFlexibility = .fixedSize

        glassContainerView.backgroundColor = .clear

        inputGlassView.clipsToBounds = true
        inputGlassView.layer.cornerRadius = 22
        inputGlassView.layer.cornerCurve = .continuous

        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.textAlignment = .natural
        textView.textContainerInset = UIEdgeInsets(
            top: 8,
            left: 8,
            bottom: 8,
            right: 8
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

        var configuration = UIButton.Configuration.prominentGlass()
        configuration.image = UIImage(
            systemName: "arrow.up",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 17,
                weight: .bold
            )
        )
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        sendButton.configuration = configuration
        sendButton.tintColor = .systemBlue
        sendButton.accessibilityIdentifier = "imessage.composer.send"
        sendButton.addTarget(
            self,
            action: #selector(sendButtonDidTap),
            for: .touchUpInside
        )

        updateComposerState()
    }

    @objc private func sendButtonDidTap() {
        let text = textView.text ?? ""
        guard sendRequested?(text) == true else { return }
        textView.text = nil
        updateComposerState()
        updateTextHeight()
    }

    private func updateComposerState() {
        let hasText = !(textView.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
        sendButton.isEnabled = hasText
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
        glassContainerView.setNeedsQuickLayout()
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
    direction: UIUserInterfaceLayoutDirection
) -> UIViewController {
    let backgroundView = UIView()
    backgroundView.backgroundColor = .systemBackground
    let composerView = IMessageChatComposerView(frame: .zero)
    composerView.configure(
        placeholder: IMessageChatPreviewData.composerPlaceholder,
        sendAccessibilityLabel: IMessageChatPreviewData
            .sendAccessibilityLabel
    )
    composerView.applyLayoutDirection(direction)
    composerView.textView.text = text
    composerView.textViewDidChange(composerView.textView)
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
    makeIMessageChatComposerPreview(text: "", direction: .leftToRight)
}

#Preview("消息输入栏 · 多行") {
    makeIMessageChatComposerPreview(
        text: IMessageChatPreviewData.composerMultilineText,
        direction: .leftToRight
    )
}

#Preview("消息输入栏 · 多行 RTL") {
    makeIMessageChatComposerPreview(
        text: IMessageChatPreviewData.composerRTLText,
        direction: .rightToLeft
    )
}
#endif
