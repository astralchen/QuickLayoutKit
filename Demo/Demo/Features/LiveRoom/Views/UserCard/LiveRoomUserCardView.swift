//
//  LiveRoomUserCardView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomUserCardView: LiveRoomCardView {

    let closeButton = LiveRoomSymbolButton(frame: .zero)

    private let titleLabel = UILabel()
    private let avatarBackgroundView = UIView()
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let seatLabel = UILabel()
    private let scoreLabel = UILabel()
    private let microphoneImageView = UIImageView()
    private let microphoneLabel = UILabel()
    private var avatarContentSize: CGFloat = 52

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                titleLabel
                    .resizable(axis: .horizontal)
                Spacer()
                closeButton.expand(by: CGSize(width: 12, height: 12))
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

    func configure(seat: LiveRoomSeat) {
        let color = LiveRoomTheme.seatColor(at: seat.themeIndex)
        titleLabel.text = DemoLocalization.text("liveRoom.userCard.title")
        nameLabel.text = DemoLocalization.text(seat.nameKey)
        seatLabel.text = seat.id == 0
            ? DemoLocalization.text("liveRoom.userCard.hostSeat")
            : DemoLocalization.text("liveRoom.userCard.guestSeat", seat.id)
        scoreLabel.text = DemoLocalization.text(
            "liveRoom.seat.score",
            seat.score
        )
        microphoneLabel.text = DemoLocalization.text(
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
        closeButton.accessibilityLabel = DemoLocalization.text("common.close")
        setNeedsQuickLayout()
    }

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
            backgroundColor: UIColor.white.withAlphaComponent(0.12),
            cornerRadius: 17.5
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
@MainActor
private func makeLiveRoomUserCardViewPreview() -> UIViewController {
    let view = LiveRoomUserCardView()
    view.configure(seat: LiveRoomPreviewData.seats[3])
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            view
                .resizable()
                .padding(
                    EdgeInsets(
                        top: 48,
                        leading: 24,
                        bottom: 48,
                        trailing: 24
                    )
                )
        }
        .frame(width: 390, height: 500)
    }
}

#Preview("用户卡片内容") {
    makeLiveRoomUserCardViewPreview()
}
#endif
