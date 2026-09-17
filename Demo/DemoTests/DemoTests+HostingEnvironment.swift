import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func bubbleWidthRatioValidatesInitializationAndAssignment() {
        let cases: [(CGFloat, CGFloat)] = [
            (-0.2, 0), (0, 0), (0.35, 0.35), (1, 1), (1.2, 1),
            (.nan, 0.70), (.infinity, 1), (-.infinity, 0),
        ]
        let view = UIView()
        for (input, expected) in cases {
            var layout = BubbleWidth(ratio: input) {
                view.resizable(axis: .horizontal).frame(height: 20).bubbleWidth()
            }
            #expect(layout.ratio == expected)
            #expect(abs(layout.quick_layoutThatFits(CGSize(width: 400, height: 20)).size.width - 400 * expected) < 0.01)
            layout.ratio = 0.5
            layout.ratio = input
            #expect(layout.ratio == expected)
            #expect(abs(layout.quick_layoutThatFits(CGSize(width: 400, height: 20)).size.width - 400 * expected) < 0.01)
        }
        var zero = BubbleWidth(ratio: 0) {
            view.resizable(axis: .horizontal).frame(height: 20).bubbleWidth()
        }
        #expect(zero.quick_layoutThatFits(CGSize(width: CGFloat.infinity, height: 20)).size.width == 0)
        zero.minWidth = 40
        #expect(zero.quick_layoutThatFits(CGSize(width: CGFloat.infinity, height: 20)).size.width == 40)
    }

    @Test func bubbleWidthBuildsContentOnceAndRestoresNestedScope() {
        var builds = 0
        let view = UIView()
        let innerView = UIView()
        let inner = BubbleWidth(ratio: 0.25) {
            innerView.resizable(axis: .horizontal).frame(height: 20).bubbleWidth()
        }
        let outer = BubbleWidth(ratio: 0.5) {
            builds += 1
            return VStack(spacing: 0) {
                inner
                view.resizable(axis: .horizontal).frame(height: 20).bubbleWidth()
            }
        }
        #expect(builds == 1)
        var views: [UIView] = []
        outer.quick_extractViewsIntoArray(&views)
        #expect(views.count == 2)
        // 内层只使用 25%，后面的兄弟恢复外层 50%，后续独立测量没有宽度残留。
        #expect(outer.quick_layoutThatFits(CGSize(width: 400, height: 100)).size.width == 200)
        #expect(outer.quick_layoutThatFits(CGSize(width: 200, height: 100)).size.width == 100)
        let content = view.resizable(axis: .horizontal).frame(height: 20).bubbleWidth()
        #expect(content.quick_layoutThatFits(CGSize(width: 400, height: 100)).size.width == 400)
        #expect(builds == 1)
    }

    @Test func quickLayoutViewMeasuresHostedContent() {
        let label = UILabel()
        label.text = "QuickLayoutKit"
        label.font = .systemFont(ofSize: 17)

        let hostingView = QuickLayoutView {
            label
                .padding(.all, 12)
        }

        let measuredSize = hostingView.sizeThatFits(in: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude))

        #expect(measuredSize.width > 0)
        #expect(measuredSize.height > 17)
    }

    @Test func hostingControllerUsesReusableQuickLayoutView() {
        let label = UILabel()
        label.text = "Hosted"

        let viewController = QuickLayoutHostingController {
            label
                .padding(.all, 8)
        }

        viewController.loadViewIfNeeded()

        #expect(viewController.view is QuickLayoutView)
        #expect(viewController.sizeThatFits(in: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height > 0)
    }

    @Test func listCellMeasuresQuickLayoutContent() {
        let titleLabel = UILabel()
        titleLabel.text = "Title"
        let messageLabel = UILabel()
        messageLabel.text = "A long message that should wrap inside the proposed collection cell width."
        messageLabel.numberOfLines = 0

        let cell = QuickLayoutCollectionViewCell {
            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                messageLabel
            }
            .padding(.all, 12)
        }

        cell.quickLayoutHorizontalFlexibility = .fixedSize
        cell.quickLayoutVerticalFlexibility = .fullyFlexible

        let size = cell.sizeThatFits(CGSize(width: 180, height: 44))

        #expect(size.width == 180)
        #expect(size.height > 44)

        // UIKit 的自适应入口必须读取同一个 body，并尊重 required 轴约束。
        let fitted = cell.systemLayoutSizeFitting(
            CGSize(width: 180, height: 44),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(fitted == size)
        let fixed = cell.systemLayoutSizeFitting(
            CGSize(width: 180, height: 44),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .required
        )
        #expect(fixed == CGSize(width: 180, height: 44))
    }

    @Test func directionalEnvironmentHelpersRespectLayoutDirection() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        view.semanticContentAttribute = .forceRightToLeft

        let margins = view.quickLayoutDirectionalLayoutMargins

        #expect(margins.top == 1)
        #expect(margins.leading == 2)
        #expect(margins.bottom == 3)
        #expect(margins.trailing == 4)
    }

    @Test func quickLayoutEnvironmentReflectsCurrentUIViewState() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.semanticContentAttribute = .forceRightToLeft
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 16, trailing: 20)

        let environment = view.quickLayoutEnvironment

        #expect(environment.layoutDirection == .rightToLeft)
        #expect(environment.preferredContentSizeCategory == view.traitCollection.preferredContentSizeCategory)
        #expect(environment.horizontalSizeClass == view.traitCollection.horizontalSizeClass)
        #expect(environment.verticalSizeClass == view.traitCollection.verticalSizeClass)
        #expect(environment.userInterfaceStyle == view.traitCollection.userInterfaceStyle)
        #expect(environment.displayScale == view.traitCollection.displayScale)
        #expect(environment.layoutMargins.leading == 12)
        #expect(environment.containerSize == CGSize(width: 320, height: 480))
        #expect(view.quickLayoutDirection == .rightToLeft)
    }

    @Test func quickLayoutEnvironmentReportsPublicChanges() {
        let previous = QuickLayoutEnvironment(
            layoutDirection: .leftToRight,
            preferredContentSizeCategory: .large,
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            userInterfaceStyle: .light,
            displayScale: 2,
            safeAreaInsets: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
            layoutMargins: .init(top: 8, leading: 8, bottom: 8, trailing: 8),
            containerSize: CGSize(width: 375, height: 480)
        )
        let current = QuickLayoutEnvironment(
            layoutDirection: .rightToLeft,
            preferredContentSizeCategory: .large,
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            userInterfaceStyle: .light,
            displayScale: 2,
            safeAreaInsets: .init(top: 0, leading: 0, bottom: 34, trailing: 0),
            layoutMargins: .init(top: 8, leading: 8, bottom: 8, trailing: 8),
            containerSize: CGSize(width: 320, height: 480)
        )

        let changes = current.changes(from: previous)

        #expect(changes == [.layoutDirection, .safeArea, .containerSize])
        #expect(QuickLayoutEnvironmentChangeReason.all.isSuperset(of: changes))
    }

    @Test func quickLayoutViewNotifiesEnvironmentChangesFromMargins() {
        let hostingView = EnvironmentRecordingQuickLayoutView()
        hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        hostingView.layoutMargins = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
        hostingView.layoutIfNeeded()

        hostingView.layoutMargins = UIEdgeInsets(top: 5, left: 6, bottom: 7, right: 8)
        hostingView.layoutMarginsDidChange()

        #expect(hostingView.environmentChanges.contains { $0.reason.contains(.layoutMargins) })
        #expect(hostingView.environmentChanges.last?.environment.layoutMargins.leading == 6)
    }

    @Test func diagnosticsRecordsLayoutPasses() {
        QuickLayoutDiagnostics.reset()
        QuickLayoutDiagnostics.isEnabled = true
        QuickLayoutDiagnostics.recordLayoutPass(for: "TestView", measuredSize: CGSize(width: 10, height: 20))

        let snapshot = QuickLayoutDiagnostics.snapshot()

        #expect(snapshot.totalLayoutPasses == 1)
        #expect(snapshot.entries.first?.viewName == "TestView")

        QuickLayoutDiagnostics.isEnabled = false
        QuickLayoutDiagnostics.reset()
    }
}

private final class EnvironmentRecordingQuickLayoutView: QuickLayoutView {

    var environmentChanges: [(environment: QuickLayoutEnvironment, reason: QuickLayoutEnvironmentChangeReason)] = []

    override func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
        environmentChanges.append((environment, reason))
    }
}
