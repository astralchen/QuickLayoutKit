//
//  LiveRoomActionBarView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomMessageTextField: UITextField {

    private let horizontalTextInset: CGFloat = 14

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        super.textRect(forBounds: bounds).insetBy(
            dx: horizontalTextInset,
            dy: 0
        )
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        super.editingRect(forBounds: bounds).insetBy(
            dx: horizontalTextInset,
            dy: 0
        )
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        super.placeholderRect(forBounds: bounds).insetBy(
            dx: horizontalTextInset,
            dy: 0
        )
    }
}

final class LiveRoomMessageInputView: QuickLayoutView {

    private static let cornerRadius: CGFloat = 8
    private static let minimumHeight: CGFloat = 35

    let textField = LiveRoomMessageTextField()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override var body: Layout {
        // 最小高度属于输入容器自身；标准字号为 35pt，辅助字号需要时仍可自然长高。
        textField
            .resizable()
            .frame(minHeight: Self.minimumHeight)
    }

    private func configureView() {
        accessibilityIdentifier = "liveRoom.message.input.container"
        backgroundColor = UIColor.white.withAlphaComponent(0.12)
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        clipsToBounds = true
    }
}

final class LiveRoomActionBarView: LiveRoomCardView, UITextFieldDelegate {

    private let messageButton = LiveRoomIconTitleButton(frame: .zero)
    private let microphoneButton = LiveRoomSymbolButton(frame: .zero)
    private let giftButton = LiveRoomSymbolButton(frame: .zero)
    // UIButton 暂时只保留在需要承载 UIMenu 的入口；QuickLayoutButton 不代理菜单 API。
    private let moreButton = UIButton(type: .system)
    private let messageInputView = LiveRoomMessageInputView()
    private let sendButton = LiveRoomCapsuleTextButton(frame: .zero)
    private let cancelButton = LiveRoomSymbolButton(frame: .zero)

    private var messageTextField: LiveRoomMessageTextField {
        messageInputView.textField
    }

    private var controlHeight: CGFloat {
        guard traitCollection.preferredContentSizeCategory
            .isAccessibilityCategory
        else { return 35 }
        return max(
            44,
            ceil(UIFont.preferredFont(forTextStyle: .body).lineHeight + 14)
        )
    }

    var messageDidSend: ((String) -> Void)?
    var giftDidTap: (() -> Void)?
    private(set) var isShowingMessageComposer = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    @LayoutBuilder
    override var body: Layout {
        if isShowingMessageComposer {
            HStack(spacing: 8) {
                messageInputView
                    .resizable(axis: .horizontal)
                    .frame(height: controlHeight)
                    .frame(minWidth: 96)
                sendButton
                    .resizable(axis: .vertical)
                    .fixedSize(axis: .horizontal)
                    .frame(height: controlHeight)
                cancelButton
                    .resizable()
                    .frame(width: controlHeight, height: controlHeight)
            }
            .padding(10)
        } else {
            // 操作条在紧凑宽度下仍保持单行。消息入口负责横向压缩，三个
            // 35pt 操作按钮保持固定尺寸，避免两行布局吞掉公屏剩余高度。
            HStack(spacing: 9) {
                messageLayout
                roundButtonsLayout
            }
            .padding(10)
        }
    }

    private var messageLayout: Layout {
        messageButton
            .resizable()
            .frame(height: controlHeight)
    }

    private var roundButtonsLayout: Layout {
        HStack(spacing: 9) {
            microphoneButton.resizable().frame(
                width: controlHeight,
                height: controlHeight
            )
            giftButton.resizable().frame(
                width: controlHeight,
                height: controlHeight
            )
            moreButton.resizable().frame(
                width: controlHeight,
                height: controlHeight
            )
        }
    }

    func configure(
        message: String,
        microphone: String,
        gift: String,
        more: String,
        inputPlaceholder: String,
        send: String,
        cancel: String
    ) {
        messageButton.configure(title: message, symbolName: "message.fill")
        microphoneButton.accessibilityLabel = microphone
        giftButton.accessibilityLabel = gift
        moreButton.accessibilityLabel = more
        messageTextField.attributedPlaceholder = NSAttributedString(
            string: inputPlaceholder,
            attributes: [
                .foregroundColor: UIColor.white.withAlphaComponent(0.52),
            ]
        )
        sendButton.configure(
            title: send,
            font: .systemFont(ofSize: 16, weight: .semibold),
            foregroundColor: .white,
            backgroundColor: .systemPink,
            borderColor: .clear,
            borderWidth: 1,
            contentInsets: EdgeInsets(
                top: 6,
                leading: 14,
                bottom: 6,
                trailing: 14
            ),
            disabledForegroundColor: UIColor.white.withAlphaComponent(0.68),
            disabledBackgroundColor: UIColor.white.withAlphaComponent(0.12),
            disabledBorderColor: UIColor.white.withAlphaComponent(0.20)
        )
        sendButton.accessibilityLabel = send
        cancelButton.accessibilityLabel = cancel
    }

    func setMoreMenu(_ menu: UIMenu) {
        moreButton.menu = menu
    }

    func giftAnimationOrigin(in view: UIView) -> CGPoint? {
        guard giftButton.window != nil else { return nil }
        return giftButton.convert(
            CGPoint(x: giftButton.bounds.midX, y: giftButton.bounds.midY),
            to: view
        )
    }

    private func configureViews() {
        accessibilityIdentifier = "liveRoom.actionBar"
        messageButton.accessibilityIdentifier = "liveRoom.message.button"
        messageButton.action = { [weak self] in self?.showMessageComposer() }

        microphoneButton.configure(symbolName: "mic.fill")
        microphoneButton.accessibilityIdentifier = "liveRoom.microphone.button"
        giftButton.configure(symbolName: "gift.fill")
        giftButton.accessibilityIdentifier = "liveRoom.gift.button"
        giftButton.action = { [weak self] in self?.showGiftSheet() }
        configureRoundButton(moreButton, symbolName: "ellipsis")
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.accessibilityIdentifier = "liveRoom.more.button"

        messageTextField.backgroundColor = .clear
        messageTextField.textColor = .white
        messageTextField.borderStyle = .none
        messageTextField.font = .preferredFont(forTextStyle: .body)
        messageTextField.adjustsFontForContentSizeCategory = true
        messageTextField.textAlignment = .natural
        messageTextField.keyboardAppearance = .dark
        messageTextField.clearButtonMode = .whileEditing
        messageTextField.returnKeyType = .send
        messageTextField.enablesReturnKeyAutomatically = true
        messageTextField.delegate = self
        messageTextField.accessibilityIdentifier = "liveRoom.message.input"
        messageTextField.addTarget(
            self,
            action: #selector(messageTextDidChange),
            for: .editingChanged
        )
        messageTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        messageTextField.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        sendButton.accessibilityIdentifier = "liveRoom.message.send"
        sendButton.isEnabled = false
        sendButton.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        sendButton.action = { [weak self] in self?.sendMessage() }

        cancelButton.configure(symbolName: "xmark")
        cancelButton.role = .cancel
        cancelButton.accessibilityIdentifier = "liveRoom.message.cancel"
        cancelButton.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        cancelButton.action = { [weak self] in self?.cancelMessage() }
    }

    private func showMessageComposer() {
        guard !isShowingMessageComposer else { return }
        isShowingMessageComposer = true
        updateComposerAppearance()
        setNeedsQuickLayout()
        layoutIfNeeded()
        messageTextField.becomeFirstResponder()
    }

    private func sendMessage() {
        let message = normalizedMessageText
        guard !message.isEmpty else { return }
        let handler = messageDidSend
        // 先恢复默认操作条，再通知 Controller 追加消息。这样公屏的“滚动到最新”
        // 请求从一开始就基于最终操作条高度，不会消费键盘态的旧 bounds。
        dismissMessageComposer()
        handler?(message)
    }

    @objc private func messageTextDidChange() {
        updateSendButtonState()
    }

    private func cancelMessage() {
        dismissMessageComposer()
    }

    private func showGiftSheet() {
        giftDidTap?()
    }

    private func dismissMessageComposer() {
        messageTextField.text = nil
        updateSendButtonState()
        messageTextField.resignFirstResponder()
        isShowingMessageComposer = false
        updateComposerAppearance()
        setNeedsQuickLayout()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard sendButton.isEnabled else { return false }
        sendMessage()
        return false
    }

    private var normalizedMessageText: String {
        messageTextField.text?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
    }

    private func updateSendButtonState() {
        // 输入内容必须包含非空白字符；按钮和键盘 Return 键共用这条发送规则。
        sendButton.isEnabled = !normalizedMessageText.isEmpty
    }

    private func configureRoundButton(_ button: UIButton, symbolName: String) {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: symbolName)
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.14)
        configuration.baseForegroundColor = .white
        button.configuration = configuration
    }

    private func updateComposerAppearance() {
        if isShowingMessageComposer {
            // 输入条会悬浮到键盘上方，使用近不透明背景保证与麦位内容清晰分层。
            backgroundColor = UIColor(
                red: 0.055,
                green: 0.045,
                blue: 0.15,
                alpha: 0.97
            )
            layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.32
            layer.shadowRadius = 14
            layer.shadowOffset = CGSize(width: 0, height: -5)
        } else {
            backgroundColor = UIColor.black.withAlphaComponent(0.18)
            layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
            layer.shadowOpacity = 0
            layer.shadowRadius = 0
            layer.shadowOffset = .zero
        }
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomMessageTextFieldPreview() -> UIViewController {
    let view = LiveRoomMessageTextField()
    view.text = "Preview 公屏消息"
    view.textColor = .white
    view.backgroundColor = UIColor.white.withAlphaComponent(0.12)
    view.layer.cornerRadius = 8
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            view.resizable().padding(16)
        }
        .frame(width: 390, height: 72)
    }
}

@MainActor
private func makeLiveRoomMessageInputViewPreview() -> UIViewController {
    let view = LiveRoomMessageInputView()
    view.textField.attributedPlaceholder = NSAttributedString(
        string: "输入 Preview 消息",
        attributes: [
            .foregroundColor: UIColor.white.withAlphaComponent(0.52),
        ]
    )
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            view.resizable().padding(16)
        }
        .frame(width: 390, height: 72)
    }
}

@MainActor
private func makeLiveRoomActionBarPreview() -> UIViewController {
    let view = LiveRoomActionBarView()
    view.configure(
        message: "说点好听的…",
        microphone: "麦克风",
        gift: "礼物",
        more: "更多",
        inputPlaceholder: "输入公屏消息",
        send: "发送",
        cancel: "取消"
    )
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            view.resizable().padding(16)
        }
        .frame(width: 390, height: 94)
    }
}

#Preview("公屏文本框") {
    makeLiveRoomMessageTextFieldPreview()
}

#Preview("公屏输入容器") {
    makeLiveRoomMessageInputViewPreview()
}

#Preview("直播操作栏") {
    makeLiveRoomActionBarPreview()
}
#endif
