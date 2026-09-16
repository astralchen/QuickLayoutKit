//
//  SeatUserCardView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 展示占麦用户头像、身份、积分和麦克风状态的资料卡片。
final class SeatUserCardView: TranslucentCardView {

    /// 请求关闭当前资料卡的按钮。
    let closeButton = SymbolButton(frame: .zero)

    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()
    /// 提供头像底色和圆角的背景视图。
    private let avatarBackgroundView = UIView()
    /// 显示用户头像或备用图标的图像视图。
    private let avatarImageView = UIImageView()
    /// 显示用户昵称或空麦名称的标签。
    private let nameLabel = UILabel()
    /// 显示麦位角色、编号或所属房间的标签。
    private let seatLabel = UILabel()
    /// 显示用户积分或空麦状态的标签。
    private let scoreLabel = UILabel()
    /// 显示麦克风可用或静音状态的图像视图。
    private let microphoneImageView = UIImageView()
    /// 显示麦克风状态的文本标签。
    private let microphoneLabel = UILabel()
    /// 资料卡头像内容的目标边长，单位为点。
    private var avatarContentSize: CGFloat = 52

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
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                titleLabel
                    .resizable(axis: .horizontal)
                Spacer()
                closeButton
            }

            ZStack {
                avatarBackgroundView
                    .resizable()
                    .frame(width: 96, height: 96)
                avatarImageView
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: avatarContentSize,
                        height: avatarContentSize
                    )
            }

            nameLabel
                .resizable(axis: .horizontal)
                .frame(maxWidth: .infinity, alignment: .center)
            seatLabel
                .resizable(axis: .horizontal)
                .frame(maxWidth: .infinity, alignment: .center)
            scoreLabel
                .expand(by: CGSize(width: 28, height: 12))

            HStack(spacing: 8) {
                microphoneImageView
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                microphoneLabel
                    .resizable(axis: .horizontal)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
    }

    /// 根据指定麦位更新用户资料、音频状态和可选的 PK 房间侧说明。
    func configure(seat: SeatAssignment, showsRoom: Bool = false) {
        let color = VoiceRoomTheme.seatColor(at: seat.themeIndex)
        titleLabel.text = Localization.text("liveRoom.userCard.title")
        nameLabel.text = Localization.text(seat.nameKey)
        if showsRoom {
            seatLabel.text = Localization.text(
                "liveRoom.pk.seatDescription",
                Localization.text(seat.roomSide == .current ? "liveRoom.pk.current" : "liveRoom.pk.opponent"),
                seat.position.rawValue
            )
        } else {
            seatLabel.text = seat.id == 0
                ? Localization.text("liveRoom.userCard.hostSeat")
                : Localization.text("liveRoom.userCard.guestSeat", seat.id)
        }
        scoreLabel.text = Localization.text(
            "liveRoom.seat.score",
            seat.score
        )
        microphoneLabel.text = Localization.text(
            seat.isMuted ? "liveRoom.seat.muted" : "liveRoom.seat.speaking"
        )
        avatarBackgroundView.backgroundColor = color.withAlphaComponent(0.22)
        avatarImageView.image = seat.avatarImage
        avatarImageView.tintColor = color
        let usesPhotoAvatar = seat.avatarImageID != nil
        avatarContentSize = usesPhotoAvatar ? 96 : 52
        avatarImageView.contentMode = usesPhotoAvatar
            ? .scaleAspectFill
            : .scaleAspectFit
        avatarImageView.layer.cornerRadius = usesPhotoAvatar ? 48 : 0
        avatarImageView.clipsToBounds = usesPhotoAvatar
        microphoneImageView.image = UIImage(
            systemName: seat.isMuted ? "mic.slash.fill" : "waveform"
        )
        microphoneImageView.tintColor = seat.isMuted ? .systemRed : .systemGreen
        closeButton.accessibilityLabel = Localization.text("common.close")
        setNeedsQuickLayout()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        accessibilityIdentifier = "liveRoom.userCard.container"
        backgroundColor = UIColor(
            red: 0.16,
            green: 0.09,
            blue: 0.38,
            alpha: 0.98
        )
        layer.cornerRadius = 28
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.34
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 12)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .white
        titleLabel.adjustsFontForContentSizeCategory = true

        closeButton.configure(
            symbolName: "xmark",
            symbolSize: 17,
            backgroundColor: UIColor.white.withAlphaComponent(0.12)
        )
        closeButton.role = .cancel
        closeButton.accessibilityIdentifier = "liveRoom.userCard.close"

        avatarBackgroundView.layer.cornerRadius = 48
        avatarBackgroundView.layer.borderWidth = 3
        avatarBackgroundView.layer.borderColor = UIColor.white
            .withAlphaComponent(0.30)
            .cgColor
        avatarImageView.contentMode = .scaleAspectFit

        nameLabel.font = .preferredFont(forTextStyle: .title2)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 0
        nameLabel.accessibilityIdentifier = "liveRoom.userCard.name"

        seatLabel.font = .preferredFont(forTextStyle: .subheadline)
        seatLabel.textColor = UIColor.white.withAlphaComponent(0.70)
        seatLabel.textAlignment = .center
        seatLabel.adjustsFontForContentSizeCategory = true
        seatLabel.numberOfLines = 0
        seatLabel.accessibilityIdentifier = "liveRoom.userCard.seat"

        scoreLabel.font = .monospacedDigitSystemFont(
            ofSize: 15,
            weight: .semibold
        )
        scoreLabel.textColor = .white
        scoreLabel.textAlignment = .center
        scoreLabel.backgroundColor = UIColor.black.withAlphaComponent(0.24)
        scoreLabel.layer.cornerRadius = 14
        scoreLabel.layer.masksToBounds = true
        scoreLabel.accessibilityIdentifier = "liveRoom.userCard.score"

        microphoneLabel.font = .preferredFont(forTextStyle: .subheadline)
        microphoneLabel.textColor = UIColor.white.withAlphaComponent(0.84)
        microphoneLabel.adjustsFontForContentSizeCategory = true
        microphoneLabel.numberOfLines = 0
        microphoneLabel.accessibilityIdentifier = "liveRoom.userCard.microphone"
    }
}

#if DEBUG
/// 创建展示麦位用户资料卡的预览控制器。
@MainActor
private func makeSeatUserCardViewPreview() -> UIViewController {
    let view = SeatUserCardView()
    view.configure(seat: VoiceRoomPreviewData.seats[3])
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view
                .resizable(axis: .horizontal)
                .padding(
                    EdgeInsets(
                        top: 48,
                        leading: 24,
                        bottom: 48,
                        trailing: 24
                    )
                )
        }
       
    }
}

@available(iOS 17.0, *)
#Preview("用户卡片内容") {
    makeSeatUserCardViewPreview()
}
#endif
