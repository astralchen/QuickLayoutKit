//
//  RoomInformationViewController.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class RoomInformationViewController:
    LocalizedQuickLayoutHostingController {

    override var localizedTitleKey: String? {
        "liveRoom.info.navigationTitle"
    }

    let viewModel: RoomInformationViewModel

    var roomID: String { viewModel.state.information.roomID }
    var audienceCount: Int { viewModel.state.audienceCount }
    var informationScrollView: UIScrollView { informationView.scrollView }

    private let informationView = RoomInformationView()

    init(viewModel: RoomInformationViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "liveRoom.information.controller"
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        let state = viewModel.state
        informationView.configure(
            content: RoomInformationView.Content(
                profile: .init(
                    roomTitle: Localization.text("liveRoom.room.title"),
                    roomSubtitle: Localization.text(
                        "liveRoom.room.subtitle"
                    ),
                    avatarAccessibilityLabel: Localization.text(
                        "liveRoom.info.avatar.accessibility"
                    ),
                    liveStatus: Localization.text(
                        "liveRoom.info.status.live"
                    )
                ),
                details: .init(
                    title: Localization.text(
                        "liveRoom.info.details.title"
                    ),
                    roomID: .init(
                        title: Localization.text("liveRoom.info.roomID"),
                        value: state.information.roomID
                    ),
                    host: .init(
                        title: Localization.text("liveRoom.info.host"),
                        value: state.information.hostDisplayName
                    ),
                    audience: .init(
                        title: Localization.text(
                            "liveRoom.info.audience"
                        ),
                        value: Localization.text(
                            "liveRoom.room.audience",
                            state.audienceCount
                        )
                    )
                ),
                announcement: .init(
                    title: Localization.text(
                        "liveRoom.info.announcement.title"
                    ),
                    value: Localization.text(
                        "liveRoom.info.announcement.value"
                    )
                )
            )
        )
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        informationView.semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        informationView.setNeedsQuickLayout()
    }

    override var body: Layout {
        informationView.resizable()
    }
}

#if DEBUG
@MainActor
private func makeRoomInformationControllerPreview() -> UIViewController {
    let rootViewController = UIViewController()
    rootViewController.title = "直播间"
    let informationViewController = RoomInformationViewController(
        viewModel: VoiceRoomPreviewData.makeRoomInformationViewModel()
    )
    let navigationController = UINavigationController()
    navigationController.setViewControllers(
        [rootViewController, informationViewController],
        animated: false
    )
    return navigationController
}

@available(iOS 17.0, *)
#Preview("直播间信息页面") {
    makeRoomInformationControllerPreview()
}
#endif
