import Testing
import QuickLayout
import UIKit
@testable import QuickLayoutKitCore
@_spi(Testing) @testable import QuickLayoutKitUIKit

@MainActor
private final class KeyboardDockingResolverState {
    weak var window: UIWindow?
    var treatsKeyboardAsSplitOrUndocked = false
}

// UIKit layout probes initialize process-wide screen metrics. Running those
// probes concurrently can deadlock Swift Testing when one worker initializes
// UIScreen-backed state while a MainActor test waits on the same static once.
@Suite(.serialized)
struct QuickLayoutKitTests {

    @MainActor
    @Test func gradientViewUsesGradientAsItsRootLayerAndUpdatesConfiguration() {
        let evenlyDistributedGradient = QuickLayoutGradient(
            colors: [.systemPink, .systemPurple, .systemBlue]
        )
        #expect(
            evenlyDistributedGradient.stops.map(\.location) == [0, 0.5, 1]
        )

        let view = QuickLayoutLinearGradientView(
            stops: [
                QuickLayoutGradient.Stop(color: .systemPink, location: 0.15),
                QuickLayoutGradient.Stop(color: .systemBlue, location: 0.85),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        view.frame = CGRect(x: 0, y: 0, width: 240, height: 120)
        view.layoutIfNeeded()

        #expect(view.layer === view.gradientLayer)
        #expect(view.gradientLayer.frame == view.bounds)
        #expect(view.gradientLayer.colors?.count == 2)
        #expect(view.gradient.stops.map(\.location) == [0.15, 0.85])
        #expect(view.startPoint.x == UnitPoint.leading.x)
        #expect(view.startPoint.y == UnitPoint.leading.y)
        #expect(view.endPoint.x == UnitPoint.trailing.x)
        #expect(view.endPoint.y == UnitPoint.trailing.y)
        #expect(view.gradientLayer.startPoint == CGPoint(x: 0, y: 0.5))
        #expect(view.gradientLayer.endPoint == CGPoint(x: 1, y: 0.5))
        #expect(view.gradientLayer.type == .axial)
        #expect(!view.isOpaque)

        view.gradient = QuickLayoutGradient(stops: [
            QuickLayoutGradient.Stop(color: .systemYellow, location: 0),
            QuickLayoutGradient.Stop(color: .systemOrange, location: 0.4),
            QuickLayoutGradient.Stop(color: .systemRed, location: 1),
        ])
        view.startPoint = .top
        view.endPoint = .bottom

        #expect(view.gradientLayer.colors?.count == 3)
        #expect(
            view.gradientLayer.locations?.map(\.doubleValue) == [0, 0.4, 1]
        )
        #expect(view.gradientLayer.startPoint == CGPoint(x: 0.5, y: 0))
        #expect(view.gradientLayer.endPoint == CGPoint(x: 0.5, y: 1))
        #expect(view.gradientLayer.type == .axial)

        view.startPoint = .leading
        view.endPoint = .trailing
        view.semanticContentAttribute = .forceRightToLeft
        view.layoutIfNeeded()
        #expect(view.gradientLayer.startPoint == CGPoint(x: 1, y: 0.5))
        #expect(view.gradientLayer.endPoint == CGPoint(x: 0, y: 0.5))
    }

    @MainActor
    @Test func shapeViewBuildsPathFromBoundsAndMapsSwiftUIStyleStroke() {
        struct InsetRectangle: QuickLayoutShape {
            let inset: CGFloat

            func path(in rect: CGRect) -> CGPath {
                CGPath(
                    rect: rect.insetBy(dx: inset, dy: inset),
                    transform: nil
                )
            }
        }

        let view = QuickLayoutShapeView(
            shape: InsetRectangle(inset: 6),
            fillColor: .systemYellow,
            strokeColor: .systemBlue,
            strokeStyle: QuickLayoutStrokeStyle(
                lineWidth: 4,
                lineCap: .round,
                lineJoin: .bevel,
                miterLimit: 8,
                dash: [6, 3],
                dashPhase: 2
            ),
            fillStyle: QuickLayoutFillStyle(
                eoFill: true,
                antialiased: true
            )
        )
        view.frame = CGRect(x: 0, y: 0, width: 120, height: 80)
        view.layoutIfNeeded()

        #expect(view.layer === view.shapeLayer)
        #expect(view.shapeLayer.frame == view.bounds)
        #expect(
            view.shapeLayer.path?.boundingBoxOfPath
                == CGRect(x: 6, y: 6, width: 108, height: 68)
        )
        #expect(view.shapeLayer.fillColor != nil)
        #expect(view.shapeLayer.strokeColor != nil)
        #expect(view.shapeLayer.lineWidth == 4)
        #expect(view.shapeLayer.lineCap == .round)
        #expect(view.shapeLayer.lineJoin == .bevel)
        #expect(view.shapeLayer.miterLimit == 8)
        #expect(view.shapeLayer.lineDashPattern?.map(\.doubleValue) == [6, 3])
        #expect(view.shapeLayer.lineDashPhase == 2)
        #expect(view.shapeLayer.fillRule == .evenOdd)
        #expect(view.shapeLayer.allowsEdgeAntialiasing)

        view.setShape(InsetRectangle(inset: 12))
        view.layoutIfNeeded()
        #expect(
            view.shapeLayer.path?.boundingBoxOfPath
                == CGRect(x: 12, y: 12, width: 96, height: 56)
        )
    }

    @MainActor
    @Test func quickLayoutButtonMeasuresAndLaysOutExternalLabelUI() {
        let iconView = UIImageView(
            image: UIImage(systemName: "checkmark")
        )
        let titleLabel = UILabel()
        titleLabel.text = "Save changes"
        titleLabel.font = .preferredFont(forTextStyle: .body)
        let backgroundView = UIView()

        let button = QuickLayoutButton(action: {}) {
            HStack(spacing: 8) {
                iconView
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                titleLabel
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background { backgroundView }
        }

        let size = button.sizeThatFits(
            CGSize(
                width: 320,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        button.frame = CGRect(origin: .zero, size: size)
        button.setNeedsLayout()
        button.layoutIfNeeded()

        #expect(size.width > titleLabel.intrinsicContentSize.width)
        #expect(size.height >= titleLabel.intrinsicContentSize.height + 24)
        #expect(iconView.frame.width == 18)
        #expect(titleLabel.frame.minX > iconView.frame.maxX)
        #expect(backgroundView.frame == button.bounds)
        #expect(button.hitTest(titleLabel.center, with: nil) === button)
        #expect(button.isAccessibilityElement)
        #expect(button.accessibilityTraits.contains(.button))
    }

    @MainActor
    @Test func quickLayoutButtonSupportsBodyOverride() {
        let button = QuickLayoutButtonBodyProbe()
        let size = button.sizeThatFits(
            CGSize(
                width: 240,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        button.frame = CGRect(origin: .zero, size: size)
        button.layoutIfNeeded()

        #expect(size.width >= button.titleLabel.intrinsicContentSize.width + 32)
        #expect(size.height >= button.titleLabel.intrinsicContentSize.height + 20)
        #expect(button.titleLabel.superview === button)
    }

    @MainActor
    @Test func quickLayoutButtonPerformsPrimaryActionAndHonorsDisabledState() {
        let titleLabel = UILabel()
        titleLabel.text = "Continue"
        var actionCount = 0
        let button = QuickLayoutButton {
            actionCount += 1
        } label: {
            titleLabel.padding(.all, 12)
        }
        var eventCount = 0
        button.addAction(
            UIAction { _ in eventCount += 1 },
            for: .primaryActionTriggered
        )

        button.performAction()
        #expect(actionCount == 1)
        #expect(eventCount == 1)

        button.isEnabled = false
        button.performAction()
        #expect(actionCount == 1)
        #expect(eventCount == 1)
        #expect(button.accessibilityTraits.contains(.notEnabled))
        #expect(!button.accessibilityActivate())

        button.isEnabled = true
        #expect(!button.accessibilityTraits.contains(.notEnabled))
        #expect(button.accessibilityActivate())
        #expect(actionCount == 2)
        #expect(eventCount == 2)
    }

    @MainActor
    @Test func quickLayoutButtonPublishesStateWithoutApplyingVisualStyle() {
        let titleLabel = UILabel()
        titleLabel.text = "Delete"
        let button = QuickLayoutButton(
            role: .destructive,
            action: {}
        ) {
            titleLabel.padding(.all, 10)
        }
        var states: [QuickLayoutButtonState] = []
        button.stateUpdateHandler = { states.append($0) }

        button.isHighlighted = true
        button.isHighlighted = true
        button.isHighlighted = false
        button.isSelected = true
        button.isEnabled = false

        #expect(states.count == 5)
        #expect(states[0].role == .destructive)
        #expect(!states[0].isPressed)
        #expect(states[1].isPressed)
        #expect(!states[2].isPressed)
        #expect(states[3].isSelected)
        #expect(!states[4].isEnabled)
        #expect(titleLabel.alpha == 1)
        #expect(button.backgroundColor == nil)
    }

    @MainActor
    @Test func quickLayoutButtonRestoresDirectionAfterReattachment() {
        let first = UIView()
        let second = UIView()
        let button = QuickLayoutButton(action: {}) {
            HStack(spacing: 8) {
                first.frame(width: 20, height: 20)
                second.frame(width: 20, height: 20)
            }
        }
        button.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: 120, height: 44)
        )
        container.semanticContentAttribute = .forceLeftToRight
        container.addSubview(button)
        button.frame = container.bounds
        button.setNeedsLayout()
        button.layoutIfNeeded()

        #expect(button.semanticContentAttribute == .forceLeftToRight)
        #expect(first.frame.minX < second.frame.minX)

        button.removeFromSuperview()
        container.semanticContentAttribute = .forceRightToLeft
        container.addSubview(button)
        _ = button.sizeThatFits(container.bounds.size)
        button.setNeedsLayout()
        button.layoutIfNeeded()

        #expect(button.semanticContentAttribute == .forceRightToLeft)
        #expect(first.frame.minX > second.frame.minX)
    }

    @MainActor
    @Test func scrollViewFillsItsProposedViewportByDefault() {
        let scrollView = QuickLayoutScrollView()
        let element = ScrollView(scrollView) {}
        let frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        let safeAreaInsets = UIEdgeInsets(
            top: 0,
            left: 59,
            bottom: 21,
            right: 47
        )

        withPhysicalSafeArea(
            containerSize: frame.size,
            containerInsets: safeAreaInsets
        ) {
            element.applyFrame(
                frame,
                alignment: .center,
                layoutDirection: .leftToRight
            )
        }

        #expect(scrollView.frame == frame)
    }

    @MainActor
    @Test func nestedScrollViewFillsItsParentsViewport() {
        let outerScrollView = QuickLayoutScrollView()
        let innerScrollView = QuickLayoutScrollView(.horizontal)
        let element = ScrollView(outerScrollView) {
            ScrollView(innerScrollView, .horizontal) {
                UIView().frame(width: 300, height: 80)
            }
            .frame(height: 80)
        }
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)

        withPhysicalSafeArea(
            containerSize: frame.size,
            containerInsets: UIEdgeInsets(
                top: 0,
                left: 20,
                bottom: 0,
                right: 20
            )
        ) {
            element.applyFrame(
                frame,
                alignment: .center,
                layoutDirection: .leftToRight
            )
        }
        outerScrollView.layoutIfNeeded()
        innerScrollView.layoutIfNeeded()

        #expect(outerScrollView.frame == frame)
        #expect(innerScrollView.frame.width == outerScrollView.bounds.width)
    }

    @MainActor
    @Test func collectionCellDefaultsToBodyContent() {
        let cell = CollectionCellBodyProbe(frame: .zero)
        cell.quickLayoutHorizontalFlexibility = .fixedSize
        cell.quickLayoutVerticalFlexibility = .fullyFlexible

        let size = cell.sizeThatFits(CGSize(width: 180, height: 44))
        cell.frame = CGRect(origin: .zero, size: size)
        cell.layoutIfNeeded()

        #expect(size == CGSize(width: 180, height: 37))
        #expect(cell.bodyView.superview === cell.contentView)
    }

    @MainActor
    @Test func tableCellDefaultsToBodyContent() {
        let bodyView = IntrinsicTestView(
            size: CGSize(width: 180, height: 37)
        )
        let cell = QuickLayoutTableViewCell(
            style: .default,
            reuseIdentifier: nil
        ) {
            bodyView
        }

        let size = cell.sizeThatFits(CGSize(width: 180, height: 44))
        let systemFittingSize = cell.systemLayoutSizeFitting(
            CGSize(width: 180, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        cell.frame = CGRect(origin: .zero, size: size)
        cell.layoutIfNeeded()

        #expect(size == CGSize(width: 180, height: 37))
        #expect(systemFittingSize == size)
        #expect(bodyView.superview === cell.contentView)
    }

    @MainActor
    @Test func tableHeaderFooterDefaultsToBodyContent() {
        let bodyView = IntrinsicTestView(
            size: CGSize(width: 180, height: 37)
        )
        let reusableView = QuickLayoutTableViewHeaderFooterView(
            reuseIdentifier: nil
        ) {
            bodyView
        }

        let size = reusableView.sizeThatFits(
            CGSize(width: 180, height: 44)
        )
        let systemFittingSize = reusableView.systemLayoutSizeFitting(
            CGSize(width: 180, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        reusableView.frame = CGRect(origin: .zero, size: size)
        reusableView.layoutIfNeeded()

        #expect(size == CGSize(width: 180, height: 37))
        #expect(systemFittingSize == size)
        #expect(bodyView.superview === reusableView.contentView)
    }

    @MainActor
    @Test func tableHeaderFooterLaysOutCenteredBodyInsideContentViewBounds() {
        let bodyView = IntrinsicTestView(
            size: CGSize(width: 80, height: 20)
        )
        let header = QuickLayoutTableViewHeaderFooterView {
            bodyView
        }
        let dataSource = TableHeaderFooterDataSource(header: header)
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            style: .insetGrouped
        )
        tableView.dataSource = dataSource
        tableView.delegate = dataSource
        let viewController = UIViewController()
        viewController.view = tableView
        let window = UIWindow(frame: tableView.bounds)
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }

        tableView.reloadData()
        window.layoutIfNeeded()

        let visibleHeader = tableView.headerView(forSection: 0)
        #expect(visibleHeader === header)
        #expect(header.contentView.bounds.width < header.bounds.width)
        #expect(header.contentView.bounds.contains(bodyView.frame))
        #expect(
            abs(bodyView.frame.midX - header.contentView.bounds.midX) < 0.5
        )
        #expect(bodyView.frame.size == CGSize(width: 80, height: 20))
    }

    @MainActor
    @Test func tableReusableHostsSynchronizeDirectionFromTheirTable() {
        let cell = DirectionProbeTableViewCell(
            style: .default,
            reuseIdentifier: nil
        )
        let header = DirectionProbeTableHeaderFooterView(
            reuseIdentifier: nil
        )
        let dataSource = TableHeaderFooterDataSource(
            header: header,
            cell: cell
        )
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            style: .plain
        )
        tableView.semanticContentAttribute = .forceLeftToRight
        tableView.dataSource = dataSource
        tableView.delegate = dataSource
        let viewController = UIViewController()
        viewController.view = tableView
        let window = UIWindow(frame: tableView.bounds)
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }

        tableView.reloadData()
        window.layoutIfNeeded()

        #expect(cell.semanticContentAttribute == .forceLeftToRight)
        #expect(cell.contentView.semanticContentAttribute == .forceLeftToRight)
        #expect(cell.directionView.semanticContentAttribute == .forceLeftToRight)
        #expect(header.semanticContentAttribute == .forceLeftToRight)
        #expect(header.contentView.semanticContentAttribute == .forceLeftToRight)
        #expect(header.directionView.semanticContentAttribute == .forceLeftToRight)

        tableView.semanticContentAttribute = .forceRightToLeft
        cell.setNeedsLayout()
        header.setNeedsLayout()
        window.layoutIfNeeded()

        #expect(cell.semanticContentAttribute == .forceRightToLeft)
        #expect(cell.contentView.semanticContentAttribute == .forceRightToLeft)
        #expect(cell.directionView.semanticContentAttribute == .forceRightToLeft)
        #expect(header.semanticContentAttribute == .forceRightToLeft)
        #expect(header.contentView.semanticContentAttribute == .forceRightToLeft)
        #expect(header.directionView.semanticContentAttribute == .forceRightToLeft)
    }

    @MainActor
    @Test func windowBackedTableReusableHostsFollowDirectionRoundTrips() {
        let cell = DirectionPairTableViewCell(
            style: .default,
            reuseIdentifier: nil
        )
        let header = DirectionPairTableHeaderFooterView(
            reuseIdentifier: nil
        )
        let dataSource = TableHeaderFooterDataSource(
            header: header,
            cell: cell
        )
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.semanticContentAttribute = .forceLeftToRight
        tableView.dataSource = dataSource
        tableView.delegate = dataSource

        let viewController = UIViewController()
        viewController.view = tableView
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240)
        )
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }

        tableView.reloadData()
        window.layoutIfNeeded()
        tableView.layoutIfNeeded()

        #expect(tableView.cellForRow(at: IndexPath(row: 0, section: 0)) === cell)
        #expect(tableView.headerView(forSection: 0) === header)
        let cellLeftToRightFrames = (cell.first.frame, cell.second.frame)
        let headerLeftToRightFrames = (header.first.frame, header.second.frame)
        #expect(cell.first.frame.minX < cell.second.frame.minX)
        #expect(header.first.frame.minX < header.second.frame.minX)

        tableView.semanticContentAttribute = .forceRightToLeft
        cell.setNeedsQuickLayout()
        header.setNeedsQuickLayout()
        tableView.setNeedsLayout()
        window.layoutIfNeeded()

        #expect(cell.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(header.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(cell.first.frame.minX > cell.second.frame.minX)
        #expect(header.first.frame.minX > header.second.frame.minX)

        tableView.semanticContentAttribute = .forceLeftToRight
        cell.setNeedsQuickLayout()
        header.setNeedsQuickLayout()
        tableView.setNeedsLayout()
        window.layoutIfNeeded()

        #expect(cell.first.frame == cellLeftToRightFrames.0)
        #expect(cell.second.frame == cellLeftToRightFrames.1)
        #expect(header.first.frame == headerLeftToRightFrames.0)
        #expect(header.second.frame == headerLeftToRightFrames.1)
    }

    @MainActor
    @Test func windowBackedCollectionReusableHostsFollowDirectionRoundTrips() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 120, height: 44)
        layout.headerReferenceSize = CGSize(width: 120, height: 44)
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        collectionView.semanticContentAttribute = .forceLeftToRight
        collectionView.register(
            DirectionPairCollectionViewCell.self,
            forCellWithReuseIdentifier: "cell"
        )
        collectionView.register(
            DirectionPairCollectionReusableView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: "header"
        )
        let dataSource = DirectionPairCollectionDataSource()
        collectionView.dataSource = dataSource

        let viewController = UIViewController()
        viewController.view = collectionView
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240)
        )
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }

        collectionView.reloadData()
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.cellForItem(at: indexPath)
            as? DirectionPairCollectionViewCell
        let header = collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: indexPath
        ) as? DirectionPairCollectionReusableView
        guard let cell, let header else {
            Issue.record("Expected the collection cell and header to be visible")
            return
        }

        let cellLeftToRightFrames = (cell.first.frame, cell.second.frame)
        let headerLeftToRightFrames = (header.first.frame, header.second.frame)
        #expect(cell.first.frame.minX < cell.second.frame.minX)
        #expect(header.first.frame.minX < header.second.frame.minX)

        collectionView.semanticContentAttribute = .forceRightToLeft
        collectionView.collectionViewLayout.invalidateLayout()
        cell.setNeedsQuickLayout()
        header.setNeedsQuickLayout()
        window.layoutIfNeeded()

        #expect(cell.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(header.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(cell.first.frame.minX > cell.second.frame.minX)
        #expect(header.first.frame.minX > header.second.frame.minX)

        collectionView.semanticContentAttribute = .forceLeftToRight
        collectionView.collectionViewLayout.invalidateLayout()
        cell.setNeedsQuickLayout()
        header.setNeedsQuickLayout()
        window.layoutIfNeeded()

        #expect(cell.first.frame == cellLeftToRightFrames.0)
        #expect(cell.second.frame == cellLeftToRightFrames.1)
        #expect(header.first.frame == headerLeftToRightFrames.0)
        #expect(header.second.frame == headerLeftToRightFrames.1)
    }

    @MainActor
    @Test func collectionReusableViewDefaultsToBodyContent() {
        let bodyView = IntrinsicTestView(
            size: CGSize(width: 180, height: 37)
        )
        let reusableView = QuickLayoutCollectionReusableView {
            bodyView
        }
        let proposedSize = CGSize(width: 180, height: 44)

        let size = reusableView.sizeThatFits(proposedSize)
        let layoutAttributes = UICollectionViewLayoutAttributes(
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            with: IndexPath(item: 0, section: 0)
        )
        layoutAttributes.size = proposedSize
        let fittedAttributes = reusableView
            .preferredLayoutAttributesFitting(layoutAttributes)
        reusableView.frame = CGRect(origin: .zero, size: size)
        reusableView.layoutIfNeeded()

        #expect(size == CGSize(width: 180, height: 37))
        #expect(fittedAttributes.size == size)
        #expect(bodyView.superview === reusableView)
    }

    @Test func maximumInsetsUseLargestDirectionalValue() {
        let insets = EdgeInsets(top: 4, leading: 12, bottom: 18, trailing: 8)

        #expect(insets.maximumHorizontalInset == 12)
        #expect(insets.maximumVerticalInset == 18)
    }

    @Test func containerRelativeFrameUsesSelectedContainerAxes() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .containerRelativeFrame([.horizontal, .vertical])

        let size = QuickLayoutContainerRelativeFrameContext.withContainerSize(
            CGSize(width: 300, height: 200)
        ) {
            element.sizeThatFits(CGSize(width: 100, height: 80))
        }

        #expect(size == CGSize(width: 300, height: 200))
    }

    @Test func containerRelativeFramePreservesUnselectedAxis() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .containerRelativeFrame(.horizontal)

        let size = QuickLayoutContainerRelativeFrameContext.withContainerSize(
            CGSize(width: 300, height: 200)
        ) {
            element.sizeThatFits(CGSize(width: 100, height: 80))
        }

        #expect(size == CGSize(width: 300, height: 30))
    }

    @Test func containerRelativeFrameResolvesCountSpanAndSpacing() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .containerRelativeFrame(
                .horizontal,
                count: 3,
                span: 2,
                spacing: 10
            )

        let size = QuickLayoutContainerRelativeFrameContext.withContainerSize(
            CGSize(width: 320, height: 200)
        ) {
            element.sizeThatFits(CGSize(width: 100, height: 80))
        }

        #expect(size == CGSize(width: 210, height: 30))
    }

    @Test func containerRelativeFrameSupportsCustomLength() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                switch axis {
                case .horizontal:
                    return length / 2
                case .vertical:
                    return length - 40
                }
            }

        let size = QuickLayoutContainerRelativeFrameContext.withContainerSize(
            CGSize(width: 320, height: 200)
        ) {
            element.sizeThatFits(CGSize(width: 100, height: 80))
        }

        #expect(size == CGSize(width: 160, height: 160))
    }

    @Test func containerRelativeFrameFallsBackToParentProposalWithoutHost() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .containerRelativeFrame(.horizontal)

        let size = element.sizeThatFits(CGSize(width: 120, height: 80))

        #expect(size == CGSize(width: 120, height: 30))
    }

    @MainActor
    @Test func contentMarginsInsetScrollContentAndRelativeViewport() {
        let scrollView = QuickLayoutScrollView(.horizontal)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
        let card = UIView()

        _ = ScrollView(scrollView, .horizontal) {
            card
                .resizable()
                .containerRelativeFrame(.horizontal)
                .frame(height: 40)
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)

        scrollView.layoutIfNeeded()

        #expect(scrollView.contentInset == UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20))
        #expect(scrollView.verticalScrollIndicatorInsets == .zero)
        #expect(abs(card.bounds.width - 260) < 0.001)
        #expect(scrollView.contentOffset.x == -20)
    }

    @MainActor
    @Test func horizontalScrollViewUsesItsContentsNaturalHeight() {
        let scrollView = QuickLayoutScrollView(.horizontal)
        scrollView.contentInsetAdjustmentBehavior = .never
        let shortView = UIView().frame(width: 120, height: 44)
        let tallView = UIView().frame(width: 120, height: 86)
        let element = ScrollView(scrollView, .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                shortView
                tallView
            }
        }

        let size = element.sizeThatFits(
            CGSize(width: 300, height: CGFloat.infinity)
        )

        #expect(size == CGSize(width: 300, height: 86))
        #expect(element.quick_flexibility(for: .horizontal) == .fullyFlexible)
        #expect(element.quick_flexibility(for: .vertical) == .fixedSize)
    }

    @MainActor
    @Test func quickLayoutViewSupportsExplicitAxisFlexibility() {
        let hostedView = QuickLayoutView {
            UIView()
                .resizable(axis: .horizontal)
                .frame(height: 44)
        }

        #expect(hostedView.quickLayoutHorizontalFlexibility == nil)
        #expect(hostedView.quickLayoutVerticalFlexibility == nil)
        #expect(hostedView.quick_flexibility(for: .horizontal) == .fullyFlexible)
        #expect(hostedView.quick_flexibility(for: .vertical) == .fixedSize)

        hostedView.quickLayoutHorizontalFlexibility = .fixedSize
        hostedView.quickLayoutVerticalFlexibility = .fullyFlexible

        #expect(hostedView.quick_flexibility(for: .horizontal) == .fixedSize)
        #expect(hostedView.quick_flexibility(for: .vertical) == .fullyFlexible)

        hostedView.quickLayoutHorizontalFlexibility = nil
        hostedView.quickLayoutVerticalFlexibility = nil

        #expect(hostedView.quick_flexibility(for: .horizontal) == .fullyFlexible)
        #expect(hostedView.quick_flexibility(for: .vertical) == .fixedSize)
    }

    @MainActor
    @Test func contentMarginsReduceTheScrollViewsCrossAxisProposal() {
        let scrollView = QuickLayoutScrollView(.vertical)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let content = UIView()

        _ = ScrollView(scrollView, .vertical) {
            content
                .resizable(axis: .horizontal)
                .frame(height: 40)
        }
        .contentMargins(.horizontal, 20)

        scrollView.layoutIfNeeded()

        #expect(content.bounds.width == 260)
        #expect(scrollView.contentSize.width == 260)
    }

    @MainActor
    @Test func contentMarginsAddToTheResolvedSafeArea() {
        let scrollView = AdjustedContentInsetQuickLayoutScrollView(
            safeAreaInsets: UIEdgeInsets(
                top: 62,
                left: 0,
                bottom: 34,
                right: 0
            )
        )
        scrollView.axis = .vertical
        scrollView.frame = CGRect(x: 0, y: 0, width: 300, height: 200)

        _ = ScrollView(scrollView, .vertical) {
            UIView().frame(width: 300, height: 400)
        }
        .contentMargins(.vertical, 20, for: .scrollContent)

        scrollView.layoutIfNeeded()

        #expect(
            scrollView.contentInset
                == UIEdgeInsets(top: 20, left: 0, bottom: 20, right: 0)
        )
        #expect(
            scrollView.adjustedContentInset
                == UIEdgeInsets(top: 82, left: 0, bottom: 54, right: 0)
        )
        #expect(scrollView.contentOffset.y == -82)
    }

    @MainActor
    @Test func contentMarginsSupplySafeAreaWhenUIKitAdjustmentIsDisabled() {
        let scrollView = SafeAreaContentMarginQuickLayoutScrollView(
            safeAreaInsets: UIEdgeInsets(
                top: 0,
                left: 40,
                bottom: 0,
                right: 50
            )
        )
        scrollView.axis = .horizontal
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
        let card = UIView()

        _ = ScrollView(scrollView, .horizontal) {
            HStack(spacing: 0) {
                card
                    .resizable()
                    .containerRelativeFrame(.horizontal)
                    .frame(height: 40)
                UIView().frame(width: 300, height: 40)
            }
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)

        scrollView.layoutIfNeeded()

        #expect(
            scrollView.contentInset
                == UIEdgeInsets(top: 0, left: 60, bottom: 0, right: 70)
        )
        #expect(card.bounds.width == 170)
        #expect(scrollView.contentOffset.x == -60)

        scrollView.updateSafeAreaInsets(
            UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 30)
        )
        scrollView.layoutIfNeeded()

        #expect(
            scrollView.contentInset
                == UIEdgeInsets(top: 0, left: 44, bottom: 0, right: 50)
        )
        #expect(card.bounds.width == 206)
        #expect(scrollView.contentOffset.x == -44)

        scrollView.contentOffset.x = 80
        scrollView.updateSafeAreaInsets(
            UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 18)
        )
        scrollView.layoutIfNeeded()

        #expect(scrollView.contentOffset.x == 80)
    }

    @MainActor
    @Test func scrollContentReceivesSafeAreaMissingFromAdjustedInsets() {
        let scrollView = SafeAreaContentMarginQuickLayoutScrollView(
            safeAreaInsets: UIEdgeInsets(
                top: 0,
                left: 40,
                bottom: 0,
                right: 50
            )
        )
        scrollView.axis = .vertical
        scrollView.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
        let content = UIView()

        _ = ScrollView(scrollView) {
            content
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .safeAreaPadding(.horizontal, 20)
        }

        scrollView.layoutIfNeeded()

        #expect(scrollView.frame.width == 300)
        #expect(content.frame.minX == 60)
        #expect(content.frame.maxX == 230)
    }

    @MainActor
    @Test func contentMarginsFollowRuntimeSafeAreaChanges() {
        let scrollView = AdjustedContentInsetQuickLayoutScrollView(
            safeAreaInsets: UIEdgeInsets(
                top: 62,
                left: 0,
                bottom: 34,
                right: 0
            )
        )
        scrollView.axis = .vertical
        scrollView.frame = CGRect(x: 0, y: 0, width: 300, height: 200)

        _ = ScrollView(scrollView, .vertical) {
            UIView().frame(width: 300, height: 400)
        }
        .contentMargins(.vertical, 20, for: .scrollContent)

        scrollView.layoutIfNeeded()
        #expect(scrollView.contentOffset.y == -82)

        scrollView.updateSafeAreaInsets(
            UIEdgeInsets(top: 44, left: 0, bottom: 21, right: 0)
        )
        scrollView.layoutIfNeeded()

        #expect(
            scrollView.adjustedContentInset
                == UIEdgeInsets(top: 64, left: 0, bottom: 41, right: 0)
        )
        #expect(scrollView.contentOffset.y == -64)

        scrollView.contentOffset.y = 80
        scrollView.updateSafeAreaInsets(
            UIEdgeInsets(top: 30, left: 0, bottom: 12, right: 0)
        )
        scrollView.layoutIfNeeded()

        #expect(
            scrollView.adjustedContentInset
                == UIEdgeInsets(top: 50, left: 0, bottom: 32, right: 0)
        )
        #expect(scrollView.contentOffset.y == 80)
    }

    @MainActor
    @Test func contentMarginsStartAtTheLeadingEdgeInRightToLeftLayout() {
        let scrollView = QuickLayoutScrollView(.horizontal)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.semanticContentAttribute = .forceRightToLeft
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        _ = ScrollView(scrollView, .horizontal) {
            UIView().frame(width: 120, height: 40)
            UIView().frame(width: 120, height: 40)
        }
        .contentMargins(.horizontal, 14)

        scrollView.layoutIfNeeded()

        let expectedOffset = scrollView.contentSize.width
            - scrollView.bounds.width
            + scrollView.adjustedContentInset.right
        #expect(scrollView.contentOffset.x == expectedOffset)
    }

    @MainActor
    @Test func horizontalScrollViewRelayoutsWhenItsDirectionChanges() {
        let first = UIView()
        let second = UIView()
        let scrollView = DirectionRecordingQuickLayoutScrollView(.horizontal) {
            first.frame(width: 120, height: 40)
            second.frame(width: 120, height: 40)
        }
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        scrollView.layoutIfNeeded()

        let leftToRightFirstFrame = first.frame
        let leftToRightSecondFrame = second.frame
        let leftToRightContentSize = scrollView.contentSize
        scrollView.contentOffset.x = 40
        #expect(leftToRightFirstFrame.minX < leftToRightSecondFrame.minX)

        let directionChangeCount = scrollView.environmentChangeReasons.count
        scrollView.semanticContentAttribute = .forceRightToLeft

        #expect(
            scrollView.environmentChangeReasons.last?
                .contains(.layoutDirection) == true
        )
        #expect(
            scrollView.environmentChangeReasons.count
                == directionChangeCount + 1
        )
        #expect(first.frame == leftToRightFirstFrame)
        #expect(second.frame == leftToRightSecondFrame)

        scrollView.layoutIfNeeded()
        #expect(first.frame.minX > second.frame.minX)
        #expect(
            first.frame.minX
                == leftToRightContentSize.width - leftToRightFirstFrame.maxX
        )
        #expect(
            second.frame.minX
                == leftToRightContentSize.width - leftToRightSecondFrame.maxX
        )
        #expect(scrollView.contentSize == leftToRightContentSize)
        #expect(scrollView.contentOffset.x == 40)

        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.layoutIfNeeded()

        #expect(first.frame == leftToRightFirstFrame)
        #expect(second.frame == leftToRightSecondFrame)
        #expect(scrollView.contentSize == leftToRightContentSize)
        #expect(scrollView.contentOffset.x == 40)
    }

    @MainActor
    @Test func horizontalScrollToUsesTheLatestDirectionAcrossRoundTrips() {
        let scrollView = QuickLayoutScrollView(.horizontal) {
            UIView().frame(width: 120, height: 40)
            UIView().frame(width: 120, height: 40)
        }
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(
            top: 0,
            left: 11,
            bottom: 0,
            right: 17
        )
        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        scrollView.layoutIfNeeded()

        let minimumX = -scrollView.adjustedContentInset.left
        let maximumX = scrollView.contentSize.width
            - scrollView.bounds.width
            + scrollView.adjustedContentInset.right

        scrollView.scrollTo(.leading, animated: false)
        #expect(scrollView.contentOffset.x == minimumX)
        scrollView.scrollTo(.trailing, animated: false)
        #expect(scrollView.contentOffset.x == maximumX)

        scrollView.semanticContentAttribute = .forceRightToLeft
        scrollView.scrollTo(.leading, animated: false)
        #expect(scrollView.contentOffset.x == maximumX)
        scrollView.scrollTo(.trailing, animated: false)
        #expect(scrollView.contentOffset.x == minimumX)

        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.scrollTo(.leading, animated: false)
        #expect(scrollView.contentOffset.x == minimumX)
        scrollView.scrollTo(.trailing, animated: false)
        #expect(scrollView.contentOffset.x == maximumX)
    }

    @MainActor
    @Test func pendingHorizontalScrollUsesDirectionAtResolutionTime() {
        let scrollView = QuickLayoutScrollView(.horizontal) {
            UIView().frame(width: 120, height: 40)
            UIView().frame(width: 120, height: 40)
        }
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(
            top: 0,
            left: 11,
            bottom: 0,
            right: 17
        )
        scrollView.semanticContentAttribute = .forceLeftToRight

        #expect(scrollView.bounds.width == 0)
        scrollView.scrollTo(.leading, animated: false)

        scrollView.semanticContentAttribute = .forceRightToLeft
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        scrollView.layoutIfNeeded()

        let rightToLeftLeadingX = scrollView.contentSize.width
            - scrollView.bounds.width
            + scrollView.adjustedContentInset.right
        #expect(scrollView.contentOffset.x == rightToLeftLeadingX)
    }

    @MainActor
    @Test func quickLayoutViewRelayoutsAndPublishesEnvironmentDirectionChanges() {
        let hostingView = DirectionRecordingQuickLayoutView()
        hostingView.semanticContentAttribute = .forceLeftToRight
        hostingView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)

        hostingView.layoutIfNeeded()
        let leftToRightFrame = hostingView.child.frame
        #expect(leftToRightFrame == CGRect(x: 12, y: 0, width: 20, height: 10))

        let layoutChangeCount = hostingView.environmentChangeReasons.count
        hostingView.semanticContentAttribute = .forceRightToLeft

        // A language switch must publish its direction before UIKit happens
        // to run another layout pass; the invalidated pass then mirrors body.
        #expect(
            hostingView.environmentChangeReasons.last?
                .contains(.layoutDirection) == true
        )
        #expect(
            hostingView.environmentChangeReasons.count
                == layoutChangeCount + 1
        )
        #expect(hostingView.child.frame == leftToRightFrame)

        hostingView.layoutIfNeeded()
        #expect(
            hostingView.child.frame
                == CGRect(x: 68, y: 0, width: 20, height: 10)
        )

        let measurementChangeCount = hostingView.environmentChangeReasons.count
        hostingView.semanticContentAttribute = .forceLeftToRight
        let measuredSize = hostingView.sizeThatFits(
            CGSize(width: 100, height: 40)
        )

        #expect(measuredSize == CGSize(width: 100, height: 40))
        #expect(
            hostingView.environmentChangeReasons.last?
                .contains(.layoutDirection) == true
        )
        #expect(
            hostingView.environmentChangeReasons.count
                == measurementChangeCount + 1
        )
        hostingView.layoutIfNeeded()

        #expect(hostingView.child.frame == leftToRightFrame)
        #expect(hostingView.child.superview === hostingView)
    }

    @MainActor
    @Test func quickLayoutViewPublishesContainerSizeOnlyWhenBoundsChange() {
        let hostingView = DirectionRecordingQuickLayoutView()
        hostingView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        hostingView.layoutIfNeeded()

        let initialCount = hostingView.environmentChangeReasons.count
        hostingView.frame.size = CGSize(width: 120, height: 40)
        hostingView.setNeedsLayout()
        hostingView.layoutIfNeeded()

        #expect(
            hostingView.environmentChangeReasons.count == initialCount + 1
        )
        #expect(
            hostingView.environmentChangeReasons.last?
                .contains(.containerSize) == true
        )
        #expect(hostingView.quickLayoutEnvironment.containerSize == hostingView.bounds.size)

        let changedCount = hostingView.environmentChangeReasons.count
        hostingView.setNeedsLayout()
        hostingView.layoutIfNeeded()
        #expect(hostingView.environmentChangeReasons.count == changedCount)
    }

    @MainActor
    @Test func traitCallbackAlwaysPublishesGenericInvalidationOnce() {
        let hostingView = DirectionRecordingQuickLayoutView()
        hostingView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        hostingView.layoutIfNeeded()
        let initialCount = hostingView.environmentChangeReasons.count

        hostingView.traitCollectionDidChange(hostingView.traitCollection)

        #expect(
            hostingView.environmentChangeReasons.count == initialCount + 1
        )
        #expect(
            hostingView.environmentChangeReasons.last == [.traitCollection]
        )
    }

    @MainActor
    @Test func standaloneHostsPreserveLocalSemanticDirectionByDefault() {
        let container = UIView()
        container.semanticContentAttribute = .forceRightToLeft
        let hostingView = QuickLayoutView()
        let scrollView = QuickLayoutScrollView()
        hostingView.semanticContentAttribute = .forceLeftToRight
        scrollView.semanticContentAttribute = .playback
        container.addSubview(hostingView)
        container.addSubview(scrollView)

        let viewController = UIViewController()
        viewController.view = container
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }

        #expect(hostingView.semanticContentAttribute == .forceLeftToRight)
        #expect(scrollView.semanticContentAttribute == .playback)
    }

    @MainActor
    @Test func detachedHostsRecoverLatestContainerDirectionWhenReattached() {
        let pair = (UIView(), UIView())
        let hostingView = DirectionRecordingQuickLayoutView()
        hostingView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer
        let scrollView = QuickLayoutScrollView(.horizontal) {
            pair.0.frame(width: 60, height: 20)
            pair.1.frame(width: 60, height: 20)
        }
        scrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: 240, height: 120)
        )
        container.semanticContentAttribute = .forceLeftToRight
        hostingView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        scrollView.frame = CGRect(x: 0, y: 50, width: 100, height: 40)
        container.addSubview(hostingView)
        container.addSubview(scrollView)

        let viewController = UIViewController()
        viewController.view = container
        let window = UIWindow(frame: container.bounds)
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()

        #expect(hostingView.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(scrollView.effectiveUserInterfaceLayoutDirection == .leftToRight)

        hostingView.removeFromSuperview()
        scrollView.removeFromSuperview()
        container.semanticContentAttribute = .forceRightToLeft
        // Detached hosts intentionally keep their last state until an owner
        // measures them or an attachment hook supplies a current container.
        #expect(hostingView.semanticContentAttribute == .forceLeftToRight)
        #expect(scrollView.semanticContentAttribute == .forceLeftToRight)

        let viewDirectionChangeCount = hostingView.environmentChangeReasons.count
        container.addSubview(hostingView)
        container.addSubview(scrollView)
        window.layoutIfNeeded()

        #expect(hostingView.semanticContentAttribute == .forceRightToLeft)
        #expect(scrollView.semanticContentAttribute == .forceRightToLeft)
        #expect(hostingView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(scrollView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(
            hostingView.environmentChangeReasons.count
                == viewDirectionChangeCount + 1
        )
        #expect(
            hostingView.environmentChangeReasons.last?
                .contains(.layoutDirection) == true
        )
    }

    @MainActor
    @Test func offWindowHostResolvesDirectionWhenContainerEntersWindow() {
        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: 160, height: 80)
        )
        container.semanticContentAttribute = .forceRightToLeft
        let hostingView = QuickLayoutView()
        hostingView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer
        hostingView.semanticContentAttribute = .forceLeftToRight
        container.addSubview(hostingView)

        #expect(hostingView.window == nil)
        #expect(hostingView.semanticContentAttribute == .forceLeftToRight)

        let viewController = UIViewController()
        viewController.view = container
        let window = UIWindow(frame: container.bounds)
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }

        #expect(hostingView.window === window)
        #expect(hostingView.semanticContentAttribute == .forceRightToLeft)
        #expect(hostingView.quickLayoutEnvironment.layoutDirection == .rightToLeft)
    }

    @MainActor
    @Test func offWindowHostsResolveContainerDirectionBeforeMeasurementAndLayout() {
        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: 160, height: 120)
        )
        container.semanticContentAttribute = .forceRightToLeft

        let hostingView = QuickLayoutView()
        hostingView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer
        hostingView.semanticContentAttribute = .forceLeftToRight
        container.addSubview(hostingView)

        let scrollView = QuickLayoutScrollView(.vertical) {
            UIView().frame(width: 40, height: 40)
        }
        scrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer
        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.frame = CGRect(x: 0, y: 40, width: 100, height: 80)
        container.addSubview(scrollView)

        #expect(container.window == nil)

        _ = hostingView.sizeThatFits(CGSize(width: 100, height: 40))
        scrollView.layoutIfNeeded()

        #expect(hostingView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            hostingView.quickLayoutEnvironment.layoutDirection == .rightToLeft
        )
        #expect(scrollView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            scrollView.quickLayoutEnvironment.layoutDirection == .rightToLeft
        )
    }

    @MainActor
    @Test func contentViewAppliesSupportedConfigurationsImmediately() {
        let contentView = ConfigurationProbeContentView(
            configuration: ConfigurationProbe(value: "initial")
        )

        #expect(contentView.appliedValues == ["initial"])
        #expect(contentView.label.text == "initial")

        contentView.configuration = ConfigurationProbe(value: "updated")

        #expect(contentView.appliedValues == ["initial", "updated"])
        #expect(contentView.label.text == "updated")
    }

    @MainActor
    @Test func contentViewsResolveEveryPublicReusableBoundary() {
        let boundaries: [UIView] = [
            UITableViewCell(style: .default, reuseIdentifier: nil),
            UITableViewHeaderFooterView(reuseIdentifier: nil),
            UICollectionViewCell(frame: .zero),
            UICollectionReusableView(frame: .zero),
        ]
        let root = UIView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        let viewController = UIViewController()
        viewController.view = root
        let window = UIWindow(frame: root.bounds)
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }

        for (index, boundary) in boundaries.enumerated() {
            boundary.frame = CGRect(
                x: 0,
                y: CGFloat(index * 80),
                width: 320,
                height: 64
            )
            boundary.semanticContentAttribute = .forceRightToLeft
            root.addSubview(boundary)

            // Simulates a UIKit-owned configuration host that retained an
            // opposite direction. The content must resolve the public owner,
            // rather than treating this intermediate view as authoritative.
            let intermediateHost = UIView(frame: boundary.bounds)
            intermediateHost.semanticContentAttribute = .forceLeftToRight
            addToReusableBoundary(intermediateHost, boundary: boundary)

            let contentView = ConfigurationProbeContentView(
                configuration: ConfigurationProbe(value: "\(index)")
            )
            contentView.frame = intermediateHost.bounds
            intermediateHost.addSubview(contentView)
            contentView.setNeedsLayout()
            contentView.layoutIfNeeded()

            #expect(
                contentView.semanticContentAttribute == .forceRightToLeft
            )
            #expect(
                contentView.quickLayoutEnvironment.layoutDirection
                    == .rightToLeft
            )
        }
    }

    @MainActor
    @Test func contentConfigurationSynchronizesDirectionBeforeBusinessContent() {
        let cell = UICollectionViewCell(
            frame: CGRect(x: 0, y: 0, width: 240, height: 60)
        )
        cell.semanticContentAttribute = .forceLeftToRight
        let intermediateHost = UIView(frame: cell.contentView.bounds)
        intermediateHost.semanticContentAttribute = .forceLeftToRight
        cell.contentView.addSubview(intermediateHost)
        let contentView = ConfigurationProbeContentView(
            configuration: ConfigurationProbe(value: "ltr")
        )
        contentView.frame = intermediateHost.bounds
        intermediateHost.addSubview(contentView)

        let viewController = UIViewController()
        viewController.view.addSubview(cell)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()

        let initialDirectionChangeCount = contentView
            .environmentChangeReasons
            .filter { $0.contains(.layoutDirection) }
            .count
        cell.semanticContentAttribute = .forceRightToLeft
        contentView.configuration = ConfigurationProbe(value: "rtl")

        #expect(contentView.appliedValues.last == "rtl")
        #expect(contentView.appliedDirections.last == .rightToLeft)
        #expect(
            contentView.environmentChangeReasons
                .filter { $0.contains(.layoutDirection) }
                .count == initialDirectionChangeCount + 1
        )

        cell.semanticContentAttribute = .forceLeftToRight
        contentView.configuration = ConfigurationProbe(value: "restored")

        #expect(contentView.appliedDirections.last == .leftToRight)
        #expect(
            contentView.semanticContentAttribute == .forceLeftToRight
        )
    }

    @MainActor
    @Test func contentViewsRecoverAfterDetachAndCanPreserveFixedSemantics() {
        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 160)
        )
        let cell = UITableViewCell(
            style: .default,
            reuseIdentifier: nil
        )
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 64)
        cell.semanticContentAttribute = .forceRightToLeft
        container.addSubview(cell)
        let host = UIView(frame: cell.contentView.bounds)
        cell.contentView.addSubview(host)
        let contentView = ConfigurationProbeContentView(
            configuration: ConfigurationProbe(value: "moving")
        )
        contentView.frame = host.bounds
        host.addSubview(contentView)

        let viewController = UIViewController()
        viewController.view = container
        let window = UIWindow(frame: container.bounds)
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        contentView.layoutIfNeeded()

        #expect(contentView.semanticContentAttribute == .forceRightToLeft)

        contentView.removeFromSuperview()
        cell.semanticContentAttribute = .forceLeftToRight
        #expect(contentView.semanticContentAttribute == .forceRightToLeft)

        host.addSubview(contentView)
        contentView.layoutIfNeeded()
        #expect(contentView.semanticContentAttribute == .forceLeftToRight)

        cell.removeFromSuperview()
        cell.semanticContentAttribute = .forceRightToLeft
        #expect(contentView.window == nil)
        #expect(contentView.semanticContentAttribute == .forceLeftToRight)

        _ = contentView.sizeThatFits(
            CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )
        #expect(contentView.semanticContentAttribute == .forceRightToLeft)

        contentView.quickLayoutSemanticDirectionBehavior = .preserve
        contentView.semanticContentAttribute = .playback
        cell.semanticContentAttribute = .forceRightToLeft
        contentView.configuration = ConfigurationProbe(value: "fixed")
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()

        #expect(contentView.semanticContentAttribute == .playback)
    }

    @MainActor
    @Test func quickLayoutHostsFollowContainerAppliedDirectionChanges() {
        let viewPair = (UIView(), UIView())
        let hostingView = QuickLayoutView {
            HStack {
                viewPair.0.frame(width: 20, height: 10)
                viewPair.1.frame(width: 20, height: 10)
            }
        }
        let scrollPair = (UIView(), UIView())
        let scrollView = QuickLayoutScrollView(.horizontal) {
            scrollPair.0.frame(width: 60, height: 20)
            scrollPair.1.frame(width: 60, height: 20)
        }
        hostingView.frame = CGRect(x: 0, y: 0, width: 160, height: 40)
        scrollView.frame = CGRect(x: 0, y: 50, width: 100, height: 40)

        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240)
        )
        container.addSubview(hostingView)
        container.addSubview(scrollView)
        let viewController = UIViewController()
        viewController.view = container
        let window = UIWindow(frame: container.bounds)
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }

        applyTestLayoutDirection(
            .leftToRight,
            container: container,
            hosts: [hostingView, scrollView]
        )
        window.layoutIfNeeded()
        hostingView.layoutIfNeeded()
        scrollView.layoutIfNeeded()

        #expect(hostingView.semanticContentAttribute == .forceLeftToRight)
        #expect(scrollView.semanticContentAttribute == .forceLeftToRight)
        #expect(viewPair.0.frame.minX < viewPair.1.frame.minX)
        #expect(scrollPair.0.frame.minX < scrollPair.1.frame.minX)
        let viewLeftToRightFrames = (viewPair.0.frame, viewPair.1.frame)
        let scrollLeftToRightFrames = (scrollPair.0.frame, scrollPair.1.frame)

        // The controller remains the source of truth, but runtime semantic
        // direction must be applied to already-materialized host boundaries.
        applyTestLayoutDirection(
            .rightToLeft,
            container: container,
            hosts: [hostingView, scrollView]
        )
        window.layoutIfNeeded()

        #expect(hostingView.semanticContentAttribute == .forceRightToLeft)
        #expect(scrollView.semanticContentAttribute == .forceRightToLeft)
        #expect(hostingView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(scrollView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(viewPair.0.frame.minX > viewPair.1.frame.minX)
        #expect(scrollPair.0.frame.minX > scrollPair.1.frame.minX)

        applyTestLayoutDirection(
            .leftToRight,
            container: container,
            hosts: [hostingView, scrollView]
        )
        window.layoutIfNeeded()

        #expect(viewPair.0.frame == viewLeftToRightFrames.0)
        #expect(viewPair.1.frame == viewLeftToRightFrames.1)
        #expect(scrollPair.0.frame == scrollLeftToRightFrames.0)
        #expect(scrollPair.1.frame == scrollLeftToRightFrames.1)
    }

    @MainActor
    @Test func hostingControllerFollowsRootDirectionRoundTrips() {
        let pair = (UIView(), UIView())
        let hostingController = QuickLayoutHostingController {
            HStack {
                pair.0.frame(width: 20, height: 10)
                pair.1.frame(width: 20, height: 10)
            }
        }
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 160, height: 80)
        )
        window.rootViewController = hostingController
        hostingController.view.semanticContentAttribute = .forceLeftToRight
        window.isHidden = false
        defer { window.isHidden = true }

        window.layoutIfNeeded()
        let leftToRightFrames = (pair.0.frame, pair.1.frame)
        #expect(pair.0.frame.minX < pair.1.frame.minX)

        hostingController.view.semanticContentAttribute = .forceRightToLeft
        window.layoutIfNeeded()

        #expect(pair.0.frame.minX > pair.1.frame.minX)

        hostingController.view.semanticContentAttribute = .forceLeftToRight
        window.layoutIfNeeded()

        #expect(pair.0.frame == leftToRightFrames.0)
        #expect(pair.1.frame == leftToRightFrames.1)
    }

    @MainActor
    @Test func representableChildFollowsContainerAppliedDirectionRoundTrips() {
        let childViewController = DirectionProbeViewController()
        let representable = QuickLayoutViewControllerRepresentable(
            childViewController
        )
        let hostingController = QuickLayoutHostingController {
            representable.frame(width: 120, height: 44)
        }
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 160, height: 80)
        )
        window.rootViewController = hostingController
        childViewController.loadViewIfNeeded()
        applyTestLayoutDirection(
            .leftToRight,
            container: hostingController.view,
            hosts: [representable, childViewController.directionView]
        )
        window.isHidden = false
        defer { window.isHidden = true }

        window.layoutIfNeeded()
        representable.quickLayoutIfNeeded()
        let directionView = childViewController.directionView
        let leftToRightFrames = (
            directionView.first.frame,
            directionView.second.frame
        )
        #expect(representable.semanticContentAttribute == .forceLeftToRight)
        #expect(directionView.semanticContentAttribute == .forceLeftToRight)
        #expect(directionView.first.frame.minX < directionView.second.frame.minX)

        applyTestLayoutDirection(
            .rightToLeft,
            container: hostingController.view,
            hosts: [representable, directionView]
        )
        window.layoutIfNeeded()
        representable.quickLayoutIfNeeded()

        #expect(representable.semanticContentAttribute == .forceRightToLeft)
        #expect(directionView.semanticContentAttribute == .forceRightToLeft)
        #expect(directionView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(directionView.first.frame.minX > directionView.second.frame.minX)

        applyTestLayoutDirection(
            .leftToRight,
            container: hostingController.view,
            hosts: [representable, directionView]
        )
        window.layoutIfNeeded()
        representable.quickLayoutIfNeeded()

        #expect(directionView.first.frame == leftToRightFrames.0)
        #expect(directionView.second.frame == leftToRightFrames.1)
    }

    @MainActor
    @Test func reusableListHostsRelayoutWhenTheirDirectionChanges() {
        let collectionCellViews = (UIView(), UIView())
        let collectionCell = QuickLayoutCollectionViewCell {
            HStack {
                collectionCellViews.0.frame(width: 20, height: 10)
                collectionCellViews.1.frame(width: 20, height: 10)
            }
        }
        let tableCellViews = (UIView(), UIView())
        let tableCell = QuickLayoutTableViewCell {
            HStack {
                tableCellViews.0.frame(width: 20, height: 10)
                tableCellViews.1.frame(width: 20, height: 10)
            }
        }
        let headerFooterViews = (UIView(), UIView())
        let headerFooter = QuickLayoutTableViewHeaderFooterView {
            HStack {
                headerFooterViews.0.frame(width: 20, height: 10)
                headerFooterViews.1.frame(width: 20, height: 10)
            }
        }
        let reusableViews = (UIView(), UIView())
        let reusableView = QuickLayoutCollectionReusableView {
            HStack {
                reusableViews.0.frame(width: 20, height: 10)
                reusableViews.1.frame(width: 20, height: 10)
            }
        }
        let scenarios: [(UIView, UIView, UIView)] = [
            (collectionCell, collectionCellViews.0, collectionCellViews.1),
            (tableCell, tableCellViews.0, tableCellViews.1),
            (headerFooter, headerFooterViews.0, headerFooterViews.1),
            (reusableView, reusableViews.0, reusableViews.1),
        ]

        for (host, first, second) in scenarios {
            host.semanticContentAttribute = .forceLeftToRight
            host.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
            host.layoutIfNeeded()
            let leftToRightFrames = (first.frame, second.frame)
            #expect(first.frame.minX < second.frame.minX)

            host.semanticContentAttribute = .forceRightToLeft
            host.layoutIfNeeded()
            #expect(first.frame.minX > second.frame.minX)

            host.semanticContentAttribute = .forceLeftToRight
            host.layoutIfNeeded()
            #expect(first.frame == leftToRightFrames.0)
            #expect(second.frame == leftToRightFrames.1)
        }
    }

    @MainActor
    @Test func reusableListHostsPublishEnvironmentDirectionChangesOnce() {
        let collectionCell = EnvironmentRecordingCollectionViewCell(
            frame: .zero
        )
        let tableCell = EnvironmentRecordingTableViewCell(
            style: .default,
            reuseIdentifier: nil
        )
        let headerFooter = EnvironmentRecordingTableHeaderFooterView(
            reuseIdentifier: nil
        )
        let reusableView = EnvironmentRecordingCollectionReusableView(
            frame: .zero
        )
        let scenarios: [(UIView, () -> [QuickLayoutEnvironmentChangeReason])] = [
            (collectionCell, { collectionCell.environmentChangeReasons }),
            (tableCell, { tableCell.environmentChangeReasons }),
            (headerFooter, { headerFooter.environmentChangeReasons }),
            (reusableView, { reusableView.environmentChangeReasons }),
        ]

        for (host, environmentChangeReasons) in scenarios {
            host.semanticContentAttribute = .forceLeftToRight
            host.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
            host.layoutIfNeeded()
            let initialChangeCount = environmentChangeReasons().count

            host.semanticContentAttribute = .forceRightToLeft
            host.layoutIfNeeded()

            #expect(environmentChangeReasons().count == initialChangeCount + 1)
            #expect(
                environmentChangeReasons().last?
                    .contains(.layoutDirection) == true
            )

            host.layoutIfNeeded()
            #expect(environmentChangeReasons().count == initialChangeCount + 1)
        }
    }

    @MainActor
    @Test func contentMarginsFollowRuntimeLayoutDirectionChanges() {
        let scrollView = QuickLayoutScrollView(.horizontal)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        _ = ScrollView(scrollView, .horizontal) {
            UIView().frame(width: 240, height: 40)
        }
        .contentMargins(.leading, 14)
        scrollView.layoutIfNeeded()

        #expect(scrollView.contentInset.left == 14)
        #expect(scrollView.contentInset.right == 0)
        #expect(scrollView.horizontalScrollIndicatorInsets.left == 14)
        #expect(scrollView.horizontalScrollIndicatorInsets.right == 0)
        scrollView.contentOffset.x = 40

        scrollView.semanticContentAttribute = .forceRightToLeft
        scrollView.layoutIfNeeded()

        #expect(scrollView.contentInset.left == 0)
        #expect(scrollView.contentInset.right == 14)
        #expect(scrollView.horizontalScrollIndicatorInsets.left == 0)
        #expect(scrollView.horizontalScrollIndicatorInsets.right == 14)
        #expect(scrollView.contentOffset.x == 40)

        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.layoutIfNeeded()

        #expect(scrollView.contentInset.left == 14)
        #expect(scrollView.contentInset.right == 0)
        #expect(scrollView.horizontalScrollIndicatorInsets.left == 14)
        #expect(scrollView.horizontalScrollIndicatorInsets.right == 0)
        #expect(scrollView.contentOffset.x == 40)
    }

    @MainActor
    @Test func changingContentMarginsPreservesAnExistingScrollPosition() {
        let scrollView = QuickLayoutScrollView(.horizontal)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        _ = ScrollView(scrollView, .horizontal) {
            UIView().frame(width: 300, height: 40)
        }
        .contentMargins(.horizontal, 20)
        scrollView.layoutIfNeeded()
        scrollView.contentOffset.x = 80

        _ = ScrollView(scrollView, .horizontal) {
            UIView().frame(width: 300, height: 40)
        }
        .contentMargins(.horizontal, 30)
        scrollView.layoutIfNeeded()

        #expect(scrollView.contentOffset.x == 80)
    }

    @MainActor
    @Test func contentMarginsCanTargetOnlyScrollIndicators() {
        let scrollView = QuickLayoutScrollView(.vertical)

        _ = ScrollView(scrollView, .vertical) {}
            .contentMargins(.vertical, 12, for: .scrollIndicators)

        let expected = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        #expect(scrollView.contentInset == .zero)
        #expect(scrollView.verticalScrollIndicatorInsets == expected)
        #expect(scrollView.horizontalScrollIndicatorInsets == .zero)
    }

    @MainActor
    @Test func automaticContentMarginsApplyToContentAndIndicators() {
        let scrollView = QuickLayoutScrollView(.vertical)

        _ = ScrollView(scrollView, .vertical) {}
            .contentMargins(10)

        let expected = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        #expect(scrollView.contentInset == expected)
        #expect(scrollView.verticalScrollIndicatorInsets == expected)
        #expect(scrollView.horizontalScrollIndicatorInsets == .zero)
    }

    @MainActor
    @Test func nilContentMarginPreservesAnEarlierMargin() {
        let scrollView = QuickLayoutScrollView(.horizontal)

        _ = ScrollView(scrollView, .horizontal) {}
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .contentMargins(.leading, nil, for: .scrollContent)

        #expect(scrollView.contentInset.left == 20)
        #expect(scrollView.contentInset.right == 20)
    }

    @MainActor
    @Test func nilContentMarginUsesTheContainersExistingDefault() {
        let scrollView = QuickLayoutScrollView(.horizontal)
        scrollView.contentInset = UIEdgeInsets(
            top: 0,
            left: 7,
            bottom: 0,
            right: 9
        )

        _ = ScrollView(scrollView, .horizontal) {}
            .contentMargins(.horizontal, nil, for: .scrollContent)

        #expect(scrollView.contentInset.left == 7)
        #expect(scrollView.contentInset.right == 9)
    }

    @MainActor
    @Test func nilSpecificPlacementDoesNotReplaceAutomaticMargins() {
        let scrollView = QuickLayoutScrollView(.vertical)

        _ = ScrollView(scrollView, .vertical) {}
            .contentMargins(.bottom, 24)
            .contentMargins(.horizontal, nil, for: .scrollContent)

        #expect(scrollView.contentInset.bottom == 24)
        #expect(scrollView.verticalScrollIndicatorInsets.bottom == 24)
    }

    @MainActor
    @Test func contentMarginsPreserveFiniteNegativeValues() {
        let scrollView = QuickLayoutScrollView(.horizontal)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 80)

        _ = ScrollView(scrollView, .horizontal) {
            UIView().frame(width: 200, height: 40)
        }
        .contentMargins(.horizontal, -20, for: .scrollContent)

        scrollView.layoutIfNeeded()

        #expect(scrollView.contentInset.left == -20)
        #expect(scrollView.contentInset.right == -20)
        #expect(scrollView.contentOffset.x == 20)
    }

    @MainActor
    @Test func contentMarginsFollowTheActiveScrollIndicatorAxis() {
        let scrollView = QuickLayoutScrollView(.vertical)

        _ = ScrollView(scrollView, .vertical) {}
            .contentMargins(.vertical, 12, for: .scrollIndicators)

        let expected = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        #expect(scrollView.verticalScrollIndicatorInsets == expected)
        #expect(scrollView.horizontalScrollIndicatorInsets == .zero)

        scrollView.axis = .horizontal

        #expect(scrollView.verticalScrollIndicatorInsets == .zero)
        #expect(scrollView.horizontalScrollIndicatorInsets == expected)
    }

    @MainActor
    @Test func specificContentMarginPlacementReplacesAutomaticForContent() {
        let scrollView = QuickLayoutScrollView(.horizontal)

        _ = ScrollView(scrollView, .horizontal) {}
            .contentMargins(.horizontal, 20)
            .contentMargins(.leading, 8, for: .scrollContent)

        #expect(scrollView.contentInset.left == 8)
        #expect(scrollView.contentInset.right == 0)
        #expect(scrollView.horizontalScrollIndicatorInsets.left == 20)
        #expect(scrollView.horizontalScrollIndicatorInsets.right == 20)
    }

    @MainActor
    @Test func explicitPlacementsDoNotInheritOtherAutomaticEdges() {
        let scrollView = QuickLayoutScrollView(.vertical)

        _ = ScrollView(scrollView, .vertical) {}
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .contentMargins(.bottom, 24)

        #expect(
            scrollView.contentInset
                == UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        )
        #expect(
            scrollView.verticalScrollIndicatorInsets
                == UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
        )
    }

    @MainActor
    @Test func explicitIndicatorPlacementReplacesAutomaticForIndicators() {
        let scrollView = QuickLayoutScrollView(.vertical)

        _ = ScrollView(scrollView, .vertical) {}
            .contentMargins(.horizontal, 24)
            .contentMargins(.bottom, 12, for: .scrollIndicators)

        #expect(
            scrollView.contentInset
                == UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        )
        #expect(
            scrollView.verticalScrollIndicatorInsets
                == UIEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        )
    }

    @MainActor
    @Test func laterContentMarginModifierOverridesSamePlacementPerEdge() {
        let scrollView = QuickLayoutScrollView(.horizontal)
        let element = ScrollView(scrollView, .horizontal) {}
            .contentMargins(.horizontal, 20)
            .contentMargins(.leading, 8)

        _ = element.views()

        #expect(scrollView.contentInset.left == 8)
        #expect(scrollView.contentInset.right == 20)
        #expect(scrollView.horizontalScrollIndicatorInsets.left == 8)
        #expect(scrollView.horizontalScrollIndicatorInsets.right == 20)
    }

    @MainActor
    @Test func contentMarginsResolveLeadingInRightToLeftLayout() {
        let scrollView = QuickLayoutScrollView(.horizontal)
        scrollView.semanticContentAttribute = .forceRightToLeft

        _ = ScrollView(scrollView, .horizontal) {}
            .contentMargins(.leading, 14)

        #expect(scrollView.contentInset.left == 0)
        #expect(scrollView.contentInset.right == 14)
        #expect(scrollView.horizontalScrollIndicatorInsets.right == 14)
    }

    @MainActor
    @Test func rebuildingScrollViewClearsRemovedContentMargins() {
        let scrollView = QuickLayoutScrollView(.vertical)

        _ = ScrollView(scrollView, .vertical) {}
            .contentMargins(10)
        #expect(scrollView.contentInset.top == 10)

        _ = ScrollView(scrollView, .vertical) {}

        #expect(scrollView.contentInset == .zero)
        #expect(scrollView.verticalScrollIndicatorInsets == .zero)
        #expect(scrollView.horizontalScrollIndicatorInsets == .zero)
    }

    @Test func safeAreaPaddingConsumesInheritedInsetsAndAddsSpacing() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .safeAreaPadding(.horizontal, 8)

        let size = withSafeArea(
            containerSize: CGSize(width: 200, height: 100),
            containerInsets: EdgeInsets(top: 20, leading: 10, bottom: 5, trailing: 15)
        ) {
            element.sizeThatFits(CGSize(width: 200, height: 100))
        }

        #expect(size == CGSize(width: 61, height: 30))
    }

    @Test func safeAreaPaddingSupportsPerEdgeInsets() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .safeAreaPadding(
                EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
            )

        let size = withSafeArea(
            containerSize: CGSize(width: 200, height: 100),
            containerInsets: EdgeInsets(top: 20, leading: 10, bottom: 5, trailing: 15)
        ) {
            element.sizeThatFits(CGSize(width: 200, height: 100))
        }

        #expect(size == CGSize(width: 51, height: 59))
    }

    @Test func repeatedSafeAreaPaddingAccumulatesPerEdge() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .safeAreaPadding(.leading, 8)
            .safeAreaPadding(.leading, 12)
            .safeAreaPadding(.bottom, 6)

        let size = withSafeArea(
            containerSize: CGSize(width: 200, height: 100),
            containerInsets: EdgeInsets(
                top: 20,
                leading: 10,
                bottom: 5,
                trailing: 15
            )
        ) {
            element.sizeThatFits(CGSize(width: 200, height: 100))
        }

        #expect(size == CGSize(width: 50, height: 41))
    }

    @Test func safeAreaPaddingClampsNegativeAndNonFiniteValuesToZero() {
        let intrinsicSize = CGSize(width: 20, height: 30)
        let proposal = CGSize(width: 200, height: 100)
        let negative = IntrinsicTestElement(size: intrinsicSize)
            .safeAreaPadding(.leading, -6)
        let perEdge = IntrinsicTestElement(size: intrinsicSize)
            .safeAreaPadding(
                EdgeInsets(
                    top: -.infinity,
                    leading: -4,
                    bottom: .nan,
                    trailing: 3
                )
            )

        let sizes = withSafeArea(
            containerSize: proposal,
            containerInsets: EdgeInsets(
                top: 20,
                leading: 10,
                bottom: 5,
                trailing: 15
            )
        ) {
            (
                negative.sizeThatFits(proposal),
                perEdge.sizeThatFits(proposal)
            )
        }

        #expect(sizes.0 == CGSize(width: 30, height: 30))
        #expect(sizes.1 == CGSize(width: 48, height: 55))
    }

    @MainActor
    @Test func localLayoutDirectionResolvesPhysicalSafeAreaEdges() {
        let leftToRightChild = UIView()
        let rightToLeftChild = UIView()
        let nestedPaddingChild = UIView()
        let ignoredLeadingChild = UIView()
        let frame = CGRect(x: 0, y: 0, width: 100, height: 40)

        func apply(
            _ child: UIView,
            layoutDirection: LayoutDirection
        ) {
            let element = child
                .frame(width: 20, height: 10)
                .safeAreaPadding(.leading, 0)
                .frame(width: 100, height: 40, alignment: .topLeading)
                .layoutDirection(layoutDirection)

            withPhysicalSafeArea(
                containerSize: frame.size,
                containerInsets: UIEdgeInsets(
                    top: 0,
                    left: 10,
                    bottom: 0,
                    right: 20
                )
            ) {
                element.applyFrame(
                    frame,
                    alignment: .topLeading,
                    layoutDirection: .leftToRight
                )
            }
        }

        apply(leftToRightChild, layoutDirection: .leftToRight)
        apply(rightToLeftChild, layoutDirection: .rightToLeft)

        let nestedPadding = nestedPaddingChild
            .frame(width: 20, height: 10)
            .safeAreaPadding(.leading, 0)
            .safeAreaPadding(.leading, 0)
            .frame(width: 100, height: 40, alignment: .topLeading)
            .layoutDirection(.rightToLeft)
        let ignoredLeading = ignoredLeadingChild
            .frame(width: 20, height: 10)
            .safeAreaPadding(.leading, 0)
            .ignoresSafeArea(.container, edges: .leading)
            .frame(width: 100, height: 40, alignment: .topLeading)
            .layoutDirection(.rightToLeft)
        withPhysicalSafeArea(
            containerSize: frame.size,
            containerInsets: UIEdgeInsets(
                top: 0,
                left: 10,
                bottom: 0,
                right: 20
            )
        ) {
            nestedPadding.applyFrame(
                frame,
                alignment: .topLeading,
                layoutDirection: .leftToRight
            )
            ignoredLeading.applyFrame(
                frame,
                alignment: .topLeading,
                layoutDirection: .leftToRight
            )
        }

        #expect(
            leftToRightChild.frame
                == CGRect(x: 10, y: 0, width: 20, height: 10)
        )
        #expect(
            rightToLeftChild.frame
                == CGRect(x: 60, y: 0, width: 20, height: 10)
        )
        #expect(frame.maxX - rightToLeftChild.frame.maxX == 20)
        #expect(nestedPaddingChild.frame == rightToLeftChild.frame)
        #expect(
            ignoredLeadingChild.frame
                == CGRect(x: 80, y: 0, width: 20, height: 10)
        )
    }

    @MainActor
    @Test func paddingIgnoringLayoutDirectionKeepsPhysicalInsets() {
        let leftToRightChild = UIView()
        let rightToLeftChild = UIView()
        let frame = CGRect(x: 0, y: 0, width: 36, height: 10)
        let physicalInsets = UIEdgeInsets(
            top: 0,
            left: 12,
            bottom: 0,
            right: 4
        )

        leftToRightChild
            .frame(width: 20, height: 10)
            .padding(ignoringLayoutDirection: physicalInsets)
            .applyFrame(
                frame,
                alignment: .topLeading,
                layoutDirection: .leftToRight
            )
        rightToLeftChild
            .frame(width: 20, height: 10)
            .padding(ignoringLayoutDirection: physicalInsets)
            .applyFrame(
                frame,
                alignment: .topLeading,
                layoutDirection: .rightToLeft
            )

        let expectedFrame = CGRect(x: 12, y: 0, width: 20, height: 10)
        #expect(leftToRightChild.frame == expectedFrame)
        #expect(rightToLeftChild.frame == expectedFrame)
    }

    @MainActor
    @Test func directionalInsetHelpersRoundTripWithLayoutDirection() {
        let view = SafeAreaProbeView(
            safeAreaInsets: UIEdgeInsets(
                top: 1,
                left: 10,
                bottom: 3,
                right: 20
            )
        )
        view.insetsLayoutMarginsFromSafeArea = false
        view.layoutMargins = UIEdgeInsets(
            top: 2,
            left: 7,
            bottom: 4,
            right: 13
        )

        view.semanticContentAttribute = .forceLeftToRight
        let leftToRightSafeArea = view.quickLayoutSafeAreaInsets
        let leftToRightMargins = view.quickLayoutLayoutMargins

        #expect(leftToRightSafeArea.leading == 10)
        #expect(leftToRightSafeArea.trailing == 20)
        #expect(leftToRightMargins.leading == 7)
        #expect(leftToRightMargins.trailing == 13)

        view.semanticContentAttribute = .forceRightToLeft
        let rightToLeftSafeArea = view.quickLayoutSafeAreaInsets
        let rightToLeftMargins = view.quickLayoutLayoutMargins

        #expect(rightToLeftSafeArea.leading == 20)
        #expect(rightToLeftSafeArea.trailing == 10)
        #expect(rightToLeftMargins.leading == 13)
        #expect(rightToLeftMargins.trailing == 7)

        view.semanticContentAttribute = .forceLeftToRight
        #expect(view.quickLayoutSafeAreaInsets.leading == 10)
        #expect(view.quickLayoutSafeAreaInsets.trailing == 20)
        #expect(view.quickLayoutLayoutMargins.leading == 7)
        #expect(view.quickLayoutLayoutMargins.trailing == 13)
    }

    @Test func safeAreaPaddingNilUsesQuickLayoutZeroSpacing() {
        let intrinsicSize = CGSize(width: 20, height: 30)
        let proposal = CGSize(width: 200, height: 100)
        let implicitNil = IntrinsicTestElement(size: intrinsicSize)
            .safeAreaPadding()
        let explicitNil = IntrinsicTestElement(size: intrinsicSize)
            .safeAreaPadding(.all, nil)
        let explicitZero = IntrinsicTestElement(size: intrinsicSize)
            .safeAreaPadding(.all, 0)

        #expect(implicitNil.sizeThatFits(proposal) == intrinsicSize)
        #expect(explicitNil.sizeThatFits(proposal) == intrinsicSize)
        #expect(explicitZero.sizeThatFits(proposal) == intrinsicSize)

        let sizesWithSafeArea = withSafeArea(
            containerSize: proposal,
            containerInsets: EdgeInsets(
                top: 20,
                leading: 10,
                bottom: 5,
                trailing: 15
            )
        ) {
            (
                implicitNil.sizeThatFits(proposal),
                explicitNil.sizeThatFits(proposal),
                explicitZero.sizeThatFits(proposal)
            )
        }

        #expect(sizesWithSafeArea.0 == CGSize(width: 45, height: 55))
        #expect(sizesWithSafeArea.1 == sizesWithSafeArea.0)
        #expect(sizesWithSafeArea.2 == sizesWithSafeArea.0)
    }

    @Test func safeAreaPaddingReevaluatesContainerAndKeyboardContext() {
        let element = IntrinsicTestElement(
            size: CGSize(width: 20, height: 30)
        ).safeAreaPadding()

        let first = withSafeArea(
            containerSize: CGSize(width: 200, height: 100),
            containerInsets: EdgeInsets(
                top: 1,
                leading: 2,
                bottom: 3,
                trailing: 4
            )
        ) {
            element.sizeThatFits(CGSize(width: 200, height: 100))
        }
        let second = withSafeArea(
            containerSize: CGSize(width: 240, height: 120),
            containerInsets: EdgeInsets(
                top: 10,
                leading: 0,
                bottom: 5,
                trailing: 7
            ),
            keyboardInsets: EdgeInsets(
                top: 0,
                leading: 9,
                bottom: 40,
                trailing: 0
            )
        ) {
            element.sizeThatFits(CGSize(width: 240, height: 120))
        }
        let third = withSafeArea(
            containerSize: CGSize(width: 120, height: 80),
            containerInsets: .zero,
            keyboardInsets: .zero
        ) {
            element.sizeThatFits(CGSize(width: 120, height: 80))
        }

        #expect(first == CGSize(width: 26, height: 34))
        #expect(second == CGSize(width: 36, height: 80))
        #expect(third == CGSize(width: 20, height: 30))
    }

    @MainActor
    @Test func quickLayoutViewKeyboardSafeAreaUsesConfiguredHiddenBaseline() {
        let host = KeyboardSafeAreaProbeQuickLayoutView(
            safeAreaInsets: UIEdgeInsets(
                top: 0,
                left: 0,
                bottom: 34,
                right: 0
            )
        )
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 480)

        #expect(
            host.quickLayoutKeyboardSafeAreaBehavior == .disabled
        )
        #expect(host.quickLayoutKeyboardSafeAreaInsets == .zero)

        host.quickLayoutKeyboardSafeAreaBehavior = .docked(
            usesBottomSafeArea: true
        )
        host.layoutIfNeeded()
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 34)
        #expect(abs(host.keyboardSafeAreaView.frame.maxY - 446) < 1)
        #expect(abs(host.containerSafeAreaView.frame.maxY - 446) < 1)

        host.quickLayoutKeyboardSafeAreaBehavior = .docked(
            usesBottomSafeArea: false
        )
        host.layoutIfNeeded()
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 0)
        #expect(abs(host.keyboardSafeAreaView.frame.maxY - 480) < 1)
        #expect(abs(host.containerSafeAreaView.frame.maxY - 446) < 1)

        host.quickLayoutKeyboardSafeAreaBehavior = .disabled
        #expect(host.quickLayoutKeyboardSafeAreaInsets == .zero)
    }

    @MainActor
    @Test func quickLayoutHostsForwardKeyboardDismissPaddingIndependently() {
        guard #available(iOS 17.0, *) else { return }

        let host = KeyboardSafeAreaProbeQuickLayoutView(
            safeAreaInsets: UIEdgeInsets(
                top: 0,
                left: 0,
                bottom: 34,
                right: 0
            )
        )
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        host.layoutIfNeeded()
        let initialKeyboardFrame = host.keyboardSafeAreaView.frame

        #expect(host.quickLayoutKeyboardDismissPadding == 0)
        host.quickLayoutKeyboardDismissPadding = 52
        #expect(host.quickLayoutKeyboardDismissPadding == 52)
        #expect(host.keyboardLayoutGuide.keyboardDismissPadding == 52)
        #expect(host.quickLayoutKeyboardSafeAreaInsets == .zero)
        host.layoutIfNeeded()
        #expect(host.keyboardSafeAreaView.frame == initialKeyboardFrame)

        host.quickLayoutKeyboardSafeAreaBehavior = .docked(
            usesBottomSafeArea: true
        )
        host.layoutIfNeeded()
        #expect(host.quickLayoutKeyboardDismissPadding == 52)
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 34)
        host.quickLayoutKeyboardSafeAreaBehavior = .disabled
        #expect(host.quickLayoutKeyboardDismissPadding == 52)
        #expect(host.quickLayoutKeyboardSafeAreaInsets == .zero)

        let hostingController = QuickLayoutHostingController {
            EmptyLayout()
        }
        hostingController.loadViewIfNeeded()
        #expect(hostingController.quickLayoutKeyboardDismissPadding == 0)
        hostingController.quickLayoutKeyboardDismissPadding = 44
        #expect(hostingController.quickLayoutKeyboardDismissPadding == 44)
        #expect(
            hostingController.view.keyboardLayoutGuide.keyboardDismissPadding
                == 44
        )
    }

    @MainActor
    @Test func quickLayoutViewKeyboardSafeAreaTracksOnlyDockedKeyboard() {
        let notificationCenter = NotificationCenter()
        let dockingState = KeyboardDockingResolverState()
        let host = KeyboardSafeAreaProbeQuickLayoutView(
            safeAreaInsets: UIEdgeInsets(
                top: 0,
                left: 0,
                bottom: 34,
                right: 0
            )
        )
        let viewController = UIViewController()
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        dockingState.window = window
        defer { window.isHidden = true }
        host.frame = viewController.view.bounds
        viewController.view.addSubview(host)
        host.configureQuickLayoutKeyboardSafeAreaForTesting(
            notificationCenter: notificationCenter
        ) { _, view in
            !dockingState.treatsKeyboardAsSplitOrUndocked
                && view.window === dockingState.window
        }
        host.quickLayoutKeyboardSafeAreaBehavior = .docked(
            usesBottomSafeArea: true
        )
        host.layoutIfNeeded()

        let dockedFrame = window.convert(
            CGRect(x: 0, y: 300, width: 320, height: 180),
            to: nil
        )
        notificationCenter.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: dockedFrame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ]
        )
        host.layoutIfNeeded()

        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 180)
        #expect(abs(host.keyboardSafeAreaView.frame.maxY - 300) < 1)
        #expect(abs(host.containerSafeAreaView.frame.maxY - 446) < 1)
        host.quickLayoutKeyboardSafeAreaBehavior = .docked(
            usesBottomSafeArea: false
        )
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 180)

        // 系统 guide 会把 split/undocked 键盘判为非 docked，即使通知只提供了一个
        // 看起来与停靠键盘相同的满宽外接矩形。
        dockingState.treatsKeyboardAsSplitOrUndocked = true
        notificationCenter.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: window.screen,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: dockedFrame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ]
        )
        host.layoutIfNeeded()
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 0)

        host.quickLayoutKeyboardSafeAreaBehavior = .docked(
            usesBottomSafeArea: true
        )
        dockingState.treatsKeyboardAsSplitOrUndocked = false

        let floatingFrame = window.convert(
            CGRect(x: 40, y: 220, width: 220, height: 180),
            to: nil
        )
        notificationCenter.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: floatingFrame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ]
        )
        host.layoutIfNeeded()

        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 34)
        #expect(abs(host.keyboardSafeAreaView.frame.maxY - 446) < 1)
        notificationCenter.post(
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(
                    x: 0,
                    y: 480,
                    width: 320,
                    height: 0
                ),
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ]
        )
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 34)

        // disabled 必须清零并取消监听；后续事件不能重新写入 keyboard safe-area。
        host.quickLayoutKeyboardSafeAreaBehavior = .disabled
        notificationCenter.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: window.screen,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: dockedFrame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ]
        )
        #expect(host.quickLayoutKeyboardSafeAreaInsets == .zero)

        // 重新启用后通过公开属性重新建立监听，bounds 变化后使用新窗口几何解析。
        host.quickLayoutKeyboardSafeAreaBehavior = .docked(
            usesBottomSafeArea: true
        )
        window.frame = CGRect(x: 0, y: 0, width: 480, height: 320)
        viewController.view.frame = window.bounds
        host.frame = viewController.view.bounds
        let rotatedDockedFrame = window.screen.coordinateSpace.convert(
            CGRect(x: 0, y: 180, width: 480, height: 140),
            from: window
        )
        notificationCenter.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: window.screen,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    rotatedDockedFrame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ]
        )
        host.layoutIfNeeded()
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 140)

        // 同一屏幕上的另一个窗口收到键盘时，当前宿主必须回退隐藏基线；重新挂载到
        // 键盘所属窗口后，再恢复 docked 几何。
        let secondViewController = UIViewController()
        let secondWindow = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 360, height: 500)
        )
        secondWindow.rootViewController = secondViewController
        secondWindow.makeKeyAndVisible()
        defer { secondWindow.isHidden = true }
        host.removeFromSuperview()
        host.frame = secondViewController.view.bounds
        secondViewController.view.addSubview(host)
        let secondDockedFrame = secondWindow.screen.coordinateSpace.convert(
            CGRect(x: 0, y: 380, width: 360, height: 120),
            from: secondWindow
        )
        notificationCenter.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: secondWindow.screen,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    secondDockedFrame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ]
        )
        host.layoutIfNeeded()
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 34)

        dockingState.window = secondWindow
        notificationCenter.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: secondWindow.screen,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    secondDockedFrame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ]
        )
        host.layoutIfNeeded()
        #expect(host.quickLayoutKeyboardSafeAreaInsets.bottom == 120)
    }

    @Test func ignoresSafeAreaExpandsContainerRelativeFrame() {
        let respectingSafeArea = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .containerRelativeFrame(.horizontal)
        let ignoringSafeArea = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .containerRelativeFrame(.horizontal)
            .ignoresSafeArea(.container, edges: .horizontal)

        let sizes = withSafeArea(
            containerSize: CGSize(width: 200, height: 100),
            containerInsets: EdgeInsets(top: 20, leading: 10, bottom: 5, trailing: 15)
        ) {
            (
                respectingSafeArea.sizeThatFits(CGSize(width: 200, height: 100)),
                ignoringSafeArea.sizeThatFits(CGSize(width: 200, height: 100))
            )
        }

        #expect(sizes.0 == CGSize(width: 175, height: 30))
        #expect(sizes.1 == CGSize(width: 200, height: 30))
    }

    @Test func ignoresSafeAreaCanTargetKeyboardRegion() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .safeAreaPadding(.bottom, 0)
            .ignoresSafeArea(.keyboard, edges: .bottom)

        let size = withSafeArea(
            containerSize: CGSize(width: 200, height: 100),
            containerInsets: EdgeInsets(top: 0, leading: 0, bottom: 5, trailing: 0),
            keyboardInsets: EdgeInsets(top: 0, leading: 0, bottom: 40, trailing: 0)
        ) {
            element.sizeThatFits(CGSize(width: 200, height: 100))
        }

        #expect(size == CGSize(width: 20, height: 35))
    }

    @Test func verticalSafeAreaInsetReservesMeasuredContentAndSpacing() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 4) {
                IntrinsicTestElement(size: CGSize(width: 50, height: 12))
            }

        let layout = withSafeArea(
            containerSize: CGSize(width: 200, height: 100),
            containerInsets: EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0)
        ) {
            element.quick_layoutThatFits(CGSize(width: 200, height: 100))
        }

        #expect(layout.size == CGSize(width: 20, height: 56))
        #expect(layout.children[1].position == CGPoint(x: 0, y: 34))
    }

    @Test func horizontalSafeAreaInsetReservesMeasuredContentAndSpacing() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .safeAreaInset(edge: .leading, alignment: .top, spacing: 4) {
                IntrinsicTestElement(size: CGSize(width: 12, height: 50))
            }

        let size = withSafeArea(
            containerSize: CGSize(width: 200, height: 100),
            containerInsets: EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0)
        ) {
            element.sizeThatFits(CGSize(width: 200, height: 100))
        }

        #expect(size == CGSize(width: 46, height: 30))
    }

    @Test func safeAreaInsetNilUsesQuickLayoutZeroSpacingOnBothAxes() {
        let proposal = CGSize(width: 200, height: 100)
        let insets = EdgeInsets(
            top: 0,
            leading: 10,
            bottom: 10,
            trailing: 0
        )
        let verticalNil = IntrinsicTestElement(
            size: CGSize(width: 20, height: 30)
        ).safeAreaInset(edge: .bottom, spacing: nil) {
            IntrinsicTestElement(size: CGSize(width: 50, height: 12))
        }
        let verticalZero = IntrinsicTestElement(
            size: CGSize(width: 20, height: 30)
        ).safeAreaInset(edge: .bottom, spacing: 0) {
            IntrinsicTestElement(size: CGSize(width: 50, height: 12))
        }
        let horizontalNil = IntrinsicTestElement(
            size: CGSize(width: 20, height: 30)
        ).safeAreaInset(
            edge: HorizontalEdge.leading,
            spacing: nil
        ) {
            IntrinsicTestElement(size: CGSize(width: 12, height: 50))
        }
        let horizontalZero = IntrinsicTestElement(
            size: CGSize(width: 20, height: 30)
        ).safeAreaInset(
            edge: HorizontalEdge.leading,
            spacing: 0
        ) {
            IntrinsicTestElement(size: CGSize(width: 12, height: 50))
        }

        let sizes = withSafeArea(
            containerSize: proposal,
            containerInsets: insets
        ) {
            (
                verticalNil.sizeThatFits(proposal),
                verticalZero.sizeThatFits(proposal),
                horizontalNil.sizeThatFits(proposal),
                horizontalZero.sizeThatFits(proposal)
            )
        }

        #expect(sizes.0 == sizes.1)
        #expect(sizes.2 == sizes.3)
        #expect(sizes.0 == CGSize(width: 20, height: 52))
        #expect(sizes.2 == CGSize(width: 42, height: 30))
    }

    @Test func safeAreaInsetNilContentUsesEmptyLayoutAndKeepsSafeArea() {
        let proposal = CGSize(width: 200, height: 100)
        let insets = EdgeInsets(
            top: 0,
            leading: 10,
            bottom: 10,
            trailing: 0
        )
        let vertical = IntrinsicTestElement(
            size: CGSize(width: 20, height: 30)
        ).safeAreaInset(edge: .bottom, spacing: nil) {
            nil as IntrinsicTestElement?
        }
        let horizontal = IntrinsicTestElement(
            size: CGSize(width: 20, height: 30)
        ).safeAreaInset(
            edge: HorizontalEdge.leading,
            spacing: nil
        ) {
            nil as IntrinsicTestElement?
        }

        let sizes = withSafeArea(
            containerSize: proposal,
            containerInsets: insets
        ) {
            (
                vertical.sizeThatFits(proposal),
                horizontal.sizeThatFits(proposal)
            )
        }

        #expect(sizes.0 == CGSize(width: 20, height: 40))
        #expect(sizes.1 == CGSize(width: 30, height: 30))
    }

    @MainActor
    @Test func leadingSafeAreaInsetUsesPhysicalEdgeForLocalDirection() {
        let leftToRightTarget = UIView()
        let leftToRightInset = UIView()
        let rightToLeftTarget = UIView()
        let rightToLeftInset = UIView()
        let frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        let physicalInsets = UIEdgeInsets(
            top: 0,
            left: 10,
            bottom: 0,
            right: 20
        )

        func apply(
            target: UIView,
            inset: UIView,
            layoutDirection: LayoutDirection
        ) {
            let element = target
                .frame(width: 20, height: 10)
                .safeAreaInset(
                    edge: HorizontalEdge.leading,
                    alignment: .top,
                    spacing: 4
                ) {
                    inset.frame(width: 12, height: 16)
                }
                .frame(width: 100, height: 40, alignment: .topLeading)
                .layoutDirection(layoutDirection)

            withPhysicalSafeArea(
                containerSize: frame.size,
                containerInsets: physicalInsets
            ) {
                element.applyFrame(
                    frame,
                    alignment: .topLeading,
                    layoutDirection: .leftToRight
                )
            }
        }

        apply(
            target: leftToRightTarget,
            inset: leftToRightInset,
            layoutDirection: .leftToRight
        )
        apply(
            target: rightToLeftTarget,
            inset: rightToLeftInset,
            layoutDirection: .rightToLeft
        )

        #expect(leftToRightInset.frame.minX == physicalInsets.left)
        #expect(
            leftToRightTarget.frame.minX
                == leftToRightInset.frame.maxX + 4
        )
        #expect(
            frame.maxX - rightToLeftInset.frame.maxX
                == physicalInsets.right
        )
        #expect(
            rightToLeftInset.frame.minX
                == rightToLeftTarget.frame.maxX + 4
        )
        #expect(leftToRightTarget.frame.size == CGSize(width: 20, height: 10))
        #expect(rightToLeftTarget.frame.size == CGSize(width: 20, height: 10))
        #expect(leftToRightInset.frame.size == CGSize(width: 12, height: 16))
        #expect(rightToLeftInset.frame.size == CGSize(width: 12, height: 16))
    }

    @Test func safeAreaPaddingScopesContainerRelativeFrameToRemainingSpace() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .containerRelativeFrame(.horizontal)
            .safeAreaPadding(.horizontal, 8)

        let size = withSafeArea(
            containerSize: CGSize(width: 200, height: 100),
            containerInsets: EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 15)
        ) {
            element.sizeThatFits(CGSize(width: 200, height: 100))
        }

        #expect(size == CGSize(width: 200, height: 30))
    }

    @Test func viewThatFitsSelectsFirstAlternativeWhoseIdealSizeFits() {
        let element = ViewThatFits {
            IntrinsicTestElement(size: CGSize(width: 180, height: 40))
            IntrinsicTestElement(size: CGSize(width: 100, height: 50))
            IntrinsicTestElement(size: CGSize(width: 60, height: 60))
        }

        let size = element.sizeThatFits(CGSize(width: 120, height: 55))

        #expect(size == CGSize(width: 100, height: 50))
    }

    @Test func viewThatFitsChecksOnlyRequestedAxes() {
        let horizontal = ViewThatFits(in: .horizontal) {
            IntrinsicTestElement(size: CGSize(width: 110, height: 200))
            IntrinsicTestElement(size: CGSize(width: 80, height: 70))
        }
        let bothAxes = ViewThatFits {
            IntrinsicTestElement(size: CGSize(width: 110, height: 200))
            IntrinsicTestElement(size: CGSize(width: 80, height: 70))
        }
        let proposal = CGSize(width: 120, height: 80)

        #expect(horizontal.sizeThatFits(proposal) == CGSize(width: 110, height: 200))
        #expect(bothAxes.sizeThatFits(proposal) == CGSize(width: 80, height: 70))
    }

    @Test func viewThatFitsUsesLastAlternativeAsFallback() {
        let element = ViewThatFits(in: .horizontal) {
            IntrinsicTestElement(size: CGSize(width: 200, height: 40))
            IntrinsicTestElement(size: CGSize(width: 150, height: 50))
        }

        let size = element.sizeThatFits(CGSize(width: 100, height: 80))

        #expect(size == CGSize(width: 150, height: 50))
    }

    @Test func viewThatFitsWithEmptyAxesAlwaysUsesFirstAlternative() {
        let element = ViewThatFits(in: []) {
            IntrinsicTestElement(size: CGSize(width: 240, height: 160))
            IntrinsicTestElement(size: CGSize(width: 80, height: 40))
        }

        let size = element.sizeThatFits(CGSize(width: 100, height: 60))

        #expect(size == CGSize(width: 240, height: 160))
    }

    @MainActor
    @Test func viewThatFitsCollapsesUnselectedViewsWhenSelectionChanges() {
        let primary = IntrinsicTestView(size: CGSize(width: 180, height: 20))
        let fallback = IntrinsicTestView(size: CGSize(width: 80, height: 30))
        let element = ViewThatFits(in: .horizontal) {
            primary
            fallback
        }

        element.applyFrame(
            CGRect(x: 0, y: 0, width: 200, height: 40),
            alignment: .topLeading
        )
        #expect(primary.bounds.size == CGSize(width: 180, height: 20))
        #expect(fallback.bounds.size == .zero)

        element.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 40),
            alignment: .topLeading
        )
        #expect(primary.bounds.size == .zero)
        #expect(fallback.bounds.size == CGSize(width: 80, height: 30))
    }

    @MainActor
    @Test func viewThatFitsExtractsSharedAlternativeViewsOnce() {
        let title = IntrinsicTestView(size: CGSize(width: 80, height: 20))
        let action = IntrinsicTestView(size: CGSize(width: 60, height: 30))
        let element = ViewThatFits {
            HStack {
                title
                action
            }
            VStack {
                title
                action
            }
        }

        let views = element.views()

        #expect(views.count == 2)
        #expect(views[0] === title)
        #expect(views[1] === action)
    }

    @MainActor
    @Test func onGeometryChangeRunsAfterApplyAndFiltersEqualValues() {
        let view = IntrinsicTestView(size: .zero)
        var widths: [CGFloat] = []
        let element = view
            .resizable()
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                widths.append(width)
            }

        _ = element.sizeThatFits(CGSize(width: 100, height: 40))
        #expect(widths.isEmpty)

        element.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 40),
            alignment: .topLeading
        )
        element.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 40),
            alignment: .topLeading
        )
        element.applyFrame(
            CGRect(x: 0, y: 0, width: 120, height: 40),
            alignment: .topLeading
        )

        #expect(widths == [100, 120])
    }

    @MainActor
    @Test func onGeometryChangeSupportsOldAndNewValues() {
        let view = IntrinsicTestView(size: .zero)
        var oldWidths: [CGFloat] = []
        var newWidths: [CGFloat] = []
        let element = view
            .resizable()
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { oldWidth, newWidth in
                oldWidths.append(oldWidth)
                newWidths.append(newWidth)
            }

        element.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 40),
            alignment: .topLeading
        )
        element.applyFrame(
            CGRect(x: 0, y: 0, width: 80, height: 40),
            alignment: .topLeading
        )

        #expect(oldWidths == [100, 100])
        #expect(newWidths == [100, 80])
    }

    @MainActor
    @Test func onGeometryChangeCanTransformGeometryIntoDerivedState() {
        let view = IntrinsicTestView(size: .zero)
        var compactValues: [Bool] = []
        let element = view
            .resizable()
            .onGeometryChange(for: Bool.self) { geometry in
                geometry.size.width < 100
            } action: { isCompact in
                compactValues.append(isCompact)
            }

        for width: CGFloat in [120, 110, 80, 70, 130] {
            element.applyFrame(
                CGRect(x: 0, y: 0, width: width, height: 40),
                alignment: .topLeading
            )
        }

        #expect(compactValues == [false, true, false])
    }

    @MainActor
    @Test func geometryProxyReportsSizeAndLocalFrame() {
        let view = IntrinsicTestView(size: .zero)
        var snapshots: [GeometrySnapshot] = []
        let element = view
            .resizable()
            .onGeometryChange(for: GeometrySnapshot.self) { geometry in
                GeometrySnapshot(
                    size: geometry.size,
                    localFrame: geometry.frame(in: .local)
                )
            } action: { snapshot in
                snapshots.append(snapshot)
            }

        element.applyFrame(
            CGRect(x: 14, y: 22, width: 90, height: 35),
            alignment: .topLeading
        )

        #expect(
            snapshots == [
                GeometrySnapshot(
                    size: CGSize(width: 90, height: 35),
                    localFrame: CGRect(x: 0, y: 0, width: 90, height: 35)
                ),
            ]
        )
    }

    @MainActor
    @Test func geometryProxyUsesTheQuickLayoutDirectionForSafeAreaInsets() {
        let view = SafeAreaProbeView(
            safeAreaInsets: UIEdgeInsets(
                top: 1,
                left: 10,
                bottom: 3,
                right: 20
            )
        )

        let leftToRight = GeometryProxy(
            observing: view,
            layoutDirection: .leftToRight
        )
        let rightToLeft = GeometryProxy(
            observing: view,
            layoutDirection: .rightToLeft
        )

        #expect(leftToRight.safeAreaInsets.leading == 10)
        #expect(leftToRight.safeAreaInsets.trailing == 20)
        #expect(rightToLeft.safeAreaInsets.leading == 20)
        #expect(rightToLeft.safeAreaInsets.trailing == 10)
    }

    @MainActor
    @Test func geometryObservationTracksLocalLayoutDirectionChanges() {
        var layoutDirection = LayoutDirection.rightToLeft
        var safeAreaSnapshots: [CGSize] = []
        let child = UIView()
        let hostingView = QuickLayoutView {
            child
                .resizable()
                .onGeometryChange(for: CGSize.self) { geometry in
                    CGSize(
                        width: geometry.safeAreaInsets.leading,
                        height: geometry.safeAreaInsets.trailing
                    )
                } action: { insets in
                    safeAreaSnapshots.append(insets)
                }
                .layoutDirection(layoutDirection)
        }
        let viewController = UIViewController()
        viewController.view = hostingView
        viewController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0,
            left: 10,
            bottom: 0,
            right: 20
        )
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        window.rootViewController = viewController
        window.isHidden = false
        defer { window.isHidden = true }

        window.layoutIfNeeded()
        hostingView.layoutIfNeeded()

        #expect(
            safeAreaSnapshots.last
                == CGSize(width: 20, height: 10)
        )

        layoutDirection = .leftToRight
        hostingView.setNeedsQuickLayout()
        hostingView.layoutIfNeeded()

        #expect(
            safeAreaSnapshots.suffix(2)
                == [
                    CGSize(width: 20, height: 10),
                    CGSize(width: 10, height: 20),
                ]
        )
    }

    @MainActor
    @Test func geometryObservationStateSurvivesBodyRebuilds() {
        let view = IntrinsicTestView(size: .zero)
        let registry = QuickLayoutGeometryObservationRegistry()
        var firstWidths: [CGFloat] = []
        var rebuiltWidths: [CGFloat] = []

        func makeElement(
            action: @escaping (CGFloat) -> Void
        ) -> Element & Layout {
            view.resizable().onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                action(width)
            }
        }

        let first = QuickLayoutGeometryObservationContext.withRegistry(registry) {
            makeElement { firstWidths.append($0) }
        }
        first.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 40),
            alignment: .topLeading
        )

        let rebuilt = QuickLayoutGeometryObservationContext.withRegistry(registry) {
            makeElement { rebuiltWidths.append($0) }
        }
        #expect(first.views().last === rebuilt.views().last)

        rebuilt.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 40),
            alignment: .topLeading
        )
        rebuilt.applyFrame(
            CGRect(x: 0, y: 0, width: 120, height: 40),
            alignment: .topLeading
        )

        #expect(firstWidths == [100])
        #expect(rebuiltWidths == [120])
    }

    @MainActor
    @Test func geometryObservationDistinguishesElementsWithoutViews() {
        let registry = QuickLayoutGeometryObservationRegistry()
        var widths: [CGFloat] = []

        func makeElement(width: CGFloat) -> Element & Layout {
            IntrinsicTestElement(size: CGSize(width: width, height: 20))
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { width in
                    widths.append(width)
                }
        }

        let first = QuickLayoutGeometryObservationContext.withRegistry(registry) {
            (makeElement(width: 20), makeElement(width: 30))
        }
        #expect(first.0.views().last !== first.1.views().last)

        first.0.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 40),
            alignment: .topLeading
        )
        first.1.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 40),
            alignment: .topLeading
        )

        let rebuilt = QuickLayoutGeometryObservationContext.withRegistry(registry) {
            (makeElement(width: 20), makeElement(width: 30))
        }
        #expect(first.0.views().last === rebuilt.0.views().last)
        #expect(first.1.views().last === rebuilt.1.views().last)

        rebuilt.0.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 40),
            alignment: .topLeading
        )
        rebuilt.1.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 40),
            alignment: .topLeading
        )

        #expect(widths == [20, 30])
    }

    @Test func proposedSizeProvidesStandardProposalsAndFallbackReplacement() {
        #expect(ProposedSize.zero == ProposedSize(width: 0, height: 0))
        #expect(
            ProposedSize.infinity
                == ProposedSize(width: .infinity, height: .infinity)
        )
        #expect(ProposedSize.unspecified.width == nil)
        #expect(ProposedSize.unspecified.height == nil)
        #expect(
            ProposedSize(width: nil, height: 24)
                .replacingUnspecifiedDimensions(
                    by: CGSize(width: 80, height: 90)
                )
                == CGSize(width: 80, height: 24)
        )
    }

    @Test func flexibleFrameUsesIdealSizeForUnspecifiedProposal() {
        let probe = FlexibleFrameProposalProbe()
        let element = FlexibleFrameProposalElement(probe: probe)
            .frame(idealWidth: 80, idealHeight: 40)

        let size = element.sizeThatFits(
            CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
        )

        #expect(probe.proposals == [CGSize(width: 80, height: 40)])
        #expect(size == CGSize(width: 80, height: 40))
    }

    @Test func flexibleFrameConstraintOrderingMatchesSwiftUIDiagnostics() {
        #expect(
            flexibleFrameConstraintsAreNondecreasing(
                minimum: nil,
                ideal: nil,
                maximum: nil
            )
        )
        #expect(
            flexibleFrameConstraintsAreNondecreasing(
                minimum: 40,
                ideal: nil,
                maximum: 100
            )
        )
        #expect(
            flexibleFrameConstraintsAreNondecreasing(
                minimum: 40,
                ideal: 60,
                maximum: 100
            )
        )
        #expect(
            !flexibleFrameConstraintsAreNondecreasing(
                minimum: 100,
                ideal: nil,
                maximum: 80
            )
        )
        #expect(
            !flexibleFrameConstraintsAreNondecreasing(
                minimum: 100,
                ideal: 80,
                maximum: 160
            )
        )
        #expect(
            !flexibleFrameConstraintsAreNondecreasing(
                minimum: 40,
                ideal: 120,
                maximum: 100
            )
        )
        #expect(
            !flexibleFrameConstraintsAreNondecreasing(
                minimum: .nan,
                ideal: nil,
                maximum: nil
            )
        )
    }

    @Test func flexibleFramePrefersFiniteProposalOverIdealSize() {
        let probe = FlexibleFrameProposalProbe()
        let element = FlexibleFrameProposalElement(probe: probe)
            .frame(idealWidth: 80, idealHeight: 40)

        let size = element.sizeThatFits(CGSize(width: 60, height: 30))

        #expect(probe.proposals == [CGSize(width: 60, height: 30)])
        #expect(size == CGSize(width: 60, height: 30))
    }

    @Test func flexibleFrameResolvesValidIdealSizeWithinMinimumAndMaximum() {
        let probe = FlexibleFrameProposalProbe()
        let element = FlexibleFrameProposalElement(probe: probe)
            .frame(
                minWidth: 50,
                idealWidth: 60,
                maxWidth: 70,
                minHeight: 20,
                idealHeight: 40,
                maxHeight: 60
            )

        let size = element.sizeThatFits(
            CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
        )

        #expect(probe.proposals == [CGSize(width: 60, height: 40)])
        #expect(size == CGSize(width: 60, height: 40))
    }

    @MainActor
    @Test func flexibleFrameAlignsChildInsideResolvedIdealSize() {
        let view = IntrinsicTestView(size: CGSize(width: 20, height: 10))
        let element = view.frame(
            minWidth: 40,
            idealWidth: 80,
            maxWidth: 120,
            minHeight: 20,
            idealHeight: 40,
            maxHeight: 60,
            alignment: .bottomTrailing
        )
        let idealSize = element.sizeThatFits(
            CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
        )

        element.applyFrame(
            CGRect(origin: .zero, size: idealSize),
            alignment: .topLeading
        )

        #expect(idealSize == CGSize(width: 80, height: 40))
        #expect(view.frame == CGRect(x: 60, y: 30, width: 20, height: 10))
    }

    @Test func aspectRatioAcceptsScalarWidthToHeightRatio() {
        let probe = AspectRatioProposalProbe(
            idealSize: CGSize(width: 200, height: 100)
        )
        let element = AspectRatioProposalElement(probe: probe)
            .aspectRatio(2, contentMode: .fit)

        let size = element.sizeThatFits(CGSize(width: 100, height: 100))

        #expect(probe.proposals == [CGSize(width: 100, height: 50)])
        #expect(size == CGSize(width: 100, height: 50))
    }

    @Test func aspectRatioKeepsExistingSizeOverloadAvailable() {
        let probe = AspectRatioProposalProbe(
            idealSize: CGSize(width: 200, height: 100)
        )
        let element = AspectRatioProposalElement(probe: probe)
            .aspectRatio(
                CGSize(width: 2, height: 1),
                contentMode: .fit
            )

        let size = element.sizeThatFits(CGSize(width: 100, height: 100))

        #expect(probe.proposals == [CGSize(width: 100, height: 50)])
        #expect(size == CGSize(width: 100, height: 50))
    }

    @Test func scaledToFitPreservesElementsIdealAspectRatio() {
        let probe = AspectRatioProposalProbe(
            idealSize: CGSize(width: 200, height: 100)
        )
        let element = AspectRatioProposalElement(probe: probe).scaledToFit()

        let size = element.sizeThatFits(CGSize(width: 100, height: 100))

        #expect(
            probe.proposals
                == [
                    CGSize(
                        width: CGFloat.infinity,
                        height: CGFloat.infinity
                    ),
                    CGSize(width: 100, height: 50),
                ]
        )
        #expect(size == CGSize(width: 100, height: 50))
    }

    @Test func scaledToFillPreservesElementsIdealAspectRatio() {
        let probe = AspectRatioProposalProbe(
            idealSize: CGSize(width: 200, height: 100)
        )
        let element = AspectRatioProposalElement(probe: probe).scaledToFill()

        let size = element.sizeThatFits(CGSize(width: 100, height: 100))

        #expect(
            probe.proposals
                == [
                    CGSize(
                        width: CGFloat.infinity,
                        height: CGFloat.infinity
                    ),
                    CGSize(width: 200, height: 100),
                ]
        )
        #expect(size == CGSize(width: 200, height: 100))
    }

    @MainActor
    @Test func layoutAlgorithmMeasuresAndPlacesSubviewsUsingAnchors() {
        let first = IntrinsicTestView(size: CGSize(width: 20, height: 10))
        let second = IntrinsicTestView(size: CGSize(width: 30, height: 16))
        let layout = CenteredOverlayLayout() {
            first
            second
        }

        layout.applyFrame(
            CGRect(x: 0, y: 0, width: 100, height: 80),
            alignment: .topLeading
        )

        #expect(first.frame == CGRect(x: 40, y: 35, width: 20, height: 10))
        #expect(second.frame == CGRect(x: 35, y: 32, width: 30, height: 16))
    }

    @MainActor
    @Test func layoutValueKeyReturnsDefaultsAndGuidesCustomLayout() {
        let first = IntrinsicTestView(size: CGSize(width: 20, height: 10))
        let second = IntrinsicTestView(size: CGSize(width: 30, height: 16))
        let layout = RankedRowLayout(spacing: 5) {
            first.layoutValue(key: LayoutOrderKey.self, value: 2)
            second
        }

        layout.applyFrame(
            CGRect(x: 0, y: 0, width: 55, height: 16),
            alignment: .topLeading
        )

        #expect(second.frame == CGRect(x: 0, y: 0, width: 30, height: 16))
        #expect(first.frame == CGRect(x: 35, y: 0, width: 20, height: 10))
    }

    @Test func layoutAlgorithmCreatesAndUpdatesItsCache() {
        let probe = LayoutCacheProbe()
        let layout = CacheProbeLayout(probe: probe) {
            IntrinsicTestElement(size: CGSize(width: 20, height: 10))
        }

        _ = layout.sizeThatFits(CGSize(width: 100, height: 80))
        _ = layout.sizeThatFits(CGSize(width: 120, height: 90))

        #expect(probe.makeCount == 1)
        #expect(probe.updateCount == 1)
    }

    @MainActor
    @Test func positionUsesPhysicalCoordinatesInBothLayoutDirections() {
        let leftToRightView = IntrinsicTestView(
            size: CGSize(width: 20, height: 10)
        )
        let rightToLeftView = IntrinsicTestView(
            size: CGSize(width: 20, height: 10)
        )
        let frame = CGRect(x: 0, y: 0, width: 100, height: 80)

        leftToRightView.position(x: 70, y: 30).applyFrame(
            frame,
            alignment: .topLeading,
            layoutDirection: .leftToRight
        )
        rightToLeftView.position(CGPoint(x: 70, y: 30)).applyFrame(
            frame,
            alignment: .topLeading,
            layoutDirection: .rightToLeft
        )

        let expectedFrame = CGRect(x: 60, y: 25, width: 20, height: 10)
        #expect(leftToRightView.frame == expectedFrame)
        #expect(rightToLeftView.frame == expectedFrame)
    }

    @MainActor
    @Test func explicitAlignmentGuidesDoNotMovePhysicalPlacements() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 80)

        let directionPairs: [(
            outer: LayoutDirection,
            local: LayoutDirection
        )] = [
            (.leftToRight, .leftToRight),
            (.rightToLeft, .rightToLeft),
            (.leftToRight, .rightToLeft),
            (.rightToLeft, .leftToRight),
        ]

        for directionPair in directionPairs {
            let positionedView = IntrinsicTestView(
                size: CGSize(width: 20, height: 10)
            )
            positionedView
                .alignmentGuide(.leading) { _ in 7 }
                .alignmentGuide(.top) { _ in 3 }
                .position(x: 70, y: 30)
                .layoutDirection(directionPair.local)
                .applyFrame(
                    frame,
                    alignment: .topLeading,
                    layoutDirection: directionPair.outer
                )

            #expect(
                positionedView.frame
                    == CGRect(x: 60, y: 25, width: 20, height: 10)
            )

            let customLayoutView = IntrinsicTestView(
                size: CGSize(width: 20, height: 10)
            )
            let layout = CenteredOverlayLayout {
                customLayoutView
                    .alignmentGuide(.leading) { _ in 7 }
                    .alignmentGuide(.top) { _ in 3 }
            }
            layout
                .layoutDirection(directionPair.local)
                .applyFrame(
                    frame,
                    alignment: .topLeading,
                    layoutDirection: directionPair.outer
                )

            #expect(
                customLayoutView.frame
                    == CGRect(x: 40, y: 35, width: 20, height: 10)
            )
        }
    }

    @MainActor
    @Test func zIndexControlsLayerAndCustomLayoutOrdering() {
        let high = IntrinsicTestView(size: CGSize(width: 20, height: 20))
        let low = IntrinsicTestView(size: CGSize(width: 20, height: 20))
        let sanitized = IntrinsicTestView(size: CGSize(width: 20, height: 20))
        let layout = CenteredOverlayLayout() {
            high.zIndex(10)
            low.zIndex(-2)
            sanitized.zIndex(.nan)
        }

        let views = layout.views()

        #expect(views == [low, sanitized, high])
        #expect(low.layer.zPosition == -2)
        #expect(sanitized.layer.zPosition == 0)
        #expect(high.layer.zPosition == 10)
    }

    @MainActor
    @Test func hostedZIndexRestoresOriginalLayerStateAcrossBodyChanges() {
        let host = ZIndexLifecycleQuickLayoutView()
        host.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        host.child.layer.zPosition = 3

        host.zIndexMode = .single(10)
        host.layoutIfNeeded()
        #expect(host.child.layer.zPosition == 10)

        host.zIndexMode = .none
        host.setNeedsQuickLayout()
        host.layoutIfNeeded()
        #expect(host.child.layer.zPosition == 3)

        host.zIndexMode = .nested(inner: -2, outer: 7)
        host.setNeedsQuickLayout()
        host.layoutIfNeeded()
        #expect(host.child.layer.zPosition == 7)

        host.zIndexMode = .none
        host.setNeedsQuickLayout()
        host.layoutIfNeeded()
        #expect(host.child.layer.zPosition == 3)
    }

    @MainActor
    @Test func hostedZIndexOwnershipTransfersWithoutLeakingItsOldValue() {
        let child = UIView()
        child.layer.zPosition = 4
        var firstHostIncludesChild = true
        let firstHost = QuickLayoutView {
            if firstHostIncludesChild {
                child.frame(width: 20, height: 10).zIndex(12)
            }
        }
        firstHost.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        firstHost.layoutIfNeeded()
        #expect(child.layer.zPosition == 12)

        let secondHost = QuickLayoutView {
            child.frame(width: 20, height: 10).zIndex(-5)
        }
        secondHost.frame = firstHost.frame
        secondHost.layoutIfNeeded()

        #expect(child.superview === secondHost)
        #expect(child.layer.zPosition == -5)

        // The old host no longer owns the view and must not overwrite the new
        // host's managed value during a later pass.
        firstHostIncludesChild = false
        firstHost.setNeedsQuickLayout()
        firstHost.layoutIfNeeded()
        #expect(child.layer.zPosition == -5)
    }

    @MainActor
    @Test func scrollHostRestoresManagedZIndexWhenModifierIsRemoved() {
        let child = UIView()
        child.layer.zPosition = 6
        let scrollView = QuickLayoutScrollView(.vertical)
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        _ = ScrollView(scrollView, .vertical) {
            child.frame(width: 20, height: 20).zIndex(11)
        }
        scrollView.layoutIfNeeded()
        #expect(child.layer.zPosition == 11)

        _ = ScrollView(scrollView, .vertical) {
            child.frame(width: 20, height: 20)
        }
        scrollView.setNeedsQuickLayout()
        scrollView.layoutIfNeeded()
        #expect(child.layer.zPosition == 6)
    }

    @MainActor
    @Test func reusableCellSizingRestoresManagedZIndexBetweenPasses() {
        let child = IntrinsicTestView(size: CGSize(width: 20, height: 20))
        child.layer.zPosition = 8
        var appliesZIndex = true
        let cell = QuickLayoutCollectionViewCell {
            if appliesZIndex {
                child.zIndex(14)
            } else {
                child
            }
        }

        _ = cell.sizeThatFits(CGSize(width: 100, height: 40))
        #expect(child.layer.zPosition == 14)

        appliesZIndex = false
        _ = cell.sizeThatFits(CGSize(width: 100, height: 40))
        #expect(child.layer.zPosition == 8)
    }

    @MainActor
    @Test func swiftUIInspiredOptionalAPISurfaceCompiles() {
        let content = UIView()
        let scrollView = QuickLayoutScrollView(.vertical)

        _ = content.safeAreaPadding()
        _ = content.safeAreaPadding(.horizontal, nil)
        _ = content.safeAreaPadding(.all, 0)
        _ = content.safeAreaPadding(
            EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        )
        _ = content.safeAreaInset(edge: .bottom, spacing: nil) {
            UIView()
        }
        _ = ScrollView(scrollView, .vertical) { content }
            .contentMargins(.horizontal, nil, for: .scrollContent)
        _ = content.frame(
            minWidth: nil,
            idealWidth: nil,
            maxWidth: .infinity,
            minHeight: nil,
            idealHeight: nil,
            maxHeight: nil
        )
        _ = ProposedSize(width: nil, height: nil)
    }
}

@MainActor
private final class DirectionRecordingQuickLayoutView: QuickLayoutView {

    let child = UIView()
    private(set) var environmentChangeReasons: [
        QuickLayoutEnvironmentChangeReason
    ] = []

    @LayoutBuilder
    override var body: Layout {
        child
            .frame(width: 20, height: 10)
            .frame(width: 88, height: 40, alignment: .topLeading)
            .padding(.leading, 12)
    }

    override func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        environmentChangeReasons.append(reason)
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
    }
}

@MainActor
private final class ZIndexLifecycleQuickLayoutView: QuickLayoutView {

    enum Mode {
        case none
        case single(Double)
        case nested(inner: Double, outer: Double)
    }

    let child = UIView()
    var zIndexMode: Mode = .none

    @LayoutBuilder
    override var body: Layout {
        switch zIndexMode {
        case .none:
            child.frame(width: 20, height: 10)
        case .single(let value):
            child.frame(width: 20, height: 10).zIndex(value)
        case .nested(let inner, let outer):
            child
                .frame(width: 20, height: 10)
                .zIndex(inner)
                .zIndex(outer)
        }
    }
}

private struct ConfigurationProbe: UIContentConfiguration, Equatable {

    let value: String

    func makeContentView() -> UIView & UIContentView {
        ConfigurationProbeContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        self
    }
}

@MainActor
private final class ConfigurationProbeContentView:
    QuickLayoutContentView {

    let label = UILabel()
    private(set) var appliedValues: [String] = []
    private(set) var appliedDirections: [
        UIUserInterfaceLayoutDirection
    ] = []
    private(set) var environmentChangeReasons: [
        QuickLayoutEnvironmentChangeReason
    ] = []

    @LayoutBuilder
    override var body: Layout {
        label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
    }

    init(configuration: ConfigurationProbe) {
        super.init(configuration: configuration)
        applyCurrentContentConfiguration()
    }

    override func applyContentConfiguration(
        _ configuration: UIContentConfiguration
    ) {
        guard let configuration = configuration as? ConfigurationProbe else {
            assertionFailure(
                "Unexpected content configuration: \(type(of: configuration))"
            )
            return
        }
        appliedValues.append(configuration.value)
        appliedDirections.append(effectiveUserInterfaceLayoutDirection)
        label.text = configuration.value
        super.applyContentConfiguration(configuration)
    }

    override func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        environmentChangeReasons.append(reason)
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
    }
}

@MainActor
private final class DirectionRecordingQuickLayoutScrollView:
    QuickLayoutScrollView {

    private(set) var environmentChangeReasons: [
        QuickLayoutEnvironmentChangeReason
    ] = []

    override func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        environmentChangeReasons.append(reason)
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
    }
}

@MainActor
private final class EnvironmentRecordingCollectionViewCell:
    QuickLayoutCollectionViewCell {

    private(set) var environmentChangeReasons: [
        QuickLayoutEnvironmentChangeReason
    ] = []

    override func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        environmentChangeReasons.append(reason)
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
    }
}

@MainActor
private final class EnvironmentRecordingTableViewCell:
    QuickLayoutTableViewCell {

    private(set) var environmentChangeReasons: [
        QuickLayoutEnvironmentChangeReason
    ] = []

    override func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        environmentChangeReasons.append(reason)
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
    }
}

@MainActor
private final class EnvironmentRecordingTableHeaderFooterView:
    QuickLayoutTableViewHeaderFooterView {

    private(set) var environmentChangeReasons: [
        QuickLayoutEnvironmentChangeReason
    ] = []

    override func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        environmentChangeReasons.append(reason)
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
    }
}

@MainActor
private final class EnvironmentRecordingCollectionReusableView:
    QuickLayoutCollectionReusableView {

    private(set) var environmentChangeReasons: [
        QuickLayoutEnvironmentChangeReason
    ] = []

    override func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        environmentChangeReasons.append(reason)
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
    }
}

@MainActor
private final class DirectionProbeTableViewCell: QuickLayoutTableViewCell {

    let directionView = UIView()

    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [directionView]
    }

    @LayoutBuilder
    override var body: Layout {
        directionView.frame(width: 20, height: 10)
    }
}

@MainActor
private final class DirectionProbeTableHeaderFooterView:
    QuickLayoutTableViewHeaderFooterView {

    let directionView = UIView()

    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [directionView]
    }

    @LayoutBuilder
    override var body: Layout {
        directionView.frame(width: 20, height: 10)
    }
}

@MainActor
private final class DirectionPairTableViewCell: QuickLayoutTableViewCell {

    let first = UIView()
    let second = UIView()

    @LayoutBuilder
    override var body: Layout {
        HStack {
            first.frame(width: 20, height: 10)
            second.frame(width: 20, height: 10)
        }
    }
}

@MainActor
private final class DirectionPairTableHeaderFooterView:
    QuickLayoutTableViewHeaderFooterView {

    let first = UIView()
    let second = UIView()

    @LayoutBuilder
    override var body: Layout {
        HStack {
            first.frame(width: 20, height: 10)
            second.frame(width: 20, height: 10)
        }
    }
}

@MainActor
private final class DirectionPairCollectionViewCell:
    QuickLayoutCollectionViewCell {

    let first = UIView()
    let second = UIView()

    @LayoutBuilder
    override var body: Layout {
        HStack {
            first.frame(width: 20, height: 10)
            second.frame(width: 20, height: 10)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class DirectionPairCollectionReusableView:
    QuickLayoutCollectionReusableView {

    let first = UIView()
    let second = UIView()

    @LayoutBuilder
    override var body: Layout {
        HStack {
            first.frame(width: 20, height: 10)
            second.frame(width: 20, height: 10)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class DirectionPairCollectionDataSource:
    NSObject,
    UICollectionViewDataSource {

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        1
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(
            withReuseIdentifier: "cell",
            for: indexPath
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: "header",
            for: indexPath
        )
    }
}

@MainActor
private final class DirectionProbeViewController: UIViewController {

    let directionView = EffectiveDirectionProbeView()

    override func loadView() {
        view = directionView
    }
}

@MainActor
private final class EffectiveDirectionProbeView: UIView {

    let first = UIView()
    let second = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(first)
        addSubview(second)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = CGSize(width: 20, height: 10)
        let spacing: CGFloat = 8
        let leadingX: CGFloat = 8
        let trailingX = bounds.width - leadingX - size.width
        let y = (bounds.height - size.height) / 2

        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            first.frame = CGRect(origin: CGPoint(x: trailingX, y: y), size: size)
            second.frame = CGRect(
                origin: CGPoint(
                    x: trailingX - spacing - size.width,
                    y: y
                ),
                size: size
            )
        } else {
            first.frame = CGRect(origin: CGPoint(x: leadingX, y: y), size: size)
            second.frame = CGRect(
                origin: CGPoint(
                    x: leadingX + size.width + spacing,
                    y: y
                ),
                size: size
            )
        }
    }
}

@MainActor
private final class SafeAreaProbeView: UIView {

    private let reportedSafeAreaInsets: UIEdgeInsets

    init(safeAreaInsets: UIEdgeInsets) {
        reportedSafeAreaInsets = safeAreaInsets
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var safeAreaInsets: UIEdgeInsets {
        reportedSafeAreaInsets
    }
}

@MainActor
private class KeyboardSafeAreaProbeQuickLayoutView: QuickLayoutView {

    private let fillView = UIView()
    let containerSafeAreaView = UIView()
    let keyboardSafeAreaView = UIView()
    private let reportedSafeAreaInsets: UIEdgeInsets

    init(safeAreaInsets: UIEdgeInsets) {
        reportedSafeAreaInsets = safeAreaInsets
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var safeAreaInsets: UIEdgeInsets {
        reportedSafeAreaInsets
    }

    override var body: Layout {
        ZStack(alignment: .bottom) {
            fillView.resizable()
            containerSafeAreaView
                .frame(width: 20, height: 20)
                .safeAreaPadding(.bottom, 0)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            keyboardSafeAreaView
                .frame(width: 20, height: 20)
                .safeAreaPadding(.bottom, 0)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class AdjustedContentInsetQuickLayoutScrollView:
    QuickLayoutScrollView {

    private var reportedSafeAreaInsets: UIEdgeInsets

    init(safeAreaInsets: UIEdgeInsets) {
        reportedSafeAreaInsets = safeAreaInsets
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var safeAreaInsets: UIEdgeInsets {
        reportedSafeAreaInsets
    }

    override var adjustedContentInset: UIEdgeInsets {
        UIEdgeInsets(
            top: contentInset.top + reportedSafeAreaInsets.top,
            left: contentInset.left + reportedSafeAreaInsets.left,
            bottom: contentInset.bottom + reportedSafeAreaInsets.bottom,
            right: contentInset.right + reportedSafeAreaInsets.right
        )
    }

    func updateSafeAreaInsets(_ insets: UIEdgeInsets) {
        reportedSafeAreaInsets = insets
        safeAreaInsetsDidChange()
    }
}

@MainActor
private final class SafeAreaContentMarginQuickLayoutScrollView:
    QuickLayoutScrollView {

    private var reportedSafeAreaInsets: UIEdgeInsets

    init(safeAreaInsets: UIEdgeInsets) {
        reportedSafeAreaInsets = safeAreaInsets
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var safeAreaInsets: UIEdgeInsets {
        reportedSafeAreaInsets
    }

    func updateSafeAreaInsets(_ insets: UIEdgeInsets) {
        reportedSafeAreaInsets = insets
        safeAreaInsetsDidChange()
    }
}

@MainActor
private final class CollectionCellBodyProbe: QuickLayoutCollectionViewCell {

    let bodyView = IntrinsicTestView(
        size: CGSize(width: 180, height: 37)
    )

    @LayoutBuilder
    override var body: Layout {
        bodyView
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private func withSafeArea<Result>(
    containerSize: CGSize,
    containerInsets: EdgeInsets,
    keyboardInsets: EdgeInsets = .zero,
    operation: () throws -> Result
) rethrows -> Result {
    try QuickLayoutSafeAreaContext.withValues(
        QuickLayoutSafeAreaValues(
            containerSize: containerSize,
            containerInsets: containerInsets,
            keyboardInsets: keyboardInsets
        ),
        operation: operation
    )
}

private func withPhysicalSafeArea<Result>(
    containerSize: CGSize,
    containerInsets: UIEdgeInsets,
    keyboardInsets: UIEdgeInsets = .zero,
    operation: () throws -> Result
) rethrows -> Result {
    try QuickLayoutSafeAreaContext.withValues(
        QuickLayoutSafeAreaValues(
            containerSize: containerSize,
            physicalContainerInsets: containerInsets,
            physicalKeyboardInsets: keyboardInsets
        ),
        operation: operation
    )
}

private struct IntrinsicTestElement: Layout {

    let size: CGSize

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        LayoutNode(view: nil, dimensions: ElementDimensions(size))
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        .fixedSize
    }

    func quick_layoutPriority() -> CGFloat {
        0
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private final class FlexibleFrameProposalProbe {
    var proposals: [CGSize] = []
}

private struct FlexibleFrameProposalElement: Layout {

    let probe: FlexibleFrameProposalProbe

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        probe.proposals.append(proposedSize)
        return LayoutNode(
            view: nil,
            dimensions: ElementDimensions(proposedSize)
        )
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        .fullyFlexible
    }

    func quick_layoutPriority() -> CGFloat {
        0
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private final class AspectRatioProposalProbe {
    let idealSize: CGSize
    var proposals: [CGSize] = []

    init(idealSize: CGSize) {
        self.idealSize = idealSize
    }
}

private struct AspectRatioProposalElement: Layout {

    let probe: AspectRatioProposalProbe

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        probe.proposals.append(proposedSize)
        let size = proposedSize.width.isFinite && proposedSize.height.isFinite
            ? proposedSize
            : probe.idealSize
        return LayoutNode(view: nil, dimensions: ElementDimensions(size))
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        .fullyFlexible
    }

    func quick_layoutPriority() -> CGFloat {
        0
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private struct GeometrySnapshot: Equatable, Sendable {
    let size: CGSize
    let localFrame: CGRect
}

private enum LayoutOrderKey: LayoutValueKey {
    static let defaultValue = 0
}

private struct CenteredOverlayLayout: LayoutAlgorithm {

    func sizeThatFits(
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for subview in subviews {
            subview.place(
                at: center,
                anchor: UnitPoint(x: 0.5, y: 0.5),
                proposal: .unspecified
            )
        }
    }
}

private struct RankedRowLayout: LayoutAlgorithm {

    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(
            width: sizes.reduce(0) { $0 + $1.width }
                + spacing * CGFloat(max(0, sizes.count - 1)),
            height: sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let orderedIndices = subviews.indices.sorted {
            subviews[$0][LayoutOrderKey.self]
                < subviews[$1][LayoutOrderKey.self]
        }
        var x = bounds.minX

        for index in orderedIndices {
            let size = subviews[index].sizeThatFits(.unspecified)
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedSize(size)
            )
            x += size.width + spacing
        }
    }
}

private final class LayoutCacheProbe {
    var makeCount = 0
    var updateCount = 0
}

private struct CacheProbeLayout: LayoutAlgorithm {

    struct Cache {}

    let probe: LayoutCacheProbe

    func makeCache(subviews: Subviews) -> Cache {
        probe.makeCount += 1
        return Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        probe.updateCount += 1
    }

    func sizeThatFits(
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        subviews.first?.sizeThatFits(.unspecified) ?? .zero
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        for subview in subviews {
            subview.place(at: bounds.origin)
        }
    }
}

@MainActor
private func applyTestLayoutDirection(
    _ direction: UIUserInterfaceLayoutDirection,
    container: UIView,
    hosts: [UIView]
) {
    let attribute: UISemanticContentAttribute = direction == .rightToLeft
        ? .forceRightToLeft
        : .forceLeftToRight
    container.semanticContentAttribute = attribute
    container.setNeedsLayout()

    for host in hosts {
        host.semanticContentAttribute = attribute
        if let updating = host as? QuickLayoutUpdating {
            updating.setNeedsQuickLayout()
        } else {
            host.setNeedsLayout()
        }
    }
}

@MainActor
private func addToReusableBoundary(
    _ view: UIView,
    boundary: UIView
) {
    switch boundary {
    case let cell as UITableViewCell:
        cell.contentView.addSubview(view)
    case let headerFooter as UITableViewHeaderFooterView:
        headerFooter.contentView.addSubview(view)
    default:
        boundary.addSubview(view)
    }
}

@MainActor
private final class TableHeaderFooterDataSource:
    NSObject,
    UITableViewDataSource,
    UITableViewDelegate {

    let header: UITableViewHeaderFooterView
    let cell: UITableViewCell?

    init(
        header: UITableViewHeaderFooterView,
        cell: UITableViewCell? = nil
    ) {
        self.header = header
        self.cell = cell
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        1
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        cell ?? UITableViewCell(style: .default, reuseIdentifier: nil)
    }

    func tableView(
        _ tableView: UITableView,
        viewForHeaderInSection section: Int
    ) -> UIView? {
        header
    }

    func tableView(
        _ tableView: UITableView,
        heightForHeaderInSection section: Int
    ) -> CGFloat {
        60
    }
}

@MainActor
private final class QuickLayoutButtonBodyProbe: QuickLayoutButton {

    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.text = "Subclass label"
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        titleLabel.text = "Subclass label"
    }

    override var body: Layout {
        titleLabel
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }
}

private final class IntrinsicTestView: UIView {

    let idealSize: CGSize

    init(size: CGSize) {
        idealSize = size
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        idealSize
    }
}
