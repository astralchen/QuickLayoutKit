import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct DirectionalGridPageTests {
    @Test func reducedFixedGridViewportFollowsSelectedAlignment() async throws {
        let root = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: root)
        defer { window.isHidden = true }
        let preview = DirectionalGridPreviewView(frame: CGRect(x: 0, y: 0, width: 420, height: 420))
        root.view.addSubview(preview)
        preview.sizing = 0
        preview.availableFraction = 0.6
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for alignment in 0..<3 {
                    preview.isHorizontal = horizontal
                    preview.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
                    preview.alignmentIndex = alignment
                    preview.setNeedsQuickLayout()
                    preview.layoutIfNeeded()
                    let scroll = try #require(preview.allSubviews(of: QuickLayoutScrollView.self).first)
                    #expect(await waitForCondition {
                        preview.layoutIfNeeded()
                        scroll.layoutIfNeeded()
                        let viewport = scroll.convert(scroll.bounds, to: preview)
                        let insetBounds = preview.bounds.insetBy(dx: 12, dy: 12)
                        let actual = horizontal ? viewport.minY : viewport.minX
                        let length = horizontal ? insetBounds.height : insetBounds.width
                        let physicalAlignment = !horizontal && rtl ? 2 - alignment : alignment
                        let expected = 12 + length * (1 - preview.availableFraction) * CGFloat(physicalAlignment) / 2
                        return abs(actual - expected) < 1
                            && abs((horizontal ? viewport.height : viewport.width) - length * 0.6) < 1
                    }, "horizontal \(horizontal), RTL \(rtl), alignment \(alignment)")
                    let first = preview.cards[0].convert(preview.cards[0].bounds, to: scroll)
                    let second = preview.cards[1].convert(preview.cards[1].bounds, to: scroll)
                    if alignment == 0 {
                        #expect(abs(horizontal ? first.minY : rtl ? first.maxX - scroll.bounds.width : first.minX) < 1)
                    } else if alignment == 2 {
                        #expect(abs(horizontal ? second.maxY - scroll.bounds.height : rtl ? second.minX : second.maxX - scroll.bounds.width) < 1)
                    }
                }
            }
        }
    }

    @Test func pageContentTracksHorizontalSafeAreaChanges() async throws {
        let page = DirectionalGridViewController()
        let navigation = UINavigationController(rootViewController: page)
        let window = try makeVisibleTestWindow(rootViewController: navigation)
        defer { window.isHidden = true }
        let scroll = try #require(page.view.allSubviews(of: QuickLayoutScrollView.self).first)
        let axis = try #require(page.view.allSubviews(of: UISegmentedControl.self)
            .first { $0.accessibilityIdentifier == "directionalGrid.axis" })
        let slider = try #require(page.view.allSubviews(of: UISlider.self).first)
        for size in [CGSize(width: 1000, height: 700), CGSize(width: 440, height: 800)] {
            window.frame.size = size
            for insets in [UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 12),
                           UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 64), .zero] {
                page.additionalSafeAreaInsets = insets
                for horizontal in [false, true] {
                    axis.selectedSegmentIndex = horizontal ? 1 : 0
                    axis.sendActions(for: .valueChanged)
                    let fitsSafeArea = await waitForCondition {
                        window.layoutIfNeeded()
                        page.view.layoutIfNeeded()
                        scroll.layoutIfNeeded()
                        let safe = page.view.safeAreaLayoutGuide.layoutFrame
                        let preview = page.preview.convert(page.preview.bounds, to: page.view)
                        let control = slider.convert(slider.bounds, to: page.view)
                        return abs(preview.minX - safe.minX - 20) < 1
                            && abs(preview.maxX - safe.maxX + 20) < 1
                            && control.minX >= safe.minX + 19
                            && control.maxX <= safe.maxX - 19
                            && abs(scroll.contentSize.width + scroll.adjustedContentInset.left
                                + scroll.adjustedContentInset.right - scroll.bounds.width) < 1
                    }
                    #expect(fitsSafeArea,
                            "size \(size), insets \(insets), horizontal \(horizontal); safe \(page.view.safeAreaLayoutGuide.layoutFrame), preview \(page.preview.convert(page.preview.bounds, to: page.view)), slider \(slider.convert(slider.bounds, to: page.view)), scroll \(scroll.frame), content \(scroll.contentSize), adjusted \(scroll.adjustedContentInset)")
                }
            }
        }
    }

    @Test func menuRouteCreatesGridPage() {
        let model = MainViewModel()
        #expect(model.state.sections.contains { $0.routes.contains { $0.route == .directionalGrid } })
        #expect(MainRouter().makeViewController(for: .directionalGrid) is DirectionalGridViewController)
    }

    @Test func resizingAndDirectionChangesKeepAllCards() async {
        let preview = DirectionalGridPreviewView()
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 700))
        window.rootViewController = root
        window.isHidden = false
        root.view.addSubview(preview)
        defer { window.isHidden = true }
        let identities = preview.cards.map(ObjectIdentifier.init)
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for fraction in [CGFloat(1), 0.5] {
                    preview.isHorizontal = horizontal
                    preview.availableFraction = fraction
                    preview.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
                    preview.frame = CGRect(x: 0, y: 0, width: 360, height: 420)
                    preview.setNeedsQuickLayout()
                    for _ in 0..<6 {
                        window.layoutIfNeeded()
                        preview.layoutIfNeeded()
                        try? await Task.sleep(for: .milliseconds(15))
                    }
                    #expect(preview.cards.map(ObjectIdentifier.init) == identities)
                    #expect(preview.cards.allSatisfy { $0.window === window && $0.bounds.width > 0 && $0.bounds.height > 0 })
                    let first = preview.cards[0].frame
                    let second = preview.cards[1].frame
                    if horizontal {
                        #expect(second.minY > first.minY)
                        let last = preview.cards[10].frame
                        #expect(rtl ? last.minX < first.minX : last.minX > first.minX)
                    } else {
                        #expect(rtl ? second.minX < first.minX : second.minX > first.minX)
                        #expect(preview.cards[10].frame.minY > first.minY)
                    }
                }
            }
        }
    }

    @Test func previewDoesNotRetainItsHostingView() async {
        weak var released: DirectionalGridPreviewView?
        autoreleasepool {
            let view = DirectionalGridPreviewView(frame: CGRect(x: 0, y: 0, width: 320, height: 420))
            released = view
            view.setNeedsQuickLayout()
            view.layoutIfNeeded()
        }
        await Task.yield()
        #expect(released == nil)
    }
}
