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
    // ListKit 的 apply completion 可能晚于下一次语言切换返回。
    // 只允许最新一代 snapshot 在完成后继续调整方向和布局。
    private var renderGeneration = 0

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
        MessageCollectionDirectionDiagnostics.logCollection(
            "controller.reloadDirection.begin",
            collectionView: collectionView,
            note: "requested=\(direction.diagnosticName) generation=\(renderGeneration)"
        )
        super.reloadLayoutDirection(direction)
        // 控制器负责把方向同步给真正管理 reusable view 的 collection。
        // semantic 不会复制给已物化的子节点；compositional layout 又会缓存
        // 方向相关的私有坐标映射，所以方向改变时必须同时重建 layout 实例。
        refreshCollectionLayoutDirection(direction)
        MessageCollectionDirectionDiagnostics.logCollection(
            "controller.reloadDirection.afterApply",
            collectionView: collectionView,
            note: "requested=\(direction.diagnosticName) generation=\(renderGeneration)"
        )

        let generation = renderGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MessageCollectionDirectionDiagnostics.logCollection(
                "controller.reloadDirection.nextRunLoop",
                collectionView: self.collectionView,
                note: "requested=\(direction.diagnosticName) capturedGeneration=\(generation) currentGeneration=\(self.renderGeneration)"
            )
        }
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
        renderGeneration &+= 1
        let generation = renderGeneration
        MessageCollectionDirectionDiagnostics.logCollection(
            "controller.render.begin",
            collectionView: collectionView,
            note: "generation=\(generation) items=\(state.items.count) locale=\(DemoLocalization.localizationController.currentLocale.identifier)"
        )

        adapter.apply(
            transaction: .disabled,
            completion: { [weak self] _ in
                // 语言可能在异步 apply 期间再次变化，过期 completion 不能
                // 用旧 snapshot 的时序覆盖当前方向。
                guard let self, self.renderGeneration == generation else {
                    if let self {
                        MessageCollectionDirectionDiagnostics.logCollection(
                            "controller.render.staleCompletion",
                            collectionView: self.collectionView,
                            note: "completionGeneration=\(generation) currentGeneration=\(self.renderGeneration)"
                        )
                    }
                    return
                }
                MessageCollectionDirectionDiagnostics.logCollection(
                    "controller.render.completion.beforeRefresh",
                    collectionView: self.collectionView,
                    note: "generation=\(generation)"
                )
                self.refreshMaterializedContentLayoutDirection()
                MessageCollectionDirectionDiagnostics.logCollection(
                    "controller.render.completion.afterRefresh",
                    collectionView: self.collectionView,
                    note: "generation=\(generation)"
                )

                DispatchQueue.main.async { [weak self] in
                    guard let self, self.renderGeneration == generation else {
                        return
                    }
                    MessageCollectionDirectionDiagnostics.logCollection(
                        "controller.render.completion.nextRunLoop",
                        collectionView: self.collectionView,
                        note: "generation=\(generation)"
                    )
                }
            }
        ) {
            ListSection(.messages) {
                ForEach(state.items, id: \.id) { item in
                    Row(model: item.model, cell: MessageCell.self) {
                        cell, message, _ in
                        cell.configure(message)
                    }
                    // Item identity 在切换语言时保持稳定；把影响内容和
                    // self-sizing 高度的值放进 refreshID，驱动可见 cell 重配。
                    .refreshID([
                        item.model.title,
                        item.model.message,
                        item.model.imageName,
                    ])
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
            MessageCollectionDirectionDiagnostics.logCollection(
                "controller.refreshMaterialized.skipped",
                collectionView: collectionView,
                note: "window=nil and semantic=unspecified"
            )
            return
        }
        MessageCollectionDirectionDiagnostics.logCollection(
            "controller.refreshMaterialized.beforeLayout",
            collectionView: collectionView
        )
        // snapshot 完成后 cell 可能刚创建或刚复用。先物化当前布局，再按
        // collection 的 effective direction 失效布局，让框架同步实际 host。
        collectionView.layoutIfNeeded()
        MessageCollectionDirectionDiagnostics.logCollection(
            "controller.refreshMaterialized.afterLayout",
            collectionView: collectionView
        )
        refreshCollectionLayoutDirection(
            collectionView.effectiveUserInterfaceLayoutDirection
        )
        MessageCollectionDirectionDiagnostics.logCollection(
            "controller.refreshMaterialized.afterApply",
            collectionView: collectionView
        )
    }

    private func refreshCollectionLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        guard let collectionView else { return }
        let attribute = direction.appLayoutDirection.semanticContentAttribute
        let directionChanged = collectionView.semanticContentAttribute
            != attribute

        collectionView.semanticContentAttribute = attribute
        if directionChanged {
            // 单纯 invalidate 原 compositional layout 不会清除 UICollectionView
            // 已缓存的 RTL counter-mirroring；换一个 layout 实例才能重置映射。
            collectionView.setCollectionViewLayout(
                adapter.makeCompositionalLayout(),
                animated: false
            )
        } else {
            collectionView.collectionViewLayout.invalidateLayout()
        }
        collectionView.setNeedsLayout()
        collectionView.layoutIfNeeded()
    }
}


#Preview {
    UINavigationController(rootViewController: MesssageViewController())
}
