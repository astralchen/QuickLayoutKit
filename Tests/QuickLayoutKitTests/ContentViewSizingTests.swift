import Testing
import UIKit
import QuickLayout
import QuickLayoutKitUIKit

@MainActor
extension QuickLayoutKitTests {
    @Test(arguments: [CGFloat.zero, 180])
    func contentViewIntrinsicSizeUsesPublicMeasurement(width: CGFloat) {
        let view = ContentSizingProbe(configuration: ContentSizingConfiguration())
        view.bounds.size = CGSize(width: width, height: 12)

        let size = view.intrinsicContentSize

        #expect(size == CGSize(width: UIView.noIntrinsicMetric, height: 73))
        #expect(view.proposals == [CGSize(
            width: width > 0 ? width : .infinity, height: CGFloat.infinity
        )])
    }

    @Test func contentViewInvalidatesIntrinsicSizeWhenWidthChanges() {
        let view = ContentSizingProbe(configuration: ContentSizingConfiguration())
        view.bounds.size = CGSize(width: 180, height: 12)
        let initialCount = view.invalidationCount

        view.bounds.size.height = 40
        #expect(view.invalidationCount == initialCount)
        view.bounds.origin.x = 10
        #expect(view.invalidationCount == initialCount)
        view.bounds.size.width = 240
        #expect(view.invalidationCount > initialCount)
        #expect(view.proposals.isEmpty)
    }

    @Test func contentViewInvalidatesIntrinsicSizeForLayoutAndConfigurationChanges() {
        let view = ContentSizingProbe(configuration: ContentSizingConfiguration())
        let initialCount = view.invalidationCount

        view.setNeedsQuickLayout()
        #expect(view.invalidationCount > initialCount)
        let layoutCount = view.invalidationCount
        view.configuration = ContentSizingConfiguration()
        #expect(view.invalidationCount > layoutCount)
        #expect(view.proposals.isEmpty)
    }

    @Test(arguments: [Flexibility.fixedSize, .partial, .fullyFlexible],
          [Flexibility.fixedSize, .partial, .fullyFlexible])
    func contentViewExplicitFlexibilityControlsIntrinsicAxes(horizontal: Flexibility, vertical: Flexibility) {
        let view = ContentSizingProbe(configuration: ContentSizingConfiguration())
        view.quickLayoutHorizontalFlexibility = horizontal
        view.quickLayoutVerticalFlexibility = vertical
        view.bounds.size = CGSize(width: 180, height: 120)
        let result = view.intrinsicContentSize
        #expect(result.width == (horizontal == .fixedSize ? UIView.noIntrinsicMetric : 91))
        #expect(result.height == (vertical == .fixedSize ? UIView.noIntrinsicMetric : 73))
        if horizontal == .fixedSize && vertical == .fixedSize {
            #expect(view.proposals.isEmpty)
        } else {
            #expect(view.proposals == [CGSize(
                width: horizontal == .fullyFlexible ? CGFloat.infinity : 180,
                height: vertical == .fullyFlexible ? CGFloat.infinity : 120
            )])
        }
        let beforeWidth = view.invalidationCount
        view.bounds.size.width += 10
        #expect((view.invalidationCount > beforeWidth) == (horizontal != .fullyFlexible && !(horizontal == .fixedSize && vertical == .fixedSize)))
        let beforeHeight = view.invalidationCount
        view.bounds.size.height += 10
        #expect((view.invalidationCount > beforeHeight) == (vertical != .fullyFlexible && !(horizontal == .fixedSize && vertical == .fixedSize)))
    }

    @Test func contentViewHorizontalIntrinsicSizeUsesPublicMeasurement() {
        let host = UIView()
        let view = ContentSizingProbe(configuration: ContentSizingConfiguration())
        view.quickLayoutHorizontalFlexibility = .fullyFlexible
        view.quickLayoutVerticalFlexibility = .fixedSize
        view.bounds.size.height = 120
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        let result = host.systemLayoutSizeFitting(
            CGSize(width: UIView.layoutFittingExpandedSize.width, height: 120),
            withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .required
        )
        #expect(result == CGSize(width: 91, height: 120))
        #expect(view.proposals.allSatisfy { $0 == CGSize(width: CGFloat.infinity, height: 120) })
    }

    @Test func contentViewProvidesHeightToAutoLayoutHost() {
        let host = UIView()
        let view = ContentSizingProbe(configuration: ContentSizingConfiguration())
        view.bounds.size.width = 180
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        let size = host.systemLayoutSizeFitting(
            CGSize(width: 180, height: UIView.layoutFittingExpandedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(size == CGSize(width: 180, height: 73))
    }
}

private struct ContentSizingConfiguration: UIContentConfiguration {
    func makeContentView() -> UIView & UIContentView {
        ContentSizingProbe(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self { self }
}

@MainActor
private final class ContentSizingProbe: QuickLayoutContentView {
    var proposals: [CGSize] = []
    var invalidationCount = 0

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        proposals.append(size)
        return CGSize(width: 91, height: 73)
    }

    override func invalidateIntrinsicContentSize() {
        invalidationCount += 1
        super.invalidateIntrinsicContentSize()
    }
}
