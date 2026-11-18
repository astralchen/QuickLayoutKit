import UIKit

/// App 表单的文字、占位提示与光标统一采用逻辑 leading。
/// 使用原生文本对齐，不改写文字、选区或 Unicode 书写方向；显式对齐保留调用方语义。
final class LocalizedTextField: UITextField {
    private var requestedAlignment: NSTextAlignment = .natural

    override init(frame: CGRect) {
        super.init(frame: frame)
        // UITextField 初始化会通过 textAlignment setter 写入自己的默认值。
        requestedAlignment = .natural
        resolveAlignment()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        requestedAlignment = super.textAlignment
    }

    override var textAlignment: NSTextAlignment {
        get { super.textAlignment }
        set { requestedAlignment = newValue; resolveAlignment() }
    }

    private func resolveAlignment() {
        let alignment: NSTextAlignment = requestedAlignment == .natural
            ? (effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left)
            : requestedAlignment
        if super.textAlignment != alignment { super.textAlignment = alignment }
    }

    override func becomeFirstResponder() -> Bool {
        resolveAlignment()
        return super.becomeFirstResponder()
    }
    override func layoutSubviews() { resolveAlignment(); super.layoutSubviews() }
    override func didMoveToWindow() { super.didMoveToWindow(); resolveAlignment() }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        resolveAlignment()
    }
}

/// App 提供的说明文字采用逻辑 leading；代码、居中标题可显式指定 textAlignment。
/// 不用于用户输入，也不改变文字的 Unicode 双向顺序或 UIView 的语义属性。
final class LocalizedLabel: UILabel {
    private var requestedAlignment: NSTextAlignment = .natural

    override var textAlignment: NSTextAlignment {
        get { super.textAlignment }
        set { requestedAlignment = newValue; resolveAlignment() }
    }

    private func resolveAlignment() {
        let alignment: NSTextAlignment = requestedAlignment == .natural
            ? (effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left)
            : requestedAlignment
        if super.textAlignment != alignment { super.textAlignment = alignment }
    }

    override func layoutSubviews() { resolveAlignment(); super.layoutSubviews() }
    override func didMoveToWindow() { super.didMoveToWindow(); resolveAlignment() }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        resolveAlignment()
    }
}

/// UIKit 的配置内容可能保留旧的图文顺序；只重新安装本按钮的公开配置。
final class LocalizedButton: UIButton {
    private var renderedDirection: UIUserInterfaceLayoutDirection?
    override func layoutSubviews() {
        let direction = effectiveUserInterfaceLayoutDirection
        if renderedDirection != direction {
            renderedDirection = direction
            if let saved = configuration {
                configuration = nil
                configuration = saved
            }
        }
        super.layoutSubviews()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        setNeedsLayout()
    }
}

/// 参数编辑滑块。外层维持身份、事件与继承语义，原生 UISlider 负责触摸和辅助功能。
/// 部分系统的轨道缓存不会随运行时方向切换更新，因此仅在方向变化后更换内部控件。
final class LocalizedSlider: UIControl {
    private(set) var slider = UISlider()
    private var renderedDirection: UIUserInterfaceLayoutDirection?
    var minimumValue: Float {
        get { slider.minimumValue }
        set { slider.minimumValue = newValue }
    }
    var maximumValue: Float {
        get { slider.maximumValue }
        set { slider.maximumValue = newValue }
    }
    var value: Float {
        get { slider.value }
        set { slider.value = newValue }
    }
    func setValue(_ value: Float, animated: Bool) { slider.setValue(value, animated: animated) }
    override var isEnabled: Bool { didSet { slider.isEnabled = isEnabled } }
    override var accessibilityIdentifier: String? { didSet { slider.accessibilityIdentifier = accessibilityIdentifier } }
    override var accessibilityLabel: String? { didSet { slider.accessibilityLabel = accessibilityLabel } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        install(slider)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { slider.intrinsicContentSize }
    override func sizeThatFits(_ size: CGSize) -> CGSize { slider.sizeThatFits(size) }

    private func install(_ control: UISlider) {
        addSubview(control)
        control.addTarget(self, action: #selector(changed), for: .valueChanged)
        control.addTarget(self, action: #selector(ended), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    @objc private func changed() { sendActions(for: .valueChanged) }
    @objc private func ended() { setNeedsLayout() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let direction = effectiveUserInterfaceLayoutDirection
        // 语言菜单通常在拖动结束后操作；仍避免打断进行中的原生 tracking。
        if renderedDirection != direction, !slider.isTracking {
            let old = slider
            let replacement = UISlider(frame: bounds)
            // 这是控件自己的渲染边界，必须在首次生成轨道前建立方向。
            // 外层仍为 unspecified，playback/spatial/固定方向由 effective direction 解析。
            replacement.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
            replacement.minimumValue = old.minimumValue
            replacement.maximumValue = old.maximumValue
            replacement.value = old.value
            replacement.isEnabled = isEnabled
            replacement.accessibilityIdentifier = accessibilityIdentifier
            replacement.accessibilityLabel = accessibilityLabel
            let wasFocused = old.accessibilityElementIsFocused()
            old.removeFromSuperview()
            slider = replacement
            renderedDirection = direction
            install(replacement)
            if wasFocused { UIAccessibility.post(notification: .layoutChanged, argument: replacement) }
        }
        slider.frame = bounds
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        setNeedsLayout()
    }
    override var semanticContentAttribute: UISemanticContentAttribute {
        didSet { setNeedsLayout() }
    }
}
