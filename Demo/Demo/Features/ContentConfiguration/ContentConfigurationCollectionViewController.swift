//
//  ContentConfigurationCollectionViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/17.
//

import UIKit
import AppLocalization
import ListKit

final class ContentConfigurationCollectionViewController: LocalizedViewController {

    override var localizedTitleKey: String? { "demo.contentConfiguration.collection.title" }

    private var collectionView: UICollectionView!
    private let viewModel: ContentConfigurationListViewModel
    private lazy var adapter = CollectionListAdapter<ContentConfigurationListSection>(
        collectionView: collectionView
    )
    // ListKit 的 apply completion 可能晚于下一次语言切换返回。
    // 只允许最新一代 snapshot 在完成后继续调整方向和布局。
    private var renderGeneration = 0

    convenience init() {
        self.init(
            viewModel: ContentConfigurationListViewModel(configuration: .collection)
        )
    }

    init(viewModel: ContentConfigurationListViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = ContentConfigurationListViewModel(configuration: .collection)
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white
        setupCollectionView()
        bindViewModel()
        reloadLayoutDirection(Localization.currentUIKitDirection)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        viewModel.refreshLocalizedContent()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        // 控制器负责把方向同步给真正管理 reusable view 的 collection。
        // semantic 不会复制给已物化的子节点；compositional layout 又会缓存
        // 方向相关的私有坐标映射。AppLocalization 统一处理方向边界、布局
        // 失效和可见项；页面只提供自己的 compositional layout 工厂。
        applyCollectionLayoutDirection(direction)
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(
            frame: view.bounds,
            collectionViewLayout: UICollectionViewFlowLayout()
        )

        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemGroupedBackground
        view.addSubview(collectionView)
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
    }

    private func bindViewModel() {
        viewModel.bind { [weak self] state in
            self?.render(state)
        }
    }

    private func render(_ state: ContentConfigurationListViewModel.State) {
        renderGeneration &+= 1
        let generation = renderGeneration
        let expectedRevision = Localization.localizationController
            .currentSnapshot.revision

        adapter.apply(
            transaction: .disabled,
            completion: { [weak self] _ in
                // 语言可能在异步 apply 期间再次变化，过期 completion 不能
                // 用旧 snapshot 的时序覆盖当前方向。
                guard let self,
                      self.renderGeneration == generation,
                      expectedRevision == Localization.localizationController
                        .currentSnapshot.revision else { return }
                self.refreshMaterializedContentLayoutDirection()
            }
        ) {
            ListSection(.content) {
                ForEach(state.items, id: \.id) { item in
                    Row(model: item.model, cell: UICollectionViewListCell.self) {
                        cell, model, _ in
                        cell.backgroundConfiguration = .clear()
                        cell.contentConfiguration = ContentConfigurationView.Configuration(
                            model: model,
                            cornerRadius: 8
                        )
                    }
                    .onSelect { context in
                        context.collectionView.deselectItem(
                            at: context.indexPath,
                            animated: true
                        )
                    }
                    // Item identity 在切换语言时保持稳定；把影响内容和
                    // self-sizing 高度的值放进 refreshID，驱动可见 cell 重配。
                    .refreshID([
                        item.model.title,
                        item.model.detail,
                        item.model.imageName,
                    ])
                }
            } header: {
                if let title = state.headerTitle {
                    Header(
                        ContentConfigurationCollectionHeaderFooterView.self,
                        id: "content-configuration-header"
                    ) { header, _ in
                        header.configure(
                            title: title,
                            detail: state.headerDetail,
                            role: .header
                        )
                    }
                    .refreshID([title, state.headerDetail])
                    .layout(height: .estimated(64), extendsBoundary: true)
                }
            } footer: {
                if let title = state.footerTitle {
                    Footer(
                        ContentConfigurationCollectionHeaderFooterView.self,
                        id: "content-configuration-footer"
                    ) { footer, _ in
                        footer.configure(title: title, detail: nil, role: .footer)
                    }
                    .refreshID(title)
                    .layout(height: .estimated(48), extendsBoundary: true)
                }
            }
            .selectionMode(.single)
            .layout(
                .list(
                    itemHeight: .estimated(80),
                    spacing: 8,
                    contentInsets: .init(
                        top: 8,
                        leading: 12,
                        bottom: 8,
                        trailing: 12
                    )
                )
            )
        }
    }

    private func refreshMaterializedContentLayoutDirection() {
        guard collectionView.window != nil
                || collectionView.semanticContentAttribute != .unspecified else {
            return
        }
        // snapshot 完成后 cell 可能刚创建或刚复用。先物化当前布局，再按
        // collection 的 effective direction 失效布局，让框架同步实际 host。
        collectionView.layoutIfNeeded()
        applyCollectionLayoutDirection(
            collectionView.effectiveUserInterfaceLayoutDirection
        )
    }

    private func applyCollectionLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        guard let collectionView else { return }
        collectionView.applyLocalization(
            Localization.layoutDirectionUpdate(direction),
            preservingVisibleItem: true,
            rebuildingLayoutWith: { [unowned self] in
                adapter.makeCompositionalLayout()
            }
        )
    }
}


#Preview {
    UINavigationController(rootViewController: ContentConfigurationCollectionViewController())
}
