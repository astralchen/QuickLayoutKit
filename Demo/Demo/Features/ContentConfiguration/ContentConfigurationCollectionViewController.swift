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
    private var collectionLayoutDirection: UIUserInterfaceLayoutDirection?


    override var localizedTitleKey: String? { "demo.contentConfiguration.collection.title" }

    private var collectionView: UICollectionView!
    private let viewModel: ContentConfigurationListViewModel
    private lazy var adapter = CollectionListAdapter<ContentConfigurationListSection>(
        collectionView: collectionView
    )

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
        // 页面拥有组合布局，在方向改变时重建其缓存；复用内容由 UIKit 管理。
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
        adapter.apply(transaction: .disabled) {
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
            } supplementaries: {
                if let title = state.headerTitle {
                    SectionSupplementary(
                        ContentConfigurationCollectionHeaderFooterView.self,
                        kind: UICollectionView.elementKindSectionHeader,
                        elementID: "content-configuration-header"
                    ) { header, _ in
                        header.configure(
                            title: title,
                            detail: state.headerDetail,
                            role: .header
                        )
                    }
                    .refreshID([title, state.headerDetail])
                }
                if let title = state.footerTitle {
                    SectionSupplementary(
                        ContentConfigurationCollectionHeaderFooterView.self,
                        kind: UICollectionView.elementKindSectionFooter,
                        elementID: "content-configuration-footer"
                    ) { footer, _ in
                        footer.configure(title: title, detail: nil, role: .footer)
                    }
                    .refreshID(title)
                }
            }
            .selectionMode(.single)
            .layout {
                GridLayout(tracks: 1)
                    .itemMainAxisSize(.estimated(80))
                    .lineSpacing(8)
                    .sectionInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .boundarySupplementaries {
                        BoundarySupplementaryLayout(
                            kind: UICollectionView.elementKindSectionHeader,
                            size: .init(width: .fractionalWidth(1), height: .estimated(64)),
                            alignment: .top
                        )
                        .whenContentExists()
                        BoundarySupplementaryLayout(
                            kind: UICollectionView.elementKindSectionFooter,
                            size: .init(width: .fractionalWidth(1), height: .estimated(48)),
                            alignment: .bottom
                        )
                        .whenContentExists()
                    }
            }
        }
    }

    private func applyCollectionLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        guard let collectionView else { return }
        let changed = collectionLayoutDirection != direction
        collectionLayoutDirection = direction
        if changed {
            let offset = collectionView.contentOffset
            collectionView.setCollectionViewLayout(adapter.makeCompositionalLayout(), animated: false)
            collectionView.layoutIfNeeded()
            collectionView.setContentOffset(offset, animated: false)
        } else {
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }
}


@available(iOS 17.0, *)
#Preview {
    UINavigationController(rootViewController: ContentConfigurationCollectionViewController())
}
