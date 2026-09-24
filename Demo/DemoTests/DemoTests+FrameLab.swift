import AppLocalization
import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

extension DemoTests {
    /// 验证模式切换保留各页状态和偏移，重置只作用于当前页，窗口变化后偏移仍有效。
    @Test func frameLabPresentationsKeepIndependentExperimentsAndScrollPositions() throws {
        let controller = FrameLabViewController()
        let navigation = UINavigationController(rootViewController: controller)
        let window = try makeVisibleTestWindow(rootViewController: navigation, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        layout(controller, in: navigation)
        let first = controller.contentView
        first.selectScenario(.bounds)
        first.selectOption(0)
        first.setContainer(widthFraction: 0.6, height: 240)
        layout(controller, in: navigation)
        first.pageScrollView.setContentOffset(CGPoint(x: 0, y: 100), animated: false)
        let firstOffset = first.pageScrollView.contentOffset.y
        let switchFrame = controller.presentationControl.convert(controller.presentationControl.bounds, to: window)
        #expect(switchFrame.height >= 44)
        #expect(switchFrame.minY >= navigation.navigationBar.convert(navigation.navigationBar.bounds, to: window).maxY)

        controller.presentationControl.selectedSegmentIndex = 1
        controller.presentationControl.sendActions(for: .valueChanged)
        layout(controller, in: navigation)
        let guided = controller.contentView
        #expect(first !== guided && first.superview == nil)
        #expect(guided.state.scenario == .alignment && guided.state.widthFraction == 1)
        guided.selectScenario(.alignment)
        guided.selectAlignment(8)
        guided.setContainer(widthFraction: 0.8, height: 260)
        guided.toggleMoreParameters()
        layout(controller, in: navigation)
        guided.pageScrollView.setContentOffset(CGPoint(x: 0, y: 160), animated: false)
        let guidedOffset = guided.pageScrollView.contentOffset.y
        controller.selectPresentation(.freeform)
        layout(controller, in: navigation)
        #expect(controller.contentView === first && guided.superview == nil)
        #expect(first.state.scenario == .bounds && first.state.option == 0)
        #expect(first.state.widthFraction == 0.6 && first.state.containerHeight == 240)
        #expect(abs(first.pageScrollView.contentOffset.y - firstOffset) < 1)
        controller.selectPresentation(.guided)
        layout(controller, in: navigation)
        #expect(guided.state.alignmentIndex == 8 && guided.showsMoreParameters)
        #expect(guided.state.widthFraction == 0.8 && guided.state.containerHeight == 260)
        #expect(abs(guided.pageScrollView.contentOffset.y - guidedOffset) < 1)
        #expect(controller.presentationControl.convert(controller.presentationControl.bounds, to: window) == switchFrame)
        controller.resetExperiment()
        layout(controller, in: navigation)
        #expect(guided.state.scenario == .alignment && guided.state.widthFraction == 1)
        #expect(!guided.showsMoreParameters)
        controller.selectPresentation(.freeform)
        window.frame.size = CGSize(width: 740, height: 390)
        navigation.view.frame = window.bounds
        layout(controller, in: navigation)
        #expect(first.state.widthFraction == 0.6 && first.state.containerHeight == 240)
        let scroll = first.pageScrollView
        #expect(scroll.contentOffset.y >= -scroll.adjustedContentInset.top)
        #expect(scroll.contentOffset.y <= max(-scroll.adjustedContentInset.top,
            scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom))
    }

    /// 验证六场景首尾导航、九宫格位置与选中状态，以及 RTL 镜像和按钮复用。
    @Test func frameLabGuidedNavigationAndAlignmentGrid() throws {
        defer { Localization.setLocale(identifier: "en-US") }
        let controller = FrameLabViewController()
        let navigation = UINavigationController(rootViewController: controller)
        let window = try makeVisibleTestWindow(rootViewController: navigation, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        controller.selectPresentation(.guided)
        let page = controller.contentView
        page.selectScenario(.fixed)
        for (index, scenario) in FrameLabScenario.allCases.enumerated() {
            layout(controller, in: navigation)
            #expect(page.state.scenario == scenario)
            let previous = try #require(page.allSubviews(of: UIButton.self).first { $0.accessibilityIdentifier == "frame.previous" })
            let next = try #require(page.allSubviews(of: UIButton.self).first { $0.accessibilityIdentifier == "frame.next" })
            #expect(previous.isEnabled == (index > 0))
            #expect(next.isEnabled == (index < 5))
            next.sendActions(for: .touchUpInside)
        }
        #expect(page.state.scenario == .composition)
        page.moveScenario(by: -1)
        #expect(page.state.scenario == .alignment)
        for locale in ["en-US", "ar"] {
            Localization.setLocale(identifier: locale)
            controller.reloadLocalizedContent()
            controller.reloadLayoutDirection(Localization.currentUIKitDirection)
            for index in 0..<9 {
                layout(controller, in: navigation)
                let button = try #require(page.allSubviews(of: UIButton.self).first {
                    $0.accessibilityIdentifier == "frame.alignment.\(FrameLabState.alignmentNames[index])"
                })
                #expect(button.bounds.width >= 44 && button.bounds.height >= 44)
                button.sendActions(for: .touchUpInside)
                layout(controller, in: navigation)
                #expect(page.state.alignmentIndex == index && button.isSelected)
                #expect(button.accessibilityTraits.contains(.selected))
                let rtl = locale == "ar"
                let column = rtl ? 2 - index % 3 : index % 3
                let availableX = page.previewView.bounds.width - page.previewView.sample.bounds.width
                let availableY = page.previewView.bounds.height - page.previewView.sample.bounds.height
                #expect(abs(page.previewView.sample.frame.minX - CGFloat(column) * availableX / 2) < 1)
                #expect(abs(page.previewView.sample.frame.minY - CGFloat(index / 3) * availableY / 2) < 1)
                let grid = try #require(button.superview)
                #expect(abs(button.frame.minX - CGFloat(column) * 54) < 1)
                let buttons = grid.allSubviews(of: UIButton.self)
                let identities = buttons.map(ObjectIdentifier.init)
                page.setContainer(widthFraction: 0.75)
                layout(controller, in: navigation)
                #expect(grid.allSubviews(of: UIButton.self).map(ObjectIdentifier.init) == identities)
            }
        }
    }

    /// 验证真实 API 布局产生的 frame、内容和最终结果尺寸，防止读数退化为预设值。
    @Test func frameLabMeasuresFramesAndContentIndependently() {
        let preview = FrameLabPreviewView()
        var state = FrameLabState()
        func measure(width: CGFloat = 300, height: CGFloat = 200) {
            preview.frame = CGRect(x: 0, y: 0, width: width, height: height)
            preview.state = state
            preview.quickLayoutIfNeeded()
            preview.layoutIfNeeded()
        }
        func expectSize(_ view: UIView, _ width: CGFloat, _ height: CGFloat) {
            #expect(abs(view.bounds.width - width) < 1)
            #expect(abs(view.bounds.height - height) < 1)
        }
        measure()
        let natural = preview.sample.bounds.size
        expectSize(preview.frameMarker, 120, 64)
        #expect(natural.width < 120 && natural.height < 64)
        state.stretchesContent = true
        measure()
        expectSize(preview.sample, 120, 64)

        state.scenario = .bounds
        state.option = 2
        for (proposal, expected) in [(CGSize(width: 80, height: 40), CGSize(width: 100, height: 48)),
                                     (CGSize(width: 180, height: 90), CGSize(width: 180, height: 90)),
                                     (CGSize(width: 300, height: 200), CGSize(width: 240, height: 120))] {
            measure(width: proposal.width, height: proposal.height)
            expectSize(preview.frameMarker, expected.width, expected.height)
        }

        state.scenario = .ideal
        state.option = 0
        measure()
        expectSize(preview.frameMarker, 300, 200)
        state.option = 1
        measure()
        expectSize(preview.frameMarker, 120, 64)

        state.scenario = .fill
        state.option = 1
        state.stretchesContent = false
        measure()
        expectSize(preview.frameMarker, 300, 200)
        expectSize(preview.sample, natural.width, natural.height)
        state.stretchesContent = true
        measure()
        expectSize(preview.sample, 300, 200)

        state.scenario = .composition
        state.stretchesContent = false
        state.option = 1
        measure()
        expectSize(preview.resultMarker, 120, 64)
        state.option = 2
        measure()
        expectSize(preview.frameMarker, 120, 64)
        expectSize(preview.resultMarker, 144, 88)
        state = FrameLabState()
        measure()
        expectSize(preview.frameMarker, 120, 64)
        expectSize(preview.sample, natural.width, natural.height)
    }

    /// 验证 leading／trailing 随布局方向镜像，保持逻辑对齐语义。
    @Test func frameLabAlignmentMirrorsLeadingAndTrailing() {
        let preview = FrameLabPreviewView()
        preview.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        for rtl in [false, true] {
            preview.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            for index in 0..<9 {
                var state = FrameLabState()
                state.scenario = .alignment
                state.alignmentIndex = index
                preview.state = state
                preview.quickLayoutIfNeeded()
                preview.layoutIfNeeded()
                let availableX = 300 - preview.sample.bounds.width
                let availableY = 200 - preview.sample.bounds.height
                let column = rtl ? 2 - index % 3 : index % 3
                #expect(abs(preview.sample.frame.minX - CGFloat(column) * availableX / 2) < 1)
                #expect(abs(preview.sample.frame.minY - CGFloat(index / 3) * availableY / 2) < 1)
            }
        }
    }

    /// 遍历两种模式、三种语言、窄屏／横屏、六场景与宽度比例，检查实际几何和横向溢出。
    @Test func frameLabAdaptsControlsAndReportsActualGeometry() throws {
        defer { Localization.setLocale(identifier: "en-US") }
        for presentation in FrameLabPresentation.allCases {
            let controller = FrameLabViewController()
            let navigation = UINavigationController(rootViewController: controller)
            let window = try makeVisibleTestWindow(rootViewController: navigation, size: CGSize(width: 390, height: 844))
            defer { window.isHidden = true }
            controller.selectPresentation(presentation)
            let page = controller.contentView
            if presentation == .guided { page.toggleMoreParameters() }
            layout(controller, in: navigation)
            for locale in ["en-US", "zh-Hans", "ar"] {
                Localization.setLocale(identifier: locale)
                controller.reloadLocalizedContent()
                controller.reloadLayoutDirection(Localization.currentUIKitDirection)
                for size in [CGSize(width: 320, height: 740), CGSize(width: 740, height: 390)] {
                    window.frame.size = size
                    navigation.view.frame = window.bounds
                    for scenario in FrameLabScenario.allCases {
                        page.selectScenario(scenario)
                        for fraction: CGFloat in [0.5, 1] {
                            page.setContainer(widthFraction: fraction, height: 180)
                            layout(controller, in: navigation)
                            let stage = try #require(page.previewView.superview)
                            #expect(abs(page.previewView.bounds.width - stage.bounds.width * fraction) < 1)
                            #expect(abs(page.previewView.bounds.height - 180) < 1)
                            #expect(page.pageScrollView.contentSize.width <= page.pageScrollView.bounds.width + 1)
                            #expect(page.codeLabel.text == page.state.code)
                            #expect(page.metricsLabel.text?.contains("180") == true)
                        }
                    }
                }
            }
            page.reset()
            #expect(page.state.scenario == presentation.initialState.scenario && page.state.option == presentation.initialState.option)
            #expect(page.state.widthFraction == 1 && page.state.containerHeight == presentation.initialState.containerHeight)
            #expect(!page.state.stretchesContent)
            #expect(navigation.topViewController?.navigationItem.rightBarButtonItems?.count == 2)
        }
    }

    /// 验证连续尺寸变化不会替换分段视图或菜单，并能正常响应后续选项与语言变化。
    @Test func frameLabResizingPreservesSelectedControls() throws {
        defer { Localization.setLocale(identifier: "en-US") }
        Localization.setLocale(identifier: "zh-Hans")
        for presentation in FrameLabPresentation.allCases {
            let controller = FrameLabViewController()
            let navigation = UINavigationController(rootViewController: controller)
            let window = try makeVisibleTestWindow(rootViewController: navigation, size: CGSize(width: 390, height: 844))
            defer { window.isHidden = true }
            layout(controller, in: navigation)
            controller.selectPresentation(presentation)
            let page = controller.contentView
            page.selectScenario(.fixed)
            if presentation == .guided { page.toggleMoreParameters() }
            layout(controller, in: navigation)
            let options = try #require(page.allSubviews(of: UISegmentedControl.self).first)
            let scenario = try #require(page.allSubviews(of: UIButton.self).first { $0.accessibilityIdentifier == "frame.scenario" })
            let width = try #require(page.allSubviews(of: UISlider.self).first { $0.accessibilityIdentifier == "frame.width" })
            let height = try #require(page.allSubviews(of: UISlider.self).first { $0.accessibilityIdentifier == "frame.height" })
            // Retain the rendered segments so a teardown/rebuild cannot reuse their identities.
            let renderedSegments = options.subviews
            let presentationSegments = controller.presentationControl.subviews
            let menu = scenario.menu
            let initialWidth = page.previewView.bounds.width
            for fraction: Float in [0.9, 0.7, 0.5, 0.8, 1] {
                width.value = fraction
                width.sendActions(for: .valueChanged)
                height.value = 180
                height.sendActions(for: .valueChanged)
                layout(controller, in: navigation)
                #expect(options.subviews.map(ObjectIdentifier.init) == renderedSegments.map(ObjectIdentifier.init))
                #expect(controller.presentationControl.subviews.map(ObjectIdentifier.init) == presentationSegments.map(ObjectIdentifier.init))
                #expect(options.selectedSegmentIndex == 2)
                #expect(scenario.menu === menu)
                #expect(abs(page.previewView.bounds.width - initialWidth * CGFloat(fraction)) < 1)
                #expect(abs(page.previewView.bounds.height - 180) < 1)
            }
            options.selectedSegmentIndex = 0
            options.sendActions(for: .valueChanged)
            layout(controller, in: navigation)
            #expect(options.subviews.map(ObjectIdentifier.init) == renderedSegments.map(ObjectIdentifier.init))
            #expect(options.selectedSegmentIndex == 0)
            #expect(page.state.option == 0)
            page.selectScenario(.bounds)
            #expect(options.titleForSegment(at: 0) == Localization.text("frame.option.minimum"))
            Localization.setLocale(identifier: "en-US")
            page.reloadLocalizedContent()
            #expect(options.titleForSegment(at: 0) == Localization.text("frame.option.minimum"))
        }
    }

    /// 验证首页顺序、搜索与路由接入，并检查实验室全部文案的中英阿翻译完整性。
    @Test func frameLabRouteAndCatalogAreComplete() throws {
        defer { Localization.setLocale(identifier: "en-US") }
        Localization.setLocale(identifier: "en-US")
        let model = MainViewModel()
        let routes = try #require(model.state.sections.first?.routes.map(\.route))
        let index = try #require(routes.firstIndex(of: .frame))
        #expect(routes[index + 1] == .fixedSize)
        model.updateSearchQuery("Frame Lab")
        #expect(model.state.sections.flatMap(\.routes).map(\.route) == [.frame])
        let source = UIViewController()
        let navigation = UINavigationController(rootViewController: source)
        MainRouter().navigate(to: .frame, from: source)
        #expect(navigation.topViewController is FrameLabViewController)

        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Demo/Localizable.xcstrings")
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let keys = strings.keys.filter { $0.hasPrefix("frame.") || $0 == "demo.frame.title" }
        #expect(keys.count > 40)
        for key in keys {
            let localizations = try #require(strings[key]?["localizations"] as? [String: [String: Any]])
            for locale in ["en", "zh-Hans", "ar"] {
                let unit = try #require(localizations[locale]?["stringUnit"] as? [String: String])
                #expect(unit["value"]?.isEmpty == false)
            }
        }
    }

    /// 验证辅助功能字号下用菜单替代分段，滑块与九宫格仍满足触控尺寸且不横向溢出。
    @Test func frameLabLargeTextKeepsControlsReachable() throws {
        defer { Localization.setLocale(identifier: "en-US") }
        Localization.setLocale(identifier: "zh-Hans")
        for presentation in FrameLabPresentation.allCases {
            let controller = FrameLabViewController()
            let navigation = UINavigationController(rootViewController: controller)
            let window = try makeVisibleTestWindow(rootViewController: navigation,
                                                   size: CGSize(width: 320, height: 740),
                                                   contentSizeCategory: .accessibilityExtraExtraExtraLarge)
            defer { window.isHidden = true }
            controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            layout(controller, in: navigation)
            controller.selectPresentation(presentation)
            let page = controller.contentView
            page.selectScenario(.fixed)
            if presentation == .guided { page.toggleMoreParameters() }
            layout(controller, in: navigation)
            let menu = try #require(page.allSubviews(of: UIButton.self).first { $0.accessibilityIdentifier == "frame.optionMenu" })
            #expect(menu.bounds.height >= 44)
            #expect(page.allSubviews(of: UISegmentedControl.self).isEmpty)
            #expect(page.pageScrollView.contentSize.width <= page.pageScrollView.bounds.width + 1)
            for slider in page.allSubviews(of: UISlider.self) { #expect(slider.bounds.height >= 44) }
            #expect(page.codeLabel.numberOfLines == 0)
            if presentation == .guided {
                page.selectScenario(.alignment)
                layout(controller, in: navigation)
                let grid = try #require(page.allSubviews(of: UIView.self).first { $0.accessibilityIdentifier == "frame.alignmentGrid" })
                for button in grid.allSubviews(of: UIButton.self) {
                    #expect(button.bounds.width >= 44 && button.bounds.height >= 44)
                }
                #expect(page.pageScrollView.contentSize.width <= page.pageScrollView.bounds.width + 1)
            }
        }
    }
}
