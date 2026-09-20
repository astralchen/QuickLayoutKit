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

/// 根据单个麦位展示状态呈现头像、音频状态、积分和名称的视图。
final class SeatView: QuickLayoutView {
    /// 当前主体周围的光晕装饰视图。
    private let haloView = UIView()
    /// 提供头像底色和圆角的背景视图。
    private let avatarBackgroundView = UIView()
    /// 显示用户头像或备用图标的图像视图。
    private let avatarImageView = UIImageView()
    /// 麦克风状态图标后方的圆形背景。
    private let microphoneBackgroundView = UIView()
    /// 显示麦克风可用或静音状态的图像视图。
    private let microphoneImageView = UIImageView()
    /// 以波形条显示当前音频活动状态的视图。
    private let speakingIndicatorView = SpeakingIndicatorView()
    /// 显示用户积分或空麦状态的标签。
    private let scoreLabel = UILabel()
    /// 积分或空麦状态文字后方的背景。
    private let scoreBackgroundView = UIView()
    /// 显示用户昵称或空麦名称的标签。
    private let nameLabel = UILabel()
    /// 覆盖麦位并转发用户选择的透明按钮。
    private let interactionButton = QuickLayoutButton(frame: .zero)
    /// 此位置绑定的麦位数据；缺失记录时为 `nil`。
    private var assignment: SeatAssignment?
    /// 当前视图正在显示的完整麦位展示状态。
    private var slotPresentation: SeatSlotPresentation?
    /// 当前环境采用的麦位尺寸等级。
    private var sizeClass = SeatSizeClass.regular
    /// 上次用于 PK 尺寸解析的视图宽度。
    private var lastPKWidth: CGFloat?

    /// 返回与实际麦位布局规则一致的确定性尺寸。
    ///
    /// 此测量与视图使用相同的头像、字体和内边距规则，防止集合视图自动尺寸计算反向改变网格列宽。
    ///
    /// - Parameters:
    ///   - styleID: 麦位的视觉尺寸样式。
    ///   - sizeClass: 当前容器采用的尺寸等级。
    ///   - width: 分配给麦位的宽度，单位为点。
    /// - Returns: 适合该麦位样式的布局尺寸，单位为点。
    static func fittingSize(
        styleID: SeatVisualStyleID,
        sizeClass: SeatSizeClass,
        width: CGFloat
    ) -> CGSize {
        if styleID.isPK {
            return CGSize(width: width, height: RoomPKSeatMetrics(styleID: styleID, width: width, sizeClass: sizeClass).height)
        }
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

    /// 用户选择可交互麦位时调用的回调；参数为当前麦位绑定。
    var seatDidSelect: ((SeatAssignment) -> Void)?

    /// 一个布尔值，指示当前样式是否属于 PK 布局。
    private var isPK: Bool {
        slotPresentation?.styleID.isPK == true
    }

    /// 按当前 PK 样式、宽度和尺寸等级计算的麦位参数。
    private var pkMetrics: RoomPKSeatMetrics {
        RoomPKSeatMetrics(styleID: slotPresentation?.styleID ?? .pkGuest, width: bounds.width, sizeClass: sizeClass)
    }

    /// 一个布尔值，指示当前麦位是否采用放大主持麦样式。
    private var usesLargeSeatPresentation: Bool {
        slotPresentation?.styleID == .emphasizedHost
    }

    /// 按当前样式和容器宽度解析的头像直径，单位为点。
    private var avatarDiameter: CGFloat {
        if isPK { return pkMetrics.avatarDiameter }
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

    /// 麦克风状态背景的直径，单位为点。
    private var microphoneDiameter: CGFloat {
        isPK ? pkMetrics.microphoneDiameter : (sizeClass == .expanded ? 28 : 22)
    }

    /// 麦克风图标的目标直径，单位为点。
    private var microphoneIconDiameter: CGFloat {
        isPK ? pkMetrics.microphoneDiameter * 0.55 : (sizeClass == .expanded ? 14 : 11)
    }

    /// 头像内容相对背景的缩放比例；备用符号使用较小比例。
    private var avatarContentScale: CGFloat {
        assignment?.avatarImageID == nil ? 0.54 : 1
    }

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
    override var body: Layout {
        if isPK { pkBody } else { standardBody }
    }

    /// PK 样式下头像、音频标记、积分和主持麦名称的布局。
    @LayoutBuilder
    private var pkBody: Layout {
        VStack(spacing: pkMetrics.spacing) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    roundedContent(haloView).frame(width: avatarDiameter + pkMetrics.haloInset, height: avatarDiameter + pkMetrics.haloInset)
                    roundedContent(avatarBackgroundView).frame(width: avatarDiameter, height: avatarDiameter)
                    roundedContent(avatarImageView, isRounded: assignment?.avatarImageID != nil).scaledToFit()
                        .frame(width: avatarDiameter * avatarContentScale, height: avatarDiameter * avatarContentScale)
                }
                ZStack {
                    roundedContent(microphoneBackgroundView)
                    microphoneImageView.resizable().scaledToFit()
                        .frame(width: microphoneIconDiameter, height: microphoneIconDiameter)
                    speakingIndicatorView.resizable()
                        .frame(width: microphoneIconDiameter, height: microphoneIconDiameter)
                }
                .frame(width: microphoneDiameter, height: microphoneDiameter)
            }
            scoreLabel.resizable(axis: .horizontal)
                .frame(width: avatarDiameter, height: pkMetrics.scoreHeight)
                .background { roundedContent(scoreBackgroundView) }
            if pkMetrics.isHost {
                nameLabel.resizable(axis: .horizontal).frame(height: pkMetrics.nameHeight)
            }
        }
    }

    /// 普通房型下头像、音频标记、积分与名称的布局。
    @LayoutBuilder
    private var standardBody: Layout {
        VStack(
            spacing: sizeClass == .compact
                ? 2
                : (usesLargeSeatPresentation || sizeClass == .expanded ? 5 : 3)
        ) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    roundedContent(haloView)
                        .frame(
                            width: avatarDiameter + 10,
                            height: avatarDiameter + 10
                        )
                    roundedContent(avatarBackgroundView)
                        .frame(
                            width: avatarDiameter,
                            height: avatarDiameter
                        )
                    roundedContent(avatarImageView, isRounded: assignment?.avatarImageID != nil)
                        .scaledToFit()
                        .frame(
                            width: avatarDiameter * avatarContentScale,
                            height: avatarDiameter * avatarContentScale
                        )
                }

                ZStack {
                    roundedContent(microphoneBackgroundView)
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
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
                .padding(.horizontal, sizeClass == .expanded ? 9 : 5)
                .padding(.vertical, sizeClass == .expanded ? 4 : 3)
                .frame(width: avatarDiameter)
                .background { roundedContent(scoreBackgroundView) }
            // Cell 缩小时仍保留单行高度，避免过渡布局将文字压成零尺寸。
            nameLabel.fixedSize(axis: .vertical)
        }
    }

    /// 在实际尺寸应用后更新圆角，避免配置目标样式时提前改变头像裁剪。
    private func roundedContent(_ view: UIView, isRounded: Bool = true) -> Layout {
        view.resizable()
            .onGeometryChange(for: CGFloat.self) { geometry in
                isRounded ? min(geometry.size.width, geometry.size.height) / 2 : 0
            } action: { [weak view] radius in
                view?.layer.cornerRadius = radius
            }
    }

    /// 更新命中区域及依赖宽度的 PK 样式。
    override func layoutSubviews() {
        if isPK {
            if lastPKWidth != bounds.width {
                lastPKWidth = bounds.width
                setNeedsQuickLayout()
            }
        }
        super.layoutSubviews()
        interactionButton.frame = bounds
        bringSubviewToFront(interactionButton)
    }

    /// 使用后台 assignment 和布局语义共同配置麦位。
    ///
    /// 用户头像、昵称和音频状态只读取 assignment；尺寸、空麦样式和交互由客户端
    /// Slot Presentation 决定。
    func configure(presentation slotPresentation: SeatSlotPresentation) {
        let assignment = slotPresentation.assignment
        let content = SeatDisplayContent(presentation: slotPresentation)
        self.assignment = assignment
        self.slotPresentation = slotPresentation
        let themeIndex = assignment?.themeIndex
            ?? slotPresentation.position.rawValue
        let color = VoiceRoomTheme.seatColor(at: themeIndex)
        haloView.layer.borderColor = color.withAlphaComponent(0.85).cgColor
        haloView.layer.shadowColor = color.cgColor
        avatarBackgroundView.backgroundColor = color.withAlphaComponent(0.22)
        avatarImageView.image = content.avatarImage
        avatarImageView.tintColor = color
        let usesPhotoAvatar = assignment?.avatarImageID != nil
        avatarImageView.contentMode = usesPhotoAvatar
            ? .scaleAspectFill
            : .scaleAspectFit
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
        scoreLabel.text = content.scoreText
        nameLabel.text = content.name
        accessibilityLabel = nameLabel.text
        accessibilityValue = Localization.text(
            isMuted ? "liveRoom.seat.muted" : "liveRoom.seat.speaking"
        )
        let position = isPK
            ? "\(slotPresentation.roomSide == .current ? "current" : "opponent").\(slotPresentation.position.rawValue)"
            : String(slotPresentation.position.rawValue)
        if isPK {
            accessibilityLabel = Localization.text(
                "liveRoom.pk.seatDescription",
                Localization.text(slotPresentation.roomSide == .current ? "liveRoom.pk.current" : "liveRoom.pk.opponent"),
                slotPresentation.position.rawValue
            ) + "，" + (nameLabel.text ?? "")
        }
        speakingIndicatorView.accessibilityIdentifier = "liveRoom.seat.waveform.\(position)"
        accessibilityIdentifier = "liveRoom.seat.\(position)"
        avatarImageView.accessibilityIdentifier = "liveRoom.seat.avatar.\(position)"
        scoreLabel.accessibilityIdentifier = "liveRoom.seat.score.\(position)"
        nameLabel.accessibilityIdentifier = "liveRoom.seat.name.\(position)"
        interactionButton.isEnabled = slotPresentation.interaction
            == .showUserCard
        interactionButton.accessibilityIdentifier =
            "liveRoom.seat.button.\(position)"
        interactionButton.accessibilityLabel = accessibilityLabel
        interactionButton.accessibilityValue = accessibilityValue
        applyVisualStyle()
        setNeedsQuickLayout()
    }

    /// 从真实头像的表示层取中心，包含 Cell、舞台及头像自身正在播放的几何动画。
    func giftTargetPoint(in view: UIView) -> CGPoint? {
        guard avatarBackgroundView.superview != nil else { return nil }
        let source = avatarBackgroundView.layer.presentation() ?? avatarBackgroundView.layer
        let destination = view.layer.presentation() ?? view.layer
        return source.convert(CGPoint(x: source.bounds.midX, y: source.bounds.midY), to: destination)
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

    /// 更新麦位尺寸等级，并同步字体、视觉样式和布局。
    func setSizeClass(_ sizeClass: SeatSizeClass) {
        guard self.sizeClass != sizeClass else { return }
        self.sizeClass = sizeClass
        configureTypography()
        setNeedsQuickLayout()
    }

    /// 根据当前样式更新外圈边框、字体和布局需求。
    private func applyVisualStyle() {
        haloView.layer.borderWidth = slotPresentation?.role == .host ? 3 : 2
        configureTypography()
        setNeedsQuickLayout()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer

        haloView.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        haloView.layer.borderWidth = 2
        haloView.layer.shadowOpacity = 0.45
        haloView.layer.shadowRadius = 8

        avatarBackgroundView.layer.masksToBounds = true
        avatarImageView.contentMode = .scaleAspectFit

        interactionButton.backgroundColor = .clear
        addSubview(interactionButton)
        interactionButton.action = { [weak self] in self?.didTapSeat() }

        microphoneImageView.tintColor = .white
        microphoneImageView.contentMode = .scaleAspectFit
        speakingIndicatorView.isHidden = true

        scoreLabel.numberOfLines = 1
        scoreLabel.adjustsFontSizeToFitWidth = true
        scoreLabel.minimumScaleFactor = 0.7
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

    /// 在麦位有人占用时转发用户选择事件。
    private func didTapSeat() {
        guard let assignment, assignment.isOccupied else { return }
        seatDidSelect?(assignment)
    }

    /// 根据麦位样式和尺寸等级设置积分及名称字体。
    private func configureTypography() {
        if isPK {
            scoreLabel.font = .monospacedDigitSystemFont(ofSize: pkMetrics.scoreFontSize, weight: .semibold)
            nameLabel.font = .systemFont(ofSize: pkMetrics.nameFontSize, weight: .semibold)
            return
        }
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
        nameLabel.font = .systemFont(
            ofSize: nameFontSize,
            weight: usesLargeSeatPresentation ? .semibold : .medium
        )
    }
}

#if DEBUG
/// 创建展示指定尺寸与样式的麦位视图的预览控制器。
@MainActor
private func makeSeatViewPreview(
    seat: SeatAssignment,
    styleID: SeatVisualStyleID,
    size: CGSize
) -> UIViewController {
    let view = SeatView(frame: .zero)
    view.configure(
        presentation: SeatSlotPresentation(
            slotID: seat.slotID,
            position: seat.position,
            assignment: seat,
            role: .roomSeat(at: seat.position),
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
