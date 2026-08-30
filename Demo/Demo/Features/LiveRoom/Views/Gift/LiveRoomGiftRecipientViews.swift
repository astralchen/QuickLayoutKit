//
//  LiveRoomGiftRecipientViews.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomGiftRecipientButton: QuickLayoutButton {

    private let avatarView = UIView()
    private let symbolImageView = UIImageView()
    private let nameLabel = UILabel()
    private let selectionBadgeView = UIView()
    private let selectionBadgeImageView = UIImageView()
    private var usesCompactMetrics = false
    private var usesPhotoAvatar = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        return nil
    }

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

    func configure(
        recipient: LiveRoomSeat,
        isSelected: Bool,
        usesCompactMetrics: Bool
    ) {
        self.usesCompactMetrics = usesCompactMetrics
        usesPhotoAvatar = recipient.avatarImageID != nil
        let color = LiveRoomTheme.seatColor(at: recipient.themeIndex)
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
        nameLabel.text = DemoLocalization.text(recipient.nameKey)
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

    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        let scale: CGFloat = state.isPressed ? 0.94 : 1
        avatarView.transform = CGAffineTransform(scaleX: scale, y: scale)
        alpha = state.isPressed ? 0.82 : (state.isEnabled ? 1 : 0.56)
    }

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

final class LiveRoomGiftSelectAllButton: QuickLayoutButton {

    private let titleLabel = UILabel()
    var displayedTitle: String? { titleLabel.text }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.textAlignment = .center
        layer.shadowOffset = .zero
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var body: Layout {
        titleLabel.padding(.horizontal, 8).padding(.vertical, 6)
    }

    func configure(
        isSelected: Bool,
        usesCompactMetrics: Bool
    ) {
        titleLabel.text = DemoLocalization.text("liveRoom.gift.selectAll")
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

final class LiveRoomGiftRecipientFogView: QuickLayoutLinearGradientView {

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

    required init?(coder: NSCoder) {
        return nil
    }

}

#if DEBUG
@MainActor
private func makeLiveRoomGiftRecipientPreview(
    selected: Bool
) -> UIViewController {
    let view = LiveRoomGiftRecipientButton(frame: .zero)
    view.configure(
        recipient: LiveRoomPreviewData.seats[1],
        isSelected: selected,
        usesCompactMetrics: false
    )
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
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

@MainActor
private func makeLiveRoomGiftSelectAllPreview(
    selected: Bool
) -> UIViewController {
    let view = LiveRoomGiftSelectAllButton(frame: .zero)
    view.configure(
        isSelected: selected,
        usesCompactMetrics: false
    )
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
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

#Preview("收礼人 · 未选择") {
    makeLiveRoomGiftRecipientPreview(selected: false)
}

#Preview("收礼人 · 已选择") {
    makeLiveRoomGiftRecipientPreview(selected: true)
}

#Preview("全选 · 未选择") {
    makeLiveRoomGiftSelectAllPreview(selected: false)
}

#Preview("全选 · 已选择") {
    makeLiveRoomGiftSelectAllPreview(selected: true)
}

#Preview("收礼人雾化") {
    QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            LiveRoomGiftRecipientFogView()
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
