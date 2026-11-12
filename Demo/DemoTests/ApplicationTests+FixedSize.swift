import QuickLayout
import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

extension ApplicationTests {
    /// 系统栏的边距在旋转时会更换物理边；页面和原生指示器应始终看到同一个安全区。
    @Test func fixedSizePageKeepsNativeIndicatorTrackWhenSafeAreaChanges() throws {
        let controller = FixedSizeViewController()
        let navigation = UINavigationController(rootViewController: controller)
        let window = try makeVisibleTestWindow(rootViewController: navigation)
        defer { window.isHidden = true }
        let page = controller.contentView.pageScrollView
        for extra in [UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84),
                      UIEdgeInsets(top: 28, left: 0, bottom: 40, right: 0)] {
            controller.additionalSafeAreaInsets = extra
            layout(controller, in: navigation)
            #expect(page.convert(page.bounds, to: controller.view) == controller.view.bounds)
            #expect(page.safeAreaInsets == controller.view.safeAreaInsets)
            #expect(page.automaticallyAdjustsScrollIndicatorInsets)
            #expect(page.verticalScrollIndicatorInsets == .zero)
        }
    }

    @Test func fixedSizeLabStatesAndOffscreenContentDetermineHeight() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }
        let controller = FixedSizeViewController()
        let navigation = UINavigationController(rootViewController: controller)
        let window = try makeVisibleTestWindow(rootViewController: navigation, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        layout(controller, in: navigation)
        #expect(controller.contentView.selectedScenario == .equal)
        let naturalHeights = controller.contentView.stageView.cards.map {
            $0.sizeThatFits(CGSize(width: $0.bounds.width, height: .infinity)).height
        }
        let tallest = try #require(naturalHeights.max())
        let scroll = controller.contentView.stageView.carouselScrollView
        let viewportWidth = scroll.bounds.width - scroll.adjustedContentInset.left - scroll.adjustedContentInset.right
        #expect(controller.contentView.stageView.cards.allSatisfy { abs($0.bounds.width - min(300, viewportWidth * 0.78)) < 1 })
        #expect(naturalHeights.last == tallest)
        #expect(controller.contentView.stageView.cards.allSatisfy { abs($0.bounds.height - tallest) < 1 })
        #expect(abs(controller.contentView.stageView.carouselScrollView.bounds.height - tallest) < 1)
        let lastFrame = controller.contentView.stageView.cards[3].convert(controller.contentView.stageView.cards[3].bounds, to: controller.contentView.stageView.carouselScrollView)
        #expect(lastFrame.minX > controller.contentView.stageView.carouselScrollView.bounds.maxX)
        await recordFixedSizeSnapshot(navigation, name: "fixed-size-equal")

        controller.contentView.stageView.carouselScrollView.setContentOffset(CGPoint(x: 100, y: 0), animated: false)
        for scenario in [FixedSizeScenario.natural, .fill, .equal, .natural, .equal] {
            controller.contentView.selectScenario(scenario)
            layout(controller, in: navigation)
            #expect(abs(controller.contentView.stageView.carouselScrollView.contentOffset.x - 100) < 1)
            let heights = controller.contentView.stageView.cards.map(\.bounds.height)
            switch scenario {
            case .natural:
                await recordFixedSizeSnapshot(navigation, name: "fixed-size-natural")
                #expect((heights.max() ?? 0) - (heights.min() ?? 0) > 40)
                for (height, expected) in zip(heights, naturalHeights) {
                    #expect(abs(height - expected) < 1)
                }
            case .fill:
                await recordFixedSizeSnapshot(navigation, name: "fixed-size-fill")
                #expect(abs(controller.contentView.stageView.carouselScrollView.bounds.height - 420) < 1)
                #expect(heights.allSatisfy { abs($0 - 420) < 1 })
            case .equal:
                #expect(heights.allSatisfy { abs($0 - tallest) < 1 })
            }
        }
        let page = controller.contentView.pageScrollView
        page.setContentOffset(CGPoint(x: 0, y: max(0,
            page.contentSize.height - page.bounds.height + page.adjustedContentInset.bottom
        )), animated: false)
        await recordFixedSizeSnapshot(navigation, name: "fixed-size-explanation")
    }

    @Test func fixedSizeLabAdaptsToWidthLargeTextAndRTL() async throws {
        Localization.setLocale(identifier: "ar")
        defer { Localization.setLocale(identifier: "en-US") }
        let controller = FixedSizeViewController()
        let navigation = UINavigationController(rootViewController: controller)
        let window = try makeVisibleTestWindow(
            rootViewController: navigation,
            size: CGSize(width: 320, height: 700),
            semanticContentAttribute: .forceRightToLeft,
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        defer { window.isHidden = true }
        controller.reloadLayoutDirection(.rightToLeft)
        layout(controller, in: navigation)
        expectCompleteFixedSizeCards(controller)
        revealFixedSizeCarousel(controller)
        await recordFixedSizeSnapshot(navigation, name: "fixed-size-arabic-large-text")
        // Duo 的实际右侧安全边距可超过 80 pt，按安全视口精确验证首张卡片。
        expectFixedSizeLeading(controller.contentView.stageView)
        #expect(controller.contentView.pageScrollView.contentSize.height > controller.contentView.pageScrollView.bounds.height)

        navigation.view.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        layout(controller, in: navigation)
        expectCompleteFixedSizeCards(controller)
        window.overrideUserInterfaceStyle = .dark
        navigation.view.layoutIfNeeded()
        revealFixedSizeCarousel(controller)
        await recordFixedSizeSnapshot(navigation, name: "fixed-size-landscape-dark")
        expectFixedSizeLeading(controller.contentView.stageView)
        let titleColor = try #require(
            controller.navigationItem.standardAppearance?.titleTextAttributes[.foregroundColor] as? UIColor
        )
        #expect(titleColor.isEqual(UIColor.label.resolvedColor(with: controller.traitCollection)))
        for card in controller.contentView.stageView.cards {
            #expect(card.bounds.width <= 300 + 1 / controller.traitCollection.displayScale)
            #expect(card.bounds.width > 0)
        }
    }

    /// Duo 安全区更新会让视口先收窄再恢复；每轮都以最终几何保持语义起点。
    @Test func fixedSizeCarouselKeepsLeadingAcrossTransientWidthsLTR() {
        checkFixedSizeCarouselLeading(rtl: false)
    }

    @Test func fixedSizeCarouselKeepsLeadingAcrossTransientWidthsRTL() {
        checkFixedSizeCarouselLeading(rtl: true)
    }

    private func checkFixedSizeCarouselLeading(rtl: Bool) {
        let stage = FixedSizeStageView()
        stage.reloadLocalizedContent()
        stage.reloadLayoutDirection(rtl ? .rightToLeft : .leftToRight)
        for width: CGFloat in [320, 236, 320, 844, 280] {
            stage.frame = CGRect(x: 0, y: 0, width: width, height: 1_200)
            stage.setNeedsQuickLayout()
            stage.layoutIfNeeded()
            expectFixedSizeLeading(stage)
            // 重复布局以及切换内容高度不应让起点漂移。
            for scenario in [FixedSizeScenario.natural, .fill, .equal] {
                stage.selectScenario(scenario)
                stage.layoutIfNeeded()
                expectFixedSizeLeading(stage)
            }
        }
    }

    /// 程序化滚动离开起点后，重排、切换场景和调整宽度均不得强制返回首张卡片。
    @Test func fixedSizeCarouselPreservesAwayOffsetAndResetsOnDirectionChangeLTR() {
        checkFixedSizeCarouselAwayOffset(rtl: false)
    }

    @Test func fixedSizeCarouselPreservesAwayOffsetAndResetsOnDirectionChangeRTL() {
        checkFixedSizeCarouselAwayOffset(rtl: true)
    }

    private func checkFixedSizeCarouselAwayOffset(rtl: Bool) {
        let stage = FixedSizeStageView()
        stage.reloadLocalizedContent()
        stage.reloadLayoutDirection(rtl ? .rightToLeft : .leftToRight)
        stage.frame = CGRect(x: 0, y: 0, width: 320, height: 1_200)
        stage.setNeedsQuickLayout()
        stage.layoutIfNeeded()
        let scroll = stage.carouselScrollView
        let offset: CGFloat = 100
        scroll.setContentOffset(CGPoint(x: offset, y: scroll.contentOffset.y), animated: false)
        for width: CGFloat in [320, 280, 360, 320] {
            stage.frame.size.width = width
            for scenario in [FixedSizeScenario.natural, .fill, .equal] {
                stage.selectScenario(scenario)
                stage.setNeedsQuickLayout()
                stage.layoutIfNeeded()
                #expect(abs(scroll.contentOffset.x - offset) < 1)
            }
        }
        stage.reloadLayoutDirection(rtl ? .leftToRight : .rightToLeft)
        stage.layoutIfNeeded()
        expectFixedSizeLeading(stage)
        stage.reloadLayoutDirection(rtl ? .rightToLeft : .leftToRight)
        stage.layoutIfNeeded()
        expectFixedSizeLeading(stage)
    }

    @Test func fixedSizeRouteIsSearchableAndNavigatesToLab() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }
        let model = MainViewModel()
        let routes = try #require(model.state.sections.first?.routes.map(\.route))
        let position = try #require(routes.firstIndex(of: .viewThatFits))
        // Frame 实验室已插入 ViewThatFits 与 FixedSize 之间。
        #expect(Array(routes.dropFirst(position).prefix(3)) == [.viewThatFits, .frame, .fixedSize])
        model.updateSearchQuery("FixedSize")
        #expect(model.state.sections.flatMap(\.routes).map(\.route) == [.fixedSize])
        let source = UIViewController()
        let navigation = UINavigationController(rootViewController: source)
        MainRouter().navigate(to: .fixedSize, from: source)
        let destination = try #require(navigation.topViewController as? FixedSizeViewController)
        #expect(destination.navigationItem.title == Localization.text("demo.fixedSize.title"))
    }

    // This also compiles the public overload with both modules imported, as in client apps.
    @Test func publicStackFixedSizeOverloadIsSelectedWithBothImports() {
        let row = makeFixedSizeQuickLayoutReference()
        let result = row.quick_layoutThatFits(CGSize(width: 300, height: 420))
        #expect(result.size.height == 140)
        #expect(result.children.map(\.layout.size.height) == [140, 140])
    }
}

@MainActor
func makeFixedSizeQuickLayoutReference() -> Layout {
    let first = UILabel()
    let second = UILabel()
    return HStack(alignment: .top, spacing: 16) {
        first.resizable().frame(width: 100, height: 80)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        second.resizable().frame(width: 100, height: 140)
            .frame(maxHeight: .infinity, alignment: .topLeading)
    }.fixedSize(axis: .vertical)
}

@MainActor
private func recordFixedSizeSnapshot(_ controller: UIViewController, name: String) async {
    // Let UIKit finish the segmented-control and appearance transactions before capture.
    try? await Task.sleep(nanoseconds: 200_000_000)
    let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
    }
    Attachment.record(image, named: "\(name).png")
}

@MainActor
private func revealFixedSizeCarousel(_ controller: FixedSizeViewController) {
    let page = controller.contentView.pageScrollView
    let frame = controller.contentView.stageView.carouselScrollView.convert(controller.contentView.stageView.carouselScrollView.bounds, to: page)
    page.setContentOffset(CGPoint(x: page.contentOffset.x, y: max(0, frame.minY - 12)), animated: false)
    page.layoutIfNeeded()
}

@MainActor
private func expectCompleteFixedSizeCards(_ controller: FixedSizeViewController) {
    let heights = controller.contentView.stageView.cards.map(\.bounds.height)
    #expect((heights.max() ?? 0) - (heights.min() ?? 0) < 1)
    for card in controller.contentView.stageView.cards {
        card.layoutIfNeeded()
        let detail = card.detailLabel
        let required = detail.sizeThatFits(CGSize(width: detail.bounds.width, height: .infinity))
        #expect(detail.bounds.width > 0)
        #expect(detail.bounds.height >= required.height - 1)
        #expect(detail.frame.maxY <= card.bounds.height - 19)
    }
}

/// 同时验证偏移和首张卡片的位置，不能仅靠 contentOffset 数值判断成功。
@MainActor
private func expectFixedSizeLeading(_ stage: FixedSizeStageView, sourceLocation: SourceLocation = #_sourceLocation) {
    let scroll = stage.carouselScrollView
    let insets = scroll.adjustedContentInset
    let rtl = scroll.effectiveUserInterfaceLayoutDirection == .rightToLeft
    let target = rtl ? max(-insets.left, scroll.contentSize.width - scroll.bounds.width + insets.right) : -insets.left
    #expect(abs(scroll.contentOffset.x - target) < 1, sourceLocation: sourceLocation)
    let first = stage.cards[0].convert(stage.cards[0].bounds, to: scroll)
    let visible = scroll.bounds.inset(by: insets)
    #expect(abs((rtl ? first.maxX : first.minX) - (rtl ? visible.maxX : visible.minX)) < 1,
            sourceLocation: sourceLocation)
}
