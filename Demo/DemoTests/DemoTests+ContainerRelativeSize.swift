import AppLocalization
import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

extension DemoTests {
    @Test func containerRelativeSizeDemoMeasuresRealContent() {
        Localization.setLocale(identifier: "en-US")
        let preview = ContainerRelativeSizePreviewView()

        func measure(_ scenario: ContainerRelativeSizeDemoViewController.Scenario, width: CGFloat) {
            preview.frame = CGRect(x: 0, y: 0, width: width, height: 240)
            preview.configure(scenario: scenario)
            preview.quickLayoutIfNeeded()
            preview.layoutIfNeeded()
        }
        func expectSize(_ view: UIView, width: CGFloat, height: CGFloat) {
            #expect(abs(view.bounds.width - width) < 1)
            #expect(abs(view.bounds.height - height) < 1)
        }

        measure(.natural, width: 360)
        let shortSize = preview.firstSample.bounds.size
        let longHeight = preview.secondSample.bounds.height
        #expect(shortSize.width > 0 && shortSize.width < 180)
        #expect(preview.secondSample.bounds.width <= 361)
        measure(.natural, width: 180)
        expectSize(preview.firstSample, width: shortSize.width, height: shortSize.height)
        #expect(preview.secondSample.bounds.width <= 181)
        #expect(preview.secondSample.bounds.height > longHeight)

        for width: CGFloat in [180, 360, 600] {
            measure(.proportional, width: width)
            expectSize(preview.firstSample, width: width * 0.7, height: 64)
            expectSize(preview.secondSample, width: width, height: 64)
            measure(.crossAxis, width: width)
            expectSize(preview.firstSample, width: width, height: min(240, width * 9 / 16))
            #expect(preview.secondSample.superview == nil)
            measure(.nested, width: width)
            expectSize(preview.firstSample, width: width * 0.7, height: 80)
            expectSize(preview.secondSample, width: width * 0.7, height: 120)
            #expect(preview.secondSample.frame.minY >= preview.firstSample.frame.maxY)
        }
        // 再次切回基础场景，保证嵌套上限没有泄漏到之后的布局。
        measure(.natural, width: 360)
        expectSize(preview.firstSample, width: shortSize.width, height: shortSize.height)
    }

    @Test func containerRelativeSizeDemoResizesAndLocalizes() throws {
        defer { Localization.setLocale(identifier: "en-US") }
        let page = ContainerRelativeSizeDemoViewController()
        let navigation = UINavigationController(rootViewController: page)
        let window = try makeVisibleTestWindow(rootViewController: navigation, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }

        for locale in ["en-US", "zh-Hans", "ar"] {
            Localization.setLocale(identifier: locale)
            page.reloadLocalizedContent()
            page.reloadLayoutDirection(Localization.currentUIKitDirection)
            for size in [CGSize(width: 320, height: 740), CGSize(width: 740, height: 390)] {
                window.frame.size = size
                navigation.view.frame = window.bounds
                for scenario in ContainerRelativeSizeDemoViewController.Scenario.allCases {
                    page.selectScenario(at: scenario.rawValue)
                    for fraction: CGFloat in [1, 0.5] {
                        page.setWidthFraction(fraction)
                        layout(page, in: navigation)
                        let preview = page.previewView
                        let stage = try #require(preview.superview)
                        #expect(abs(preview.bounds.width - stage.bounds.width * fraction) < 1)
                        #expect(abs(preview.bounds.height - 240) < 1)
                        #expect(page.pageScrollView.contentSize.width <= page.pageScrollView.bounds.width + 1)
                        #expect(preview.effectiveUserInterfaceLayoutDirection == Localization.currentUIKitDirection)
                        #expect(page.metricsLabel.text?.contains("240") == true)
                        for sample in preview.visibleSamples {
                            #expect(sample.frame.minX >= -1)
                            #expect(sample.frame.maxX <= preview.bounds.width + 1)
                        }
                        if scenario == .proportional || scenario == .nested {
                            let first = preview.firstSample
                            #expect(abs(first.bounds.width - preview.bounds.width * 0.7) < 1)
                            if locale == "ar" {
                                #expect(abs(first.frame.maxX - preview.bounds.width) < 1)
                            } else {
                                #expect(abs(first.frame.minX) < 1)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func containerRelativeSizeDemoRouteAndStrings() throws {
        defer { Localization.setLocale(identifier: "en-US") }
        let viewModel = MainViewModel()
        let routes = try #require(viewModel.state.sections.first?.routes.map(\.route))
        let index = try #require(routes.firstIndex(of: .fixedSize))
        #expect(routes[index + 1] == .containerRelativeSize)
        viewModel.updateSearchQuery("ContainerRelativeSize")
        #expect(viewModel.state.sections.flatMap(\.routes).map(\.route) == [.containerRelativeSize])

        let source = UIViewController()
        let navigation = UINavigationController(rootViewController: source)
        MainRouter().navigate(to: .containerRelativeSize, from: source)
        #expect(navigation.topViewController is ContainerRelativeSizeDemoViewController)

        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Demo/Localizable.xcstrings")
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let keys = strings.keys.filter { $0.hasPrefix("containerRelativeSize.") || $0 == "demo.containerRelativeSize.title" }
        #expect(!keys.isEmpty)
        for key in keys {
            let localizations = try #require(strings[key]?["localizations"] as? [String: [String: Any]])
            for locale in ["en", "zh-Hans", "ar"] {
                let unit = try #require(localizations[locale]?["stringUnit"] as? [String: String])
                #expect(unit["value"]?.isEmpty == false)
            }
        }
    }
}
