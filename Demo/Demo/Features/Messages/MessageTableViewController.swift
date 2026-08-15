//
//  MessageTableViewController.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import UIKit
import AppLocalization

final class MessageTableViewController: DemoViewController {

    override var localizedTitleKey: String? {
        "demo.tableMessages.title"
    }

    private let contentView = MessageTableListView()

    var tableView: UITableView? {
        isViewLoaded ? contentView.tableView : nil
    }

    override func loadView() {
        view = contentView
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        guard isViewLoaded else { return }
        contentView.render(
            items: MessageListFactory.localizedItems(repeating: 3),
            headerTitle: DemoLocalization.text(
                "demo.tableMessages.header"
            ),
            headerDetail: DemoLocalization.text(
                "demo.tableMessages.header.detail"
            ),
            footerTitle: DemoLocalization.text(
                "demo.tableMessages.footer"
            )
        )
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        guard isViewLoaded else { return }
        contentView.applyLayoutDirection(direction)
    }

}

#Preview {
    UINavigationController(rootViewController: MessageTableViewController())
}
