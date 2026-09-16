//
//  AudienceSheetViewController.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import ListKit
import QuickLayout
import QuickLayoutKit
import UIKit

/// 展示在线观众列表并转发用户选择的面板控制器。
final class AudienceSheetViewController:
    LocalizedQuickLayoutHostingController {

    /// 提供当前页面业务状态并处理用户操作的视图模型。
    let viewModel: AudienceSheetViewModel

    /// 当前已加载并去重的观众数量。
    var memberCount: Int { viewModel.state.members.count }
    /// 在线总人数，不小于已加载的观众数量。
    var totalCount: Int { viewModel.state.totalCount }
    /// 展示在线观众的集合视图。
    var audienceCollectionView: UICollectionView { sheetView.collectionView }
    /// 用户选择观众条目时调用的回调；参数为所选观众的当前资料。
    var memberDidSelect: ((AudienceMember) -> Void)?

    /// 控制器管理的面板内容视图。
    private let sheetView = AudienceSheetView()
    /// 负责列表数据提交、单元格配置和选择事件的适配器。
    private lazy var adapter = CollectionListAdapter<String>(
        collectionView: sheetView.collectionView
    )
    /// 当前列表渲染代次，用于忽略旧渲染任务的后续处理。
    private var renderGeneration = 0

    /// 使用指定的观众列表视图模型创建面板控制器。
    init(viewModel: AudienceSheetViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        preferredContentSize = CGSize(width: 540, height: 620)
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 更新在线人数和观众列表，并刷新面板内容。
    func update(totalCount: Int, members: [AudienceMember]) {
        viewModel.update(totalCount: totalCount, members: members)
        if isViewLoaded { reloadLocalizedContent() }
    }

    /// 在视图加载后配置界面并连接内容与交互。
    override func viewDidLoad() {
        configureAudienceList()
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "liveRoom.audience.controller"
        configureSheetPresentation()
    }

    /// 在页面显示后完成依赖可见状态的界面更新。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIAccessibility.post(
            notification: .screenChanged,
            argument: sheetView
        )
    }

    /// 根据当前语言刷新显示文案和辅助功能描述。
    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        sheetView.configure(
            title: Localization.text("liveRoom.audience.title"),
            summary: Localization.text(
                "liveRoom.room.audience",
                viewModel.state.totalCount
            ),
            subtitle: Localization.text("liveRoom.audience.subtitle")
        )
        renderMembers()
    }

    /// 应用新的界面布局方向，并使相关内容重新布局。
    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        sheetView.semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        sheetView.collectionView.applyLocalization(
            Localization.layoutDirectionUpdate(direction),
            preservingVisibleItem: true,
            rebuildingLayoutWith: { [unowned self] in
                makeAudienceListLayout()
            }
        )
        sheetView.setNeedsQuickLayout()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        sheetView.resizable()
    }

    /// 设置观众面板的高度档位、圆角和拖动指示器。
    private func configureSheetPresentation() {
        guard let sheetPresentationController else { return }
        // 系统 Sheet 负责手势、旋转、键盘和无障碍；列表内容只承担自身纵向滚动。
        sheetPresentationController.detents = [.medium(), .large()]
        sheetPresentationController.prefersGrabberVisible = true
        sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge =
            true
        sheetPresentationController.prefersEdgeAttachedInCompactHeight = true
        sheetPresentationController.widthFollowsPreferredContentSizeWhenEdgeAttached =
            true
        sheetPresentationController.preferredCornerRadius = 28
    }

    /// 配置观众集合视图的列表布局。
    private func configureAudienceList() {
        sheetView.collectionView.collectionViewLayout = makeAudienceListLayout()
    }

    /// 将观众状态映射为列表条目并提交最新渲染任务。
    private func renderMembers() {
        renderGeneration &+= 1
        let generation = renderGeneration
        adapter.apply(
            transaction: .disabled,
            completion: { [weak self] _ in
                // 列表可能已提交更新的快照，旧 diff 的完成回调不再修改当前布局方向。
                guard let self, generation == renderGeneration else { return }
                // ListKit 完成 diff 后 Cell 才全部物化，再同步当前语言方向和自适应尺寸。
                sheetView.collectionView.applyLocalization(
                    Localization.layoutDirectionUpdate(
                        sheetView.collectionView
                            .effectiveUserInterfaceLayoutDirection,
                        reasons: [.layoutDirection, .configuration]
                    ),
                    preservingVisibleItem: true
                )
            }
        ) {
            ListSection("audience") {
                ForEach(viewModel.state.members, id: \.id) { member in
                    Row(
                        model: member,
                        cell: AudienceMemberCell.self
                    ) { cell, member, _ in
                        cell.configure(member: member)
                    }
                    .onSelect { [weak self] member, _ in
                        self?.memberDidSelect?(member)
                    }
                    .refreshID([
                        member.displayName,
                        member.avatarImageID.rawValue,
                        String(member.contributionScore),
                        member.presence.refreshIdentifier,
                    ])
                }
            }
            .selectionMode(.single)
            .layout(
                .list(
                    itemHeight: .estimated(66),
                    spacing: 8,
                    contentInsets: .init(
                        top: 2,
                        leading: 16,
                        bottom: 24,
                        trailing: 16
                    )
                )
            )
        }
    }

    /// 创建适用于观众列表的全宽纵向组合布局。
    private func makeAudienceListLayout()
        -> UICollectionViewCompositionalLayout {
        adapter.makeCompositionalLayout(
            configuration: ListCompositionalLayoutConfiguration(
                scrollDirection: .vertical,
                interSectionSpacing: 0,
                contentInsetsReference: .none
            )
        )
    }
}

private extension AudienceMember.Presence {
    /// 表示当前在麦状态的内容标识，用于触发列表条目刷新。
    var refreshIdentifier: String {
        switch self {
        case let .onMicrophone(address):
            return "microphone-\(address.roomSide.rawValue)-\(address.position.rawValue)"
        case .listening:
            return "listening"
        }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("在线用户 Sheet") {
    AudienceSheetViewController(
        viewModel: AudienceSheetViewModel(
            totalCount: 1_280,
            members: VoiceRoomPreviewData.audienceMembers
        )
    )
}
#endif
