//
//  DashboardViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

final class DashboardViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.dashboard.title" }

    let scrollView = QuickLayoutScrollView()
    let pageBackgroundView = UIView()
    let overviewLabel = UILabel()
    let recentActivityLabel = UILabel()

    private let profileSummaryView = DashboardProfileSummaryView()
    private let metricsOverviewView = DashboardMetricsOverviewView()
    private let weeklyGoalView = DashboardWeeklyGoalCardView(progress: 0.72)
    private let activityFeedView = DashboardActivityCardView()

    var profileCardView: UIView { profileSummaryView.cardBackgroundView }
    var activityCardView: UIView { activityFeedView.cardBackgroundView }

    var dashboardMetricViews: [UIView] {
        metricsOverviewView.metricViews
    }

    var dashboardMetricBackgroundViews: [UIView] {
        metricsOverviewView.metricBackgroundViews
    }

    var weeklyGoalCardView: UIView { weeklyGoalView.cardBackgroundView }
    var weeklyProgressView: UIProgressView { weeklyGoalView.progressView }
    var weeklyProgressLabel: UILabel { weeklyGoalView.progressLabel }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        reloadLocalizedContent()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()

        profileSummaryView.configure(
            name: DemoLocalization.text("dashboard.name"),
            score: DemoLocalization.text("dashboard.score", 1_250),
            achievement: DemoLocalization.text("dashboard.achievement"),
            trend: DemoLocalization.text("dashboard.score.trend")
        )
        overviewLabel.text = DemoLocalization.text("dashboard.overview")
        weeklyGoalView.configure(
            title: DemoLocalization.text("dashboard.weekly.title"),
            progressText: DemoLocalization.text("dashboard.weekly.progress"),
            detail: DemoLocalization.text("dashboard.weekly.detail")
        )
        recentActivityLabel.text = DemoLocalization.text(
            "dashboard.activity.title"
        )

        metricsOverviewView.configure(
            focus: (
                value: DemoLocalization.text("dashboard.metric.focus.value"),
                title: DemoLocalization.text("dashboard.metric.focus")
            ),
            streak: (
                value: DemoLocalization.text("dashboard.metric.streak.value"),
                title: DemoLocalization.text("dashboard.metric.streak")
            ),
            ranking: (
                value: DemoLocalization.text("dashboard.metric.ranking.value"),
                title: DemoLocalization.text("dashboard.metric.ranking")
            )
        )
        activityFeedView.configure(
            goal: (
                title: DemoLocalization.text("dashboard.activity.goal.title"),
                detail: DemoLocalization.text("dashboard.activity.goal.detail")
            ),
            badge: (
                title: DemoLocalization.text("dashboard.activity.badge.title"),
                detail: DemoLocalization.text("dashboard.activity.badge.detail")
            )
        )

        setNeedsQuickLayout()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        let semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        scrollView.semanticContentAttribute = semanticContentAttribute
        [
            profileSummaryView,
            metricsOverviewView,
            activityFeedView,
        ].forEach {
            $0.semanticContentAttribute = semanticContentAttribute
        }
        weeklyGoalView.applyLayoutDirection(direction)
    }

    override var body: Layout {
        ZStack {
            pageBackgroundView
                .resizable()
                .containerRelativeFrame([.horizontal, .vertical])
                .ignoresSafeArea(.container)

            ScrollView(scrollView) {
                VStack(alignment: .leading, spacing: 20) {
                    profileSummaryView
                        .resizable(axis: .horizontal)

                    overviewLabel
                    metricsOverviewView
                        .resizable(axis: .horizontal)

                    weeklyGoalView
                        .resizable(axis: .horizontal)

                    recentActivityLabel
                    activityFeedView
                        .resizable(axis: .horizontal)
                }
                .padding(.vertical, 12)
            }
            .contentMargins(.horizontal, 16)
            .contentMargins(.bottom, 24)
        }
    }

    private func configureViews() {
        view.backgroundColor = .systemGroupedBackground
        pageBackgroundView.backgroundColor = .systemGroupedBackground

        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .automatic
        scrollView.showsVerticalScrollIndicator = false
        scrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        configureSectionLabel(overviewLabel)
        configureSectionLabel(recentActivityLabel)
    }

    private func configureSectionLabel(_ label: UILabel) {
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
    }

}

private final class DashboardProfileSummaryView: QuickLayoutView {

    fileprivate let cardBackgroundView = UIView()

    private let profileImageView = UIImageView()
    private let nameLabel = UILabel()
    private let scoreLabel = UILabel()
    private let achievementLabel = UILabel()
    private let avatarBackgroundView = UIView()
    private let achievementBackgroundView = UIView()
    private let scoreTrendImageView = UIImageView()
    private let scoreTrendLabel = UILabel()
    private let dividerView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer

        profileImageView.image = UIImage(systemName: "person.crop.circle.fill")
        profileImageView.tintColor = .systemBlue
        profileImageView.contentMode = .scaleAspectFit
        profileImageView.isAccessibilityElement = false

        avatarBackgroundView.backgroundColor = UIColor.systemBlue
            .withAlphaComponent(0.12)
        avatarBackgroundView.layer.cornerRadius = 32

        nameLabel.font = .preferredFont(forTextStyle: .title3)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 0

        scoreLabel.font = .preferredFont(forTextStyle: .headline)
        scoreLabel.adjustsFontForContentSizeCategory = true
        scoreLabel.textColor = .label
        scoreLabel.numberOfLines = 0

        achievementLabel.font = .preferredFont(forTextStyle: .caption1)
        achievementLabel.adjustsFontForContentSizeCategory = true
        achievementLabel.textColor = .systemOrange
        achievementLabel.numberOfLines = 0

        achievementBackgroundView.backgroundColor = UIColor.systemOrange
            .withAlphaComponent(0.12)
        achievementBackgroundView.layer.cornerRadius = 12

        scoreTrendImageView.image = UIImage(systemName: "arrow.up.right")
        scoreTrendImageView.tintColor = .systemGreen
        scoreTrendImageView.contentMode = .scaleAspectFit
        scoreTrendImageView.isAccessibilityElement = false

        scoreTrendLabel.font = .preferredFont(forTextStyle: .caption1)
        scoreTrendLabel.adjustsFontForContentSizeCategory = true
        scoreTrendLabel.textColor = .systemGreen
        scoreTrendLabel.numberOfLines = 1
        scoreTrendLabel.adjustsFontSizeToFitWidth = true
        scoreTrendLabel.minimumScaleFactor = 0.8

        dividerView.backgroundColor = .separator
        dividerView.isAccessibilityElement = false

        cardBackgroundView.backgroundColor = .secondarySystemGroupedBackground
        cardBackgroundView.layer.cornerRadius = 16
        cardBackgroundView.layer.cornerCurve = .continuous
        cardBackgroundView.layer.shadowColor = UIColor.black.cgColor
        cardBackgroundView.layer.shadowOpacity = 0.07
        cardBackgroundView.layer.shadowRadius = 12
        cardBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 5)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        name: String,
        score: String,
        achievement: String,
        trend: String
    ) {
        nameLabel.text = name
        scoreLabel.text = score
        achievementLabel.text = achievement
        scoreTrendLabel.text = trend
        setNeedsQuickLayout()
    }

    @LayoutBuilder
    override var body: Layout {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    avatarBackgroundView
                        .frame(width: 64, height: 64)
                    profileImageView
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                }

                VStack(alignment: .leading, spacing: 7) {
                    nameLabel
                    achievementLabel
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background { achievementBackgroundView }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            dividerView
                .resizable(axis: .horizontal)
                .frame(height: 1)

            HStack(spacing: 8) {
                scoreLabel
                Spacer()
                HStack(spacing: 4) {
                    scoreTrendImageView
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    scoreTrendLabel
                }
            }
        }
        .padding(.all, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { cardBackgroundView }
    }
}

private final class DashboardMetricsOverviewView: QuickLayoutView {

    private let focusMetricView = DashboardMetricCardView(
        symbolName: "checkmark.circle.fill",
        tintColor: .systemBlue
    )
    private let streakMetricView = DashboardMetricCardView(
        symbolName: "flame.fill",
        tintColor: .systemOrange
    )
    private let rankingMetricView = DashboardMetricCardView(
        symbolName: "chart.line.uptrend.xyaxis",
        tintColor: .systemPurple
    )

    fileprivate var metricViews: [UIView] {
        [focusMetricView, streakMetricView, rankingMetricView]
    }

    fileprivate var metricBackgroundViews: [UIView] {
        metricCards.map(\.cardBackgroundView)
    }

    private var metricCards: [DashboardMetricCardView] {
        [focusMetricView, streakMetricView, rankingMetricView]
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        focus: (value: String, title: String),
        streak: (value: String, title: String),
        ranking: (value: String, title: String)
    ) {
        focusMetricView.configure(value: focus.value, title: focus.title)
        streakMetricView.configure(value: streak.value, title: streak.title)
        rankingMetricView.configure(value: ranking.value, title: ranking.title)
        setNeedsQuickLayout()
    }

    @LayoutBuilder
    override var body: Layout {
        if traitCollection.preferredContentSizeCategory
            .isAccessibilityCategory {
            VStack(spacing: 10) {
                ForEach(metricCards) { metricView in
                    metricView
                        .resizable(axis: .horizontal)
                        .frame(minHeight: 104)
                }
            }
        } else {
            Grid(alignment: .topLeading, horizontalSpacing: 10) {
                GridRow(alignment: .top) {
                    ForEach(metricCards) { metricView in
                        metricView
                            .resizable(axis: .horizontal)
                            .frame(minHeight: 126)
                    }
                }
            }
        }
    }
}

private final class DashboardMetricCardView: QuickLayoutView {

    private let iconBackgroundView = UIView()
    private let iconImageView = UIImageView()
    private let valueLabel = UILabel()
    private let titleLabel = UILabel()
    fileprivate let cardBackgroundView = UIView()

    init(symbolName: String, tintColor: UIColor) {
        super.init(frame: .zero)

        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        iconImageView.image = UIImage(systemName: symbolName)
        iconImageView.tintColor = tintColor
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.isAccessibilityElement = false

        iconBackgroundView.backgroundColor = tintColor.withAlphaComponent(0.12)
        iconBackgroundView.layer.cornerRadius = 10

        valueLabel.font = .preferredFont(forTextStyle: .title3)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = .label
        valueLabel.numberOfLines = 1
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.8

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.numberOfLines = 2

        cardBackgroundView.backgroundColor = .secondarySystemGroupedBackground
        cardBackgroundView.layer.cornerRadius = 16
        cardBackgroundView.layer.cornerCurve = .continuous

        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(value: String, title: String) {
        valueLabel.text = value
        titleLabel.text = title
        accessibilityLabel = title
        accessibilityValue = value
        setNeedsQuickLayout()
    }

    @LayoutBuilder
    override var body: Layout {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                iconBackgroundView.frame(width: 34, height: 34)
                iconImageView
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
            }
            Spacer()
            valueLabel
            titleLabel
        }
        .padding(.all, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { cardBackgroundView }
    }
}

private final class DashboardWeeklyGoalCardView: QuickLayoutView {

    fileprivate let progressLabel = UILabel()
    fileprivate let progressView = UIProgressView(progressViewStyle: .default)
    fileprivate let cardBackgroundView = UIView()

    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    init(progress: Float) {
        super.init(frame: .zero)

        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        progressLabel.font = .preferredFont(forTextStyle: .headline)
        progressLabel.adjustsFontForContentSizeCategory = true
        progressLabel.textColor = .systemBlue
        progressLabel.numberOfLines = 1
        progressLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        progressView.progress = progress
        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = UIColor.systemBlue
            .withAlphaComponent(0.14)

        cardBackgroundView.backgroundColor = .secondarySystemGroupedBackground
        cardBackgroundView.layer.cornerRadius = 16
        cardBackgroundView.layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, progressText: String, detail: String) {
        titleLabel.text = title
        progressLabel.text = progressText
        progressView.accessibilityLabel = title
        progressView.accessibilityValue = progressText
        detailLabel.text = detail
        setNeedsQuickLayout()
    }

    func applyLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        let attribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        semanticContentAttribute = attribute
        cardBackgroundView.semanticContentAttribute = attribute
        // UIProgressView 没有公开的填充起始边 API。先固定其内部渲染方向，
        // 再根据应用本地化方向对控件进行一次镜像，避免重复翻转。
        progressView.semanticContentAttribute = .forceLeftToRight
        progressView.transform = direction == .rightToLeft
            ? CGAffineTransform(scaleX: -1, y: 1)
            : .identity
        setNeedsQuickLayout()
    }

    @LayoutBuilder
    override var body: Layout {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                titleLabel
                Spacer()
                progressLabel
            }
            progressView
                .resizable(axis: .horizontal)
            detailLabel
        }
        .padding(.all, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { cardBackgroundView }
    }
}

private final class DashboardActivityCardView: QuickLayoutView {

    fileprivate let cardBackgroundView = UIView()

    private let goalActivityView = DashboardActivityRowView(
        symbolName: "target",
        tintColor: .systemGreen
    )
    private let badgeActivityView = DashboardActivityRowView(
        symbolName: "medal.fill",
        tintColor: .systemOrange
    )
    private let separatorView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        separatorView.backgroundColor = .separator
        separatorView.isAccessibilityElement = false
        cardBackgroundView.backgroundColor = .secondarySystemGroupedBackground
        cardBackgroundView.layer.cornerRadius = 16
        cardBackgroundView.layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        goal: (title: String, detail: String),
        badge: (title: String, detail: String)
    ) {
        goalActivityView.configure(title: goal.title, detail: goal.detail)
        badgeActivityView.configure(title: badge.title, detail: badge.detail)
        setNeedsQuickLayout()
    }

    @LayoutBuilder
    override var body: Layout {
        VStack(spacing: 0) {
            goalActivityView
                .resizable(axis: .horizontal)
            separatorView
                .resizable(axis: .horizontal)
                .frame(height: 1)
                .padding(.leading, 62)
            badgeActivityView
                .resizable(axis: .horizontal)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { cardBackgroundView }
    }
}

private final class DashboardActivityRowView: QuickLayoutView {

    private let iconBackgroundView = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    init(symbolName: String, tintColor: UIColor) {
        super.init(frame: .zero)

        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        iconImageView.image = UIImage(systemName: symbolName)
        iconImageView.tintColor = tintColor
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.isAccessibilityElement = false

        iconBackgroundView.backgroundColor = tintColor.withAlphaComponent(0.12)
        iconBackgroundView.layer.cornerRadius = 12

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        detailLabel.font = .preferredFont(forTextStyle: .caption1)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, detail: String) {
        titleLabel.text = title
        detailLabel.text = detail
        accessibilityLabel = title
        accessibilityValue = detail
        setNeedsQuickLayout()
    }

    @LayoutBuilder
    override var body: Layout {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                iconBackgroundView.frame(width: 40, height: 40)
                iconImageView
                    .resizable()
                    .scaledToFit()
                    .frame(width: 19, height: 19)
            }
            VStack(alignment: .leading, spacing: 3) {
                titleLabel
                detailLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    UINavigationController(rootViewController: DashboardViewController())
}
