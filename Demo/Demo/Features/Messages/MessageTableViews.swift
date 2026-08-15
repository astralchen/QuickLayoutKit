//
//  MessageTableViews.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import UIKit
import ListKit
import QuickLayout
import QuickLayoutKit

final class MessageTableListView: UIView {

    let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private lazy var adapter = TableListAdapter<MessageListSection>(
        tableView: tableView
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTableView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(
        items: [MessageListItem],
        headerTitle: String,
        headerDetail: String,
        footerTitle: String
    ) {
        adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableForEach(items, id: \.id) { item in
                    TableRow(
                        model: item.model,
                        cell: MessageTableCell.self
                    ) { cell, message, _ in
                        cell.configure(message)
                    }
                    .height(.automatic(estimated: 80))
                }
            } header: {
                TableHeader(
                    MessageTableHeaderFooterView.self,
                    id: "messages-header"
                ) { header, _ in
                    header.configure(
                        title: headerTitle,
                        detail: headerDetail,
                        role: .header
                    )
                }
                .height(.automatic(estimated: 64))
            } footer: {
                TableFooter(
                    MessageTableHeaderFooterView.self,
                    id: "messages-footer"
                ) { footer, _ in
                    footer.configure(
                        title: footerTitle,
                        detail: nil,
                        role: .footer
                    )
                }
                .height(.automatic(estimated: 48))
            }
            .selectionMode(.single)
        }
    }

    func applyLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        semanticContentAttribute = direction == .rightToLeft
            ? .forceRightToLeft
            : .forceLeftToRight
    }

    private func setupTableView() {
        backgroundColor = .systemGroupedBackground
        tableView.frame = bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = .systemGroupedBackground
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 64
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionFooterHeight = 48
        addSubview(tableView)
    }
}

enum MessageSectionContentRole {
    case header
    case footer
}

private struct MessageSectionContentConfiguration: UIContentConfiguration {

    let title: String
    let detail: String?
    let role: MessageSectionContentRole
    private(set) var isPinned = false

    @MainActor
    func makeContentView() -> UIView & UIContentView {
        MessageSectionContentView(configuration: self)
    }

    func updated(
        for state: any UIConfigurationState
    ) -> MessageSectionContentConfiguration {
        guard let state = state as? UIViewConfigurationState else {
            return self
        }
        var configuration = self
        configuration.isPinned = state.isPinned
        return configuration
    }
}

private final class MessageSectionContentView: QuickLayoutView, UIContentView {

    let titleLabel = UILabel()
    let detailLabel = UILabel()

    private var sectionConfiguration: MessageSectionContentConfiguration

    var configuration: any UIContentConfiguration {
        get { sectionConfiguration }
        set {
            guard
                let configuration = newValue
                    as? MessageSectionContentConfiguration
            else {
                assertionFailure(
                    "Unsupported content configuration: \(type(of: newValue))"
                )
                return
            }
            apply(configuration)
        }
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 3) {
            titleLabel
            detailLabel
        }
        .padding(.horizontal, 16)
        .padding(.vertical, sectionConfiguration.role == .header ? 10 : 8)
    }

    init(configuration: MessageSectionContentConfiguration) {
        self.sectionConfiguration = configuration
        super.init(frame: .zero)

        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0
        apply(configuration)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func supports(_ configuration: any UIContentConfiguration) -> Bool {
        configuration is MessageSectionContentConfiguration
    }

    private func apply(
        _ configuration: MessageSectionContentConfiguration
    ) {
        sectionConfiguration = configuration
        titleLabel.text = configuration.title
        detailLabel.text = configuration.detail

        switch configuration.role {
        case .header:
            titleLabel.font = .preferredFont(forTextStyle: .headline)
            titleLabel.textColor = .label
            detailLabel.font = .preferredFont(forTextStyle: .footnote)
            detailLabel.textColor = .secondaryLabel

        case .footer:
            titleLabel.font = .preferredFont(forTextStyle: .footnote)
            titleLabel.textColor = .secondaryLabel
            detailLabel.font = .preferredFont(forTextStyle: .caption1)
            detailLabel.textColor = .tertiaryLabel
        }

        backgroundColor = configuration.isPinned
            ? .secondarySystemGroupedBackground
            : .clear
        setNeedsQuickLayout()
    }
}

final class MessageTableCell: QuickLayoutTableViewCell {

    private var model: MessageModel?

    override init(
        style: UITableViewCell.CellStyle,
        reuseIdentifier: String?
    ) {
        super.init(
            style: style,
            reuseIdentifier: reuseIdentifier,
            contentSource: .contentConfiguration
        )
        automaticallyUpdatesContentConfiguration = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: MessageModel) {
        self.model = model
        setNeedsUpdateConfiguration()
    }

    override func updateConfiguration(
        using state: UICellConfigurationState
    ) {
        guard let model else {
            contentConfiguration = nil
            backgroundConfiguration = nil
            return
        }

        contentConfiguration = MessageContentConfiguration(model: model)
            .updated(for: state)

        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = state.isSelected
            ? .tertiarySystemGroupedBackground
            : .secondarySystemGroupedBackground
        backgroundConfiguration = background
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        model = nil
        contentConfiguration = nil
        backgroundConfiguration = nil
    }
}

final class MessageTableHeaderFooterView: QuickLayoutTableViewHeaderFooterView {

    private var titleText: String?
    private var detailText: String?
    private var role: MessageSectionContentRole = .header

    override init(reuseIdentifier: String?) {
        super.init(
            reuseIdentifier: reuseIdentifier,
            contentSource: .contentConfiguration
        )
        automaticallyUpdatesContentConfiguration = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String,
        detail: String?,
        role: MessageSectionContentRole
    ) {
        titleText = title
        detailText = detail
        self.role = role
        setNeedsUpdateConfiguration()
    }

    override func updateConfiguration(
        using state: UIViewConfigurationState
    ) {
        guard let titleText else {
            contentConfiguration = nil
            backgroundConfiguration = nil
            return
        }

        contentConfiguration = MessageSectionContentConfiguration(
            title: titleText,
            detail: detailText,
            role: role
        ).updated(for: state)
        backgroundConfiguration = .clear()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleText = nil
        detailText = nil
        role = .header
        contentConfiguration = nil
        backgroundConfiguration = nil
    }
}
