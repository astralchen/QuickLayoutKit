//
//  AudienceProfileViewController.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class AudienceProfileViewController:
    LocalizedQuickLayoutHostingController {

    override var localizedTitleKey: String? {
        "liveRoom.audience.profile.navigationTitle"
    }

    let viewModel: AudienceProfileViewModel

    var memberID: Int { viewModel.state.member.id }
    var displayName: String { viewModel.state.member.displayName }
    var profileScrollView: UIScrollView { profileView.scrollView }

    private let profileView = AudienceProfileView()

    init(viewModel: AudienceProfileViewModel) {
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
            content: AudienceProfileView.Content(
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
                themeColor: VoiceRoomTheme.seatColor(at: member.themeIndex)
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
        _ presence: AudienceMember.Presence
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
private func makeAudienceProfileControllerPreview()
    -> UIViewController {
    let rootViewController = UIViewController()
    rootViewController.title = "当前在线"
    let profileViewController = AudienceProfileViewController(
        viewModel: AudienceProfileViewModel(
            member: VoiceRoomPreviewData.audienceMembers[1]
        )
    )
    let navigationController = UINavigationController()
    navigationController.setViewControllers(
        [rootViewController, profileViewController],
        animated: false
    )
    return navigationController
}

@available(iOS 17.0, *)
#Preview("在线用户主页页面") {
    makeAudienceProfileControllerPreview()
}
#endif
