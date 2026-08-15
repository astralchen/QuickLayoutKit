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
    private var data = MessageListFactory.localizedItems()
    private lazy var adapter = CollectionListAdapter<MessageListSection>(
        collectionView: collectionView
    )

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white
        setupCollectionView()
        reloadLocalizedContent()
        reloadLayoutDirection(DemoLocalization.currentUIKitDirection)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        data = MessageListFactory.localizedItems()
        guard collectionView != nil else { return }
        render()
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

    private func render() {
        adapter.apply(transaction: .disabled) {
            ListSection(.messages) {
                ForEach(data, id: \.id) { item in
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
