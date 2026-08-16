import Testing
import QuickLayout
import UIKit
@testable import QuickLayoutKitCore
@testable import QuickLayoutKitUIKit

@Suite
struct QuickLayoutKitTests {

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
        let scrollView = QuickLayoutScrollView(.horizontal) {
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

        scrollView.semanticContentAttribute = .forceRightToLeft
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
        hostingView.layoutIfNeeded()

        #expect(
            hostingView.environmentChangeReasons.last?
                .contains(.layoutDirection) == true
        )
        #expect(
            hostingView.environmentChangeReasons.count
                == layoutChangeCount + 1
        )
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
        #expect(scrollView.horizontalScrollIndicatorInsets == expected)
    }

    @MainActor
    @Test func automaticContentMarginsApplyToContentAndIndicators() {
        let scrollView = QuickLayoutScrollView(.vertical)

        _ = ScrollView(scrollView, .vertical) {}
            .contentMargins(10)

        let expected = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        #expect(scrollView.contentInset == expected)
        #expect(scrollView.verticalScrollIndicatorInsets == expected)
        #expect(scrollView.horizontalScrollIndicatorInsets == expected)
    }

    @MainActor
    @Test func specificContentMarginPlacementOverridesAutomaticPerEdge() {
        let scrollView = QuickLayoutScrollView(.horizontal)

        _ = ScrollView(scrollView, .horizontal) {}
            .contentMargins(.horizontal, 20)
            .contentMargins(.leading, 8, for: .scrollContent)

        #expect(scrollView.contentInset.left == 8)
        #expect(scrollView.contentInset.right == 20)
        #expect(scrollView.horizontalScrollIndicatorInsets.left == 20)
        #expect(scrollView.horizontalScrollIndicatorInsets.right == 20)
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

    @Test func safeAreaPaddingUsesDefaultSpacing() {
        let element = IntrinsicTestElement(size: CGSize(width: 20, height: 30))
            .safeAreaPadding()

        #expect(
            element.sizeThatFits(CGSize(width: 200, height: 100))
                == CGSize(width: 52, height: 62)
        )
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

    @Test func flexibleFramePrefersFiniteProposalOverIdealSize() {
        let probe = FlexibleFrameProposalProbe()
        let element = FlexibleFrameProposalElement(probe: probe)
            .frame(idealWidth: 80, idealHeight: 40)

        let size = element.sizeThatFits(CGSize(width: 60, height: 30))

        #expect(probe.proposals == [CGSize(width: 60, height: 30)])
        #expect(size == CGSize(width: 60, height: 30))
    }

    @Test func flexibleFrameClampsIdealSizeToMinimumAndMaximum() {
        let probe = FlexibleFrameProposalProbe()
        let element = FlexibleFrameProposalElement(probe: probe)
            .frame(
                minWidth: 50,
                idealWidth: 80,
                maxWidth: 70,
                minHeight: 20,
                idealHeight: 10,
                maxHeight: 60
            )

        let size = element.sizeThatFits(
            CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
        )

        #expect(probe.proposals == [CGSize(width: 70, height: 20)])
        #expect(size == CGSize(width: 70, height: 20))
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
        let layout = CenteredOverlayLayout() {
            high.zIndex(10)
            low.zIndex(-2)
        }

        let views = layout.views()

        #expect(views == [low, high])
        #expect(low.layer.zPosition == -2)
        #expect(high.layer.zPosition == 10)
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
