//
//  LiveRoomSeatCollectionDataSource.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import UIKit

/// 集中管理麦位 CollectionView 的注册、Diffable Snapshot 与 Cell 查询。
///
/// Item 内容仍由 Stage 持有；该对象只处理 UIKit 数据源生命周期，避免布局和
/// 场景转场代码依赖 `IndexPath` 或重复创建 Registration。
@MainActor
final class LiveRoomSeatCollectionDataSource {

    private nonisolated enum Section: Hashable, Sendable {
        case seats
    }

    private let collectionView: UICollectionView
    private var dataSource: UICollectionViewDiffableDataSource<
        Section,
        LiveRoomSeatCollectionItemID
    >!
    private var cellRegistration: UICollectionView.CellRegistration<
        LiveRoomSeatCollectionCell,
        LiveRoomSeatCollectionItemID
    >!

    init(
        collectionView: UICollectionView,
        itemProvider: @escaping (LiveRoomSeatCollectionItemID)
            -> LiveRoomSeatCollectionItem?,
        metricsProvider: @escaping () -> LiveRoomSeatLayoutMetrics,
        seatDidSelect: @escaping (LiveRoomSeatAssignment) -> Void
    ) {
        self.collectionView = collectionView

        // Registration 必须在 DataSource 首次请求 Cell 之前创建。若在 cell provider
        // 内惰性创建，UIKit 会把它视为在 cellForItemAtIndexPath 中创建并触发断言。
        let registration = UICollectionView.CellRegistration<
            LiveRoomSeatCollectionCell,
            LiveRoomSeatCollectionItemID
        > { cell, _, itemID in
            guard let item = itemProvider(itemID) else { return }
            cell.configure(
                item: item,
                metrics: metricsProvider(),
                seatDidSelect: seatDidSelect
            )
        }
        cellRegistration = registration
        dataSource = UICollectionViewDiffableDataSource(
            collectionView: collectionView
        ) { collectionView, indexPath, itemID in
            collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: itemID
            )
        }
    }

    func applySnapshot(
        itemIDs: [LiveRoomSeatCollectionItemID],
        reconfigureExisting: Bool = false
    ) {
        var snapshot = NSDiffableDataSourceSnapshot<
            Section,
            LiveRoomSeatCollectionItemID
        >()
        snapshot.appendSections([.seats])
        snapshot.appendItems(itemIDs, toSection: .seats)
        if reconfigureExisting {
            let existing = Set(dataSource.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(itemIDs.filter(existing.contains))
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func cell(
        for itemID: LiveRoomSeatCollectionItemID
    ) -> LiveRoomSeatCollectionCell? {
        guard let indexPath = dataSource.indexPath(for: itemID) else {
            return nil
        }
        collectionView.layoutIfNeeded()
        return collectionView.cellForItem(at: indexPath)
            as? LiveRoomSeatCollectionCell
    }
}
