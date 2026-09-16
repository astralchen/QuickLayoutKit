//
//  RoomActionBarView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 为公屏输入文字和占位文字提供统一水平内边距的文本框。
final class RoomMessageTextField: UITextField {

    /// 文本和占位文字两侧的内边距，单位为点。
    private let horizontalTextInset: CGFloat = 14

    /// 返回应用水平内边距后的静态文本绘制区域。
    override func textRect(forBounds bounds: CGRect) -> CGRect {
        super.textRect(forBounds: bounds).insetBy(
            dx: horizontalTextInset,
            dy: 0
        )
    }

    /// 返回应用水平内边距后的编辑区域。
    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        super.editingRect(forBounds: bounds).insetBy(
            dx: horizontalTextInset,
            dy: 0
        )
    }

    /// 返回与正文对齐的占位文字绘制区域。
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        super.placeholderRect(forBounds: bounds).insetBy(
            dx: horizontalTextInset,
            dy: 0
        )
    }
}

/// 包裹公屏文本框并提供圆角背景的输入容器。
final class RoomMessageInputView: QuickLayoutView {

    /// 组件背景的圆角半径，单位为点。
    private static let cornerRadius: CGFloat = 8
    /// 组件布局允许的最小高度，单位为点。
    private static let minimumHeight: CGFloat = 35

    /// 接收公屏消息输入的文本框。
    let textField = RoomMessageTextField()

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        // 最小高度属于输入容器自身；标准字号为 35pt，辅助字号需要时仍可自然长高。
        textField
            .resizable()
            .frame(minHeight: Self.minimumHeight)
    }

    /// 配置组件的基础样式和交互行为。
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

/// 在常规操作按钮与公屏消息编辑区域之间切换的底部工具栏。
final class RoomActionBarView: TranslucentCardView, UITextFieldDelegate {

    /// 进入消息编辑状态的按钮。
    private let messageButton = IconTitleButton(frame: .zero)
    /// 显示麦克风操作入口的按钮。
    private let microphoneButton = SymbolButton(frame: .zero)
    /// 打开礼物面板的按钮。
    private let giftButton = SymbolButton(frame: .zero)
    // UIButton 暂时只保留在需要承载 UIMenu 的入口；QuickLayoutButton 不代理菜单 API。
    /// 展示房间业务菜单的按钮。
    private let moreButton = UIButton(type: .system)
    /// 公屏消息编辑区域的输入容器。
    private let messageInputView = RoomMessageInputView()
    /// 维护文本输入本地化及布局方向的绑定。
    private lazy var inputBinding = Localization.reusableContext.makeTextInputBinding(to: messageTextField)
    /// 提交当前选择或输入内容的按钮。
    private let sendButton = CapsuleTextButton(frame: .zero)
    /// 取消当前消息编辑的按钮。
    private let cancelButton = SymbolButton(frame: .zero)

    /// 公屏消息输入容器中的实际文本框。
    private var messageTextField: RoomMessageTextField {
        messageInputView.textField
    }

    /// 根据当前内容环境解析的操作控件高度，单位为点。
    private var controlHeight: CGFloat {
        guard traitCollection.preferredContentSizeCategory
            .isAccessibilityCategory
        else { return 35 }
        return max(
            44,
            ceil(UIFont.preferredFont(forTextStyle: .body).lineHeight + 14)
        )
    }

    /// 提交非空消息时调用的回调；参数为规范化后的消息文本。
    var messageDidSend: ((String) -> Void)?
    /// 用户点击礼物入口时调用的回调。
    var giftDidTap: (() -> Void)?
    /// 一个布尔值，指示底部操作栏是否显示消息编辑区域。
    private(set) var isShowingMessageComposer = false

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
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

    /// 常规状态下消息入口的布局。
    private var messageLayout: Layout {
        messageButton
            .resizable()
            .frame(height: controlHeight)
    }

    /// 麦克风、礼物和更多圆形按钮的布局。
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

    /// 更新操作按钮文案、输入占位文字及辅助功能描述。
    func configure(
        message: String,
        microphone: String,
        gift: String,
        more: String,
        inputPlaceholder: String,
        send: String,
        cancel: String
    ) {
        inputBinding.refresh()
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

    /// 设置更多按钮展示的房间业务菜单。
    func setMoreMenu(_ menu: UIMenu) {
        moreButton.menu = menu
    }

    /// 返回礼物飞行起点在指定视图坐标系中的位置；视图不可用时为 `nil`。
    func giftAnimationOrigin(in view: UIView) -> CGPoint? {
        guard giftButton.window != nil else { return nil }
        return giftButton.convert(
            CGPoint(x: giftButton.bounds.midX, y: giftButton.bounds.midY),
            to: view
        )
    }

    /// 配置子视图的样式、交互和辅助功能属性。
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
        inputBinding.refresh()
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

    /// 视图进入窗口后刷新文本输入的本地化绑定。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { inputBinding.refresh() }
    }

    /// 显示消息编辑区域并请求文本框成为第一响应者。
    private func showMessageComposer() {
        guard !isShowingMessageComposer else { return }
        isShowingMessageComposer = true
        updateComposerAppearance()
        setNeedsQuickLayout()
        layoutIfNeeded()
        inputBinding.refresh()
        messageTextField.becomeFirstResponder()
    }

    /// 提交规范化后的非空消息并退出编辑状态。
    private func sendMessage() {
        let message = normalizedMessageText
        guard !message.isEmpty else { return }
        let handler = messageDidSend
        // 先恢复默认操作条，再通知 Controller 追加消息。这样公屏的“滚动到最新”
        // 请求从一开始就基于最终操作条高度，不会消费键盘态的旧 bounds。
        dismissMessageComposer()
        handler?(message)
    }

    /// 在文本变化时更新发送按钮的可用状态。
    @objc private func messageTextDidChange() {
        updateSendButtonState()
    }

    /// 取消当前消息编辑并恢复常规操作栏。
    private func cancelMessage() {
        dismissMessageComposer()
    }

    /// 结束消息编辑并通知宿主打开礼物面板。
    private func showGiftSheet() {
        giftDidTap?()
    }

    /// 结束文本输入并恢复常规操作按钮布局。
    private func dismissMessageComposer() {
        messageTextField.text = nil
        inputBinding.refresh()
        updateSendButtonState()
        messageTextField.resignFirstResponder()
        isShowingMessageComposer = false
        updateComposerAppearance()
        setNeedsQuickLayout()
    }

    /// 响应键盘发送动作，提交当前消息。
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard sendButton.isEnabled else { return false }
        sendMessage()
        return false
    }

    /// 去除首尾空白与换行后的当前输入文本。
    private var normalizedMessageText: String {
        messageTextField.text?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
    }

    /// 根据当前输入是否包含非空文本更新发送按钮。
    private func updateSendButtonState() {
        // 输入内容必须包含非空白字符；按钮和键盘 Return 键共用这条发送规则。
        sendButton.isEnabled = !normalizedMessageText.isEmpty
    }

    /// 为圆形工具按钮设置指定符号和统一样式。
    private func configureRoundButton(_ button: UIButton, symbolName: String) {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: symbolName)
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.14)
        configuration.baseForegroundColor = .white
        button.configuration = configuration
    }

    /// 同步编辑状态对应的控件可见性、布局和辅助功能状态。
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
/// 创建展示公屏消息文本框的预览控制器。
@MainActor
private func makeRoomMessageTextFieldPreview() -> UIViewController {
    let view = RoomMessageTextField()
    view.text = "Preview 公屏消息"
    view.textColor = .white
    view.backgroundColor = UIColor.white.withAlphaComponent(0.12)
    view.layer.cornerRadius = 8
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view.resizable().padding(16)
        }
        .frame(width: .infinity, height: 72)
    }
}

/// 创建展示公屏输入容器的预览控制器。
@MainActor
private func makeRoomMessageInputViewPreview() -> UIViewController {
    let view = RoomMessageInputView()
    view.textField.attributedPlaceholder = NSAttributedString(
        string: "输入 Preview 消息",
        attributes: [
            .foregroundColor: UIColor.white.withAlphaComponent(0.52),
        ]
    )
    return QuickLayoutHostingController {
        ZStack(alignment: .bottom) {
            StarfieldBackgroundView().resizable()
            view.resizable(axis: .horizontal)
                .frame(height: 35)
                .safeAreaPadding(.horizontal, 16)
                .safeAreaPadding()
        }
    }
}

/// 创建展示房间底部操作栏的预览控制器。
@MainActor
private func makeRoomActionBarPreview() -> UIViewController {
    let view = RoomActionBarView()
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
        ZStack(alignment: .bottom) {
            StarfieldBackgroundView().resizable()
            view.resizable(axis: .horizontal)
                .safeAreaPadding(.horizontal, 18)
                .safeAreaPadding()
        }
    }
}

@available(iOS 17.0, *)
#Preview("公屏文本框") {
    makeRoomMessageTextFieldPreview()
}

@available(iOS 17.0, *)
#Preview("公屏输入容器") {
    makeRoomMessageInputViewPreview()
}

@available(iOS 17.0, *)
#Preview("直播操作栏") {
    makeRoomActionBarPreview()
}
#endif
