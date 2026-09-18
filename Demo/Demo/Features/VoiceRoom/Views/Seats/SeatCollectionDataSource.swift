//
//  SeatCollectionDataSource.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import UIKit

/// 集中管理麦位 CollectionView 的注册、Diffable Snapshot 与 Cell 查询。
///
/// Item 内容仍由 Stage 持有；该对象只处理 UIKit 数据源生命周期，避免布局和
/// 场景转场代码依赖 `IndexPath` 或重复创建 Registration。
@MainActor
final class SeatCollectionDataSource {

    /// 麦位集合视图的数据分区。
    private nonisolated enum Section: Hashable, Sendable {
        /// 包含全部舞台麦位的唯一分区。
        case seats
    }

    /// 负责内容条目展示和复用的集合视图。
    private let collectionView: UICollectionView
    /// 维护稳定条目标识与集合单元格映射的差异化数据源。
    private var dataSource: UICollectionViewDiffableDataSource<
        Section,
        SeatCollectionItemID
    >!
    /// 注册麦位单元格并提供当前数据和尺寸参数的配置器。
    private var cellRegistration: UICollectionView.CellRegistration<
        SeatCollectionCell,
        SeatCollectionItemID
    >!

    /// 将稳定条目数据源连接到指定集合视图。
    ///
    /// 条目和尺寸通过提供者在配置单元格时读取；选择事件交由宿主处理。
    init(
        collectionView: UICollectionView,
        itemProvider: @escaping (SeatCollectionItemID)
            -> SeatCollectionItem?,
        metricsProvider: @escaping () -> SeatLayoutMetrics,
        seatDidSelect: @escaping (SeatAssignment) -> Void
    ) {
        self.collectionView = collectionView

        // Registration 必须在 DataSource 首次请求 Cell 之前创建。若在 cell provider
        // 内惰性创建，UIKit 会把它视为在 cellForItemAtIndexPath 中创建并触发断言。
        let registration = UICollectionView.CellRegistration<
            SeatCollectionCell,
            SeatCollectionItemID
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

    /// 按给定条目顺序提交快照，并可重新配置已有条目。
    func applySnapshot(
        itemIDs: [SeatCollectionItemID],
        reconfigureExisting: Bool = false,
        animated: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        var snapshot = NSDiffableDataSourceSnapshot<
            Section,
            SeatCollectionItemID
        >()
        snapshot.appendSections([.seats])
        snapshot.appendItems(itemIDs, toSection: .seats)
        if reconfigureExisting {
            let existing = Set(dataSource.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(itemIDs.filter(existing.contains))
        }
        dataSource.apply(snapshot, animatingDifferences: animated, completion: completion)
    }

    /// 返回当前 Snapshot 在指定索引路径上的稳定身份，供布局查询几何。
    func itemIdentifier(for indexPath: IndexPath) -> SeatCollectionItemID? {
        dataSource.itemIdentifier(for: indexPath)
    }

    /// 返回指定稳定条目当前已实例化的麦位单元格；不可见时可为 `nil`。
    func cell(
        for itemID: SeatCollectionItemID
    ) -> SeatCollectionCell? {
        guard let indexPath = dataSource.indexPath(for: itemID) else {
            return nil
        }
        collectionView.layoutIfNeeded()
        return collectionView.cellForItem(at: indexPath)
            as? SeatCollectionCell
    }
}
