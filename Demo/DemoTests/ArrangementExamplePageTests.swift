#if compiler(>=6.4)
import Testing
import UIKit
@testable import Demo

@MainActor
struct ArrangementExamplePageTests {
    @Test func resizingLabKeepsSliderPositionAndUsesAvailableHeight() async throws {
        let page = ArrangementViewController()
        let window = try makeVisibleTestWindow(rootViewController: page)
        defer { window.isHidden = true }
        let slider = try #require(page.view.allSubviews(of: UISlider.self).first)
        let preview = try #require(page.view.allSubviews(of: ArrangementPreview.self).first)
        slider.value = 0.7
        slider.sendActions(for: .valueChanged)
        for size in [CGSize(width: 600, height: 800), CGSize(width: 430, height: 340),
                     CGSize(width: 600, height: 800)] {
            window.frame.size = size
            #expect(await waitForCondition {
                window.layoutIfNeeded()
                let available = page.view.safeAreaLayoutGuide.layoutFrame.height
                let minimum = min(180, available)
                let expected = floor(minimum + CGFloat(slider.value) * (available - minimum))
                return page.view.bounds.size == size && slider.value == 0.7
                    && preview.bounds.height == expected
            })
        }
    }

    @available(iOS 27.1, *)
    @Test func compactWindowAndWidePanesMatchNativeTraits() async throws {
        let root = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: root)
        defer { window.isHidden = true }
        let kit = ArrangementPreview()
        let native = makeArrangementReference(.automatic, direction: root.view.effectiveUserInterfaceLayoutDirection)
        root.view.addSubview(kit)
        root.view.addSubview(native)
        for sizeClass in [UIUserInterfaceSizeClass.compact, .regular] {
            root.traitOverrides.horizontalSizeClass = sizeClass
            root.traitOverrides.verticalSizeClass = sizeClass
            for size in [CGSize(width: 800, height: 300), CGSize(width: 300, height: 800),
                         CGSize(width: 1400, height: 600)] {
                kit.frame = CGRect(origin: CGPoint(x: 0, y: 100), size: size)
                native.frame = kit.frame
                await expectMatchingPanes(kit, native, context: "\(sizeClass) \(size)")
            }
        }
    }

    /// 同一内容、同一位置，只替换排列实现。覆盖菜单里实际运行的每一种场景。
    @available(iOS 27.1, *)
    @Test func examplesMatchSwiftUIInWindowAndResizedPreviews() async throws {
        let root = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: root)
        defer { window.isHidden = true }
        let kit = ArrangementPreview()
        root.view.addSubview(kit)
        for example in ArrangementExample.allCases {
            kit.example = example
            let reference = makeArrangementReference(example, direction: root.view.effectiveUserInterfaceLayoutDirection)
            root.view.addSubview(reference)
            defer { reference.removeFromSuperview() }

            for frame in [root.view.bounds, CGRect(x: 24, y: 110, width: 320, height: 200),
                          CGRect(x: 24, y: 110, width: 320, height: 400)] {
                kit.frame = frame
                reference.frame = frame
                kit.setNeedsLayout()
                await expectMatchingPanes(kit, reference, context: "\(example) \(frame)")
            }
        }
    }

    private struct Sample {
        let frame: CGRect
        let text: String
        let horizontal: UIUserInterfaceSizeClass
        let vertical: UIUserInterfaceSizeClass

        func matches(_ other: Sample) -> Bool {
            abs(frame.minX - other.frame.minX) <= 1 && abs(frame.minY - other.frame.minY) <= 1
                && abs(frame.width - other.frame.width) <= 1 && abs(frame.height - other.frame.height) <= 1
                && text == other.text && horizontal == other.horizontal && vertical == other.vertical
        }
    }

    /// 预览随内容滚动经过折痕时，在相同位置与原生排列比较两个区域。
    @available(iOS 27.1, *)
    @Test func scrollingPreviewMatchesSwiftUI() async throws {
        let root = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: root)
        defer { window.isHidden = true }
        let scroll = UIScrollView(frame: root.view.bounds)
        scroll.contentInsetAdjustmentBehavior = .never
        root.view.addSubview(scroll)
        scroll.contentSize = CGSize(width: scroll.bounds.width, height: scroll.bounds.height + 200)
        let kit = ArrangementPreview()
        scroll.addSubview(kit)
        for example in [ArrangementExample.ratio, .overlay] {
            kit.example = example
            let native = makeArrangementReference(example, direction: .leftToRight)
            scroll.addSubview(native)
            defer { native.removeFromSuperview() }
            for height: CGFloat in [394, 720] {
                kit.frame = CGRect(x: 20, y: 215, width: scroll.bounds.width - 40, height: height)
                native.frame = kit.frame
                kit.setNeedsLayout()
                for y: CGFloat in [0, 140, 0] {
                    scroll.contentOffset.y = y
                    scroll.layoutIfNeeded()
                    await expectMatchingPanes(kit, native, context: "\(example), height \(height), offset \(y)")
                }
            }
        }
    }

    @available(iOS 27.1, *)
    @Test func sidebarDetailMatchesSwiftUIAsPreviewExtendsPastWindow() async throws {
        let root = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: root)
        defer { window.isHidden = true }
        let kit = ArrangementPreview()
        let native = makeArrangementReference(.automatic, direction: .leftToRight)
        let scroll = UIScrollView(frame: root.view.bounds)
        scroll.contentInsetAdjustmentBehavior = .never
        root.view.addSubview(scroll)
        scroll.contentSize = CGSize(width: scroll.bounds.width, height: scroll.bounds.height + 100)
        scroll.addSubview(kit)
        scroll.addSubview(native)
        // 模拟侧栏右边的详情列，滚动前预览下端超出窗口，滚动后完全可见。
        let x = max(0, window.bounds.midX - 189)
        let width = min(540, window.bounds.width - x)
        kit.frame = CGRect(x: x, y: window.bounds.maxY - 490 + 36, width: width, height: 490)
        native.frame = kit.frame
        for offset: CGFloat in [0, 76, 0] {
            scroll.contentOffset.y = offset
            scroll.layoutIfNeeded()
            await expectMatchingPanes(kit, native, context: "sidebar detail, scroll offset \(offset)")
        }
    }

    @available(iOS 27.1, *)
    @Test func constrainedSplitMatchesSwiftUIAtDifferentFoldPositions() async throws {
        let root = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: root)
        defer { window.isHidden = true }
        let width = min(540, window.bounds.width)
        for direction in [UIUserInterfaceLayoutDirection.leftToRight, .rightToLeft] {
            root.traitOverrides.layoutDirection = direction == .rightToLeft ? .rightToLeft : .leftToRight
            for example in [ArrangementExample.range, .size, .fixed] {
                let kit = ArrangementPreview()
                kit.example = example
                kit.semanticContentAttribute = direction == .leftToRight ? .forceLeftToRight : .forceRightToLeft
                let native = makeArrangementReference(example, direction: direction)
                root.view.addSubview(kit)
                root.view.addSubview(native)
                defer { kit.removeFromSuperview(); native.removeFromSuperview() }
                for leadingFraction in [0.313, 0.36, 0.46, 0.613, 0.83] {
                    let x = window.bounds.midX - width * leadingFraction - 20
                    kit.frame = CGRect(x: max(0, min(window.bounds.width - width, x)),
                                       y: 175, width: width, height: 340)
                    native.frame = kit.frame
                    kit.setNeedsLayout()
                    await expectMatchingPanes(kit, native, context: "\(example), \(direction), \(kit.frame)")
                }
            }
        }
    }

    private func samples(in host: UIView) -> [String: Sample] {
        host.layoutIfNeeded()
        var result: [String: Sample] = [:]
        for pane in host.allSubviews(of: ArrangementExamplePane.self) {
            guard let label = pane.subviews.compactMap({ $0 as? UILabel }).first,
                  let id = label.accessibilityIdentifier, let text = label.text else { continue }
            result[id] = Sample(frame: pane.convert(pane.bounds, to: host), text: text,
                                horizontal: pane.traitCollection.horizontalSizeClass,
                                vertical: pane.traitCollection.verticalSizeClass)
        }
        return result
    }

    private func expectMatchingPanes(_ kit: UIView, _ native: UIView, context: String) async {
        let matched = await waitForCondition {
            let actual = samples(in: kit), expected = samples(in: native)
            guard actual["arrangement.primary"]?.frame.isEmpty == false, actual.keys == expected.keys else { return false }
            return actual.allSatisfy { id, pane in expected[id].map(pane.matches) == true }
        }
        #expect(matched, "\(context), kit \(samples(in: kit)), SwiftUI \(samples(in: native))")
    }
}
#endif
