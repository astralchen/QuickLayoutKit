//
//  LiveRoomAudienceProfileViewController.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomAudienceProfileViewController:
    LocalizedQuickLayoutHostingController {

    override var localizedTitleKey: String? {
        "liveRoom.audience.profile.navigationTitle"
    }

    let viewModel: LiveRoomAudienceProfileViewModel

    var memberID: Int { viewModel.state.member.id }
    var displayName: String { viewModel.state.member.displayName }
    var profileScrollView: UIScrollView { profileView.scrollView }

    private let profileView = LiveRoomAudienceProfileView()

    init(viewModel: LiveRoomAudienceProfileViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "liveRoom.audience.profile.controller"
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        let member = viewModel.state.member
        profileView.configure(
            content: LiveRoomAudienceProfileView.Content(
                displayName: member.displayName,
                avatarImage: member.avatarImage,
                avatarAccessibilityLabel: Localization.text(
                    "liveRoom.audience.profile.avatar",
                    member.displayName
                ),
                presence: localizedPresence(member.presence),
                detailsTitle: Localization.text(
                    "liveRoom.audience.profile.details.title"
                ),
                memberIDTitle: Localization.text(
                    "liveRoom.audience.profile.memberID"
                ),
                memberID: String(member.id),
                contributionTitle: Localization.text(
                    "liveRoom.audience.profile.contribution.title"
                ),
                contribution: Localization.text(
                    "liveRoom.audience.contribution",
                    member.contributionScore
                ),
                aboutTitle: Localization.text(
                    "liveRoom.audience.profile.about.title"
                ),
                about: Localization.text(
                    "liveRoom.audience.profile.about.value",
                    member.displayName
                ),
                themeColor: LiveRoomTheme.seatColor(at: member.themeIndex)
            )
        )
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        profileView.semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        profileView.setNeedsQuickLayout()
    }

    override var body: Layout {
        profileView.resizable()
    }

    private func localizedPresence(
        _ presence: LiveRoomAudienceMember.Presence
    ) -> String {
        switch presence {
        case let .onMicrophone(seatNumber):
            return Localization.text(
                "liveRoom.audience.onMicrophone",
                seatNumber
            )
        case .listening:
            return Localization.text("liveRoom.audience.listening")
        }
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomAudienceProfileControllerPreview()
    -> UIViewController {
    let rootViewController = UIViewController()
    rootViewController.title = "当前在线"
    let profileViewController = LiveRoomAudienceProfileViewController(
        viewModel: LiveRoomAudienceProfileViewModel(
            member: LiveRoomPreviewData.audienceMembers[1]
        )
    )
    let navigationController = UINavigationController()
    navigationController.setViewControllers(
        [rootViewController, profileViewController],
        animated: false
    )
    return navigationController
}

#Preview("在线用户主页页面") {
    makeLiveRoomAudienceProfileControllerPreview()
}
#endif
