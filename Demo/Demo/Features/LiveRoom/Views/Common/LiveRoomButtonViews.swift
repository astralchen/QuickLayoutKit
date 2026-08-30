//
//  LiveRoomButtonViews.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 直播间通用的纯文字按钮。
///
/// 视觉层级由 QuickLayout 构建，交互状态由 `QuickLayoutButton` 统一发布，避免不同页面
/// 分别依赖 `UIButton.Configuration` 产生不一致的测量和禁用态效果。
final class LiveRoomTextButton: QuickLayoutButton {

    private let titleLabel = UILabel()
    private var enabledForegroundColor: UIColor = .white
    private var disabledForegroundColor = UIColor.white.withAlphaComponent(0.62)
    private var enabledBackgroundColor: UIColor = .clear
    private var disabledBackgroundColor = UIColor.white.withAlphaComponent(0.08)
    private var enabledBorderColor: UIColor = .clear
    private var disabledBorderColor = UIColor.white.withAlphaComponent(0.16)
    private var contentInsets = EdgeInsets(
        top: 6,
        leading: 10,
        bottom: 6,
        trailing: 10
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override var body: Layout {
        titleLabel
            .fixedSize(axis: .horizontal)
            .padding(contentInsets)
    }

    func configure(
        title: String,
        font: UIFont,
        foregroundColor: UIColor,
        backgroundColor: UIColor,
        borderColor: UIColor = .clear,
        borderWidth: CGFloat = 0,
        cornerRadius: CGFloat,
        contentInsets: EdgeInsets = EdgeInsets(
            top: 6,
            leading: 10,
            bottom: 6,
            trailing: 10
        ),
        disabledForegroundColor: UIColor? = nil,
        disabledBackgroundColor: UIColor? = nil,
        disabledBorderColor: UIColor? = nil
    ) {
        titleLabel.text = title
        accessibilityLabel = title
        titleLabel.font = font
        enabledForegroundColor = foregroundColor
        enabledBackgroundColor = backgroundColor
        enabledBorderColor = borderColor
        self.disabledForegroundColor = disabledForegroundColor
            ?? foregroundColor.withAlphaComponent(0.62)
        self.disabledBackgroundColor = disabledBackgroundColor
            ?? backgroundColor.withAlphaComponent(0.34)
        self.disabledBorderColor = disabledBorderColor
            ?? borderColor.withAlphaComponent(0.62)
        self.contentInsets = contentInsets
        layer.cornerRadius = cornerRadius
        layer.borderWidth = borderWidth
        setNeedsQuickLayout()
        apply(state: buttonState)
    }

    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        apply(state: state)
    }

    private func configureView() {
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        titleLabel.isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
    }

    private func apply(state: QuickLayoutButtonState) {
        titleLabel.textColor = state.isEnabled
            ? enabledForegroundColor
            : disabledForegroundColor
        backgroundColor = state.isEnabled
            ? enabledBackgroundColor
            : disabledBackgroundColor
        layer.borderColor = (
            state.isEnabled ? enabledBorderColor : disabledBorderColor
        ).cgColor
        transform = state.isPressed
            ? CGAffineTransform(scaleX: 0.96, y: 0.96)
            : .identity
        alpha = state.isPressed ? 0.84 : 1
    }
}

/// 直播间通用的 SF Symbol 圆形按钮。
final class LiveRoomSymbolButton: QuickLayoutButton {

    private let imageView = UIImageView()
    private var symbolSize: CGFloat = 18
    private var enabledTintColor: UIColor = .white
    private var disabledTintColor = UIColor.white.withAlphaComponent(0.58)
    private var enabledBackgroundColor = UIColor.white.withAlphaComponent(0.14)
    private var disabledBackgroundColor = UIColor.white.withAlphaComponent(0.08)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override var body: Layout {
        imageView
            .resizable()
            .scaledToFit()
            .frame(width: symbolSize, height: symbolSize)
            .padding(8)
    }

    func configure(
        symbolName: String,
        symbolSize: CGFloat = 18,
        weight: UIImage.SymbolWeight = .medium,
        tintColor: UIColor = .white,
        backgroundColor: UIColor = UIColor.white.withAlphaComponent(0.14),
        cornerRadius: CGFloat = 17.5
    ) {
        self.symbolSize = symbolSize
        enabledTintColor = tintColor
        enabledBackgroundColor = backgroundColor
        disabledTintColor = tintColor.withAlphaComponent(0.58)
        disabledBackgroundColor = backgroundColor.withAlphaComponent(0.58)
        imageView.image = UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: symbolSize,
                weight: weight
            )
        )
        layer.cornerRadius = cornerRadius
        setNeedsQuickLayout()
        apply(state: buttonState)
    }

    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        apply(state: state)
    }

    private func configureView() {
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
    }

    private func apply(state: QuickLayoutButtonState) {
        imageView.tintColor = state.isEnabled
            ? enabledTintColor
            : disabledTintColor
        backgroundColor = state.isEnabled
            ? enabledBackgroundColor
            : disabledBackgroundColor
        transform = state.isPressed
            ? CGAffineTransform(scaleX: 0.92, y: 0.92)
            : .identity
        alpha = state.isPressed ? 0.82 : 1
    }
}

/// 直播间操作栏的“图标 + 文案”按钮。
final class LiveRoomIconTitleButton: QuickLayoutButton {

    private let imageView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override var body: Layout {
        HStack(spacing: 7) {
            imageView
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            titleLabel
                .resizable(axis: .horizontal)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    func configure(title: String, symbolName: String) {
        titleLabel.text = title
        imageView.image = UIImage(systemName: symbolName)
        accessibilityLabel = title
        setNeedsQuickLayout()
    }

    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        transform = state.isPressed
            ? CGAffineTransform(scaleX: 0.98, y: 0.98)
            : .identity
        alpha = state.isPressed ? 0.84 : (state.isEnabled ? 1 : 0.58)
    }

    private func configureView() {
        backgroundColor = UIColor.white.withAlphaComponent(0.14)
        layer.cornerRadius = 17.5
        layer.cornerCurve = .continuous
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = .white
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.isUserInteractionEnabled = false
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomButtonViewsPreview() -> UIViewController {
    let messageButton = LiveRoomIconTitleButton(frame: .zero)
    messageButton.configure(title: "说点好听的…", symbolName: "message.fill")
    let symbolButton = LiveRoomSymbolButton(frame: .zero)
    symbolButton.configure(symbolName: "gift.fill")
    let textButton = LiveRoomTextButton(frame: .zero)
    textButton.configure(
        title: "赠送",
        font: .systemFont(ofSize: 16, weight: .semibold),
        foregroundColor: UIColor(red: 0.12, green: 0.10, blue: 0.04, alpha: 1),
        backgroundColor: .systemYellow,
        cornerRadius: 18
    )
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            HStack(spacing: 10) {
                messageButton.resizable(axis: .horizontal)
                symbolButton.resizable().frame(width: 35, height: 35)
                textButton
                    .resizable(axis: .vertical)
                    .fixedSize(axis: .horizontal)
                    .frame(height: 35)
            }
            .padding(16)
        }
        .frame(width: 390, height: 82)
    }
}

#Preview("QuickLayoutButton 样式") {
    makeLiveRoomButtonViewsPreview()
}
#endif
