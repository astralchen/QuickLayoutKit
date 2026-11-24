import QuickLayoutKit
import SwiftUI
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct HostingControllerSizingTests {
    @Test func flagsAreIndependentAndShareOneIdealMeasurement() {
        let probe = SizingProbe()
        let host = PreferredSizeProbeController { probe }
        let fallback = UIView().intrinsicContentSize
        #expect(host.sizingOptions.isEmpty)
        host.loadViewIfNeeded()
        host.view.frame.size = CGSize(width: 320, height: 400)
        host.setNeedsQuickLayout()
        host.quickLayoutIfNeeded()
        #expect(host.view.intrinsicContentSize == fallback)
        #expect(probe.idealMeasurements == 0)

        host.sizingOptions = [.intrinsicContentSize]
        #expect(host.view.intrinsicContentSize == probe.contentSize)
        #expect(host.preferredContentSize == .zero)
        host.sizingOptions.insert(.preferredContentSize)
        #expect(host.preferredContentSize == probe.contentSize)
        #expect(probe.idealMeasurements == 1)

        let writes = host.preferredSizeWrites
        host.setNeedsQuickLayout()
        host.setNeedsQuickLayout()
        host.quickLayoutIfNeeded()
        #expect(host.view.intrinsicContentSize == probe.contentSize)
        #expect(probe.idealMeasurements == 2)
        #expect(host.preferredSizeWrites == writes)

        host.sizingOptions.remove(.intrinsicContentSize)
        #expect(host.view.intrinsicContentSize == fallback)
        probe.contentSize = CGSize(width: 72, height: 40)
        host.setNeedsQuickLayout()
        host.quickLayoutIfNeeded()
        #expect(host.preferredContentSize == probe.contentSize)
        host.sizingOptions = []
        let retained = host.preferredContentSize
        probe.contentSize = CGSize(width: 125, height: 56)
        host.setNeedsQuickLayout()
        host.quickLayoutIfNeeded()
        #expect(host.preferredContentSize == retained)
        host.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        #expect(host.preferredContentSize == probe.contentSize)
        #expect(host.view.intrinsicContentSize == probe.contentSize)
    }

    @Test func idealSizeIsSeparateFromTextWrappingAndTracksEnvironment() {
        let label = UILabel()
        label.numberOfLines = 0
        label.text = "A multiline label that wraps at a narrow proposed width."
        let host = QuickLayoutHostingController(sizingOptions: [.preferredContentSize, .intrinsicContentSize]) {
            label
        }
        #expect(!host.isViewLoaded)
        host.loadViewIfNeeded()

        let ideal = host.view.intrinsicContentSize
        let wrapped = host.sizeThatFits(in: CGSize(width: 90, height: CGFloat.infinity))
        #expect(ideal.width > wrapped.width)
        #expect(wrapped.height > ideal.height)
        #expect(host.preferredContentSize == ideal)
        host.view.frame.size = CGSize(width: 90, height: 200)
        host.quickLayoutIfNeeded()
        #expect(label.bounds.height == wrapped.height)

        label.text = "Short"
        host.view.semanticContentAttribute = .forceRightToLeft
        host.quickLayoutIfNeeded()
        #expect(host.view.intrinsicContentSize.width < ideal.width)
        #expect(host.preferredContentSize == host.view.intrinsicContentSize)
    }

    @Test func idealMeasurementPreservesNestedRelativeContainer() {
        let leaf = UIView()
        let nested = QuickLayoutView { leaf.resizable().containerRelativeFrame(.horizontal) }
        let host = QuickLayoutHostingController { nested.frame(width: 80, height: 48) }
        host.view.frame.size = CGSize(width: 320, height: 180)
        host.quickLayoutIfNeeded()
        host.sizingOptions = [.preferredContentSize]
        nested.setNeedsQuickLayout()
        nested.quickLayoutIfNeeded()
        #expect(leaf.bounds.width == 320)
    }

    @Test func stackViewGrowsAndShrinksAfterContentChanges() async throws {
        let parent = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: parent)
        defer { window.isHidden = true }
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        parent.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: parent.view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
        ])
        let probe = SizingProbe()
        let child = QuickLayoutHostingController { probe }
        child.sizingOptions = [.intrinsicContentSize]
        parent.addChild(child)
        stack.addArrangedSubview(child.view)
        child.didMove(toParent: parent)

        for size in [probe.contentSize, CGSize(width: 180, height: 80), CGSize(width: 54, height: 30)] {
            probe.contentSize = size
            child.setNeedsQuickLayout()
            #expect(await waitForCondition {
                parent.view.layoutIfNeeded()
                return stack.bounds.size == size && child.view.bounds.size == size
            })
        }
    }

    @available(iOS 16.0, *)
    @Test func fixedContentMatchesNativeHostingOptions() async throws {
        let parent = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: parent)
        defer { window.isHidden = true }
        let probe = SizingProbe()
        let initialSize = probe.contentSize
        let native = UIHostingController(rootView: Color.clear.frame(width: initialSize.width, height: initialSize.height))
        native.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        let host = QuickLayoutHostingController { probe }
        host.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        for child in [native, host] as [UIViewController] {
            parent.addChild(child)
            parent.view.addSubview(child.view)
            child.view.frame = CGRect(x: parent.view.bounds.midX - 100, y: parent.view.bounds.midY - 60,
                                      width: 200, height: 120)
            child.didMove(toParent: parent)
            child.view.layoutIfNeeded()
            #expect(child.view.safeAreaInsets == .zero)
        }
        for size in [initialSize, CGSize(width: 164, height: 78)] {
            probe.contentSize = size
            host.setNeedsQuickLayout()
            native.rootView = Color.clear.frame(width: size.width, height: size.height)
            #expect(await waitForCondition {
                native.preferredContentSize == size && host.preferredContentSize == size
            })
            #expect(host.view.intrinsicContentSize == native.view.intrinsicContentSize)
        }
    }

    @Test(.enabled { @MainActor in UIDevice.current.userInterfaceIdiom == .pad })
    func popoverTracksPreferredSizeWhilePresented() async throws {
        let parent = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: parent)
        defer { window.isHidden = true }
        let probe = SizingProbe()
        probe.contentSize = CGSize(width: 260, height: 150)
        let host = QuickLayoutHostingController { probe }
        host.sizingOptions = [.preferredContentSize]
        host.modalPresentationStyle = .popover
        let popover = try #require(host.popoverPresentationController)
        popover.sourceView = parent.view
        popover.sourceRect = CGRect(x: parent.view.bounds.midX, y: 80, width: 1, height: 1)
        await withCheckedContinuation { continuation in
            parent.present(host, animated: false) { continuation.resume() }
        }
        defer { host.dismiss(animated: false) }
        #expect(host.preferredContentSize == probe.contentSize)
        #expect(abs(host.view.bounds.width - probe.contentSize.width) <= 1)
        let initialHeight = host.view.bounds.height
        probe.contentSize = CGSize(width: 340, height: 230)
        host.setNeedsQuickLayout()
        #expect(await waitForCondition {
            host.preferredContentSize == probe.contentSize
                && abs(host.view.bounds.width - probe.contentSize.width) <= 1
                && host.view.bounds.height >= initialHeight + 79
        })
    }
}

@MainActor
private final class SizingProbe: UIView {
    var contentSize = CGSize(width: 104, height: 48)
    private(set) var idealMeasurements = 0

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        if size.width.isInfinite && size.height.isInfinite { idealMeasurements += 1 }
        return contentSize
    }
}

@MainActor
private final class PreferredSizeProbeController: QuickLayoutHostingController {
    private(set) var preferredSizeWrites = 0

    override var preferredContentSize: CGSize {
        didSet { preferredSizeWrites += 1 }
    }
}
