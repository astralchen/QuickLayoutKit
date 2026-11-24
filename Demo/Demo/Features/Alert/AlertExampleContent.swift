import AppLocalization
import ListKit
import QuickLayoutKit
import UIKit

@MainActor
final class AlertExampleContent: UIViewController {
    private let content: UIView

    init(_ content: UIView, height: CGFloat? = nil) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        if let height { preferredContentSize.height = height }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() { view = content }
}

@available(iOS 16, *)
@MainActor
final class AlertExampleCalendar: QuickLayoutHostingController, UICalendarSelectionSingleDateDelegate {
    private static let topInset: CGFloat = 8
    private let calendar = Calendar(identifier: .gregorian)
    private let calendarView = UICalendarView()
    private(set) lazy var selectedDate = calendar.startOfDay(for: .now)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        calendarView.calendar = calendar
        calendarView.locale = Localization.localizationController.locale
        calendarView.fontDesign = .rounded
        calendarView.accessibilityIdentifier = "alerts.calendar.header"
        let selection = UICalendarSelectionSingleDate(delegate: self)
        calendarView.selectionBehavior = selection
        selection.setSelected(calendar.dateComponents([.year, .month, .day], from: selectedDate), animated: false)
        updatePreferredHeight()
    }

    override var body: Layout {
        GeometryReader { [calendarView] geometry in
            // 紧凑 Popover 优先收缩外侧留白，保留日历所需的 220 pt。
            calendarView.resizable()
                .frame(width: max(220, geometry.size.width - 24))
                .frame(width: geometry.size.width)
                .padding(.top, Self.topInset)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreferredHeight()
    }

    private func updatePreferredHeight() {
        let calendarHeight = calendarView.intrinsicContentSize.height
        guard calendarHeight > 0 else { return }
        let height = ceil(calendarHeight) + Self.topInset
        if preferredContentSize.height != height { preferredContentSize.height = height }
    }

    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
        if let dateComponents, let date = calendar.date(from: dateComponents) { selectedDate = date }
    }
}

@MainActor
final class AlertExampleFields: UIViewController, UITextFieldDelegate {
    private final class FieldIconView: QuickLayoutView {
        private static let iconSize = CGSize(width: 38, height: 28)
        private let imageView: UIImageView

        init(symbol: String) {
            imageView = UIImageView(image: UIImage(systemName: symbol))
            super.init(frame: CGRect(origin: .zero, size: Self.iconSize))
            isUserInteractionEnabled = false
            imageView.tintColor = .secondaryLabel
            imageView.contentMode = .center
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override var body: Layout { imageView.resizable() }
        override var intrinsicContentSize: CGSize { Self.iconSize }
        override func sizeThatFits(_ size: CGSize) -> CGSize { Self.iconSize }
    }

    private let login: Bool
    private let usesPopover: Bool
    private let report: (String) -> Void
    private var fields: [UITextField] = []
    private var fieldCount: Int { login ? 2 : 1 }

    init(login: Bool, usesPopover: Bool, report: @escaping (String) -> Void) {
        self.login = login
        self.usesPopover = usesPopover
        self.report = report
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        fields = (0..<fieldCount).map { index in
            let field = LocalizedTextField()
            configure(field, at: index)
            if #available(iOS 26, *) {
                field.borderStyle = .none
            } else {
                field.borderStyle = .roundedRect
            }
            configureIcon(for: field, at: index)
            return field
        }

        if #available(iOS 26, *) {
            // Popover 在标题下只预留 2 pt，补足到 Alert 的 16 pt。
            let topInset: CGFloat = usesPopover ? 14 : 0
            let divider = UIView()
            divider.backgroundColor = .separator
            let form = QuickLayoutView { [fields, login] in
                VStack(spacing: 0) {
                    fields[0].resizable().frame(height: 44)
                    if login {
                        GeometryReader { geometry in
                            divider.resizable()
                                .frame(width: geometry.size.width * 0.88)
                                .frame(width: geometry.size.width)
                        }
                        .frame(height: 1)
                        fields[1].resizable().frame(height: 44)
                    }
                }
            }
            form.backgroundColor = .tertiarySystemFill
            form.layer.cornerRadius = 12
            form.layer.cornerCurve = .continuous
            let height: CGFloat = login ? 89 : 44
            view = QuickLayoutView {
                form.resizable(axis: .horizontal)
                    .frame(height: height)
                    .padding(.horizontal, 16)
                    .padding(.top, topInset)
            }
            preferredContentSize.height = height + topInset
        } else {
            view = QuickLayoutView { [fields] in
                VStack(spacing: 8) {
                    for field in fields {
                        field.resizable().frame(height: 44)
                    }
                }
            }
            preferredContentSize.height = login ? 96 : 44
        }
    }

    func prepareForNativeActionSheet(panelWidth: CGFloat) {
        loadViewIfNeeded()
        preferredContentSize.width = panelWidth
        // UIKit 可能按内容的压缩尺寸布局。让首轮测量即可使用面板宽度。
        let width = view.widthAnchor.constraint(equalToConstant: panelWidth)
        width.priority = UILayoutPriority(999)
        width.isActive = true
    }

    func addTextFields(to alert: AlertController) {
        for index in 0..<fieldCount {
            alert.addTextField { field in self.configure(field, at: index) }
        }
        fields = alert.textFields ?? []
    }

    func addNativeTextFields(to alert: UIAlertController) {
        for index in 0..<fieldCount {
            alert.addTextField { field in self.configure(field, at: index) }
        }
        fields = alert.textFields ?? []
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        focusFirstFieldIfNeeded()
    }

    func focusFirstFieldIfNeeded() {
        if !fields.contains(where: \.isFirstResponder) { fields.first?.becomeFirstResponder() }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === fields.first, fields.count > 1 {
            fields.last?.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
            report(result)
        }
        return false
    }

    var result: String {
        let account = fields.first?.text ?? ""
        if !login { return account.isEmpty ? Localization.text("demo.alertExamples.field.empty") : account }
        let length = fields.last?.text?.count ?? 0
        return Localization.text("demo.alertExamples.field.loginResult", account, length)
    }

    private func configure(_ field: UITextField, at index: Int) {
        let isPassword = index > 0
        if !(field is LocalizedTextField) {
            field.textAlignment = Localization.currentUIKitDirection == .rightToLeft ? .right : .left
        }
        field.placeholder = isPassword ? Localization.text("demo.alertExamples.field.password") : (login ? Localization.text("demo.alertExamples.field.account") : Localization.text("demo.alertExamples.field.placeholder"))
        field.accessibilityIdentifier = isPassword ? "alerts.field.password" : "alerts.field.first"
        field.isSecureTextEntry = isPassword
        if login { field.textContentType = isPassword ? .password : .username }
        field.returnKeyType = login && !isPassword ? .next : .done
        field.clearButtonMode = .whileEditing
        field.autocapitalizationType = .none
        field.delegate = self
    }

    private func configureIcon(for field: UITextField, at index: Int) {
        let symbol = index > 0 ? "lock" : (login ? "person" : "pencil")
        // UITextField 会随界面方向将 leftView 放在前缘。
        field.leftView = FieldIconView(symbol: symbol)
        field.leftViewMode = .always
    }
}

@MainActor
final class AlertExampleWheel: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    private let heights = Array(150...300)
    private let initialHeight = 216
    private let report: (String) -> Void
    var selection: Int { heights[wheel.selectedRow(inComponent: 0)] }

    private lazy var wheel: UIPickerView = {
        let wheel = UIPickerView()
        wheel.dataSource = self
        wheel.delegate = self
        wheel.accessibilityIdentifier = "alerts.height.wheel"
        return wheel
    }()

    init(report: @escaping (String) -> Void) {
        self.report = report
        super.init(nibName: nil, bundle: nil)
        preferredContentSize.height = CGFloat(initialHeight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = wheel
        wheel.selectRow(initialHeight - heights[0], inComponent: 0, animated: false)
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { heights.count }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        Localization.text("demo.alertExamples.height.row", heights[row])
    }
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        preferredContentSize.height = CGFloat(heights[row])
        report(Localization.text("demo.alertExamples.height.result", heights[row]))
    }
}

@MainActor
final class AlertExampleList: QuickLayoutHostingController, UISearchBarDelegate {
    private final class TableHost: UIView {
        let table = UITableView(frame: .zero, style: .plain)

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                table.removeFromSuperview()
            } else if table.superview == nil {
                table.frame = bounds
                table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                addSubview(table)
            }
        }
    }

    struct Row: Hashable, Sendable {
        let id: String
        let title: String
        let detail: String?
        var result: String { detail.map { "\(title) · \($0)" } ?? title }
    }

    private var rows: [Row]
    var loadOnAppearance: (() -> Void)?
    private let select: (Row) -> Void
    private let search = UISearchBar()
    private let tableHost = TableHost()
    private var table: UITableView { tableHost.table }
    private lazy var adapter = TableListAdapter<Int>(tableView: table)
    private let status = LocalizedLabel()
    private var pendingQuery: String?

    init(rows: [Row] = [], select: @escaping (Row) -> Void) {
        self.rows = rows
        self.select = select
        super.init(nibName: nil, bundle: nil)
        preferredContentSize.height = 264
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        search.placeholder = Localization.text("demo.alertExamples.list.search")
        search.searchBarStyle = .minimal
        search.delegate = self
        search.accessibilityIdentifier = "alerts.picker.search"
        search.searchTextField.accessibilityIdentifier = "alerts.picker.searchField"
        table.keyboardDismissMode = .onDrag
        table.accessibilityIdentifier = "alerts.picker.list"
        // 列表没有分区标题或页脚，避免默认的浮动页脚遮住底部货币行。
        table.sectionHeaderTopPadding = 0
        table.sectionHeaderHeight = .leastNormalMagnitude
        table.estimatedSectionHeaderHeight = 0
        table.sectionFooterHeight = .leastNormalMagnitude
        table.estimatedSectionFooterHeight = 0
        if #available(iOS 26, *) {
            // 列表和搜索栏共用宿主面板底色，避免出现一块独立的白底。
            table.backgroundColor = .clear
        }
        status.font = .preferredFont(forTextStyle: .footnote)
        status.numberOfLines = 0
        status.textColor = .secondaryLabel
        status.isHidden = status.text == nil
        applyFilter(search.text ?? "")
    }

    override var body: Layout {
        VStack(spacing: 0) {
            search.resizable().frame(height: 44)
            if !status.isHidden { status.resizable(axis: .horizontal) }
            tableHost.resizable()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyPendingFilter()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let load = loadOnAppearance
        loadOnAppearance = nil
        load?()
    }

    func setRows(_ rows: [Row], message: String? = nil) {
        self.rows = rows
        status.text = message
        guard isViewLoaded else { return }
        status.isHidden = message == nil
        setNeedsQuickLayout()
        applyFilter(search.text ?? "")
    }

    private func applyFilter(_ query: String) {
        pendingQuery = query
        applyPendingFilter()
    }

    private func applyPendingFilter() {
        guard table.window != nil, let query = pendingQuery else { return }
        pendingQuery = nil
        let filtered = query.isEmpty ? rows : rows.filter { $0.result.localizedStandardContains(query) }
        adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableForEach(filtered, id: \.id) { row in
                    TableRow(model: row, cell: UITableViewCell.self) { cell, row, _ in
                        if #available(iOS 26, *) { cell.backgroundColor = .clear }
                        var content = UIListContentConfiguration.subtitleCell()
                        content.text = row.title
                        content.secondaryText = row.detail
                        // Popover 转场结束前继承的边距可能为 0，首帧就使用列表的水平内边距。
                        content.directionalLayoutMargins.leading = 16
                        content.directionalLayoutMargins.trailing = 16
                        cell.contentConfiguration = content
                    }
                    .refreshID(row)
                    .onSelect { [weak self] row, context in
                        context.tableView.deselectRow(at: context.indexPath, animated: true)
                        self?.select(row)
                    }
                }
            }
            .selectionMode(.single)
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { applyFilter(searchText) }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("登录表单") {
    AlertExamplesViewController.preview(.login)
}

@available(iOS 17.0, *)
#Preview("国家搜索") {
    AlertExamplesViewController.preview(.country)
}

@available(iOS 17.0, *)
#Preview("日历 Action Sheet · QuickLayoutKit") {
    AlertExamplesViewController.preview(.calendar, style: .actionSheet)
}

@available(iOS 17.0, *)
#Preview("日历 Action Sheet · UIKit") {
    AlertExamplesViewController.preview(.calendar, style: .actionSheet, useUIKit: true)
}
#endif
