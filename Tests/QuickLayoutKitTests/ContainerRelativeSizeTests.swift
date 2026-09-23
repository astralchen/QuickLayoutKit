import QuickLayout
@testable import QuickLayoutKitCore
import QuickLayoutKitUIKit
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct ContainerRelativeSizeTests {
    private let proposal = CGSize(width: 400, height: 600)

    @Test(arguments: [Axis.horizontal, .vertical])
    func peerScopesShareMainAxisSpace(axis: Axis) {
        let axes: AxisSet = axis == .horizontal ? .horizontal : .vertical
        for style in 0..<3 {
            func scoped() -> Element & Layout {
                switch style {
                case 0:
                    return ContainerRelativeSize(axes) { LimitProbe().containerRelativeSize(axes) }
                case 1:
                    return ContainerRelativeSize(axes, length: { length, _ in length / 2 }) {
                        LimitProbe().containerRelativeSize(axes)
                    }
                default:
                    return ContainerRelativeSize(axes, maxSize: { size in
                        CGSize(width: size.width / 2, height: size.height / 2)
                    }) { LimitProbe().containerRelativeSize(axes) }
                }
            }
            let node = stack(axis, scoped(), scoped())
                .quick_layoutThatFits(CGSize(width: 400, height: 400))
            #expect(mainLengths(node, axis: axis) == [200, 200], "Scope style: \(style)")
        }
    }

    @Test(arguments: [Axis.horizontal, .vertical], [false, true])
    func scopeHonorsSiblingPriorityInEitherOrder(axis: Axis, reversed: Bool) {
        let axes: AxisSet = axis == .horizontal ? .horizontal : .vertical
        let low = ContainerRelativeSize(axes) { LimitProbe().containerRelativeSize(axes) }
            .layoutPriority(-1)
        let high = LimitProbe().containerRelativeSize(axes).layoutPriority(1)
        let node = stack(axis, reversed ? high : low, reversed ? low : high)
            .quick_layoutThatFits(CGSize(width: 400, height: 400))
        #expect(mainLengths(node, axis: axis) == (reversed ? [400, 0] : [0, 400]))
    }

    @Test func allScopeOverloadsPreserveIndependentAxisFlexibility() {
        let selections: [AxisSet] = [.horizontal, .vertical, [.horizontal, .vertical], []]
        let flexibilities: [Flexibility] = [.fixedSize, .partial, .fullyFlexible]
        for axes in selections {
            for horizontal in flexibilities {
                for vertical in flexibilities {
                    let child = LimitProbe(horizontalFlexibility: horizontal, verticalFlexibility: vertical)
                    let basic = ContainerRelativeSize(axes) { child }
                    let length = ContainerRelativeSize(axes, length: { length, _ in length / 2 }) { child }
                    let size = ContainerRelativeSize(axes, maxSize: { $0 }) { child }
                    for scope in [basic, length, size] {
                        #expect(scope.quick_flexibility(for: .horizontal) == horizontal)
                        #expect(scope.quick_flexibility(for: .vertical) == vertical)
                        #expect(scope.quick_layoutPriority() == child.quick_layoutPriority())
                    }
                }
            }
        }
    }

    @Test(arguments: [Axis.horizontal, .vertical])
    func scopeLeavesUnmarkedAndFixedContentSizingIntact(axis: Axis) {
        let axes: AxisSet = axis == .horizontal ? .horizontal : .vertical
        let unmarked = ContainerRelativeSize(axes, length: { _, _ in 10 }) { LimitProbe() }
        let bare = LimitProbe()
        let proposed = CGSize(width: 400, height: 400)
        let scoped = stack(axis, unmarked, unmarked).quick_layoutThatFits(proposed)
        let baseline = stack(axis, bare, bare).quick_layoutThatFits(proposed)
        #expect(mainLengths(scoped, axis: axis) == mainLengths(baseline, axis: axis))
        #expect(mainLengths(scoped, axis: axis) == [200, 200])

        let fixed = ContainerRelativeSize(axes, length: { _, _ in 10 }) {
            LimitProbe().frame(width: 80, height: 80).containerRelativeSize(axes)
        }
        let fixedNode = stack(axis, fixed, bare).quick_layoutThatFits(proposed)
        #expect(mainLengths(fixedNode, axis: axis) == [80, 320])
        let unmarkedFixed = ContainerRelativeSize(axes) { bare.frame(width: 80, height: 80) }
        #expect(unmarkedFixed.quick_flexibility(for: axis) == .fixedSize)
        #expect(unmarkedFixed.quick_layoutThatFits(proposed).size == CGSize(width: 80, height: 80))
    }

    @Test(arguments: [Axis.horizontal, .vertical])
    func stackRemeasureRecalculatesLimitUsingNewProposal(axis: Axis) {
        let axes: AxisSet = axis == .horizontal ? .horizontal : .vertical
        for useFullSize in [false, true] {
            let calls = LimitInvocationRecorder()
            let child = LimitProbe().containerRelativeSize(axes)
            let scope: any Layout
            if useFullSize {
                scope = ContainerRelativeSize(axes, maxSize: { size in
                    calls.record(size)
                    return CGSize(width: size.width * 0.75, height: size.height * 0.75)
                }) { child }
            } else {
                scope = ContainerRelativeSize(axes, length: { length, axis in
                    calls.record(length, axis: axis)
                    return length * 0.75
                }) { child }
            }
            let sibling = LimitProbe(idealSize: CGSize(width: 200, height: 200)).containerRelativeSize(axes)
            let node = stack(axis, scope, sibling).quick_layoutThatFits(CGSize(width: 400, height: 400))
            #expect(mainLengths(node, axis: axis) == [150, 200])
            let references = useFullSize
                ? calls.sizes.map { axis == .horizontal ? $0.width : $0.height }
                : calls.lengths.map(\.length)
            #expect(references == [400, 200])
        }
    }

    private func stack(_ axis: Axis, _ first: Element, _ second: Element) -> Element & Layout {
        if axis == .horizontal {
            return HStack(spacing: 0) { first; second }
        }
        return VStack(spacing: 0) { first; second }
    }

    private func mainLengths(_ node: LayoutNode, axis: Axis) -> [CGFloat] {
        node.children.map { axis == .horizontal ? $0.layout.size.width : $0.layout.size.height }
    }

    @Test func allOverloadsRespectSelectedAxesAndKeepShortContentSmall() {
        let cases: [(AxisSet, CGSize)] = [
            (.horizontal, CGSize(width: 200, height: 600)),
            (.vertical, CGSize(width: 400, height: 300)),
            ([.horizontal, .vertical], CGSize(width: 200, height: 300)),
            ([], proposal),
        ]
        for (axes, expected) in cases {
            let builder = ContainerRelativeSize(axes) { LimitProbe().containerRelativeSize() }
            let basic = LimitProbe().containerRelativeSize(axes)
            #expect(builder.quick_layoutThatFits(proposal).size == proposal)
            #expect(basic.quick_layoutThatFits(proposal).size == proposal)
            let lengthBuilder = ContainerRelativeSize(axes, length: { length, _ in length / 2 }) {
                LimitProbe().containerRelativeSize()
            }
            let sizeBuilder = ContainerRelativeSize(axes, maxSize: { size in
                CGSize(width: size.width / 2, height: size.height / 2)
            }) { LimitProbe().containerRelativeSize() }
            let lengthModifier = LimitProbe().containerRelativeSize(axes) { length, _ in length / 2 }
            let sizeModifier = LimitProbe().containerRelativeSize(axes, maxSize: { size in
                CGSize(width: size.width / 2, height: size.height / 2)
            })
            for element in [lengthBuilder, sizeBuilder, lengthModifier, sizeModifier] {
                #expect(element.quick_layoutThatFits(proposal).size == expected)
            }
        }
        let small = ContainerRelativeSize([.horizontal, .vertical]) {
            LimitProbe(idealSize: CGSize(width: 50, height: 20)).containerRelativeSize()
        }
        #expect(small.quick_layoutThatFits(proposal).size == CGSize(width: 50, height: 20))
    }

    @Test func calculationsRunOncePerMeasurementAndUseCurrentContainerDimensions() {
        let lengthCalls = LimitInvocationRecorder()
        let sizeCalls = LimitInvocationRecorder()
        let builder = ContainerRelativeSize([.horizontal, .vertical], maxSize: { size in
            sizeCalls.record(size)
            return size
        }) {
            LimitProbe().containerRelativeSize([.horizontal, .vertical]) { length, axis in
                lengthCalls.record(length, axis: axis)
                return length / 2
            }
        }
        let resized = CGSize(width: 800, height: 200)
        #expect(builder.quick_layoutThatFits(proposal).size == CGSize(width: 200, height: 300))
        #expect(builder.quick_layoutThatFits(resized).size == CGSize(width: 400, height: 100))
        #expect(sizeCalls.sizes == [proposal, resized])
        #expect(lengthCalls.lengths.map(\.length) == [400, 600, 800, 200])
        #expect(lengthCalls.lengths.map(\.axis) == [.horizontal, .vertical, .horizontal, .vertical])

        let outerCalls = LimitInvocationRecorder()
        let innerCalls = LimitInvocationRecorder()
        let reversed = ContainerRelativeSize(.horizontal, length: { length, axis in
            outerCalls.record(length, axis: axis)
            return length
        }) {
            LimitProbe().containerRelativeSize(.vertical, maxSize: { size in
                innerCalls.record(size)
                return CGSize(width: 0, height: size.width / 2)
            })
        }
        #expect(reversed.quick_layoutThatFits(proposal).size == CGSize(width: 400, height: 200))
        #expect(outerCalls.lengths.count == 1)
        #expect(outerCalls.lengths.first?.axis == .horizontal)
        #expect(innerCalls.sizes == [proposal])
    }

    @Test func crossAxisCalculationSupportsUnboundedInputAndIgnoresUnselectedResult() {
        let builder = ContainerRelativeSize(.vertical, maxSize: { size in
            CGSize(width: 0, height: min(240, size.width * 9 / 16))
        }) { LimitProbe().containerRelativeSize() }
        let modifier = LimitProbe().containerRelativeSize(.vertical, maxSize: { size in
            CGSize(width: 0, height: min(240, size.width * 9 / 16))
        })
        for element in [builder, modifier] {
            #expect(element.quick_layoutThatFits(proposal).size == CGSize(width: 400, height: 225))
            #expect(element.quick_layoutThatFits(CGSize(width: 800, height: 100)).size == CGSize(width: 800, height: 100))
            #expect(element.quick_layoutThatFits(CGSize(width: CGFloat.infinity, height: CGFloat.infinity)).size
                == CGSize(width: CGFloat.infinity, height: 240))
        }
    }

    @Test func customModifierUsesRawReferenceButCannotExceedScopeOrParent() {
        for width: CGFloat in [100, 300] {
            let calls = LimitInvocationRecorder()
            let recorder = LimitProposalRecorder()
            let layout = ContainerRelativeSize(.horizontal, length: { length, _ in length * 0.5 }) {
                LimitProbe(recorder: recorder).containerRelativeSize(.horizontal, maxSize: { size in
                    calls.record(size)
                    return CGSize(width: size.width * 0.75, height: 0)
                }).frame(width: width)
            }
            _ = layout.quick_layoutThatFits(proposal)
            #expect(calls.sizes == [proposal])
            #expect(recorder.proposals.last == CGSize(width: min(width, 200), height: 600))
        }
    }

    @Test func nestedScopeProvidesOneCompleteReferenceAndInheritsOtherAxisLimit() {
        let calls = LimitInvocationRecorder()
        let recorder = LimitProposalRecorder()
        let layout = ContainerRelativeSize([.horizontal, .vertical], length: { length, _ in length / 2 }) {
            ContainerRelativeSize(.vertical, maxSize: { _ in CGSize(width: 0, height: 80) }) {
                LimitProbe(recorder: recorder).containerRelativeSize([.horizontal, .vertical], maxSize: { size in
                    calls.record(size)
                    return CGSize(width: size.height, height: size.width)
                })
            }.frame(width: 200, height: 100)
        }
        _ = layout.quick_layoutThatFits(proposal)
        #expect(calls.sizes == [CGSize(width: 200, height: 100)])
        #expect(recorder.proposals.last == CGSize(width: 100, height: 80))
    }

    @Test func emptyScopesAreTransparentToDescendantContainerLookup() {
        for variant in 0..<3 {
            let calls = LimitInvocationRecorder()
            let recorder = LimitProposalRecorder()
            let child = LimitProbe(recorder: recorder).containerRelativeSize([.horizontal, .vertical], maxSize: { size in
                calls.record(size)
                return CGSize(width: size.height / 4, height: size.width / 8)
            })
            let empty: any Layout
            switch variant {
            case 0: empty = ContainerRelativeSize([]) { child.containerRelativeSize([]) }
            case 1:
                empty = ContainerRelativeSize([], length: { _, _ in
                    Issue.record("Empty scope must not calculate a length")
                    return 0
                }) {
                    child.containerRelativeSize([]) { _, _ in
                        Issue.record("Empty modifier must not calculate a length")
                        return 0
                    }
                }
            default:
                empty = ContainerRelativeSize([], maxSize: { _ in
                    Issue.record("Empty scope must not calculate a size")
                    return .zero
                }) {
                    child.containerRelativeSize([], maxSize: { _ in
                        Issue.record("Empty modifier must not calculate a size")
                        return .zero
                    })
                }
            }
            let layout = ContainerRelativeSize([.horizontal, .vertical]) {
                empty.frame(width: 200, height: 100)
            }
            _ = layout.quick_layoutThatFits(proposal)
            #expect(calls.sizes == [proposal])
            #expect(recorder.proposals.last == CGSize(width: 150, height: 50))
        }
    }

    @Test func hostAndFallbackResolveCurrentReferenceBeforeLocalFrame() {
        let calls = LimitInvocationRecorder()
        let recorder = LimitProposalRecorder()
        let host = QuickLayoutView {
            LimitProbe(recorder: recorder).containerRelativeSize(.horizontal, maxSize: { size in
                calls.record(size)
                return CGSize(width: size.width / 2, height: 0)
            }).frame(width: 300)
        }
        _ = host.sizeThatFits(in: proposal)
        #expect(calls.sizes.last == proposal)
        #expect(recorder.proposals.last?.width == 200)
        _ = host.sizeThatFits(in: CGSize(width: 800, height: 200))
        #expect(calls.sizes.last == CGSize(width: 800, height: 200))
        #expect(recorder.proposals.last?.width == 300)

        let explicitRecorder = LimitProposalRecorder()
        let explicitHost = QuickLayoutView {
            ContainerRelativeSize(.horizontal) {
                LimitProbe(recorder: explicitRecorder).containerRelativeSize(.horizontal) { width, _ in
                    width / 2
                }
            }.frame(width: 200)
        }
        _ = explicitHost.sizeThatFits(in: proposal)
        #expect(explicitRecorder.proposals.last?.width == 100)

        let fallback = LimitProbe().containerRelativeSize(.horizontal) { length, _ in length / 4 }
        #expect(fallback.quick_layoutThatFits(proposal).size.width == 100)
    }

    @Test func safeAreaReferenceRespectsCurrentInsets() {
        let size = QuickLayoutSafeAreaContext.withValues(QuickLayoutSafeAreaValues(
            containerSize: proposal,
            containerInsets: EdgeInsets(top: 20, leading: 10, bottom: 30, trailing: 15)
        )) {
            LimitProbe().containerRelativeSize().quick_layoutThatFits(proposal).size
        }
        #expect(size == CGSize(width: 375, height: 550))
    }

    @Test func scrollReferenceUsesInsetViewportAndUpdatesAfterResize() {
        let scrollView = QuickLayoutScrollView(.horizontal)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
        let card = UIView()
        let calls = LimitInvocationRecorder()
        _ = ScrollView(scrollView, .horizontal) {
            HStack(spacing: 10) {
                card.resizable().containerRelativeSize(.horizontal, maxSize: { size in
                    calls.record(size)
                    return size
                }).frame(height: 40)
                UIView().frame(width: 500, height: 40)
            }
        }.contentMargins(.horizontal, 20, for: .scrollContent)
        scrollView.layoutIfNeeded()
        #expect(card.bounds.width == 260)
        #expect(scrollView.contentSize.width > scrollView.bounds.width)
        #expect(calls.sizes.last?.width == 260)
        scrollView.frame.size.width = 400
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()
        #expect(card.bounds.width == 360)
        #expect(calls.sizes.last?.width == 360)
    }

    @Test func compositionPreservesPaddingAspectFitAndExplicitFixedSize() {
        let padded = ContainerRelativeSize(.horizontal, length: { length, _ in length / 2 }) {
            LimitProbe(idealSize: CGSize(width: 500, height: 20))
                .containerRelativeSize(.horizontal).padding(.horizontal, 10)
        }
        #expect(padded.quick_layoutThatFits(proposal).size == CGSize(width: 220, height: 20))
        let media = LimitProbe().aspectRatio(2, contentMode: .fit)
            .containerRelativeSize([.horizontal, .vertical], maxSize: { _ in CGSize(width: 200, height: 200) })
        #expect(media.quick_layoutThatFits(proposal).size == CGSize(width: 200, height: 100))
        let fixed = LimitProbe().frame(width: 500, height: 30)
            .containerRelativeSize(.horizontal) { _, _ in 100 }
        #expect(fixed.quick_layoutThatFits(proposal).size == CGSize(width: 500, height: 30))
    }

    @Test func layoutValuesPassThroughBothWrappersIntoCustomLayout() {
        let layout = LimitValueLayout() {
            ContainerRelativeSize(.horizontal) {
                LimitProbe().layoutValue(key: LimitValueKey.self, value: 73)
                    .containerRelativeSize(.horizontal, maxSize: { $0 })
            }
        }
        #expect(layout.sizeThatFits(proposal).width == 73)
    }

    @Test func selectedAxesAndModifierAxesAreIndependent() {
        let cases: [(AxisSet, CGSize)] = [
            (.horizontal, CGSize(width: 200, height: 600)),
            (.vertical, CGSize(width: 400, height: 300)),
            ([.horizontal, .vertical], CGSize(width: 200, height: 300)),
            ([], CGSize(width: 400, height: 600)),
        ]
        for (axes, expected) in cases {
            let layout = ContainerRelativeSize(axes, length: { length, _ in length * 0.5 }) {
                LimitProbe().containerRelativeSize()
            }
            #expect(layout.quick_layoutThatFits(proposal).size == expected)
        }
        let horizontalOnly = ContainerRelativeSize([.horizontal, .vertical], length: { length, _ in length * 0.5 }) {
            LimitProbe().containerRelativeSize(.horizontal)
        }
        #expect(horizontalOnly.quick_layoutThatFits(proposal).size == CGSize(width: 200, height: 600))
        let unmarked = ContainerRelativeSize([.horizontal, .vertical], length: { length, _ in length * 0.5 }) { LimitProbe() }
        #expect(unmarked.quick_layoutThatFits(proposal).size == proposal)
    }

    @Test func customLengthUsesEachAxesProposalAndSupportsUnboundedInput() {
        let layout = ContainerRelativeSize([.horizontal, .vertical], length: { length, axis in
            axis == .horizontal ? min(420, length * 0.75) : min(240, length - 20)
        }) {
            LimitProbe().containerRelativeSize()
        }
        #expect(layout.quick_layoutThatFits(proposal).size == CGSize(width: 300, height: 240))
        #expect(layout.quick_layoutThatFits(CGSize(width: 800, height: 200)).size == CGSize(width: 420, height: 180))
        #expect(layout.quick_layoutThatFits(CGSize(width: CGFloat.infinity, height: CGFloat.infinity)).size == CGSize(width: 420, height: 240))
    }

    @Test func referenceIsTheProposalReceivedByTheScope() {
        let recorder = LimitProposalRecorder()
        let layout = ContainerRelativeSize(.horizontal, length: { length, _ in length * 0.5 }) {
            LimitProbe(recorder: recorder).containerRelativeSize(.horizontal)
        }.frame(width: 200)
        _ = layout.quick_layoutThatFits(CGSize(width: 800, height: 600))
        #expect(recorder.proposals.last?.width == 100)
    }

    @Test func limitsPreserveNaturalSizeAndParentAvailableSpace() {
        let shortContent = ContainerRelativeSize(.horizontal, length: { length, _ in min(420, max(140, length * 0.75)) }) {
            LimitProbe(idealSize: CGSize(width: 60, height: 20)).containerRelativeSize()
        }
        #expect(shortContent.quick_layoutThatFits(proposal).size == CGSize(width: 60, height: 20))
        let expanding = ContainerRelativeSize(.horizontal, length: { length, _ in min(420, max(140, length * 0.75)) }) {
            LimitProbe().containerRelativeSize()
        }
        #expect(expanding.quick_layoutThatFits(CGSize(width: 834, height: 100)).size.width == 420)
        #expect(expanding.quick_layoutThatFits(CGSize(width: 100, height: 100)).size.width == 100)
    }

    @Test func invalidResultsNormalizeEachSelectedAxis() {
        let lengths: [(CGFloat, CGFloat)] = [(-20, 0), (-.infinity, 0), (.nan, 400), (.infinity, 400)]
        for (length, expected) in lengths {
            let builder = ContainerRelativeSize(.horizontal, length: { _, _ in length }) {
                LimitProbe().containerRelativeSize()
            }
            let sizeBuilder = ContainerRelativeSize(.horizontal, maxSize: { _ in
                CGSize(width: length, height: 0)
            }) { LimitProbe().containerRelativeSize() }
            let modifier = LimitProbe().containerRelativeSize(.horizontal) { _, _ in length }
            let sizeModifier = LimitProbe().containerRelativeSize(.horizontal, maxSize: { _ in
                CGSize(width: length, height: 0)
            })
            for element in [builder, sizeBuilder, modifier, sizeModifier] {
                #expect(element.quick_layoutThatFits(proposal).size == CGSize(width: expected, height: 600))
            }
        }
        let mixed = LimitProbe().containerRelativeSize([.horizontal, .vertical], maxSize: { _ in
            CGSize(width: CGFloat.nan, height: -10)
        })
        #expect(mixed.quick_layoutThatFits(proposal).size == CGSize(width: 400, height: 0))
    }

    @Test func nestedScopesOverrideOnlySelectedAxesAndRestoreSiblings() {
        let innerRecorder = LimitProposalRecorder()
        let siblingRecorder = LimitProposalRecorder()
        let layout = ContainerRelativeSize([.horizontal, .vertical], length: { length, _ in length * 0.5 }) {
            ZStack {
                ContainerRelativeSize(.vertical, length: { length, _ in length * 0.25 }) {
                    LimitProbe(recorder: innerRecorder).containerRelativeSize()
                }
                LimitProbe(recorder: siblingRecorder).containerRelativeSize()
            }
        }
        _ = layout.quick_layoutThatFits(proposal)
        #expect(innerRecorder.proposals.last == CGSize(width: 200, height: 150))
        #expect(siblingRecorder.proposals.last == CGSize(width: 200, height: 300))
        #expect(LimitProbe().containerRelativeSize().quick_layoutThatFits(proposal).size == proposal)
    }

    @Test func contentBuildsOnceAcrossMeasurementAndViewExtraction() {
        var builds = 0
        let view = UIView()
        let innerView = UIView()
        let inner = ContainerRelativeSize(.horizontal, length: { length, _ in length * 0.25 }) {
            innerView.resizable(axis: .horizontal).frame(height: 20).containerRelativeSize(.horizontal)
        }
        let outer = ContainerRelativeSize(.horizontal, length: { length, _ in length * 0.5 }) {
            builds += 1
            return VStack(spacing: 0) {
                inner
                view.resizable(axis: .horizontal).frame(height: 20).containerRelativeSize(.horizontal)
            }
        }
        var views: [UIView] = []
        outer.quick_extractViewsIntoArray(&views)
        #expect(views.count == 2)
        #expect(outer.quick_layoutThatFits(CGSize(width: 400, height: 100)).size.width == 200)
        #expect(outer.quick_layoutThatFits(CGSize(width: 200, height: 100)).size.width == 100)
        #expect(builds == 1)
    }

    @Test func emptyAxesSkipClosureAndPreserveLayoutTraits() {
        let layout = ContainerRelativeSize([], length: { _, _ in
            Issue.record("Empty axes must not invoke the length closure")
            return 0
        }) { LimitProbe() }
        #expect(layout.quick_layoutThatFits(proposal).size == proposal)
        #expect(layout.quick_flexibility(for: .horizontal) == .fullyFlexible)
        #expect(layout.quick_flexibility(for: .vertical) == .fullyFlexible)
        #expect(layout.quick_layoutPriority() == 7)
        let modifier = LimitProbe().containerRelativeSize(.vertical)
        #expect(modifier.quick_flexibility(for: .horizontal) == .fullyFlexible)
        #expect(modifier.quick_flexibility(for: .vertical) == .partial)
        #expect(modifier.quick_layoutPriority() == 7)
    }
}

private final class LimitProposalRecorder {
    var proposals: [CGSize] = []
}

private struct LimitProbe: Layout {
    var idealSize = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
    var recorder: LimitProposalRecorder?
    var horizontalFlexibility: Flexibility = .fullyFlexible
    var verticalFlexibility: Flexibility = .fullyFlexible

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        recorder?.proposals.append(proposedSize)
        return LayoutNode(view: nil, dimensions: ElementDimensions(CGSize(
            width: min(idealSize.width, proposedSize.width),
            height: min(idealSize.height, proposedSize.height)
        )))
    }
    func quick_flexibility(for axis: Axis) -> Flexibility {
        axis == .horizontal ? horizontalFlexibility : verticalFlexibility
    }
    func quick_layoutPriority() -> CGFloat { 7 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private final class LimitInvocationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSizes: [CGSize] = []
    private var recordedLengths: [(length: CGFloat, axis: Axis)] = []

    var sizes: [CGSize] { lock.withLock { recordedSizes } }
    var lengths: [(length: CGFloat, axis: Axis)] { lock.withLock { recordedLengths } }
    func record(_ size: CGSize) { lock.withLock { recordedSizes.append(size) } }
    func record(_ length: CGFloat, axis: Axis) {
        lock.withLock { recordedLengths.append((length, axis)) }
    }
}

private enum LimitValueKey: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

private struct LimitValueLayout: LayoutAlgorithm {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout Void) -> CGSize {
        CGSize(width: subviews[0][LimitValueKey.self], height: 20)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedSize, subviews: Subviews, cache: inout Void) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}
