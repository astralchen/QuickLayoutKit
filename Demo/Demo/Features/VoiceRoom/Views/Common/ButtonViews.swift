//
//  ButtonViews.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 直播间按钮共享的最小事件命中区域。
///
/// 仅重写 UIKit 命中测试，不参与 QuickLayout 测量，避免为了可点击性修改视觉尺寸。
class MinimumHitTargetButton: QuickLayoutButton {

    /// 按钮响应点击的最小尺寸；默认值为 44 × 44 点。
    var minimumHitTargetSize = CGSize(width: 44, height: 44)

    /// 返回指定点是否位于扩展后的可点击区域内。
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let horizontalExpansion = max(
            0,
            (minimumHitTargetSize.width - bounds.width) / 2
        )
        let verticalExpansion = max(
            0,
            (minimumHitTargetSize.height - bounds.height) / 2
        )
        return bounds.insetBy(
            dx: -horizontalExpansion,
            dy: -verticalExpansion
        ).contains(point)
    }
}

/// 直播间通用的纯文字胶囊按钮。
///
/// 视觉层级由 QuickLayout 构建，交互状态由 `QuickLayoutButton` 统一发布，避免不同页面
/// 分别依赖 `UIButton.Configuration` 产生不一致的测量和禁用态效果。
final class CapsuleTextButton: MinimumHitTargetButton {

    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()
    /// 按钮可用时的前景颜色。
    private var enabledForegroundColor: UIColor = .white
    /// 按钮不可用时的前景颜色。
    private var disabledForegroundColor = UIColor.white.withAlphaComponent(0.62)
    /// 按钮可用时的背景颜色。
    private var enabledBackgroundColor: UIColor = .clear
    /// 按钮不可用时的背景颜色。
    private var disabledBackgroundColor = UIColor.white.withAlphaComponent(0.08)
    /// 按钮可用时的边框颜色。
    private var enabledBorderColor: UIColor = .clear
    /// 按钮不可用时的边框颜色。
    private var disabledBorderColor = UIColor.white.withAlphaComponent(0.16)
    /// 按钮文字与边界之间的内容内边距，单位为点。
    private var contentInsets = EdgeInsets(
        top: 6,
        leading: 10,
        bottom: 6,
        trailing: 10
    )

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
        titleLabel
            .fixedSize(axis: .horizontal)
            .padding(contentInsets)
    }

    /// 按布局后的最短边更新胶囊圆角半径。
    override func layoutSubviews() {
        super.layoutSubviews()
        // 胶囊半径依赖最终高度，不能由调用方根据字体和 contentInsets 手工同步。
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    /// 设置按钮标题、字体、内边距及可用和不可用状态的颜色。
    func configure(
        title: String,
        font: UIFont,
        foregroundColor: UIColor,
        backgroundColor: UIColor,
        borderColor: UIColor = .clear,
        borderWidth: CGFloat = 0,
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
        layer.borderWidth = borderWidth
        setNeedsQuickLayout()
        apply(state: buttonState)
    }

    /// 在按钮状态变化时刷新对应的文字、颜色和交互外观。
    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        apply(state: state)
    }

    /// 配置组件的基础样式和交互行为。
    private func configureView() {
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        titleLabel.isUserInteractionEnabled = false
        layer.cornerCurve = .circular
    }

    /// 按按钮可用及高亮状态刷新文字、背景和边框颜色。
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
final class SymbolButton: MinimumHitTargetButton {

    /// 显示组件符号图像的视图。
    private let imageView = UIImageView()
    /// 符号图像的目标尺寸，单位为点。
    private var symbolSize: CGFloat = 18
    /// 按钮可用时的图标颜色。
    private var enabledTintColor: UIColor = .white
    /// 按钮不可用时的图标颜色。
    private var disabledTintColor = UIColor.white.withAlphaComponent(0.58)
    /// 按钮可用时的背景颜色。
    private var enabledBackgroundColor = UIColor.white.withAlphaComponent(0.14)
    /// 按钮不可用时的背景颜色。
    private var disabledBackgroundColor = UIColor.white.withAlphaComponent(0.08)

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
        imageView
            .resizable()
            .scaledToFit()
            .frame(width: symbolSize, height: symbolSize)
            .padding(8)
    }

    /// 根据实际高度更新圆形按钮背景。
    override func layoutSubviews() {
        super.layoutSubviews()
        // 圆形是该组件的结构约束，半径必须以最终布局结果为准，不能由调用方根据
        // symbolSize 或 padding 猜测，否则外部尺寸变化后会退化成圆角矩形。
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    /// 设置符号名称、尺寸、字重及前景和背景颜色。
    func configure(
        symbolName: String,
        symbolSize: CGFloat = 18,
        weight: UIImage.SymbolWeight = .medium,
        tintColor: UIColor = .white,
        backgroundColor: UIColor = UIColor.white.withAlphaComponent(0.14)
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
        setNeedsQuickLayout()
        apply(state: buttonState)
    }

    /// 在按钮状态变化时刷新对应的文字、颜色和交互外观。
    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        apply(state: state)
    }

    /// 配置组件的基础样式和交互行为。
    private func configureView() {
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        layer.cornerCurve = .circular
    }

    /// 根据按钮可用及高亮状态更新图标透明度和颜色。
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
final class IconTitleButton: QuickLayoutButton {

    /// 显示组件符号图像的视图。
    private let imageView = UIImageView()
    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()

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

    /// 设置图标文字按钮的标题与 SF Symbols 图像。
    func configure(title: String, symbolName: String) {
        titleLabel.text = title
        imageView.image = UIImage(systemName: symbolName)
        accessibilityLabel = title
        setNeedsQuickLayout()
    }

    /// 在按钮状态变化时刷新对应的文字、颜色和交互外观。
    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        transform = state.isPressed
            ? CGAffineTransform(scaleX: 0.98, y: 0.98)
            : .identity
        alpha = state.isPressed ? 0.84 : (state.isEnabled ? 1 : 0.58)
    }

    /// 配置组件的基础样式和交互行为。
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
/// 创建展示房间通用按钮组的预览控制器。
@MainActor
private func makeButtonViewsPreview() -> UIViewController {
    let messageButton = IconTitleButton(frame: .zero)
    messageButton.configure(title: "说点好听的…", symbolName: "message.fill")
    let symbolButton = SymbolButton(frame: .zero)
    symbolButton.configure(symbolName: "gift.fill")
    let textButton = CapsuleTextButton(frame: .zero)
    textButton.configure(
        title: "赠送",
        font: .systemFont(ofSize: 16, weight: .semibold),
        foregroundColor: UIColor(red: 0.12, green: 0.10, blue: 0.04, alpha: 1),
        backgroundColor: .systemYellow
    )
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
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

@available(iOS 17.0, *)
#Preview("QuickLayoutButton 样式") {
    makeButtonViewsPreview()
}
#endif
