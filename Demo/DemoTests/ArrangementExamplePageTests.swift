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
