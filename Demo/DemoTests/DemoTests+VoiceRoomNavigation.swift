import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func voiceRoomOccupiedSeatPresentsUserCardAndEmptySeatDoesNot() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = VoiceRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        let occupiedSeatButton = try #require(
            viewController.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.seat.button.1"
            }
        )
        let emptySeatButton = try #require(
            viewController.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.seat.button.5"
            }
        )

        #expect(occupiedSeatButton.isEnabled)
        #expect(!emptySeatButton.isEnabled)

        activate(emptySeatButton)
        #expect(viewController.presentedViewController == nil)

        activate(occupiedSeatButton)

        #expect(viewController.presentedUserCardSeatID == 1)
        let presentedViewController = try #require(
            viewController.presentedViewController
        )
        presentedViewController.loadViewIfNeeded()
        presentedViewController.view.frame = window.bounds
        presentedViewController.view.setNeedsLayout()
        presentedViewController.view.layoutIfNeeded()
        let userCardView = try #require(
            presentedViewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.userCard.container"
            }
        )
        let nameLabel = try #require(
            presentedViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "liveRoom.userCard.name"
            }
        )
        let scoreLabel = try #require(
            presentedViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "liveRoom.userCard.score"
            }
        )
        let microphoneLabel = try #require(
            presentedViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "liveRoom.userCard.microphone"
            }
        )
        let closeButton = try #require(
            presentedViewController.view
                .allSubviews(of: SymbolButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.userCard.close"
            }
        )

        #expect(
            nameLabel.text
                == Localization.text("liveRoom.user.party.1")
        )
        #expect(
            scoreLabel.text
                == Localization.text("liveRoom.seat.score", 3_820)
        )
        #expect(
            microphoneLabel.text
                == Localization.text("liveRoom.seat.speaking")
        )
        let scoreIntrinsicSize = scoreLabel.sizeThatFits(
            CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        #expect(scoreLabel.bounds.width - scoreIntrinsicSize.width >= 27)
        #expect(scoreLabel.bounds.height - scoreIntrinsicSize.height >= 11)
        #expect(closeButton.layer.cornerCurve == .circular)
        #expect(closeButton.bounds.width >= 32)
        #expect(closeButton.bounds.height >= 32)
        #expect(closeButton.bounds.width < 44)
        #expect(closeButton.bounds.height < 44)
        #expect(abs(closeButton.bounds.width - closeButton.bounds.height) < 1)
        #expect(
            abs(
                closeButton.layer.cornerRadius
                    - min(closeButton.bounds.width, closeButton.bounds.height) / 2
            ) < 0.5
        )
        let pointOutsideVisualBounds = CGPoint(
            x: -1,
            y: closeButton.bounds.midY
        )
        #expect(!closeButton.bounds.contains(pointOutsideVisualBounds))
        #expect(
            closeButton.point(inside: pointOutsideVisualBounds, with: nil)
        )
        #expect(userCardView.bounds.width <= 340)
        #expect(
            userCardView.convert(userCardView.bounds, to: window).minX >= 24
        )
    }

    @Test func voiceRoomFollowButtonShowsRequestingState() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let requestHandler = ControlledFollowRequestHandler()
        let viewModel = VoiceRoomViewModel(
            isFollowing: false,
            followRequestHandler: requestHandler
        )
        let viewController = VoiceRoomViewController(viewModel: viewModel)
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let followButton = try #require(
            viewController.view
                .allSubviews(of: FollowButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.follow.button"
            }
        )

        #expect(followButton.accessibilityLabel == "关注直播间")
        #expect(!followButton.isSelected)
        #expect(!followButton.accessibilityTraits.contains(.selected))

        activate(followButton)

        #expect(
            await waitForCondition {
                viewModel.state.pendingFollowingState == true
            }
        )
        layout(viewController, in: navigationController)
        #expect(!viewModel.state.isFollowing)
        #expect(
            followButton.allSubviews(of: UILabel.self).count == 2
        )
        #expect(followButton.accessibilityLabel == "关注中…")
        #expect(!followButton.isEnabled)
        #expect(followButton.accessibilityTraits.contains(.notEnabled))
        let activityIndicatorView = try #require(
            followButton.allSubviews(
                of: UIActivityIndicatorView.self
            ).first {
                $0.accessibilityIdentifier
                    == "liveRoom.follow.activityIndicator"
            }
        )
        #expect(activityIndicatorView.isAnimating)
        #expect(abs(activityIndicatorView.bounds.width - 14) < 0.5)
        #expect(abs(activityIndicatorView.bounds.height - 14) < 0.5)

        activate(followButton)
        #expect(requestHandler.requestedStates == [true])

        requestHandler.succeed()
        #expect(
            await waitForCondition {
                viewModel.state.isFollowing
                    && viewModel.state.pendingFollowingState == nil
                    && viewController.followRequestTask == nil
            }
        )
        layout(viewController, in: navigationController)
        #expect(followButton.accessibilityLabel == "已关注")
        #expect(followButton.isEnabled)
        #expect(followButton.isSelected)
        #expect(followButton.accessibilityTraits.contains(.selected))
        #expect(followButton.allSubviews(of: UIView.self).contains {
            $0.layer.borderColor == UIColor.white.withAlphaComponent(0.24).cgColor
        })
        #expect(followButton.layer.cornerCurve == .circular)
        layout(viewController, in: navigationController)
        let checkmarkImageView = try #require(
            followButton.allSubviews(of: UIImageView.self).first {
                $0.accessibilityIdentifier == "liveRoom.follow.checkmark"
            }
        )
        #expect(abs(checkmarkImageView.bounds.width - 12) < 0.5)
        let checkmarkImage = try #require(checkmarkImageView.image)
        let fittedHeight = 12 * checkmarkImage.size.height / checkmarkImage.size.width
        #expect(abs(checkmarkImageView.bounds.height - fittedHeight) < 0.5)
        #expect(
            abs(
                followButton.layer.cornerRadius
                    - min(
                        followButton.bounds.width,
                        followButton.bounds.height
                    ) / 2
            ) < 0.5
        )

        activate(followButton)

        #expect(
            await waitForCondition {
                viewModel.state.pendingFollowingState == false
            }
        )
        layout(viewController, in: navigationController)
        #expect(viewModel.state.isFollowing)
        #expect(
            followButton.allSubviews(of: UILabel.self).count == 2
        )
        #expect(followButton.accessibilityLabel == "取消关注中…")
        #expect(!followButton.isEnabled)
        #expect(followButton.accessibilityTraits.contains(.selected))
        #expect(followButton.accessibilityTraits.contains(.notEnabled))
        #expect(activityIndicatorView.isAnimating)

        requestHandler.succeed()
        #expect(
            await waitForCondition {
                !viewModel.state.isFollowing
                    && viewModel.state.pendingFollowingState == nil
                    && viewController.followRequestTask == nil
            }
        )
        #expect(!viewModel.state.isFollowing)
        #expect(followButton.accessibilityLabel == "关注直播间")
        #expect(followButton.isEnabled)
        #expect(!followButton.isSelected)
        #expect(!followButton.accessibilityTraits.contains(.selected))
    }

    @Test func voiceRoomAudienceButtonPresentsAdaptiveSheet() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let members = Array(VoiceRoomViewModel().state.audienceMembers.prefix(7))
        let viewModel = VoiceRoomViewModel(
            audienceCount: 42,
            audienceMembers: members
        )
        let viewController = VoiceRoomViewController(viewModel: viewModel)
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let audienceButton = try #require(
            viewController.view
                .allSubviews(of: CapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.audience.button"
            }
        )
        #expect(audienceButton.accessibilityLabel == "42 人在线")
        #expect(audienceButton.accessibilityHint == "查看当前在线用户")
        #expect(audienceButton.layer.cornerCurve == .circular)
        #expect(
            abs(
                audienceButton.layer.cornerRadius
                    - min(
                        audienceButton.bounds.width,
                        audienceButton.bounds.height
                    ) / 2
            ) < 0.5
        )
        let audiencePointOutsideVisualBounds = CGPoint(
            x: audienceButton.bounds.midX,
            y: -1
        )
        #expect(
            audienceButton.point(
                inside: audiencePointOutsideVisualBounds,
                with: nil
            )
        )

        activate(audienceButton)

        let sheetViewController = try #require(
            viewController.presentedViewController
                as? AudienceSheetViewController
        )
        try #require(await waitForCondition {
            sheetViewController.view.window != nil
                && sheetViewController.transitionCoordinator == nil
                && sheetViewController.audienceCollectionView.numberOfItems(inSection: 0) == 7
        })
        sheetViewController.loadViewIfNeeded()
        sheetViewController.view.setNeedsLayout()
        sheetViewController.view.layoutIfNeeded()
        sheetViewController.audienceCollectionView.layoutIfNeeded()
        let audienceHeaderView = try #require(
            sheetViewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.audience.header"
            }
        )
        let headerFrame = audienceHeaderView.convert(
            audienceHeaderView.bounds,
            to: sheetViewController.view
        )
        let safeAreaFrame = sheetViewController.view.safeAreaLayoutGuide
            .layoutFrame

        #expect(viewController.presentedAudienceMemberCount == 7)
        #expect(sheetViewController.totalCount == 42)
        #expect(headerFrame.minY >= safeAreaFrame.minY - 0.5)
        // 页头和列表共用安全宽度；改变侧边区域后不得遗漏或重复扣除安全边距。
        for extraInsets in [
            UIEdgeInsets.zero,
            UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 40),
            UIEdgeInsets(top: 0, left: 40, bottom: 0, right: 0),
            UIEdgeInsets.zero,
        ] {
            sheetViewController.additionalSafeAreaInsets = extraInsets
            sheetViewController.view.setNeedsLayout()
            sheetViewController.view.layoutIfNeeded()
            let safeFrame = sheetViewController.view.safeAreaLayoutGuide.layoutFrame
            let collection = sheetViewController.audienceCollectionView
            for content in [audienceHeaderView, collection] {
                let frame = content.convert(content.bounds, to: sheetViewController.view)
                #expect(abs(frame.minX - safeFrame.minX) < 0.5)
                #expect(abs(frame.maxX - safeFrame.maxX) < 0.5)
            }
            #expect(abs(collection.adjustedContentInset.left) < 0.5)
            #expect(abs(collection.adjustedContentInset.right) < 0.5)
        }
        #expect(
            sheetViewController.sheetPresentationController?.detents.count
                == 2
        )
        #expect(
            sheetViewController.audienceCollectionView.numberOfItems(
                inSection: 0
            ) == 7
        )
        #expect(
            sheetViewController.audienceCollectionView
                .collectionViewLayout.collectionViewContentSize.height > 0
        )
        #expect(
            sheetViewController.audienceCollectionView
                .contentInsetAdjustmentBehavior == .always
        )
        #expect(viewModel.consumeStageSnapshot(
            VoiceRoomViewModel.makeDefaultStageSnapshot(revision: 2, assignments: [])
        ))
        #expect(sheetViewController.viewModel.state.members.allSatisfy {
            $0.presence == .listening
        })
        try #require(await waitForCondition {
            sheetViewController.audienceCollectionView.visibleCells
                .flatMap { $0.allSubviews(of: UILabel.self) }
                .contains { $0.text == Localization.text("liveRoom.audience.listening") }
        })
    }

    @Test func voiceRoomAudienceItemPushesUserProfile() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let members = Array(VoiceRoomViewModel().state.audienceMembers.prefix(7))
        let viewModel = VoiceRoomViewModel(
            audienceCount: 42,
            audienceMembers: members
        )
        let viewController = VoiceRoomViewController(viewModel: viewModel)
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let audienceButton = try #require(
            viewController.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.audience.button"
            }
        )
        activate(audienceButton)

        let sheetViewController = try #require(
            viewController.presentedViewController
                as? AudienceSheetViewController
        )
        let indexPath = IndexPath(item: 0, section: 0)
        try #require(await waitForCondition {
            sheetViewController.view.layoutIfNeeded()
            sheetViewController.audienceCollectionView.layoutIfNeeded()
            return sheetViewController.view.window != nil
                && sheetViewController.transitionCoordinator == nil
                && sheetViewController.audienceCollectionView.cellForItem(at: indexPath) != nil
        })
        let selectedMember = try #require(
            sheetViewController.viewModel.state.members.first
        )
        let memberCell = try #require(
            sheetViewController.audienceCollectionView.cellForItem(
                at: indexPath
            ) as? AudienceMemberCell
        )
        #expect(memberCell.accessibilityTraits.contains(.button))
        #expect(memberCell.accessibilityHint == "查看该用户的主页")

        sheetViewController.audienceCollectionView.delegate?
            .collectionView?(
                sheetViewController.audienceCollectionView,
                didSelectItemAt: indexPath
            )
        // 等待关闭面板和导航转场完成，单次 yield 不保证 UIKit 已执行 completion。
        try #require(await waitForCondition {
            viewController.presentedViewController == nil
                && navigationController.topViewController is AudienceProfileViewController
                && navigationController.transitionCoordinator == nil
        })

        let profileViewController = try #require(
            navigationController.topViewController
                as? AudienceProfileViewController
        )
        profileViewController.loadViewIfNeeded()
        layout(profileViewController, in: navigationController)

        #expect(viewController.presentedViewController == nil)
        #expect(viewController.audienceSheetViewController == nil)
        #expect(
            viewController.pushedAudienceProfileViewController
                === profileViewController
        )
        #expect(profileViewController.memberID == selectedMember.id)
        #expect(profileViewController.displayName == selectedMember.displayName)
        #expect(profileViewController.title == "用户主页")
        #expect(!profileViewController.navigationItem.hidesBackButton)

        let scrollFrame = profileViewController.profileScrollView.convert(
            profileViewController.profileScrollView.bounds,
            to: profileViewController.view
        )
        let safeAreaFrame = profileViewController.view.safeAreaLayoutGuide
            .layoutFrame
        #expect(scrollFrame.minY >= safeAreaFrame.minY - 0.5)
        #expect(scrollFrame.maxY <= safeAreaFrame.maxY + 0.5)

        let memberIDLabel = try #require(
            profileViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.audience.profile.memberID"
            }
        )
        #expect(memberIDLabel.text == selectedMember.id.rawValue)
        #expect(viewModel.consumeStageSnapshot(
            VoiceRoomViewModel.makeDefaultStageSnapshot(revision: 2, assignments: [])
        ))
        #expect(profileViewController.viewModel.state.member.presence == .listening)
        #expect(profileViewController.view.allSubviews(of: UILabel.self).contains {
            $0.text == Localization.text("liveRoom.audience.listening")
        })

        Localization.setLocale(identifier: "ar")
        profileViewController.applyLocalization(
            Localization.currentUIKitUpdate
        )
        #expect(profileViewController.title == "الملف الشخصي")
        #expect(!profileViewController.navigationItem.hidesBackButton)
        #expect(profileViewController.navigationItem.leftBarButtonItem == nil)
        #expect(
            profileViewController.navigationItem.rightBarButtonItem?
                .accessibilityIdentifier == "demo.language.menu"
        )
    }

    @Test func voiceRoomAvatarPushesInformationController() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let roomInformation = RoomInformation(
            roomID: "TEST-9527",
            hostDisplayName: "测试主播"
        )
        let viewModel = VoiceRoomViewModel(
            audienceCount: 42,
            roomInformation: roomInformation
        )
        let viewController = VoiceRoomViewController(viewModel: viewModel)
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let avatarButton = try #require(
            viewController.view
                .allSubviews(of: SymbolButton.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.room.avatar.button"
            }
        )
        #expect(avatarButton.bounds.width >= 44)
        #expect(avatarButton.bounds.height >= 44)
        #expect(
            abs(
                avatarButton.layer.cornerRadius
                    - min(avatarButton.bounds.width, avatarButton.bounds.height) / 2
            ) < 0.5
        )
        #expect(avatarButton.accessibilityLabel == "直播间头像")
        #expect(avatarButton.accessibilityHint == "查看直播间信息")

        activate(avatarButton)

        let informationViewController = try #require(
            navigationController.topViewController
                as? RoomInformationViewController
        )
        informationViewController.loadViewIfNeeded()
        layout(informationViewController, in: navigationController)

        #expect(navigationController.viewControllers.count == 2)
        #expect(
            viewController.pushedRoomInformationViewController
                === informationViewController
        )
        #expect(informationViewController.roomID == "TEST-9527")
        #expect(informationViewController.audienceCount == 42)
        #expect(informationViewController.title == "直播间信息")
        #expect(!informationViewController.navigationItem.hidesBackButton)

        let scrollFrame = informationViewController.informationScrollView
            .convert(
                informationViewController.informationScrollView.bounds,
                to: informationViewController.view
            )
        let safeAreaFrame = informationViewController.view
            .safeAreaLayoutGuide.layoutFrame
        #expect(scrollFrame.minY >= safeAreaFrame.minY - 0.5)
        #expect(scrollFrame.maxY <= safeAreaFrame.maxY + 0.5)

        let roomIDLabel = try #require(
            informationViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "liveRoom.information.roomID"
            }
        )
        let audienceLabel = try #require(
            informationViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.information.audience"
            }
        )
        #expect(roomIDLabel.text == "TEST-9527")
        #expect(audienceLabel.text == "42 人在线")

        let profileLabels = try [
            "星光音乐小屋",
            "唱歌 · 聊天 · 遇见有趣的人",
            "直播中"
        ].map { text in
            try #require(
                informationViewController.view
                    .allSubviews(of: UILabel.self)
                    .first { $0.text == text }
            )
        }
        let profileHostView = try #require(profileLabels.first?.superview)
        for label in profileLabels {
            #expect(label.superview === profileHostView)
            #expect(label.bounds.height >= label.intrinsicContentSize.height - 0.5)
            #expect(label.frame.minY >= -0.5)
            #expect(label.frame.maxY <= profileHostView.bounds.height + 0.5)
        }

        Localization.setLocale(identifier: "ar")
        informationViewController.applyLocalization(
            Localization.currentUIKitUpdate
        )
        #expect(!informationViewController.navigationItem.hidesBackButton)
        #expect(informationViewController.navigationItem.leftBarButtonItem == nil)
        #expect(
            informationViewController.navigationItem.rightBarButtonItem?
                .accessibilityIdentifier == "demo.language.menu"
        )

        let poppedViewController = navigationController.popViewController(
            animated: false
        )
        #expect(poppedViewController === informationViewController)
        #expect(navigationController.topViewController === viewController)
    }

    @Test func voiceRoomKeepsSystemBackButtonAfterSwitchingToArabic() {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let rootViewController = UIViewController()
        let navigationController = UINavigationController(
            rootViewController: rootViewController
        )
        let voiceRoomViewController = VoiceRoomViewController()
        navigationController.pushViewController(
            voiceRoomViewController,
            animated: false
        )
        voiceRoomViewController.loadViewIfNeeded()

        #expect(navigationController.viewControllers.count == 2)
        #expect(voiceRoomViewController.navigationItem.leftBarButtonItem == nil)
        #expect(!voiceRoomViewController.navigationItem.hidesBackButton)

        Localization.setLocale(identifier: "ar")
        Localization.reloadLanguageMenu(on: voiceRoomViewController)

        let languageItem = voiceRoomViewController.navigationItem
            .rightBarButtonItem
        #expect(
            languageItem?.accessibilityIdentifier == "demo.language.menu"
        )
        #expect(voiceRoomViewController.navigationItem.leftBarButtonItem == nil)
        #expect(!voiceRoomViewController.navigationItem.hidesBackButton)
    }
}
