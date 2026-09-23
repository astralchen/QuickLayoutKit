//
//  ProfileViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit
import QuickLayout
import QuickLayoutKit

final class ProfileViewController: LocalizedQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.profile.title" }

    private let scrollView = QuickLayoutScrollView()
    private let heroView = ProfileHeroView()
    private let statsView = ProfileStatsView()
    private let aboutView = ProfileAboutView()
    private let activityView = ProfileActivityView()
    private let skillsView = ProfileSkillsView()
    private let actionsView = ProfileActionsView()

    private let skillLocalizationKeys = [
        "profile.skill.uikit",
        "profile.skill.quicklayout",
        "profile.skill.localization",
        "profile.skill.rtl",
        "profile.skill.dynamicType",
        "profile.skill.keyboard",
        "profile.skill.scroll",
        "profile.skill.collection",
        "profile.skill.controllerHosting",
        "profile.skill.accessibility"
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        scrollView.backgroundColor = .systemGroupedBackground
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-profile-scroll-probe") {
            scrollView.accessibilityIdentifier = "profile.scroll"
            scrollView.accessibilityValue = "0"
            scrollView.delegate = self
        }
        #endif
        reloadLocalizedContent()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()

        heroView.configure(
            name: Localization.text("profile.name"),
            role: Localization.text("profile.role"),
            location: Localization.text("profile.location"),
            availability: Localization.text("profile.availability")
        )
        statsView.configure(
            projects: .init(
                value: Localization.text("profile.stats.projects.value"),
                title: Localization.text("profile.stats.projects.title")
            ),
            followers: .init(
                value: Localization.text("profile.stats.followers.value"),
                title: Localization.text("profile.stats.followers.title")
            ),
            response: .init(
                value: Localization.percent(0.98),
                title: Localization.text("profile.stats.response.title")
            )
        )
        aboutView.configure(
            title: Localization.text("profile.section.about"),
            body: Localization.text("profile.bio")
        )
        activityView.configure(
            sectionTitle: Localization.text("profile.section.activity"),
            title: Localization.text("profile.activity.title"),
            detail: Localization.text("profile.activity.detail")
        )
        skillsView.configure(
            title: Localization.text("profile.section.skills"),
            skills: skillLocalizationKeys.map(Localization.text)
        )
        actionsView.configure(
            messageTitle: Localization.text("profile.action.message"),
            portfolioTitle: Localization.text("profile.action.portfolio")
        )

        setNeedsQuickLayout()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)

        // 滚动视图是该控制器唯一负责的应用方向边界。各分区组件在挂载、测量和布局时，
        // 从外层容器恢复当前方向。
        scrollView.semanticContentAttribute = view.semanticContentAttribute
        scrollView.setNeedsLayout()
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ScrollView(scrollView) {
            VStack(spacing: 18) {
                heroView
                    .resizable(axis: .horizontal)
                statsView
                aboutView
                activityView
                skillsView
                actionsView
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }
}

#if DEBUG
/// 仅在 UI 回归启动参数启用时记录拖动过程，避免松手回弹掩盖横向位移。
extension ProfileViewController: UIScrollViewDelegate {
    /// 记录偏离正常水平起点的最大距离，供 UI 测试在手势结束后读取。
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        let previousMaximum = Double(scrollView.accessibilityValue ?? "0") ?? 0
        let horizontalDisplacement = abs(scrollView.contentOffset.x + scrollView.adjustedContentInset.left)
        scrollView.accessibilityValue = String(max(previousMaximum, Double(horizontalDisplacement)))
    }
}
#endif

@available(iOS 17.0, *)
#Preview {
    UINavigationController(rootViewController: ProfileViewController())
}
