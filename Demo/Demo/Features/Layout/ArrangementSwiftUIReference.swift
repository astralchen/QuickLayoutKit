#if compiler(>=6.4)
import SwiftUI
import UIKit

@available(iOS 27.1, *)
struct ArrangementSwiftUIReference: View {
    let example: ArrangementExample

    var body: some View {
        let panes = ArrangementView { primary } secondary: { ReferencePane(primary: false) }
        switch example {
        case .automatic: panes.arrangementViewStyle(.automatic)
        case .horizontal: panes.arrangementViewStyle(.split.axes(.horizontal))
        case .vertical: panes.arrangementViewStyle(.split.axes(.vertical))
        case .overlay: panes.arrangementViewStyle(.overlay.axes([.horizontal, .vertical]))
        case .custom: panes.arrangementViewStyle(FloatingStyle())
        default: panes.arrangementViewStyle(.split)
        }
    }

    @ViewBuilder private var primary: some View {
        let pane = ReferencePane(primary: true)
        switch example {
        case .ratio: pane.splitArrangementLayoutRatio(0.65)
        case .range: pane.splitArrangementLayoutRatio(
            minHorizontal: 0.4, idealHorizontal: 0.6, maxHorizontal: 0.8,
            minVertical: 0.2, idealVertical: 0.35, maxVertical: 0.5)
        case .size: pane.splitArrangementLayoutSize(
            minWidth: 100, idealWidth: 160, maxWidth: 200,
            minHeight: 60, idealHeight: 100, maxHeight: 140)
        case .fixed: pane.splitArrangementFixedLayoutSize(horizontal: true, vertical: true)
        case .overlay: pane.overlayArrangementEdge(.trailing).overlayArrangementEdge(.bottom)
        default: pane
        }
    }

    private struct FloatingStyle: ArrangementViewStyle {
        func makeBody(configuration: Configuration) -> some View {
            ArrangementView(configuration).arrangementViewStyle(.overlay.axes([]))
        }
    }

    private struct ReferencePane: UIViewRepresentable {
        let primary: Bool
        @Environment(\.splitArrangementAxis) var axis
        @Environment(\.overlayArrangementZIndex) var zIndex

        func makeUIView(context: Context) -> ArrangementExamplePane { ArrangementExamplePane(primary: primary) }
        func updateUIView(_ view: ArrangementExamplePane, context: Context) {
            view.nativeContext = (axis.map { $0 == .horizontal ? "horizontal" : "vertical" } ?? "nil", zIndex)
        }
        func sizeThatFits(_ proposal: ProposedViewSize, uiView: ArrangementExamplePane, context: Context) -> CGSize? {
            proposal.replacingUnspecifiedDimensions(by: uiView.intrinsicContentSize)
        }
    }
}

@available(iOS 27.1, *)
@MainActor
func makeArrangementReference(_ example: ArrangementExample, direction: UIUserInterfaceLayoutDirection) -> UIView {
    UIHostingConfiguration {
        ArrangementSwiftUIReference(example: example)
            .environment(\.layoutDirection, direction == .rightToLeft ? .rightToLeft : .leftToRight)
    }.margins(.all, 0).makeContentView()
}
#endif
