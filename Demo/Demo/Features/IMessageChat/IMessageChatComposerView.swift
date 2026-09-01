//
//  IMessageChatComposerView.swift
//  Demo
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

@available(iOS 26.0, *)
final class IMessageChatComposerView: UIView, UITextViewDelegate {

    let textView = UITextView()
    let placeholderLabel = UILabel()
    let sendButton = UIButton(type: .system)

    var sendRequested: ((String) -> Bool)?
    var heightDidChange: (() -> Void)?

    private let glassContainerView: UIVisualEffectView
    private let inputGlassView: UIVisualEffectView
    private var inputHeightConstraint: NSLayoutConstraint!
    private var currentInputHeight: CGFloat = 44
    private var lastMeasuredWidth: CGFloat = 0

    override init(frame: CGRect) {
        let containerEffect = UIGlassContainerEffect()
        containerEffect.spacing = 8
        glassContainerView = UIVisualEffectView(effect: containerEffect)

        let inputEffect = UIGlassEffect(style: .regular)
        inputEffect.isInteractive = true
        inputGlassView = UIVisualEffectView(effect: inputEffect)
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let availableTextWidth = max(0, inputGlassView.bounds.width - 8)
        if abs(availableTextWidth - lastMeasuredWidth) > 0.5 {
            lastMeasuredWidth = availableTextWidth
            updateTextHeight()
        }
    }

    func configure(
        placeholder: String,
        sendAccessibilityLabel: String
    ) {
        placeholderLabel.text = placeholder
        textView.accessibilityLabel = placeholder
        sendButton.accessibilityLabel = sendAccessibilityLabel
        updateComposerState()
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
        setNeedsLayout()
    }

    func textViewDidChange(_ textView: UITextView) {
        updateComposerState()
        updateTextHeight()
    }

    private func configureViews() {
        accessibilityIdentifier = "imessage.composer"
        backgroundColor = .clear

        glassContainerView.translatesAutoresizingMaskIntoConstraints = false
        glassContainerView.backgroundColor = .clear
        addSubview(glassContainerView)

        inputGlassView.translatesAutoresizingMaskIntoConstraints = false
        inputGlassView.clipsToBounds = true
        inputGlassView.layer.cornerRadius = 22
        inputGlassView.layer.cornerCurve = .continuous
        glassContainerView.contentView.addSubview(inputGlassView)

        textView.translatesAutoresizingMaskIntoConstraints = false
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
        inputGlassView.contentView.addSubview(textView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isAccessibilityElement = false
        textView.addSubview(placeholderLabel)

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
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.accessibilityIdentifier = "imessage.composer.send"
        sendButton.addTarget(
            self,
            action: #selector(sendButtonDidTap),
            for: .touchUpInside
        )
        glassContainerView.contentView.addSubview(sendButton)

        inputHeightConstraint = inputGlassView.heightAnchor.constraint(
            equalToConstant: currentInputHeight
        )
        inputHeightConstraint.priority = .required

        NSLayoutConstraint.activate([
            glassContainerView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 10
            ),
            glassContainerView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -10
            ),
            glassContainerView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 8
            ),
            glassContainerView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -8
            ),

            inputGlassView.leadingAnchor.constraint(
                equalTo: glassContainerView.contentView.leadingAnchor
            ),
            inputGlassView.topAnchor.constraint(
                equalTo: glassContainerView.contentView.topAnchor
            ),
            inputGlassView.bottomAnchor.constraint(
                equalTo: glassContainerView.contentView.bottomAnchor
            ),
            inputHeightConstraint,

            sendButton.leadingAnchor.constraint(
                equalTo: inputGlassView.trailingAnchor,
                constant: 8
            ),
            sendButton.trailingAnchor.constraint(
                equalTo: glassContainerView.contentView.trailingAnchor
            ),
            sendButton.bottomAnchor.constraint(
                equalTo: glassContainerView.contentView.bottomAnchor
            ),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44),

            textView.leadingAnchor.constraint(
                equalTo: inputGlassView.contentView.leadingAnchor,
                constant: 4
            ),
            textView.trailingAnchor.constraint(
                equalTo: inputGlassView.contentView.trailingAnchor,
                constant: -4
            ),
            textView.topAnchor.constraint(
                equalTo: inputGlassView.contentView.topAnchor
            ),
            textView.bottomAnchor.constraint(
                equalTo: inputGlassView.contentView.bottomAnchor
            ),

            placeholderLabel.leadingAnchor.constraint(
                equalTo: textView.leadingAnchor,
                constant: 8
            ),
            placeholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: textView.trailingAnchor,
                constant: -8
            ),
            placeholderLabel.topAnchor.constraint(
                equalTo: textView.topAnchor,
                constant: 8
            ),
        ])

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

    private func updateTextHeight() {
        let font = textView.font ?? .preferredFont(forTextStyle: .body)
        let maximumHeight = ceil(font.lineHeight * 5)
            + textView.textContainerInset.top
            + textView.textContainerInset.bottom
        let width = max(1, textView.bounds.width)
        let measuredHeight = textView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
        let resolvedHeight = min(max(44, ceil(measuredHeight)), maximumHeight)
        textView.isScrollEnabled = measuredHeight > maximumHeight + 0.5

        guard abs(resolvedHeight - currentInputHeight) > 0.5 else { return }
        currentInputHeight = resolvedHeight
        inputHeightConstraint.constant = resolvedHeight
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
