//
//  ViewController.swift
//  MessageCell
//
//  Created by Sondra on 2025/12/17.
//

import UIKit
import AppLocalization
import ListKit

final class MesssageViewController: DemoViewController {

    override var localizedTitleKey: String? { "demo.messages.title" }

    private var collectionView: UICollectionView!
    private let viewModel: MessageListViewModel
    private lazy var adapter = CollectionListAdapter<MessageListSection>(
        collectionView: collectionView
    )

    convenience init() {
        self.init(
            viewModel: MessageListViewModel(configuration: .collection)
        )
    }

    init(viewModel: MessageListViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = MessageListViewModel(configuration: .collection)
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white
        setupCollectionView()
        bindViewModel()
        reloadLayoutDirection(DemoLocalization.currentUIKitDirection)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        viewModel.refreshLocalizedContent()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        collectionView?.applyUserInterfaceLayoutDirection(
            direction.appLayoutDirection,
            preservingVisibleItem: false
        )
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

    private func render(_ state: MessageListViewModel.State) {
        adapter.apply(transaction: .disabled) {
            ListSection(.messages) {
                ForEach(state.items, id: \.id) { item in
                    Row(model: item.model, cell: MessageCell.self) {
                        cell, message, _ in
                        cell.configure(message)
                    }
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
}


#Preview {
    UINavigationController(rootViewController: MesssageViewController())
}
