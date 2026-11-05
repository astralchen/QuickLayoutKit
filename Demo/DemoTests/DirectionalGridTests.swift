import QuickLayout
import QuickLayoutKitCore
import SwiftUI
import Testing
import UIKit

private typealias QLAlignment = QuickLayout.Alignment
private typealias QLHorizontalAlignment = QuickLayout.HorizontalAlignment
private typealias QLVerticalAlignment = QuickLayout.VerticalAlignment

@MainActor
@Suite(.serialized)
struct DirectionalGridTests {
    @Test func defaultsAndEmptyContent() {
        let item = QuickLayoutKitCore.GridItem()
        #expect(item.size == .flexible())
        #expect(item.spacing == 0)
        #expect(item.alignment == nil)
        #expect(VGrid(columns: [item]) {}.sizeThatFits(CGSize(width: 300, height: 300)) == CGSize(width: 300, height: 0))
        #expect(HGrid(rows: []) { UIView() }.views().isEmpty)
    }

    @Test func adaptiveBreakpointsAndIncompleteRows() {
        let views = (0..<7).map { _ in UIView() }
        let grid = VGrid(columns: [.init(.adaptive(minimum: 80), spacing: 10)], spacing: 12) {
            for view in views { view.resizable().frame(height: 30) }
        }
        for (width, columns) in [(169.0, 1), (170, 2), (259, 2), (260, 3), (350, 4)] {
            let size = grid.sizeThatFits(CGSize(width: width, height: 1000))
            grid.applyFrame(CGRect(origin: .zero, size: size), alignment: .topLeading, layoutDirection: .leftToRight)
            let cell = (width - CGFloat(columns - 1) * 10) / CGFloat(columns)
            #expect(abs(size.width - width) < 0.5)
            #expect(size.height == CGFloat((7 + columns - 1) / columns) * 42 - 12)
            for (index, view) in views.enumerated() {
                #expect(abs(view.frame.width - cell) < 0.5)
                #expect(abs(view.frame.minX - CGFloat(index % columns) * (cell + 10)) < 0.5)
                #expect(abs(view.frame.minY - CGFloat(index / columns) * 42) < 0.5)
            }
        }
        #expect(grid.views().map(ObjectIdentifier.init) == views.map(ObjectIdentifier.init))
    }

    @Test func defaultSpacingMatchesQuickLayoutGrid() {
        for horizontal in [false, true] {
            let views = (0..<4).map { _ in UIView() }
            let items: [QuickLayoutKitCore.GridItem] = [.init(.fixed(20)), .init(.fixed(20))]
            var grid: any QuickLayout.Layout = horizontal
                ? HGrid(rows: items) { for view in views { view.resizable().frame(width: 20, height: 20) } }
                : VGrid(columns: items) { for view in views { view.resizable().frame(width: 20, height: 20) } }
            #expect(grid.sizeThatFits(.zero) == CGSize(width: 40, height: 40))
            grid.applyFrame(CGRect(x: 0, y: 0, width: 40, height: 40), alignment: .topLeading,
                            layoutDirection: .leftToRight)
            for (index, view) in views.enumerated() {
                let column = horizontal ? index / 2 : index % 2
                let row = horizontal ? index % 2 : index / 2
                #expect(view.frame == CGRect(x: column * 20, y: row * 20, width: 20, height: 20))
            }
        }
    }

    @Test func spacingSanitizationMatchesQuickLayoutGrid() {
        for gap: CGFloat in [0, 12, -8, .infinity, -.infinity, .nan] {
            for horizontal in [false, true] {
                let items: [QuickLayoutKitCore.GridItem] = [
                    .init(.fixed(20), spacing: gap), .init(.fixed(20), spacing: gap)
                ]
                let views = (0..<4).map { _ in UIView() }
                var grid: any QuickLayout.Layout = horizontal
                    ? HGrid(rows: items, spacing: gap) { for view in views { view.resizable().frame(width: 20, height: 20) } }
                    : VGrid(columns: items, spacing: gap) { for view in views { view.resizable().frame(width: 20, height: 20) } }
                let referenceViews = (0..<4).map { _ in UIView() }
                let reference = GridElement(rows: [
                    GridRowElement(children: referenceViews.prefix(2).map { $0.resizable().frame(width: 20, height: 20) }, alignment: nil),
                    GridRowElement(children: referenceViews.suffix(2).map { $0.resizable().frame(width: 20, height: 20) }, alignment: nil)
                ], alignment: .topLeading, horizontalSpacing: gap, verticalSpacing: gap)
                let size = reference.sizeThatFits(.zero)
                #expect(grid.sizeThatFits(.zero) == size)
                let frame = CGRect(origin: .zero, size: size)
                grid.applyFrame(frame, alignment: .topLeading, layoutDirection: .leftToRight)
                reference.applyFrame(frame, alignment: .topLeading, layoutDirection: .leftToRight)
                for index in views.indices {
                    let referenceIndex = horizontal ? (index % 2) * 2 + index / 2 : index
                    #expect(views[index].frame == referenceViews[referenceIndex].frame)
                }
            }
        }
    }

    @Test func allContentIsBuiltOnceAndMeasuredOncePerProposal() {
        let counter = GridCounter()
        let grid = VGrid(columns: [.init(.flexible()), .init(.flexible())]) {
            for _ in 0..<9 {
                GridProbe(counter: counter)
                    .alignmentGuide(QLHorizontalAlignment.center) { $0[QLHorizontalAlignment.center] + 12 }
                    .alignmentGuide(QLVerticalAlignment.center) { $0[QLVerticalAlignment.center] - 9 }
            }
        }
        #expect(counter.builds == 9)
        _ = grid.sizeThatFits(CGSize(width: 300, height: 20))
        #expect(counter.measures == 9)
        _ = grid.sizeThatFits(CGSize(width: 200, height: 20))
        #expect(counter.builds == 9)
        #expect(counter.measures == 18)
    }

    @Test func internalTrackAlignmentDoesNotShiftSiblingViews() {
        let gridCell = UIView()
        let sibling = UIView()
        let layout = StackElement.verticalStack(children: [
            VGrid(columns: [.init(.fixed(60))]) { gridCell.resizable().frame(height: 20) },
            sibling.resizable().frame(width: 300, height: 20)
        ], spacing: 10, alignment: .leading)
        let size = layout.sizeThatFits(CGSize(width: 300, height: 500))
        #expect(size == CGSize(width: 300, height: 50))
        layout.applyFrame(CGRect(origin: .zero, size: size), alignment: .topLeading, layoutDirection: .leftToRight)
        #expect(sibling.frame.minX == 0)
        #expect(gridCell.frame.minX == 120)
    }

    /// 显式传入相同间距，使用原生 LazyVGrid / LazyHGrid 的实际 UIView 背景矩形作为基准。
    @Test func framesMatchSwiftUI() async {
        let configurations: [[QuickLayoutKitCore.GridItem]] = [
            [.init(.fixed(60)), .init(.fixed(90))],
            [.init(), .init()],
            [.init(.fixed(60), spacing: 17), .init(.flexible()), .init(.flexible())],
            [.init(.flexible(minimum: 40, maximum: 60)), .init(.flexible(minimum: 100))],
            [.init(.flexible(minimum: 200)), .init(.flexible(minimum: 20))],
            [.init(.adaptive(minimum: 70), spacing: 10)],
            [.init(.adaptive(minimum: 70, maximum: 80), spacing: 10)],
            [.init(.fixed(40), spacing: 5), .init(.adaptive(minimum: 60), spacing: 12)],
            [.init(.adaptive(minimum: 60), spacing: 10), .init(.flexible())],
            [.init(.adaptive(minimum: 400))],
            [.init(.fixed(70), alignment: .bottomTrailing), .init(.fixed(90), alignment: .topLeading)]
        ]
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for (configuration, items) in configurations.enumerated() {
                    await compare(items: items, horizontal: horizontal, rtl: rtl,
                                  context: "configuration=\(configuration), horizontal=\(horizontal), rtl=\(rtl)")
                }
            }
        }
    }

    @Test func alignmentSpacingAndUnspecifiedSizeMatchSwiftUI() async {
        for horizontal in [false, true] {
            for alignment in 0..<3 {
                for rtl in [false, true] {
                    await compare(items: [.init(.fixed(70), spacing: 13), .init(.fixed(90))],
                                  horizontal: horizontal, rtl: rtl, alignmentIndex: alignment,
                                  fixedCross: true, lineSpacing: 0,
                                  context: "alignment=\(alignment), horizontal=\(horizontal), rtl=\(rtl)")
                }
            }
            for items: [QuickLayoutKitCore.GridItem] in [
                [.init(), .init()], [.init(.adaptive(minimum: 80))],
                [.init(.flexible(minimum: 40)), .init(.fixed(50))]
            ] {
                await compare(items: items, horizontal: horizontal, rtl: false, unspecifiedCross: true,
                              context: "unspecified, horizontal=\(horizontal), items=\(items)")
            }
            for width: CGFloat in [50, 170, 260, 500] {
                await compare(items: [.init(.adaptive(minimum: 80), spacing: 10)],
                              horizontal: horizontal, rtl: false, crossProposal: width,
                              context: "adaptive cross=\(width), horizontal=\(horizontal)")
            }
        }
    }

    @Test func emptySparseAndOverflowingGridsMatchSwiftUI() async {
        for horizontal in [false, true] {
            await compare(items: [.init(.adaptive(minimum: 60), spacing: 10)],
                          horizontal: horizontal, rtl: false, itemCount: 1, context: "single adaptive cell")
            await compare(items: [.init(), .init()], horizontal: horizontal, rtl: false,
                          itemCount: 0, context: "empty content")
            await compare(items: [], horizontal: horizontal, rtl: false, context: "empty tracks")
            await compare(items: [.init(.fixed(200)), .init(.fixed(200))],
                          horizontal: horizontal, rtl: false, context: "fixed track overflow")
        }
    }

    @Test func mixedTrackLimitsAndFractionalProposalsMatchSwiftUI() async {
        let configurations: [[QuickLayoutKitCore.GridItem]] = [
            [.init(.flexible(minimum: 10, maximum: 60)), .init(.flexible(minimum: 10, maximum: 60))],
            [.init(.adaptive(minimum: 70, maximum: 80), spacing: 7), .init(.adaptive(minimum: 40, maximum: 50), spacing: 13)],
            [.init(.adaptive(minimum: 40), spacing: 7), .init(.fixed(60), spacing: 3), .init(.adaptive(minimum: 80), spacing: 13)],
            [.init(.flexible(minimum: 10, maximum: 100), spacing: 9), .init(.flexible(minimum: 80, maximum: 120)), .init(.fixed(30))],
            [.init(.flexible(minimum: 200)), .init(.flexible(minimum: 20))],
            [.init(.fixed(0)), .init(.flexible(minimum: 0, maximum: 0))],
            [.init(.adaptive(minimum: 50, maximum: 50), spacing: 0)],
            [.init(.fixed(70), spacing: 100)]
        ]
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for (index, items) in configurations.enumerated() {
                    for width: CGFloat in [120, 301.5] {
                        await compare(items: items, horizontal: horizontal, rtl: rtl,
                                      crossProposal: width, itemCount: 11,
                                      knownEstimatedMainSize: index == 3 && width == 120,
                                      context: "limits \(index), cross=\(width), horizontal=\(horizontal), RTL=\(rtl)")
                    }
                }
            }
        }
    }

    @Test func individualAlignmentsAndOversizedChildrenMatchSwiftUI() async {
        let alignments: [(QuickLayout.Alignment, SwiftUI.Alignment)] = [
            (.topLeading, .topLeading), (.top, .top), (.topTrailing, .topTrailing),
            (.leading, .leading), (.center, .center), (.trailing, .trailing),
            (.bottomLeading, .bottomLeading), (.bottom, .bottom), (.bottomTrailing, .bottomTrailing)
        ]
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for (index, pair) in alignments.enumerated() {
                    await compare(items: [.init(.fixed(70), spacing: 13, alignment: pair.0),
                                          .init(.fixed(90), alignment: pair.0)],
                                  horizontal: horizontal, rtl: rtl, alignmentIndex: 0,
                                  cellCross: index.isMultiple(of: 2) ? 120 : 30,
                                  nativeAlignments: [pair.1, pair.1],
                                  context: "cell alignment=\(index), horizontal=\(horizontal), RTL=\(rtl)")
                    await compare(items: [.init(.fixed(70), spacing: 13, alignment: pair.0),
                                          .init(.fixed(90), alignment: pair.0)],
                                  horizontal: horizontal, rtl: rtl, alignmentIndex: 0,
                                  nativeAlignments: [pair.1, pair.1], mainGuideOffset: 12, crossGuideOffset: -9,
                                  context: "guided cell alignment=\(index), horizontal=\(horizontal), RTL=\(rtl)")
                }
            }
        }
    }

    @Test func childAlignmentGuidesMatchSwiftUI() async {
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for offset: CGFloat in [-12, 0, 12] {
                    await compare(items: [.init(.fixed(70)), .init(.fixed(90))],
                                  horizontal: horizontal, rtl: rtl, fixedCross: true,
                                  mainGuideOffset: offset, mainGuideOnly: true,
                                  context: "single main-axis guide=\(offset), horizontal=\(horizontal), RTL=\(rtl)")
                    await compare(items: [.init(.fixed(70)), .init(.fixed(90))],
                                  horizontal: horizontal, rtl: rtl, fixedCross: true,
                                  mainGuideOffset: offset,
                                  context: "main-axis guides=\(offset), horizontal=\(horizontal), RTL=\(rtl)")
                    await compare(items: [.init(.fixed(70)), .init(.fixed(90))],
                                  horizontal: horizontal, rtl: rtl, fixedCross: true,
                                  mainGuideOffset: 0, crossGuideOffset: offset,
                                  context: "cross-axis guides=\(offset), horizontal=\(horizontal), RTL=\(rtl)")
                }
                await compare(items: [.init(.adaptive(minimum: 60), spacing: 10)],
                              horizontal: horizontal, rtl: rtl, itemCount: 1,
                              mainGuideOffset: 0,
                              context: "sparse explicit guides, horizontal=\(horizontal), RTL=\(rtl)")
            }
        }
    }

    @Test func childGuidesDoNotPropagateToParentStacks() async {
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for alignmentIndex in 0..<3 {
                    await compare(items: [.init(.fixed(70)), .init(.fixed(90))],
                                  horizontal: horizontal, rtl: rtl, alignmentIndex: alignmentIndex,
                                  fixedCross: true, mainGuideOffset: 12, crossGuideOffset: -9,
                                  nested: true,
                                  context: "parent stack alignment=\(alignmentIndex), horizontal=\(horizontal), RTL=\(rtl)")
                    await compare(items: [.init(.adaptive(minimum: 60), spacing: 10)],
                                  horizontal: horizontal, rtl: rtl, alignmentIndex: alignmentIndex,
                                  itemCount: 1, mainGuideOffset: 0, nested: true,
                                  context: "sparse parent alignment=\(alignmentIndex), horizontal=\(horizontal), RTL=\(rtl)")
                }
            }
        }
    }

    @Test func explicitGridGuidesMatchSwiftUIInParentStacks() async {
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for alignmentIndex in 0..<3 {
                    for offset: CGFloat in [-17, 0, 17] {
                        await compare(items: [.init(.fixed(70)), .init(.fixed(90))],
                                      horizontal: horizontal, rtl: rtl, alignmentIndex: alignmentIndex,
                                      fixedCross: true, mainGuideOffset: 12, crossGuideOffset: -9,
                                      nested: true, outerGuideOffset: offset,
                                      context: "explicit grid guide=\(offset), alignment=\(alignmentIndex), horizontal=\(horizontal), RTL=\(rtl)")
                    }
                }
            }
        }
    }

    @Test func customTrackGuidesMatchSwiftUI() async {
        let actualAlignment = QLAlignment(horizontal: QLHorizontalAlignment(GridHorizontalGuide.self),
                                                   vertical: QLVerticalAlignment(GridVerticalGuide.self))
        let nativeAlignment = SwiftUI.Alignment(horizontal: SwiftUI.HorizontalAlignment(GridHorizontalGuide.self),
                                               vertical: SwiftUI.VerticalAlignment(GridVerticalGuide.self))
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for nested in [false, true] {
                    await compare(items: [.init(.fixed(70), spacing: 9, alignment: actualAlignment),
                                          .init(.fixed(90), alignment: actualAlignment)],
                                  horizontal: horizontal, rtl: rtl, nativeAlignments: [nativeAlignment, nativeAlignment],
                                  mainGuideOffset: 12, crossGuideOffset: -9, customGuides: true,
                                  parentUsesCustomGuide: true, nested: nested,
                                  context: "custom track guides, horizontal=\(horizontal), RTL=\(rtl), nested=\(nested)")
                }
            }
        }
    }

    @Test func overflowingTracksHaveKnownReportedSizeDifference() async {
        for count in [3, 6, 9, 10, 11, 12] {
            await compare(items: [.init(.flexible(minimum: 10, maximum: 100), spacing: 9),
                                  .init(.flexible(minimum: 80, maximum: 120)), .init(.fixed(30))],
                          horizontal: false, rtl: false, crossProposal: 120, itemCount: count,
                          knownEstimatedMainSize: count >= 9,
                          context: "overflow reported size, count=\(count)")
        }
    }

    @Test func overflowingTracksUseReportedCrossSizeWhenCommittingCachedLayout() async {
        let configurations: [[QuickLayoutKitCore.GridItem]] = [
            [.init(.flexible(minimum: 10, maximum: 100), spacing: 9),
             .init(.flexible(minimum: 80, maximum: 120)), .init(.fixed(30))],
            [.init(.flexible(minimum: 50), spacing: 8), .init(.flexible(minimum: 120))],
            [.init(.adaptive(minimum: 20), spacing: 4), .init(.flexible(minimum: 160)), .init(.fixed(30))]
        ]
        for (configuration, items) in configurations.enumerated() {
            for horizontal in [false, true] {
                for rtl in [false, true] {
                    for alignment in 0..<3 {
                        for nested in [false, true] {
                            // 等长内容隔离 LazyGrid 的增长轴估算；仍验证全部报告尺寸和每个矩形。
                            // 11 个元素同时覆盖多行/列以及不完整的末行/列。
                            await compare(items: items, horizontal: horizontal, rtl: rtl,
                                          alignmentIndex: alignment, crossProposal: configuration == 1 ? 200 : 120,
                                          itemCount: 11, mainStep: 0, nested: nested,
                                          context: "cached overflow \(configuration), H=\(horizontal), RTL=\(rtl), alignment=\(alignment), nested=\(nested)")
                        }
                    }
                }
            }
        }
    }

    @Test func overflowingTracksWithVariableAndResponsiveCellsMatchSwiftUI() async {
        let items: [QuickLayoutKitCore.GridItem] = [
            .init(.flexible(minimum: 10, maximum: 100), spacing: 9),
            .init(.flexible(minimum: 80, maximum: 120)), .init(.fixed(30))
        ]
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for responsive in [false, true] {
                    for nested in [false, true] {
                        for count in [3, 6] {
                            await compare(items: items, horizontal: horizontal, rtl: rtl,
                                          crossProposal: 120, itemCount: count, responsiveCells: responsive,
                                          nested: nested,
                                          context: "responsive overflow H=\(horizontal), RTL=\(rtl), responsive=\(responsive), nested=\(nested), count=\(count)")
                        }
                    }
                }
            }
        }
    }

    @Test func fractionalMainLengthsMatchSwiftUI() async {
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for count in [3, 6] {
                    await compare(items: [.init(.fixed(60)), .init(.fixed(80)), .init(.fixed(30))],
                                  horizontal: horizontal, rtl: rtl, itemCount: count, mainStep: 0.6,
                                  context: "fractional main H=\(horizontal), RTL=\(rtl), count=\(count)")
                }
            }
        }
    }

    @Test func overflowingTracksMeasureFinalProposalsOnce() {
        for horizontal in [false, true] {
            let counter = GridCounter()
            let items: [QuickLayoutKitCore.GridItem] = [
                .init(.flexible(minimum: 10, maximum: 100), spacing: 9),
                .init(.flexible(minimum: 80, maximum: 120)), .init(.fixed(30))
            ]
            let children = (0..<11).map { _ in GridCrossProposalProbe(counter: counter, horizontal: horizontal) }
            let grid: any QuickLayout.Layout = horizontal
                ? HGrid(rows: items) { for child in children { child } }
                : VGrid(columns: items) { for child in children { child } }
            for rtl in [false, true] {
                let size = grid.layoutThatFits(CGSize(width: horizontal ? 300 : 120,
                                                     height: horizontal ? 120 : 300), layoutDirection: rtl ? .rightToLeft : .leftToRight).size
                #expect(size == CGSize(width: horizontal ? 80 : 159.5, height: horizontal ? 159.5 : 80))
                #expect(Array(counter.crossProposals.suffix(11)) == [60.25, 80, 30, 60.25, 80, 30, 60.25, 80, 30, 60.25, 80])
            }
            #expect(counter.measures == 22)
        }
    }

    private func compare(items: [QuickLayoutKitCore.GridItem], horizontal: Bool, rtl: Bool,
                         alignmentIndex: Int = 1, fixedCross: Bool = false, lineSpacing: CGFloat = 11,
                         unspecifiedCross: Bool = false, crossProposal: CGFloat = 300,
                         itemCount: Int = 7, mainStep: CGFloat = 3,
                         knownEstimatedMainSize: Bool = false,
                         responsiveCells: Bool = false,
                         cellCross: CGFloat = 30,
                         nativeAlignments: [SwiftUI.Alignment?]? = nil,
                         mainGuideOffset: CGFloat? = nil,
                         crossGuideOffset: CGFloat = 0,
                         mainGuideOnly: Bool = false,
                         customGuides: Bool = false,
                         parentUsesCustomGuide: Bool = false,
                         nested: Bool = false,
                         outerGuideOffset: CGFloat = 0,
                         context: String) async {
        let actualViews = (0..<itemCount).map { _ in UIView() }
        let referenceViews = (0..<itemCount).map { _ in UIView() }
        let boundsProbe = UIView()
        let actualSibling = UIView()
        let referenceSibling = UIView()
        let nativeItems = items.enumerated().map { index, item -> SwiftUI.GridItem in
            let size: SwiftUI.GridItem.Size
            switch item.size {
            case let .fixed(value): size = .fixed(value)
            case let .flexible(minimum, maximum): size = .flexible(minimum: minimum, maximum: maximum)
            case let .adaptive(minimum, maximum): size = .adaptive(minimum: minimum, maximum: maximum)
            }
            // 最后一组专门覆盖每条轨道的独立二维对齐。
            let alignment: SwiftUI.Alignment? = nativeAlignments.map { $0[index] }
                ?? (item.alignment == nil ? nil : (item.size == .fixed(70) ? .bottomTrailing : .topLeading))
            return .init(size, spacing: item.spacing, alignment: alignment)
        }
        let nativeHorizontal = customGuides ? SwiftUI.HorizontalAlignment(GridHorizontalGuide.self) : .center
        let nativeVertical = customGuides ? SwiftUI.VerticalAlignment(GridVerticalGuide.self) : .center
        let actualHorizontal = customGuides ? QLHorizontalAlignment(GridHorizontalGuide.self) : .center
        let actualVertical = customGuides ? QLVerticalAlignment(GridVerticalGuide.self) : .center
        let usesFixedCross = fixedCross || items.contains { $0.alignment != nil }
        let content = SwiftUI.ForEach(0..<itemCount, id: \.self) { index in
            let cell = responsiveCells && index % 3 == 0
                ? AnyView(SwiftUI.Color.blue.aspectRatio(horizontal ? 2 : 0.5, contentMode: .fit))
                : AnyView(SwiftUI.Color.blue.frame(width: horizontal ? (20 + CGFloat(index) * mainStep) : (usesFixedCross ? cellCross : nil),
                       height: horizontal ? (usesFixedCross ? cellCross : nil) : (20 + CGFloat(index) * mainStep)))
            if let mainGuideOffset, mainGuideOnly {
                if horizontal {
                    cell.alignmentGuide(SwiftUI.HorizontalAlignment.center) { $0[SwiftUI.HorizontalAlignment.center] + CGFloat(index % 2) * mainGuideOffset }
                        .background(GridBoundsProbe(view: referenceViews[index]))
                } else {
                    cell.alignmentGuide(SwiftUI.VerticalAlignment.center) { $0[SwiftUI.VerticalAlignment.center] + CGFloat(index % 2) * mainGuideOffset }
                        .background(GridBoundsProbe(view: referenceViews[index]))
                }
            } else if let mainGuideOffset {
                cell
                .alignmentGuide(nativeHorizontal) { dimensions in
                    dimensions[nativeHorizontal] + CGFloat(index % 2) * (horizontal ? mainGuideOffset : crossGuideOffset)
                }
                .alignmentGuide(nativeVertical) { dimensions in
                    dimensions[nativeVertical] + CGFloat(index % 2) * (horizontal ? crossGuideOffset : mainGuideOffset)
                }
                .background(GridBoundsProbe(view: referenceViews[index]))
            } else {
                cell.background(GridBoundsProbe(view: referenceViews[index]))
            }
        }
        var native: AnyView = horizontal
            ? AnyView(SwiftUI.LazyHGrid(rows: nativeItems, alignment: [.top, .center, .bottom][alignmentIndex], spacing: lineSpacing) { content })
            : AnyView(SwiftUI.LazyVGrid(columns: nativeItems, alignment: [.leading, .center, .trailing][alignmentIndex], spacing: lineSpacing) { content })
        if outerGuideOffset != 0 {
            let h: SwiftUI.HorizontalAlignment = [.leading, .center, .trailing][alignmentIndex]
            let v: SwiftUI.VerticalAlignment = [.top, .center, .bottom][alignmentIndex]
            native = horizontal
                ? AnyView(native.alignmentGuide(v) { $0[v] + outerGuideOffset })
                : AnyView(native.alignmentGuide(h) { $0[h] + outerGuideOffset })
        }
        // 扩大增长轴视口并检查所有元素创建；溢出轨道仍可能触发原生尺寸估算，
        // 因此已知估算差异只标记增长轴尺寸及受其影响的 RTL x 坐标。
        let mainProposal = max(CGFloat(300), CGFloat(itemCount) * 70)
        let nativeRoot: AnyView
        if nested {
            let sibling = SwiftUI.Color.red.frame(width: horizontal ? 20 : crossProposal,
                                                  height: horizontal ? crossProposal : 20)
                .background(GridBoundsProbe(view: referenceSibling))
            nativeRoot = horizontal
                ? AnyView(SwiftUI.HStack(alignment: parentUsesCustomGuide ? nativeVertical : [.top, .center, .bottom][alignmentIndex], spacing: 7) { native; sibling })
                : AnyView(SwiftUI.VStack(alignment: parentUsesCustomGuide ? nativeHorizontal : [.leading, .center, .trailing][alignmentIndex], spacing: 7) { native; sibling })
        } else { nativeRoot = native }
        let host = UIHostingController(rootView: nativeRoot
            .background(GridBoundsProbe(view: boundsProbe))
            .fixedSize(horizontal: unspecifiedCross && !horizontal, vertical: unspecifiedCross && horizontal)
            .frame(width: horizontal ? mainProposal : crossProposal, height: horizontal ? crossProposal : mainProposal, alignment: .topLeading)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: max(400, mainProposal + 100), height: max(600, mainProposal + 100)))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<5 {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
        let children: [QuickLayout.Element] = actualViews.enumerated().map { index, view in
            let cell: any QuickLayout.Layout = responsiveCells && index % 3 == 0
                ? AspectRatioElement(child: view.resizable(), aspectRatio: horizontal ? 2 : 0.5, contentMode: .fit)
                : view.resizable().frame(width: horizontal ? (20 + CGFloat(index) * mainStep) : (usesFixedCross ? cellCross : nil),
                                   height: horizontal ? (usesFixedCross ? cellCross : nil) : (20 + CGFloat(index) * mainStep))
            guard let mainGuideOffset else { return cell }
            if mainGuideOnly {
                if horizontal {
                    return cell.alignmentGuide(QLHorizontalAlignment.center) { $0[QLHorizontalAlignment.center] + CGFloat(index % 2) * mainGuideOffset }
                } else {
                    return cell.alignmentGuide(QLVerticalAlignment.center) { $0[QLVerticalAlignment.center] + CGFloat(index % 2) * mainGuideOffset }
                }
            }
            return cell
                .alignmentGuide(actualHorizontal) { dimensions in
                    dimensions[actualHorizontal] + CGFloat(index % 2) * (horizontal ? mainGuideOffset : crossGuideOffset)
                }
                .alignmentGuide(actualVertical) { dimensions in
                    dimensions[actualVertical] + CGFloat(index % 2) * (horizontal ? crossGuideOffset : mainGuideOffset)
                }
        }
        var grid: any QuickLayout.Layout = horizontal
            ? HGrid(rows: items, alignment: [.top, .center, .bottom][alignmentIndex], spacing: lineSpacing) { for child in children { child } }
            : VGrid(columns: items, alignment: [.leading, .center, .trailing][alignmentIndex], spacing: lineSpacing) { for child in children { child } }
        if outerGuideOffset != 0 {
            let h: QLHorizontalAlignment = [.leading, .center, .trailing][alignmentIndex]
            let v: QLVerticalAlignment = [.top, .center, .bottom][alignmentIndex]
            grid = horizontal
                ? grid.alignmentGuide(v) { $0[v] + outerGuideOffset }
                : grid.alignmentGuide(h) { $0[h] + outerGuideOffset }
        }
        let actual: any QuickLayout.Layout
        if nested {
            let sibling = actualSibling.resizable().frame(width: horizontal ? 20 : crossProposal,
                                                         height: horizontal ? crossProposal : 20)
            actual = horizontal
                ? StackElement.horizontalStack(children: [grid, sibling], spacing: 7, alignment: parentUsesCustomGuide ? actualVertical : [.top, .center, .bottom][alignmentIndex])
                : StackElement.verticalStack(children: [grid, sibling], spacing: 7, alignment: parentUsesCustomGuide ? actualHorizontal : [.leading, .center, .trailing][alignmentIndex])
        } else { actual = grid }
        let cross: CGFloat = unspecifiedCross ? .infinity : crossProposal
        let proposal = CGSize(width: horizontal ? mainProposal : cross, height: horizontal ? cross : mainProposal)
        let measured = actual.layoutThatFits(proposal, layoutDirection: rtl ? .rightToLeft : .leftToRight)
        let size = measured.size
        // 直接提交同一次测量的节点，避免重新测量掩盖网格溢出时的放置差异。
        actual._applyFrame(CGRect(origin: .zero, size: size), alignment: .topLeading,
                           layoutDirection: rtl ? .rightToLeft : .leftToRight, cachedLayout: measured)
        let actualCross = horizontal ? size.height : size.width
        let referenceCross = horizontal ? boundsProbe.bounds.height : boundsProbe.bounds.width
        #expect(abs(actualCross - referenceCross) < 0.6, "\(context): cross size \(size) vs \(boundsProbe.bounds.size)")
        let checkMainSize = {
            let actualMain = horizontal ? size.width : size.height
            let referenceMain = horizontal ? boundsProbe.bounds.width : boundsProbe.bounds.height
            #expect(abs(actualMain - referenceMain) < 0.6, "\(context): main size \(size) vs \(boundsProbe.bounds.size)")
        }
        if knownEstimatedMainSize {
            // 已知估算差异不豁免本库的完整报告长度：此固定三轨道案例独立计算每行最大值。
            let completeMain = stride(from: 0, to: itemCount, by: 3).reduce(CGFloat.zero) {
                $0 + 20 + CGFloat(min($1 + 2, itemCount - 1)) * mainStep
            } + CGFloat((itemCount - 1) / 3) * lineSpacing
            #expect(abs((horizontal ? size.width : size.height) - ceil(completeMain)) < 0.001)
            withKnownIssue("原生 LazyGrid 的增长轴报告长度仍受估算影响，与完整测量不同") { checkMainSize() }
        } else { checkMainSize() }
        if nested {
            let expected = referenceSibling.convert(referenceSibling.bounds, to: boundsProbe)
            #expect(abs(actualSibling.frame.minX - expected.minX) < 0.6 && abs(actualSibling.frame.minY - expected.minY) < 0.6,
                    "\(context): sibling \(actualSibling.frame) vs \(expected)")
        }
        for index in actualViews.indices where !items.isEmpty {
            #expect(referenceViews[index].superview != nil, "\(context), item=\(index): 原生对照元素必须实际创建")
            let expected = referenceViews[index].convert(referenceViews[index].bounds, to: boundsProbe)
            let actual = actualViews[index].frame
            let checkX = {
                #expect(abs(actual.minX - expected.minX) < 0.6, "\(context), item=\(index): x \(actual) vs \(expected)")
            }
            if knownEstimatedMainSize && horizontal && rtl {
                // 绝对原点仍记录为差异；距各自报告右边界的位置必须与原生一致。
                #expect(abs((actual.maxX - size.width) - (expected.maxX - boundsProbe.bounds.width)) < 0.6,
                        "\(context), item=\(index): RTL distance from reported boundary")
                withKnownIssue("RTL HGrid 原点受原生增长轴估算宽度影响") { checkX() }
            } else { checkX() }
            #expect(abs(actual.minY - expected.minY) < 0.6
                    && abs(actual.width - expected.width) < 0.6 && abs(actual.height - expected.height) < 0.6,
                    "\(context), item=\(index): \(actual) vs \(expected)")
        }
    }
}

private struct GridBoundsProbe: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class GridCounter {
    var builds = 0
    var measures = 0
    var crossProposals: [CGFloat] = []
}

private struct GridProbe: QuickLayout.Layout {
    let counter: GridCounter
    init(counter: GridCounter) { self.counter = counter; counter.builds += 1 }
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        counter.measures += 1
        return LayoutNode(view: nil, dimensions: ElementDimensions(CGSize(width: proposedSize.width, height: 20)))
    }
    func quick_flexibility(for axis: QuickLayout.Axis) -> Flexibility { .fullyFlexible }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

/// 两套布局使用同一个自定义参考线定义，独立验证内置 center 以外的参考线。
private enum GridHorizontalGuide: QuickLayout.AlignmentID, SwiftUI.AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { context.width / 3 }
    static func defaultValue(in context: SwiftUI.ViewDimensions) -> CGFloat { context.width / 3 }
}

private enum GridVerticalGuide: QuickLayout.AlignmentID, SwiftUI.AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { context.height / 3 }
    static func defaultValue(in context: SwiftUI.ViewDimensions) -> CGFloat { context.height / 3 }
}

/// 记录最终建议尺寸；两阶段轨道分配只测量一次内容。
private struct GridCrossProposalProbe: QuickLayout.Layout {
    let counter: GridCounter
    let horizontal: Bool
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        counter.measures += 1
        let cross = horizontal ? proposedSize.height : proposedSize.width
        counter.crossProposals.append(cross)
        return LayoutNode(view: nil, dimensions: ElementDimensions(
            CGSize(width: horizontal ? 20 : cross, height: horizontal ? cross : 20)))
    }
    func quick_flexibility(for axis: QuickLayout.Axis) -> Flexibility { .fullyFlexible }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}
