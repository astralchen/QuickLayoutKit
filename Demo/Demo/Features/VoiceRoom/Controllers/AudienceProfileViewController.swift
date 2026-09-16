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

/// 将观众资料状态和本地化文案绑定到资料页的控制器。
final class AudienceProfileViewController:
    LocalizedQuickLayoutHostingController {

    /// 导航标题使用的本地化资源键。
    override var localizedTitleKey: String? {
        "liveRoom.audience.profile.navigationTitle"
    }

    /// 提供当前页面业务状态并处理用户操作的视图模型。
    let viewModel: AudienceProfileViewModel

    /// 当前观众的稳定用户标识。
    var memberID: RoomUserID { viewModel.state.member.id }
    /// 界面显示的用户昵称。
    var displayName: String { viewModel.state.member.displayName }
    /// 观众资料页的纵向内容滚动视图。
    var profileScrollView: UIScrollView { profileView.scrollView }

    /// 显示观众头像、状态和详细资料的内容视图。
    private let profileView = AudienceProfileView()

    /// 使用指定的观众资料视图模型创建资料页控制器。
    init(viewModel: AudienceProfileViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 应用最新观众资料并刷新已加载页面的本地化内容。
    func update(member: AudienceMember) {
        viewModel.update(member: member)
        if isViewLoaded { reloadLocalizedContent() }
    }

    /// 在视图加载后配置界面并连接内容与交互。
    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "liveRoom.audience.profile.controller"
    }

    /// 根据当前语言刷新显示文案和辅助功能描述。
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
                memberID: member.id.rawValue,
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

    /// 应用新的界面布局方向，并使相关内容重新布局。
    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        profileView.semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        profileView.setNeedsQuickLayout()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        profileView.resizable()
    }

    /// 返回观众参与状态的本地化描述；麦位编号按一基值显示。
    private func localizedPresence(
        _ presence: AudienceMember.Presence
    ) -> String {
        switch presence {
        case let .onMicrophone(address):
            return Localization.text(
                "liveRoom.audience.onMicrophone",
                address.position.rawValue + 1
            )
        case .listening:
            return Localization.text("liveRoom.audience.listening")
        }
    }
}

#if DEBUG
/// 创建展示观众资料控制器的预览控制器。
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
