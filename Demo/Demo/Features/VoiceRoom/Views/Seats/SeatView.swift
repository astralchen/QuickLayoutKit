//
//  SeatView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class SeatView: QuickLayoutView {
    private let haloView = UIView()
    private let avatarBackgroundView = UIView()
    private let avatarImageView = UIImageView()
    private let microphoneBackgroundView = UIView()
    private let microphoneImageView = UIImageView()
    private let speakingIndicatorView = SpeakingIndicatorView()
    private let scoreLabel = UILabel()
    private let scoreBackgroundView = UIView()
    private let nameLabel = UILabel()
    private let interactionButton = QuickLayoutButton(frame: .zero)
    private var assignment: SeatAssignment?
    private var slotPresentation: SeatSlotPresentation?
    private var sizeClass = SeatSizeClass.regular

    /// 自定义 Collection Layout 使用的确定性麦位尺寸。
    ///
    /// 尺寸与 `body` 使用同一组头像、字体和内边距规则，避免 CollectionView
    /// self-sizing 反向改变网格列宽并触发布局失效循环。
    static func fittingSize(
        styleID: SeatVisualStyleID,
        sizeClass: SeatSizeClass,
        width: CGFloat
    ) -> CGSize {
        let usesLargePresentation = styleID == .emphasizedHost
        let avatarDiameter: CGFloat
        switch (usesLargePresentation, sizeClass) {
        case (true, .compact): avatarDiameter = 74
        case (true, .regular): avatarDiameter = 94
        case (true, .expanded): avatarDiameter = 128
        case (false, .compact): avatarDiameter = 46
        case (false, .regular): avatarDiameter = 58
        case (false, .expanded): avatarDiameter = 84
        }
        let spacing: CGFloat = sizeClass == .compact
            ? 2
            : (usesLargePresentation || sizeClass == .expanded ? 5 : 3)
        let scoreFontSize: CGFloat
        let nameFontSize: CGFloat
        switch (usesLargePresentation, sizeClass) {
        case (true, .expanded):
            scoreFontSize = 16
            nameFontSize = 20
        case (true, _):
            scoreFontSize = 13
            nameFontSize = 16
        case (false, .expanded):
            scoreFontSize = 12
            nameFontSize = 15
        case (false, _):
            scoreFontSize = 10
            nameFontSize = 12
        }
        let scoreHeight = ceil(
            UIFont.monospacedDigitSystemFont(
                ofSize: scoreFontSize,
                weight: .semibold
            ).lineHeight
        ) + (sizeClass == .expanded ? 8 : 6)
        let nameHeight = ceil(
            UIFont.systemFont(
                ofSize: nameFontSize,
                weight: usesLargePresentation ? .semibold : .medium
            ).lineHeight
        )
        return CGSize(
            width: width,
            height: ceil(avatarDiameter + 10 + scoreHeight + nameHeight + spacing * 2)
        )
    }

    var seatDidSelect: ((SeatAssignment) -> Void)?

    private var usesLargeSeatPresentation: Bool {
        slotPresentation?.styleID == .emphasizedHost
    }

    private var avatarDiameter: CGFloat {
        switch (usesLargeSeatPresentation, sizeClass) {
        case (true, .compact):
            return 74
        case (true, .regular):
            return 94
        case (true, .expanded):
            return 128
        case (false, .compact):
            return 46
        case (false, .regular):
            return 58
        case (false, .expanded):
            return 84
        }
    }

    private var microphoneDiameter: CGFloat {
        sizeClass == .expanded ? 28 : 22
    }

    private var microphoneIconDiameter: CGFloat {
        sizeClass == .expanded ? 14 : 11
    }

    private var avatarContentScale: CGFloat {
        assignment?.avatarImageID == nil ? 0.54 : 1
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        VStack(
            spacing: sizeClass == .compact
                ? 2
                : (usesLargeSeatPresentation || sizeClass == .expanded ? 5 : 3)
        ) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    haloView
                        .resizable()
                        .frame(
                            width: avatarDiameter + 10,
                            height: avatarDiameter + 10
                        )
                    avatarBackgroundView
                        .resizable()
                        .frame(
                            width: avatarDiameter,
                            height: avatarDiameter
                        )
                    avatarImageView
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: avatarDiameter * avatarContentScale,
                            height: avatarDiameter * avatarContentScale
                        )
                }

                ZStack {
                    microphoneBackgroundView
                        .resizable()
                        .frame(
                            width: microphoneDiameter,
                            height: microphoneDiameter
                        )
                    microphoneImageView
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: microphoneIconDiameter,
                            height: microphoneIconDiameter
                        )
                    speakingIndicatorView
                        .resizable()
                        .frame(
                            width: microphoneIconDiameter,
                            height: microphoneIconDiameter
                        )
                }
            }

            scoreLabel
                .padding(.horizontal, sizeClass == .expanded ? 9 : 7)
                .padding(.vertical, sizeClass == .expanded ? 4 : 3)
                .background { scoreBackgroundView }
            nameLabel
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        interactionButton.frame = bounds
        bringSubviewToFront(interactionButton)
    }

    /// 使用后台 assignment 和布局语义共同配置麦位。
    ///
    /// 用户头像、昵称和音频状态只读取 assignment；尺寸、空麦样式和交互由客户端
    /// Slot Presentation 决定。
    func configure(
        assignment: SeatAssignment?,
        presentation slotPresentation: SeatSlotPresentation
    ) {
        self.assignment = assignment
        self.slotPresentation = slotPresentation
        let themeIndex = assignment?.themeIndex
            ?? slotPresentation.position.rawValue
        let color = VoiceRoomTheme.seatColor(at: themeIndex)
        haloView.layer.borderColor = color.withAlphaComponent(0.85).cgColor
        haloView.layer.shadowColor = color.cgColor
        avatarBackgroundView.backgroundColor = color.withAlphaComponent(0.22)
        avatarImageView.image = assignment?.avatarImage
        avatarImageView.tintColor = color
        let usesPhotoAvatar = assignment?.avatarImageID != nil
        avatarImageView.contentMode = usesPhotoAvatar
            ? .scaleAspectFill
            : .scaleAspectFit
        avatarImageView.layer.cornerRadius = usesPhotoAvatar
            ? avatarDiameter / 2
            : 0
        avatarImageView.clipsToBounds = usesPhotoAvatar
        let isMuted = assignment?.isMuted ?? true
        microphoneBackgroundView.backgroundColor = isMuted
            ? UIColor.systemRed.withAlphaComponent(0.92)
            : UIColor.systemGreen.withAlphaComponent(0.92)
        microphoneImageView.image = UIImage(
            systemName: isMuted ? "mic.slash.fill" : "waveform"
        )
        let showsSpeakingIndicator = assignment?.isOccupied == true && !isMuted
        microphoneImageView.isHidden = showsSpeakingIndicator
        speakingIndicatorView.isHidden = !showsSpeakingIndicator
        speakingIndicatorView.setAnimating(showsSpeakingIndicator)
        speakingIndicatorView.accessibilityIdentifier =
            "liveRoom.seat.waveform.\(slotPresentation.position.rawValue)"
        let score = assignment?.score ?? 0
        scoreLabel.text = score > 0
            ? Localization.text("liveRoom.seat.score", score)
            : Localization.text("liveRoom.seat.available")
        if let occupantNameKey = assignment?.occupantNameKey {
            nameLabel.text = Localization.text(occupantNameKey)
        } else {
            nameLabel.text = emptySeatName(
                for: slotPresentation.position.rawValue
            )
        }
        accessibilityLabel = nameLabel.text
        accessibilityValue = Localization.text(
            isMuted ? "liveRoom.seat.muted" : "liveRoom.seat.speaking"
        )
        let position = slotPresentation.position.rawValue
        accessibilityIdentifier = "liveRoom.seat.\(position)"
        scoreLabel.accessibilityIdentifier = "liveRoom.seat.score.\(position)"
        nameLabel.accessibilityIdentifier = "liveRoom.seat.name.\(position)"
        interactionButton.isEnabled = slotPresentation.interaction
            == .showUserCard
        interactionButton.accessibilityIdentifier =
            "liveRoom.seat.button.\(position)"
        interactionButton.accessibilityLabel = nameLabel.text
        interactionButton.accessibilityValue = accessibilityValue
        applyVisualStyle()
        setNeedsQuickLayout()
    }

    func giftTargetPoint(in view: UIView) -> CGPoint? {
        guard window != nil, avatarBackgroundView.window != nil else {
            return nil
        }
        return avatarBackgroundView.convert(
            CGPoint(
                x: avatarBackgroundView.bounds.midX,
                y: avatarBackgroundView.bounds.midY
            ),
            to: view
        )
    }

    /// 返回头像中心在麦位自身坐标中的位置，供移动中的 Cell 使用
    /// presentation layer 计算实时送礼锚点。
    func giftTargetPointInBounds() -> CGPoint? {
        guard avatarBackgroundView.superview != nil else { return nil }
        return avatarBackgroundView.convert(
            CGPoint(
                x: avatarBackgroundView.bounds.midX,
                y: avatarBackgroundView.bounds.midY
            ),
            to: self
        )
    }

    /// 使用当前原生配置的样式展示到达反馈；省略时采用礼物默认样式。
    func playGiftArrival(gift: Gift, color: UIColor, style: GiftEffectStyle? = nil) {
        let style = style ?? gift.effectStyle
        let avatarFrame = avatarBackgroundView.convert(
            avatarBackgroundView.bounds,
            to: self
        )
        let ringView = QuickLayoutShapeView(
            fillColor: .clear,
            strokeColor: color,
            strokeStyle: QuickLayoutStrokeStyle(
                lineWidth: style == .celebration ? 4 : 3
            ),
            path: { rect in UIBezierPath(ovalIn: rect).cgPath }
        )
        ringView.frame = avatarFrame.insetBy(dx: -8, dy: -8)
        ringView.isUserInteractionEnabled = false
        ringView.layer.shadowColor = color.cgColor
        ringView.layer.shadowOpacity = 0.9
        ringView.layer.shadowRadius = 8
        insertSubview(ringView, belowSubview: interactionButton)

        let ringScale = CAKeyframeAnimation(keyPath: "transform.scale")
        ringScale.values = style == .celebration
            ? [0.62, 1.08, 1.62]
            : [0.72, 1.0, 1.34]
        ringScale.keyTimes = [0, 0.28, 1]
        let ringOpacity = CAKeyframeAnimation(keyPath: "opacity")
        ringOpacity.values = [0, 1, 0]
        ringOpacity.keyTimes = [0, 0.24, 1]
        let ringGroup = CAAnimationGroup()
        ringGroup.animations = [ringScale, ringOpacity]
        ringGroup.duration = UIAccessibility.isReduceMotionEnabled
            ? 0.28
            : (style == .celebration ? 1.0 : 0.72)
        ringGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ringView.layer.add(ringGroup, forKey: "liveRoom.gift.arrival.ring")

        let badgeDiameter: CGFloat = style == .celebration ? 42 : 34
        let badgeView = UIView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: badgeDiameter,
                height: badgeDiameter
            )
        )
        badgeView.center = CGPoint(x: avatarFrame.midX, y: avatarFrame.midY)
        badgeView.backgroundColor = color
        badgeView.layer.cornerRadius = badgeDiameter / 2
        badgeView.layer.shadowColor = color.cgColor
        badgeView.layer.shadowOpacity = 0.75
        badgeView.layer.shadowRadius = 8
        badgeView.isUserInteractionEnabled = false

        let imageInset: CGFloat = style == .celebration ? 9 : 8
        let badgeImageView = UIImageView(
            frame: badgeView.bounds.insetBy(dx: imageInset, dy: imageInset)
        )
        badgeImageView.image = UIImage(systemName: gift.symbolName)
        badgeImageView.tintColor = .white
        badgeImageView.contentMode = .scaleAspectFit
        badgeView.addSubview(badgeImageView)
        addSubview(badgeView)

        badgeView.alpha = 0
        badgeView.transform = CGAffineTransform(scaleX: 0.45, y: 0.45)
        UIView.animateKeyframes(
            withDuration: UIAccessibility.isReduceMotionEnabled ? 0.30 : 0.76,
            delay: 0,
            options: [.calculationModeCubic, .beginFromCurrentState]
        ) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.28) {
                badgeView.alpha = 1
                badgeView.transform = CGAffineTransform(scaleX: 1.16, y: 1.16)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.28, relativeDuration: 0.28) {
                badgeView.transform = .identity
            }
            UIView.addKeyframe(withRelativeStartTime: 0.58, relativeDuration: 0.42) {
                badgeView.alpha = 0
                badgeView.transform = CGAffineTransform(
                    translationX: 0,
                    y: -avatarFrame.height * 0.34
                ).scaledBy(x: 0.82, y: 0.82)
            }
        } completion: { _ in
            Task { @MainActor in
                badgeView.removeFromSuperview()
                ringView.removeFromSuperview()
            }
        }
    }

    func setSizeClass(_ sizeClass: SeatSizeClass) {
        guard self.sizeClass != sizeClass else { return }
        self.sizeClass = sizeClass
        haloView.layer.cornerRadius = (avatarDiameter + 10) / 2
        avatarBackgroundView.layer.cornerRadius = avatarDiameter / 2
        avatarImageView.layer.cornerRadius = avatarImageIDCornerRadius
        microphoneBackgroundView.layer.cornerRadius = microphoneDiameter / 2
        configureTypography()
        setNeedsQuickLayout()
    }

    private func applyVisualStyle() {
        haloView.layer.cornerRadius = (avatarDiameter + 10) / 2
        avatarBackgroundView.layer.cornerRadius = avatarDiameter / 2
        avatarImageView.layer.cornerRadius = avatarImageIDCornerRadius
        haloView.layer.borderWidth = slotPresentation?.role == .host ? 3 : 2
        configureTypography()
        setNeedsQuickLayout()
    }

    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer

        haloView.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        haloView.layer.cornerRadius = (avatarDiameter + 10) / 2
        haloView.layer.borderWidth = 2
        haloView.layer.shadowOpacity = 0.45
        haloView.layer.shadowRadius = 8

        avatarBackgroundView.layer.cornerRadius = avatarDiameter / 2
        avatarBackgroundView.layer.masksToBounds = true
        avatarImageView.contentMode = .scaleAspectFit

        interactionButton.backgroundColor = .clear
        addSubview(interactionButton)
        interactionButton.action = { [weak self] in self?.didTapSeat() }

        microphoneBackgroundView.layer.cornerRadius = microphoneDiameter / 2
        microphoneImageView.tintColor = .white
        microphoneImageView.contentMode = .scaleAspectFit
        speakingIndicatorView.isHidden = true

        scoreLabel.textColor = .white
        scoreLabel.textAlignment = .center
        scoreBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.72
        configureTypography()
    }

    private func didTapSeat() {
        guard let assignment, assignment.isOccupied else { return }
        seatDidSelect?(assignment)
    }

    private var avatarImageIDCornerRadius: CGFloat {
        assignment?.avatarImageID == nil ? 0 : avatarDiameter / 2
    }

    /// 空麦文案只描述 Slot，不复用任何用户昵称 key。
    private func emptySeatName(for position: Int) -> String {
        switch position {
        case 0:
            return Localization.text("liveRoom.userCard.hostSeat")
        case 8:
            return Localization.text("liveRoom.seat.eight")
        case 1...7:
            return Localization.text(
                "liveRoom.userCard.guestSeat",
                position
            )
        default:
            return Localization.text("liveRoom.seat.available")
        }
    }

    private func configureTypography() {
        let scoreFontSize: CGFloat
        let nameFontSize: CGFloat
        switch (usesLargeSeatPresentation, sizeClass) {
        case (true, .expanded):
            scoreFontSize = 16
            nameFontSize = 20
        case (true, _):
            scoreFontSize = 13
            nameFontSize = 16
        case (false, .expanded):
            scoreFontSize = 12
            nameFontSize = 15
        case (false, _):
            scoreFontSize = 10
            nameFontSize = 12
        }
        scoreLabel.font = .monospacedDigitSystemFont(
            ofSize: scoreFontSize,
            weight: .semibold
        )
        scoreBackgroundView.layer.cornerRadius = usesLargeSeatPresentation
            ? 10
            : 8
        nameLabel.font = .systemFont(
            ofSize: nameFontSize,
            weight: usesLargeSeatPresentation ? .semibold : .medium
        )
    }
}

#if DEBUG
@MainActor
private func makeSeatViewPreview(
    seat: SeatAssignment,
    styleID: SeatVisualStyleID,
    size: CGSize
) -> UIViewController {
    let view = SeatView(frame: .zero)
    view.configure(
        assignment: seat,
        presentation: SeatSlotPresentation(
            slotID: seat.slotID,
            position: seat.position,
            assignment: seat,
            role: seat.position.rawValue == 0 ? .host : .guest(
                index: seat.position.rawValue
            ),
            styleID: styleID,
            isVisible: true,
            interaction: seat.isOccupied ? .showUserCard : .none
        )
    )
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view.resizable().padding(16)
        }
        .frame(width: size.width, height: size.height)
    }
}

@available(iOS 17.0, *)
#Preview("主持麦位") {
    makeSeatViewPreview(
        seat: VoiceRoomPreviewData.seats[0],
        styleID: .emphasizedHost,
        size: CGSize(width: 180, height: 190)
    )
}

@available(iOS 17.0, *)
#Preview("普通麦位 · 未上麦") {
    makeSeatViewPreview(
        seat: VoiceRoomPreviewData.seats[5],
        styleID: .standardGuest,
        size: CGSize(width: 120, height: 150)
    )
}
#endif
