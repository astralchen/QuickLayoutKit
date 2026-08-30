//
//  LiveRoomAudienceSheetViewController.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import ListKit
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomAudienceSheetViewController:
    DemoQuickLayoutHostingController {

    let viewModel: LiveRoomAudienceViewModel

    var memberCount: Int { viewModel.state.members.count }
    var totalCount: Int { viewModel.state.totalCount }
    var audienceCollectionView: UICollectionView { sheetView.collectionView }
    var memberDidSelect: ((LiveRoomAudienceMember) -> Void)?

    private let sheetView = LiveRoomAudienceSheetView()
    private lazy var adapter = CollectionListAdapter<String>(
        collectionView: sheetView.collectionView
    )
    private var renderGeneration = 0

    init(viewModel: LiveRoomAudienceViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        preferredContentSize = CGSize(width: 540, height: 620)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        configureAudienceList()
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "liveRoom.audience.controller"
        configureSheetPresentation()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIAccessibility.post(
            notification: .screenChanged,
            argument: sheetView
        )
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        sheetView.configure(
            title: DemoLocalization.text("liveRoom.audience.title"),
            summary: DemoLocalization.text(
                "liveRoom.room.audience",
                viewModel.state.totalCount
            ),
            subtitle: DemoLocalization.text("liveRoom.audience.subtitle")
        )
        renderMembers()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        sheetView.semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        sheetView.collectionView.applyLocalization(
            DemoLocalization.layoutDirectionUpdate(direction),
            preservingVisibleItem: true,
            rebuildingLayoutWith: { [unowned self] in
                makeAudienceListLayout()
            }
        )
        sheetView.setNeedsQuickLayout()
    }

    override var body: Layout {
        sheetView.resizable()
    }

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

    private func configureAudienceList() {
        sheetView.collectionView.collectionViewLayout = makeAudienceListLayout()
    }

    private func renderMembers() {
        renderGeneration &+= 1
        let generation = renderGeneration
        adapter.apply(
            transaction: .disabled,
            completion: { [weak self] _ in
                guard let self, generation == renderGeneration else { return }
                // ListKit 完成 diff 后 Cell 才全部物化，再同步当前语言方向和自适应尺寸。
                sheetView.collectionView.applyLocalization(
                    DemoLocalization.layoutDirectionUpdate(
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
                        cell: LiveRoomAudienceMemberCell.self
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

private extension LiveRoomAudienceMember.Presence {
    var refreshIdentifier: String {
        switch self {
        case let .onMicrophone(seatNumber):
            return "microphone-\(seatNumber)"
        case .listening:
            return "listening"
        }
    }
}

#if DEBUG
#Preview("在线用户 Sheet") {
    LiveRoomAudienceSheetViewController(
        viewModel: LiveRoomAudienceViewModel(
            totalCount: 1_280,
            members: LiveRoomPreviewData.audienceMembers
        )
    )
}
#endif
