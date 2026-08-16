//
//  MessageTableViews.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import UIKit
import AppLocalization
import ListKit
import QuickLayout
import QuickLayoutKit

final class MessageTableListView: UIView {

    let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private lazy var adapter = TableListAdapter<MessageListSection>(
        tableView: tableView
    )
    private var renderGeneration = 0

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
        footerTitle: String,
        completion: (() -> Void)? = nil
    ) {
        renderGeneration &+= 1
        let generation = renderGeneration

        adapter.apply(
            transaction: .disabled,
            completion: { [weak self] summary in
                guard let self else {
                    completion?()
                    return
                }
                guard self.renderGeneration == generation else {
                    completion?()
                    return
                }

                self.refreshMaterializedContentLayoutDirection()
                if summary.visibleSupplementaryRefreshCount > 0,
                   !summary.animation.layoutInvalidated {
                    self.refreshAutomaticSectionLayoutPreservingVisibleRow()
                }
                completion?()
            }
        ) {
            TableSection(.messages) {
                TableForEach(items, id: \.id) { item in
                    TableRow(
                        model: item.model,
                        cell: MessageTableCell.self
                    ) { cell, message, _ in
                        cell.configure(message)
                    }
                    .refreshID([
                        item.model.title,
                        item.model.message,
                        item.model.imageName,
                    ])
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
                .refreshID([headerTitle, headerDetail])
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
                .refreshID([footerTitle])
                .height(.automatic(estimated: 48))
            }
            .selectionMode(.single)
        }
    }

    func applyLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        tableView.applyUserInterfaceLayoutDirection(
            direction.appLayoutDirection,
            preservingVisibleRow: true
        )
    }

    private func refreshMaterializedContentLayoutDirection() {
        guard tableView.window != nil
                || tableView.semanticContentAttribute != .unspecified else {
            return
        }
        tableView.layoutIfNeeded()
        tableView.applyUserInterfaceLayoutDirection(
            tableView.effectiveUserInterfaceLayoutDirection
                .appLayoutDirection,
            preservingVisibleRow: true
        )
    }

    private func refreshAutomaticSectionLayoutPreservingVisibleRow() {
        let minimumOffsetY = -tableView.adjustedContentInset.top
        let maximumOffsetY = max(
            minimumOffsetY,
            tableView.contentSize.height
                - tableView.bounds.height
                + tableView.adjustedContentInset.bottom
        )
        let wasAtTop = tableView.contentOffset.y <= minimumOffsetY + 1
        let wasAtBottom = tableView.contentOffset.y >= maximumOffsetY - 1
        let visibleRowAnchor = tableView.indexPathsForVisibleRows?
            .sorted()
            .first
            .map {
                (
                    indexPath: $0,
                    offsetFromViewportTop: tableView.rectForRow(at: $0).minY
                        - tableView.contentOffset.y
                )
            }

        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
            tableView.layoutIfNeeded()

            let updatedMinimumOffsetY = -tableView.adjustedContentInset.top
            let updatedMaximumOffsetY = max(
                updatedMinimumOffsetY,
                tableView.contentSize.height
                    - tableView.bounds.height
                    + tableView.adjustedContentInset.bottom
            )
            let proposedOffsetY: CGFloat
            if wasAtTop {
                proposedOffsetY = updatedMinimumOffsetY
            } else if wasAtBottom {
                proposedOffsetY = updatedMaximumOffsetY
            } else if let visibleRowAnchor,
                      visibleRowAnchor.indexPath.section < tableView.numberOfSections,
                      visibleRowAnchor.indexPath.row < tableView.numberOfRows(
                        inSection: visibleRowAnchor.indexPath.section
                      ) {
                proposedOffsetY = tableView.rectForRow(
                    at: visibleRowAnchor.indexPath
                ).minY - visibleRowAnchor.offsetFromViewportTop
            } else {
                proposedOffsetY = tableView.contentOffset.y
            }

            var restoredOffset = tableView.contentOffset
            restoredOffset.y = min(
                max(proposedOffsetY, updatedMinimumOffsetY),
                updatedMaximumOffsetY
            )
            tableView.setContentOffset(restoredOffset, animated: false)
        }
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

final class MessageSectionContentView: QuickLayoutView {

    let titleLabel = UILabel()
    let detailLabel = UILabel()

    private var role: MessageSectionContentRole = .header

    override var body: Layout {
        VStack(alignment: .leading, spacing: 3) {
            titleLabel
            detailLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, role == .header ? 10 : 8)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String,
        detail: String?,
        role: MessageSectionContentRole
    ) {
        self.role = role
        titleLabel.text = title
        detailLabel.text = detail

        switch role {
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

        backgroundColor = .clear
        setNeedsQuickLayout()
    }

    func reset() {
        role = .header
        titleLabel.text = nil
        detailLabel.text = nil
        backgroundColor = .clear
        setNeedsQuickLayout()
    }
}

final class MessageTableCell: QuickLayoutTableViewCell {

    let messageContentView = MessageContentView(frame: .zero)

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            updateVisualState()
        }
    }

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            updateVisualState()
        }
    }

    override var body: Layout {
        messageContentView
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    override init(
        style: UITableViewCell.CellStyle,
        reuseIdentifier: String?
    ) {
        super.init(
            style: style,
            reuseIdentifier: reuseIdentifier
        )
        selectionStyle = .none
        updateVisualState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: MessageModel) {
        messageContentView.configure(model)
        setNeedsQuickLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        messageContentView.reset()
        isHighlighted = false
        isSelected = false
        updateVisualState()
    }

    private func updateVisualState() {
        contentView.backgroundColor = isSelected
            ? .tertiarySystemGroupedBackground
            : .secondarySystemGroupedBackground
        messageContentView.alpha = isHighlighted || isSelected ? 0.72 : 1
    }
}

final class MessageTableHeaderFooterView:
    QuickLayoutTableViewHeaderFooterView {

    let sectionContentView = MessageSectionContentView(frame: .zero)

    override var body: Layout {
        sectionContentView
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        let backgroundView = UIView()
        backgroundView.backgroundColor = .clear
        self.backgroundView = backgroundView
        contentView.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String,
        detail: String?,
        role: MessageSectionContentRole
    ) {
        sectionContentView.configure(
            title: title,
            detail: detail,
            role: role
        )
        setNeedsQuickLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        sectionContentView.reset()
        setNeedsQuickLayout()
    }
}
