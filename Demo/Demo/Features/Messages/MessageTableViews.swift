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
    // 防止较早一次语言刷新晚完成后，重新调整已经进入新语言的列表。
    private var renderGeneration = 0
    // ListKit 的异步 apply completion 必须沿用 Controller 最近一次明确应用的
    // 方向；测试、局部容器以及未来 Scene provider 都不能被全局当前值覆盖。
    private var lastAppliedLayoutDirection: UIUserInterfaceLayoutDirection?

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
        let expectedRevision = DemoLocalization.localizationController
            .currentSnapshot.revision

        adapter.apply(
            transaction: .disabled,
            completion: { [weak self] summary in
                guard let self else {
                    completion?()
                    return
                }
                guard self.renderGeneration == generation,
                      expectedRevision == DemoLocalization.localizationController
                        .currentSnapshot.revision else {
                    completion?()
                    return
                }

                // apply 完成时 header/footer/cell 可能刚被创建或复用，必须在
                // 最终视图集合上再次同步当前 table 方向。
                self.refreshMaterializedContentLayoutDirection()
                if summary.refreshMetrics
                    .visibleReconfiguredSupplementaryCount > 0,
                   !summary.animation.layoutInvalidated {
                    // 可见 supplementary 已重配但 adapter 没有失效布局时，
                    // 主动触发自动高度计算，并在前后保持同一可见行锚点。
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
                    // 行 identity 不随语言变化，文案参与 refreshID 才能让
                    // 已显示的 self-sizing cell 重新配置并测量高度。
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
                // Header identity 固定，标题和详情负责触发内容与高度刷新。
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
                // Footer 文案变化同样需要重新配置和 self-sizing。
                .refreshID([footerTitle])
                .height(.automatic(estimated: 48))
            }
            .selectionMode(.single)
        }
    }

    func applyLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        lastAppliedLayoutDirection = direction
        // 方向边界由 table 容器控制，同时保留用户当前看到的逻辑行。
        tableView.applyLocalization(
            DemoLocalization.layoutDirectionUpdate(direction),
            preservingVisibleRow: true
        )
    }

    private func refreshMaterializedContentLayoutDirection() {
        guard tableView.window != nil
                || tableView.semanticContentAttribute != .unspecified else {
            return
        }
        // 等待 snapshot 后新增/复用的视图物化，再用 table 当前的最终方向
        // 统一触发 reusable host 和自动尺寸布局刷新。
        tableView.layoutIfNeeded()
        let direction = lastAppliedLayoutDirection
            ?? tableView.effectiveUserInterfaceLayoutDirection
        tableView.applyLocalization(
            DemoLocalization.layoutDirectionUpdate(
                direction,
                reasons: [.layoutDirection, .configuration]
            ),
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

    // Cell/contentView 由框架默认同步；把真正执行 QuickLayout 的内部 host
    // 一并声明，确保复用后的 cell 不携带上一次语言方向。
    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [messageContentView]
    }

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
        ZStack {
            messageContentView
        }
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

    // Header/footer 的 contentView、QuickLayout host 和文本叶子都可能来自
    // 复用池；显式列出后由 table 的最终 effective direction 一次同步。
    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [
            sectionContentView,
            sectionContentView.titleLabel,
            sectionContentView.detailLabel,
        ]
    }

    override var body: Layout {
        ZStack {
            sectionContentView
        }
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
