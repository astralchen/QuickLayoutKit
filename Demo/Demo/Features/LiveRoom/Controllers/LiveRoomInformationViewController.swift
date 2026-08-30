//
//  LiveRoomInformationViewController.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomInformationViewController:
    DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? {
        "liveRoom.info.navigationTitle"
    }

    let viewModel: LiveRoomInformationViewModel

    var roomID: String { viewModel.state.information.roomID }
    var audienceCount: Int { viewModel.state.audienceCount }
    var informationScrollView: UIScrollView { informationView.scrollView }

    private let informationView = LiveRoomInformationView()

    init(viewModel: LiveRoomInformationViewModel) {
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
            content: LiveRoomInformationView.Content(
                roomTitle: DemoLocalization.text("liveRoom.room.title"),
                roomSubtitle: DemoLocalization.text("liveRoom.room.subtitle"),
                avatarAccessibilityLabel: DemoLocalization.text(
                    "liveRoom.info.avatar.accessibility"
                ),
                liveStatus: DemoLocalization.text(
                    "liveRoom.info.status.live"
                ),
                detailsTitle: DemoLocalization.text(
                    "liveRoom.info.details.title"
                ),
                roomIDTitle: DemoLocalization.text("liveRoom.info.roomID"),
                roomID: state.information.roomID,
                hostTitle: DemoLocalization.text("liveRoom.info.host"),
                hostDisplayName: state.information.hostDisplayName,
                audienceTitle: DemoLocalization.text(
                    "liveRoom.info.audience"
                ),
                audienceValue: DemoLocalization.text(
                    "liveRoom.room.audience",
                    state.audienceCount
                ),
                announcementTitle: DemoLocalization.text(
                    "liveRoom.info.announcement.title"
                ),
                announcement: DemoLocalization.text(
                    "liveRoom.info.announcement.value"
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
private func makeLiveRoomInformationControllerPreview() -> UIViewController {
    let rootViewController = UIViewController()
    rootViewController.title = "直播间"
    let informationViewController = LiveRoomInformationViewController(
        viewModel: LiveRoomPreviewData.makeRoomInformationViewModel()
    )
    let navigationController = UINavigationController()
    navigationController.setViewControllers(
        [rootViewController, informationViewController],
        animated: false
    )
    return navigationController
}

#Preview("直播间信息页面") {
    makeLiveRoomInformationControllerPreview()
}
#endif
