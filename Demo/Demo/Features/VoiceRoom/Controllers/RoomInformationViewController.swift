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

/// 展示房间基础资料、在线人数和公告的控制器。
final class RoomInformationViewController:
    LocalizedQuickLayoutHostingController {

    /// 导航标题使用的本地化资源键。
    override var localizedTitleKey: String? {
        "liveRoom.info.navigationTitle"
    }

    /// 提供当前页面业务状态并处理用户操作的视图模型。
    let viewModel: RoomInformationViewModel

    /// 房间的业务标识。
    var roomID: String { viewModel.state.information.roomID }
    /// 房间当前显示的在线人数。
    var audienceCount: Int { viewModel.state.audienceCount }
    /// 房间资料页的纵向内容滚动视图。
    var informationScrollView: UIScrollView { informationView.scrollView }

    /// 显示房间资料和公告的内容视图。
    private let informationView = RoomInformationView()

    /// 使用指定的房间资料视图模型创建资料页控制器。
    init(viewModel: RoomInformationViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 在视图加载后配置界面并连接内容与交互。
    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "liveRoom.information.controller"
    }

    /// 根据当前语言刷新显示文案和辅助功能描述。
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

    /// 应用新的界面布局方向，并使相关内容重新布局。
    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        informationView.semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        informationView.setNeedsQuickLayout()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        informationView.resizable()
    }
}

#if DEBUG
/// 创建展示房间资料控制器的预览控制器。
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
