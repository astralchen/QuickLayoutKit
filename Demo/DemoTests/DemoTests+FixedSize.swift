import QuickLayout
import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

extension DemoTests {
    @Test func fixedSizeLabStatesAndOffscreenContentDetermineHeight() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }
        let controller = FixedSizeDemoViewController()
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
        let controller = FixedSizeDemoViewController()
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
        let scroll = controller.contentView.stageView.carouselScrollView
        let first = controller.contentView.stageView.cards[0].convert(controller.contentView.stageView.cards[0].bounds, to: scroll)
        #expect(first.maxX <= scroll.bounds.maxX + 1)
        #expect(first.maxX > scroll.bounds.maxX - 80)
        #expect(controller.contentView.pageScrollView.contentSize.height > controller.contentView.pageScrollView.bounds.height)

        navigation.view.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        layout(controller, in: navigation)
        expectCompleteFixedSizeCards(controller)
        window.overrideUserInterfaceStyle = .dark
        navigation.view.layoutIfNeeded()
        revealFixedSizeCarousel(controller)
        await recordFixedSizeSnapshot(navigation, name: "fixed-size-landscape-dark")
        let titleColor = try #require(
            controller.navigationItem.standardAppearance?.titleTextAttributes[.foregroundColor] as? UIColor
        )
        #expect(titleColor.isEqual(UIColor.label.resolvedColor(with: controller.traitCollection)))
        for card in controller.contentView.stageView.cards {
            #expect(card.bounds.width <= 300)
            #expect(card.bounds.width > 0)
        }
    }

    @Test func fixedSizeRouteIsSearchableAndNavigatesToLab() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }
        let model = MainViewModel()
        let routes = try #require(model.state.sections.first?.routes.map(\.route))
        let position = try #require(routes.firstIndex(of: .viewThatFits))
        #expect(routes[position + 1] == .fixedSize)
        model.updateSearchQuery("FixedSize")
        #expect(model.state.sections.flatMap(\.routes).map(\.route) == [.fixedSize])
        let source = UIViewController()
        let navigation = UINavigationController(rootViewController: source)
        MainRouter().navigate(to: .fixedSize, from: source)
        let destination = try #require(navigation.topViewController as? FixedSizeDemoViewController)
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
private func revealFixedSizeCarousel(_ controller: FixedSizeDemoViewController) {
    let page = controller.contentView.pageScrollView
    let frame = controller.contentView.stageView.carouselScrollView.convert(controller.contentView.stageView.carouselScrollView.bounds, to: page)
    page.setContentOffset(CGPoint(x: page.contentOffset.x, y: max(0, frame.minY - 12)), animated: false)
    page.layoutIfNeeded()
}

@MainActor
private func expectCompleteFixedSizeCards(_ controller: FixedSizeDemoViewController) {
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
