import AppLocalization
import QuickLayoutKit
import UIKit

/// 系统 sheet 的 Device Poses 示例。内容使用容器宽度，位置与尺寸交给 UIKit。
final class DailyRecordViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.dailyRecord.title" }

    private let scroll = QuickLayoutScrollView()
    private let heading = recordLabel(.title2)
    private let introduction = recordLabel(.subheadline, color: .secondaryLabel)
    private let month = recordLabel(.headline)
    private let summary = RecordSummaryView()
    private let openButton = UIButton(type: .system)
    private var days: [UIButton] = []
    private var recordMonth = DailyRecordMonth()

    override func viewDidLoad() {
        openButton.configuration = .filled()
        openButton.configuration?.image = UIImage(systemName: "calendar")
        openButton.configuration?.imagePadding = 8
        openButton.accessibilityIdentifier = "dailyRecord.open"
        openButton.addAction(UIAction { [weak self] _ in self?.showRecord(date: Date()) }, for: .touchUpInside)
        observeRecordDateChanges(self, selector: #selector(refreshDateContent))
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.accessibilityIdentifier = "dailyRecord.page"
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        heading.text = Localization.text("dailyRecord.activity")
        introduction.text = Localization.text("dailyRecord.introduction")
        recordMonth = DailyRecordMonth()
        month.text = formattedRecordDate(recordMonth.today, template: "yyyyMMMM")
        summary.configure(hasRecord: true)
        openButton.configuration?.title = Localization.text("dailyRecord.open")
        days = recordMonth.dates.map { date in
            let day = recordMonth.calendar.component(.day, from: date)
            let isToday = recordMonth.isToday(date)
            let lunarText = recordMonth.lunarText(for: date)
            let button = UIButton(type: .system)
            button.configuration = isToday ? .filled() : .tinted()
            button.configuration?.title = day.formatted(.number.locale(Localization.localizationController.locale))
            button.configuration?.subtitle = lunarText
            button.configuration?.titleAlignment = .center
            button.configuration?.titlePadding = 2
            button.configuration?.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .preferredFont(forTextStyle: .caption2)
                if !isToday { attributes.foregroundColor = .secondaryLabel }
                return attributes
            }
            button.configuration?.cornerStyle = .medium
            button.configuration?.contentInsets = .init(top: 12, leading: 2, bottom: 12, trailing: 2)
            button.accessibilityIdentifier = "dailyRecord.day.\(day)"
            button.accessibilityLabel = formattedRecordDate(date, template: "yyyyMMMMdEEEE")
                + ", " + Localization.text("dailyRecord.lunarDate", lunarText)
            button.accessibilityValue = Localization.text(isToday ? "dailyRecord.oneRecord" : "dailyRecord.empty")
            button.addAction(UIAction { [weak self] _ in self?.showRecord(date: date) }, for: .touchUpInside)
            return button
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDateContent()
    }

    @objc private func refreshDateContent() {
        guard isViewLoaded else { return }
        reloadLocalizedContent()
    }

    override var body: Layout {
        ScrollView(scroll) {
            VStack(alignment: .leading, spacing: 20) {
                heading
                introduction
                summary.resizable(axis: .horizontal)
                openButton.resizable(axis: .horizontal)
                month
                // 周一为首列；按当月首日补齐空白，所有行共用七列宽度。
                VGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 7),
                    spacing: 8
                ) {
                    for _ in 0..<recordMonth.leadingEmptyDays {
                        Spacer().frame(height: 0)
                    }
                    for day in days {
                        day.resizable(axis: .horizontal)
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    private func showRecord(date: Date) {
        guard presentedViewController == nil else { return }
        let content = DailyRecordSheetViewController(date: date)
        let navigation = UINavigationController(rootViewController: content)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            if #available(iOS 17.0, *) { sheet.prefersPageSizing = true }
            #if compiler(>=6.4)
            // 不设置 sourceView，不计算折痕坐标，也不在姿态变化时重新 present。
            if #available(iOS 27.0, *) { sheet.preferredPlacement = .automatic }
            #endif
        }
        present(navigation, animated: true)
    }
}

final class DailyRecordSheetViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "dailyRecord.sheetTitle" }
    let date: Date
    private var recordMonth = DailyRecordMonth()
    private let scroll = QuickLayoutScrollView()
    private let dateLabel = recordLabel(.title3, color: .secondaryLabel)
    private let summary = RecordSummaryView()
    private let record = RecordSessionView()
    private let empty = recordLabel(.body, color: .secondaryLabel)

    init(date: Date) {
        self.date = date
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        observeRecordDateChanges(self, selector: #selector(refreshDateContent))
        view.accessibilityIdentifier = "dailyRecord.sheet"
        dateLabel.accessibilityIdentifier = "dailyRecord.date"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "dailyRecord.close"
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        recordMonth = DailyRecordMonth()
        dateLabel.text = formattedRecordDate(date, template: "yyyyMMMMdEEEE")
        summary.configure(hasRecord: recordMonth.isToday(date))
        record.reloadLocalizedContent()
        empty.text = Localization.text("dailyRecord.empty")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDateContent()
    }

    @objc private func refreshDateContent() {
        guard isViewLoaded else { return }
        reloadLocalizedContent()
    }

    override var body: Layout {
        ScrollView(scroll) {
            VStack(alignment: .leading, spacing: 20) {
                dateLabel
                summary.resizable(axis: .horizontal)
                if recordMonth.isToday(date) {
                    record.resizable(axis: .horizontal)
                } else {
                    empty
                }
            }
            .padding(.vertical, 24)
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
    }
}

private final class RecordSummaryView: QuickLayoutView {
    private let countTitle = recordLabel(.caption1, color: .secondaryLabel)
    private let count = recordLabel(.title1)
    private let durationTitle = recordLabel(.caption1, color: .secondaryLabel)
    private let duration = recordLabel(.title2, color: .systemBlue)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 20
        duration.textAlignment = .natural
        duration.accessibilityIdentifier = "dailyRecord.duration"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(hasRecord: Bool) {
        countTitle.text = Localization.text("dailyRecord.count")
        count.text = (hasRecord ? 1 : 0).formatted(.number.locale(Localization.localizationController.locale))
        durationTitle.text = Localization.text("dailyRecord.duration")
        duration.text = Localization.text(hasRecord ? "dailyRecord.sampleDuration" : "dailyRecord.zeroDuration")
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) { countTitle; count }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) { durationTitle; duration }
            }
            VStack(alignment: .leading, spacing: 16) {
                countTitle
                count
                durationTitle
                duration
            }
        }
        .padding(20)
    }
}

private final class RecordSessionView: QuickLayoutView {
    private let time = recordLabel(.headline)
    private let detail = recordLabel(.subheadline, color: .secondaryLabel)
    private let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .tertiarySystemGroupedBackground
        layer.cornerRadius = 24
        check.tintColor = .systemGreen
        check.contentMode = .scaleAspectFit
        isAccessibilityElement = true
        accessibilityIdentifier = "dailyRecord.session"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reloadLocalizedContent() {
        time.text = "06:22 – 06:55"
        detail.text = Localization.text("dailyRecord.sessionDuration")
        accessibilityLabel = [time.text, detail.text, Localization.text("dailyRecord.completed")]
            .compactMap { $0 }.joined(separator: ", ")
        setNeedsQuickLayout()
    }

    override var body: Layout {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) { time; detail }
            Spacer()
            check.resizable().frame(width: 24, height: 24)
        }
        .padding(20)
    }
}

@MainActor
private func recordLabel(_ style: UIFont.TextStyle, color: UIColor = .label) -> UILabel {
    let label = UILabel()
    label.font = .preferredFont(forTextStyle: style)
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 0
    label.textColor = color
    return label
}

@MainActor
private func formattedRecordDate(_ date: Date, template: String) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.locale = Localization.localizationController.locale
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
}

@MainActor
private func observeRecordDateChanges(_ observer: Any, selector: Selector) {
    for name in [Notification.Name.NSCalendarDayChanged,
                 UIApplication.significantTimeChangeNotification,
                 UIApplication.didBecomeActiveNotification] {
        NotificationCenter.default.addObserver(observer, selector: selector, name: name, object: nil)
    }
}
