//
//  ContentConfigurationTableViewController.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import UIKit
import AppLocalization

final class ContentConfigurationTableViewController: LocalizedViewController {

    override var localizedTitleKey: String? {
        "demo.contentConfiguration.table.title"
    }

    private let contentView = ContentConfigurationTableListView()
    private let viewModel: ContentConfigurationListViewModel

    var tableView: UITableView? {
        isViewLoaded ? contentView.tableView : nil
    }

    convenience init() {
        self.init(viewModel: ContentConfigurationListViewModel(configuration: .table))
    }

    init(viewModel: ContentConfigurationListViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = ContentConfigurationListViewModel(configuration: .table)
        super.init(coder: coder)
    }

    override func loadView() {
        view = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindViewModel()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        viewModel.refreshLocalizedContent()
    }

    private func bindViewModel() {
        viewModel.bind { [weak self] state in
            self?.render(state)
        }
    }

    private func render(_ state: ContentConfigurationListViewModel.State) {
        guard
            let headerTitle = state.headerTitle,
            let headerDetail = state.headerDetail,
            let footerTitle = state.footerTitle
        else {
            assertionFailure("The table content configuration example requires header and footer content")
            return
        }

        contentView.render(
            items: state.items,
            headerTitle: headerTitle,
            headerDetail: headerDetail,
            footerTitle: footerTitle
        )
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        // Controller 只负责建立容器方向边界；已物化和复用视图的同步、
        // 自动高度刷新与可见行锚点由 ContentConfigurationTableListView 统一处理。
        contentView.applyLayoutDirection(direction)
    }

}

#Preview {
    UINavigationController(rootViewController: ContentConfigurationTableViewController())
}
