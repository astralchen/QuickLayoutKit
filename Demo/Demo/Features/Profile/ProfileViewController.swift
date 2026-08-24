//
//  ProfileViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit
import QuickLayout
import QuickLayoutKit

final class ProfileViewController: DemoQuickLayoutHostingController {

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
        reloadLocalizedContent()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()

        heroView.configure(
            name: DemoLocalization.text("profile.name"),
            role: DemoLocalization.text("profile.role"),
            location: DemoLocalization.text("profile.location"),
            availability: DemoLocalization.text("profile.availability")
        )
        statsView.configure(
            projects: .init(
                value: DemoLocalization.text("profile.stats.projects.value"),
                title: DemoLocalization.text("profile.stats.projects.title")
            ),
            followers: .init(
                value: DemoLocalization.text("profile.stats.followers.value"),
                title: DemoLocalization.text("profile.stats.followers.title")
            ),
            response: .init(
                value: DemoLocalization.text("profile.stats.response.value"),
                title: DemoLocalization.text("profile.stats.response.title")
            )
        )
        aboutView.configure(
            title: DemoLocalization.text("profile.section.about"),
            body: DemoLocalization.text("profile.bio")
        )
        activityView.configure(
            sectionTitle: DemoLocalization.text("profile.section.activity"),
            title: DemoLocalization.text("profile.activity.title"),
            detail: DemoLocalization.text("profile.activity.detail")
        )
        skillsView.configure(
            title: DemoLocalization.text("profile.section.skills"),
            skills: skillLocalizationKeys.map(DemoLocalization.text)
        )
        actionsView.configure(
            messageTitle: DemoLocalization.text("profile.action.message"),
            portfolioTitle: DemoLocalization.text("profile.action.portfolio")
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

#Preview {
    UINavigationController(rootViewController: ProfileViewController())
}
