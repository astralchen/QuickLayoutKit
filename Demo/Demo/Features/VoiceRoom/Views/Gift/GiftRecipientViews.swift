//
//  GiftRecipientViews.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 显示收礼人头像、名称和选择标记的按钮。
final class GiftRecipientButton: QuickLayoutButton {

    /// 承载收礼人头像和主题背景的容器。
    private let avatarView = UIView()
    /// 显示用户头像或备用人物符号的图像视图。
    private let symbolImageView = UIImageView()
    /// 显示用户昵称或空麦名称的标签。
    private let nameLabel = UILabel()
    /// 收礼人选中标记的圆形背景。
    private let selectionBadgeView = UIView()
    /// 收礼人选中标记中的勾选图像。
    private let selectionBadgeImageView = UIImageView()
    /// 一个布尔值，指示组件是否使用紧凑尺寸参数。
    private var usesCompactMetrics = false
    /// 一个布尔值，指示头像是否来自图片资源而非备用符号。
    private var usesPhotoAvatar = false

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        let avatarDiameter: CGFloat = usesCompactMetrics ? 34 : 40
        avatarView.layer.shadowPath = UIBezierPath(
            ovalIn: CGRect(
                x: 0,
                y: 0,
                width: avatarDiameter,
                height: avatarDiameter
            )
        ).cgPath
        let symbolInset: CGFloat
        if usesPhotoAvatar {
            symbolInset = 0
        } else {
            symbolInset = usesCompactMetrics ? 8 : 9
        }
        let badgeDiameter: CGFloat = usesCompactMetrics ? 14 : 16
        return VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    avatarView
                        .resizable()
                        .frame(
                            width: avatarDiameter,
                            height: avatarDiameter
                        )
                    symbolImageView
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: avatarDiameter - symbolInset * 2,
                            height: avatarDiameter - symbolInset * 2
                        )
                }
                selectionBadgeView
                    .resizable()
                    .frame(width: badgeDiameter, height: badgeDiameter)
                    .overlay {
                        selectionBadgeImageView
                            .resizable()
                            .scaledToFit()
                            .padding(usesCompactMetrics ? 3.5 : 4)
                    }
            }
            nameLabel
                .resizable(axis: .horizontal)
                .frame(maxWidth: .infinity)
        }
    }

    /// 根据当前收礼人更新头像、名称、选择状态和紧凑尺寸。
    func configure(
        recipient: SeatAssignment,
        isSelected: Bool,
        usesCompactMetrics: Bool
    ) {
        self.usesCompactMetrics = usesCompactMetrics
        usesPhotoAvatar = recipient.avatarImageID != nil
        let color = VoiceRoomTheme.seatColor(at: recipient.themeIndex)
        symbolImageView.image = recipient.avatarImage
        symbolImageView.tintColor = isSelected ? .white : color
        symbolImageView.alpha = isSelected ? 1 : 0.76
        symbolImageView.contentMode = usesPhotoAvatar
            ? .scaleAspectFill
            : .scaleAspectFit
        symbolImageView.layer.cornerRadius = usesPhotoAvatar
            ? (usesCompactMetrics ? 17 : 20)
            : 0
        symbolImageView.clipsToBounds = usesPhotoAvatar
        nameLabel.text = Localization.text(recipient.nameKey)
        nameLabel.textColor = isSelected
            ? .white
            : UIColor.white.withAlphaComponent(0.70)
        nameLabel.font = .systemFont(
            ofSize: usesCompactMetrics ? 9 : 10,
            weight: isSelected ? .semibold : .medium
        )
        avatarView.backgroundColor = color.withAlphaComponent(
            isSelected ? 0.38 : 0.18
        )
        avatarView.layer.borderWidth = isSelected ? 3 : 1.5
        avatarView.layer.borderColor = (
            isSelected
                ? UIColor.systemYellow
                : UIColor.white.withAlphaComponent(0.46)
        ).cgColor
        avatarView.layer.shadowColor = UIColor.systemYellow.cgColor
        avatarView.layer.shadowOpacity = isSelected ? 0.44 : 0
        avatarView.layer.shadowRadius = 7
        avatarView.layer.shadowOffset = .zero
        avatarView.layer.cornerRadius = (usesCompactMetrics ? 34 : 40) / 2
        selectionBadgeView.layer.cornerRadius = (usesCompactMetrics ? 14 : 16) / 2
        selectionBadgeView.isHidden = !isSelected
        self.isSelected = isSelected
        setNeedsQuickLayout()
    }

    /// 在按钮状态变化时刷新对应的文字、颜色和交互外观。
    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        let scale: CGFloat = state.isPressed ? 0.94 : 1
        avatarView.transform = CGAffineTransform(scaleX: scale, y: scale)
        alpha = state.isPressed ? 0.82 : (state.isEnabled ? 1 : 0.56)
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        backgroundColor = .clear
        layer.borderWidth = 0
        clipsToBounds = false

        avatarView.isUserInteractionEnabled = false
        avatarView.accessibilityIdentifier = "liveRoom.gift.recipient.avatar"
        symbolImageView.isUserInteractionEnabled = false
        symbolImageView.contentMode = .scaleAspectFit
        selectionBadgeView.isUserInteractionEnabled = false
        selectionBadgeView.backgroundColor = .systemYellow
        selectionBadgeView.layer.borderWidth = 2
        selectionBadgeView.layer.borderColor = UIColor(
            red: 0.055,
            green: 0.055,
            blue: 0.10,
            alpha: 1
        ).cgColor
        selectionBadgeView.accessibilityIdentifier =
            "liveRoom.gift.recipient.selectionBadge"
        selectionBadgeImageView.isUserInteractionEnabled = false
        selectionBadgeImageView.image = UIImage(systemName: "checkmark")
        selectionBadgeImageView.tintColor = UIColor(
            red: 0.12,
            green: 0.10,
            blue: 0.04,
            alpha: 1
        )
        selectionBadgeImageView.contentMode = .scaleAspectFit
        nameLabel.isUserInteractionEnabled = false
        nameLabel.textAlignment = .center
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.72

    }
}

/// 切换全部收礼人选择状态的按钮。
final class GiftSelectAllButton: QuickLayoutButton {

    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()
    /// 按钮当前显示的标题文本。
    var displayedTitle: String? { titleLabel.text }

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.textAlignment = .center
        layer.shadowOffset = .zero
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        titleLabel.padding(.horizontal, 8).padding(.vertical, 6)
    }

    /// 更新全选按钮的文案、选择外观和紧凑尺寸。
    func configure(
        isSelected: Bool,
        usesCompactMetrics: Bool
    ) {
        titleLabel.text = Localization.text("liveRoom.gift.selectAll")
        titleLabel.font = .systemFont(
            ofSize: usesCompactMetrics ? 10 : 11,
            weight: .semibold
        )
        titleLabel.textColor = isSelected ? .systemYellow : .white
        backgroundColor = isSelected
            ? UIColor.systemYellow.withAlphaComponent(0.14)
            : UIColor.white.withAlphaComponent(0.09)
        layer.borderWidth = 1
        layer.borderColor = (
            isSelected
                ? UIColor.systemYellow.withAlphaComponent(0.88)
                : UIColor.white.withAlphaComponent(0.24)
        ).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.20
        layer.shadowRadius = 5
        layer.cornerRadius = usesCompactMetrics ? 15 : 17
        self.isSelected = isSelected
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        setNeedsQuickLayout()
    }

    /// 在按钮状态变化时刷新对应的文字、颜色和交互外观。
    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        transform = state.isPressed
            ? CGAffineTransform(scaleX: 0.94, y: 0.94)
            : .identity
        alpha = state.isPressed ? 0.82 : (state.isEnabled ? 1 : 0.56)
    }
}

/// 在收礼人滚动区域边缘提供渐隐效果的装饰视图。
final class GiftRecipientFadeView: QuickLayoutLinearGradientView {

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityIdentifier = "liveRoom.gift.recipientFog"
        // 使用连续透明渐变模拟雾化，避免窄区域内 UIVisualEffectView 的矩形合成边界。
        gradient = QuickLayoutGradient(stops: [
            QuickLayoutGradient.Stop(color: .clear, location: 0),
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.055, green: 0.055, blue: 0.10, alpha: 0.10),
                location: 0.30
            ),
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.055, green: 0.055, blue: 0.10, alpha: 0.38),
                location: 0.72
            ),
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.055, green: 0.055, blue: 0.10, alpha: 0.70),
                location: 1
            ),
        ])
        startPoint = .leading
        endPoint = .trailing
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

}

#if DEBUG
/// 创建展示指定选择状态的收礼人按钮的预览控制器。
@MainActor
private func makeGiftRecipientPreview(
    selected: Bool
) -> UIViewController {
    let view = GiftRecipientButton(frame: .zero)
    view.configure(
        recipient: VoiceRoomPreviewData.seats[1],
        isSelected: selected,
        usesCompactMetrics: false
    )
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view
                .resizable()
                .padding(
                    EdgeInsets(
                        top: 16,
                        leading: 24,
                        bottom: 16,
                        trailing: 24
                    )
                )
        }
        .frame(width: 100, height: 96)
    }
}

/// 创建展示指定选择状态的全选按钮的预览控制器。
@MainActor
private func makeGiftSelectAllPreview(
    selected: Bool
) -> UIViewController {
    let view = GiftSelectAllButton(frame: .zero)
    view.configure(
        isSelected: selected,
        usesCompactMetrics: false
    )
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view
                .resizable()
                .padding(
                    EdgeInsets(
                        top: 18,
                        leading: 32,
                        bottom: 18,
                        trailing: 32
                    )
                )
        }
        .frame(width: 130, height: 72)
    }
}

@available(iOS 17.0, *)
#Preview("收礼人 · 未选择") {
    makeGiftRecipientPreview(selected: false)
}

@available(iOS 17.0, *)
#Preview("收礼人 · 已选择") {
    makeGiftRecipientPreview(selected: true)
}

@available(iOS 17.0, *)
#Preview("全选 · 未选择") {
    makeGiftSelectAllPreview(selected: false)
}

@available(iOS 17.0, *)
#Preview("全选 · 已选择") {
    makeGiftSelectAllPreview(selected: true)
}

@available(iOS 17.0, *)
#Preview("收礼人雾化") {
    QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            GiftRecipientFadeView()
                .resizable()
                .padding(
                    EdgeInsets(
                        top: 16,
                        leading: 30,
                        bottom: 16,
                        trailing: 30
                    )
                )
        }
        .frame(width: 140, height: 80)
    }
}
#endif
