import QuickLayoutKit
import Testing
import UIKit

@MainActor
struct AlertRichTextTests {
    @Test func hostingContentWrapsAtTheAvailableWidthUnlessItProvidesAPreferredHeight() throws {
        let presenter = UIViewController()
        presenter.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(preferredStyle: .alert)
        alert.contentExtendsToPanelEdges = true
        let label = UILabel()
        label.numberOfLines = 0
        label.text = "A multiline label inside an alert needs to wrap as the available width changes."
        let content = QuickLayoutHostingController { label }
        alert.contentViewController = content

        func measuredHeight(at width: CGFloat) throws -> CGFloat {
            alert.panelWidth = .points(width)
            let size = try #require(alert.prepareForPresentation(from: presenter)?.contentSize)
            #expect(size.width == width)
            #expect(size.height == ceil(content.sizeThatFits(in: CGSize(width: width, height: .infinity)).height))
            return size.height
        }

        let wideHeight = try measuredHeight(at: 280)
        let narrowHeight = try measuredHeight(at: 140)
        #expect(narrowHeight > wideHeight)
        content.preferredContentSize.height = 42
        #expect(alert.prepareForPresentation(from: presenter)?.contentSize.height == 42)
    }

    @Test func embeddedViewsMountAtTheirMeasuredSizes() throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(title: "Title", preferredStyle: .alert)
        let header = UIViewController()
        let body = UIViewController()
        for child in [header, body] {
            child.preferredContentSize = CGSize(width: 200, height: 44)
            let label = UILabel()
            label.text = "Content"
            label.translatesAutoresizingMaskIntoConstraints = false
            child.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: child.view.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: child.view.trailingAnchor, constant: -12),
                label.topAnchor.constraint(equalTo: child.view.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: child.view.bottomAnchor),
            ])
        }
        alert.headerContentViewController = header
        alert.contentViewController = body
        alert.loadViewIfNeeded()
        #expect(header.view.superview == nil)
        #expect(body.view.superview == nil)

        let layout = try #require(alert.prepareForPresentation(from: host))
        #expect(header.view.bounds.size == CGSize(width: 200, height: 44))
        #expect(body.view.bounds.size == layout.contentSize)
        #expect(layout.contentSize == CGSize(width: 200, height: 44))
    }

    @Test(arguments: [UIAlertController.Style.alert, .actionSheet])
    func headerContentStartsAtThePanelEdgeAndPreservesBodyLayout(style: UIAlertController.Style) throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(title: "Title", message: "Message", preferredStyle: style)
        alert.addAction(AlertAction(title: "Done"))
        let body = UIViewController()
        body.preferredContentSize.height = 44
        alert.contentViewController = body
        #expect(alert.headerContentViewController == nil)
        let original = try #require(alert.prepareForPresentation(from: host))
        let scrollView = try #require(body.view.superview?.superview?.superview as? UIScrollView)
        let bodyBefore = scrollView.convert(body.view.bounds, from: body.view)

        let header = UIViewController()
        header.preferredContentSize = CGSize(width: 120, height: 72)
        alert.headerContentViewController = header
        let withHeader = try #require(alert.prepareForPresentation(from: host))
        let headerFrame = scrollView.convert(header.view.bounds, from: header.view)
        let bodyAfter = scrollView.convert(body.view.bounds, from: body.view)
        #expect(header.parent === alert)
        #expect(headerFrame.size == CGSize(width: 120, height: 72))
        #expect(abs(headerFrame.minY) < 0.5)
        #expect(abs(headerFrame.midX - bodyAfter.midX) < 0.5)
        #expect(abs(bodyAfter.minY - bodyBefore.minY - 72) < 0.5)
        #expect(abs(withHeader.panelSize.height - original.panelSize.height - 72) < 0.5)
        #expect(withHeader.contentSize == original.contentSize)
    }

    @Test func headerContentResizesReplacesAndRemovesItsChild() throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(title: "Title", preferredStyle: .alert)
        let first = UIViewController()
        let body = UIViewController()
        body.preferredContentSize.height = 36
        alert.headerContentViewController = first
        alert.contentViewController = body
        #expect(!alert.isViewLoaded)
        let fallback = try #require(alert.prepareForPresentation(from: host))
        #expect(first.parent === alert)
        #expect(first.view.bounds.height == 100)

        first.preferredContentSize = CGSize(width: 800, height: 44)
        let resized = try #require(alert.prepareForPresentation(from: host))
        #expect(first.view.bounds.size == CGSize(width: resized.panelSize.width, height: 44))
        #expect(abs(fallback.panelSize.height - resized.panelSize.height - 56) < 0.5)
        alert.panelWidth = .points(180)
        alert.prepareForPresentation(from: host)
        #expect(first.view.bounds.width == 180)
        alert.panelWidth = .automatic

        let replacement = UIViewController()
        replacement.preferredContentSize.height = 26
        alert.headerContentViewController = replacement
        let replaced = try #require(alert.prepareForPresentation(from: host))
        #expect(first.parent == nil)
        #expect(first.view.superview == nil)
        #expect(replacement.parent === alert)
        #expect(replacement.view.bounds.size == CGSize(width: replaced.panelSize.width, height: 26))

        first.preferredContentSize = CGSize(width: 75, height: 26)
        alert.headerContentViewController = first
        alert.prepareForPresentation(from: host)
        #expect(abs(first.view.bounds.width - 75) < 0.5)
        #expect(replacement.parent == nil)
        #expect(replacement.view.superview == nil)

        alert.headerContentViewController = nil
        let removed = try #require(alert.prepareForPresentation(from: host))
        #expect(abs(fallback.panelSize.height - removed.panelSize.height - 100) < 0.5)
        #expect(removed.contentSize == fallback.contentSize)
        #expect(first.parent == nil)
        #expect(first.view.superview == nil)
        #expect(body.parent === alert)
    }

    @Test func headerAndBodyUseTheSameContentSizingStrategy() throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(preferredStyle: .alert)
        alert.contentExtendsToPanelEdges = true
        alert.panelWidth = .points(160)

        let header = UIViewController()
        let body = UIViewController()
        for controller in [header, body] {
            let fittingView = WidthFittingView()
            let subview = UIView()
            subview.translatesAutoresizingMaskIntoConstraints = false
            fittingView.addSubview(subview)
            let bottom = subview.bottomAnchor.constraint(equalTo: fittingView.bottomAnchor)
            bottom.priority = .defaultHigh
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: fittingView.topAnchor),
                bottom,
                subview.heightAnchor.constraint(equalToConstant: 52),
            ])
            controller.view = fittingView
        }
        alert.headerContentViewController = header
        alert.contentViewController = body

        let automatic = try #require(alert.prepareForPresentation(from: host))
        #expect(automatic.contentSize == CGSize(width: 160, height: 52))
        #expect(header.view.bounds.size == automatic.contentSize)

        alert.contentSizing = .sizeThatFits
        let fitted = try #require(alert.prepareForPresentation(from: host))
        #expect(fitted.contentSize == CGSize(width: 160, height: 80))
        #expect(header.view.bounds.size == fitted.contentSize)
    }

    @Test(arguments: [UIAlertController.Style.alert, .actionSheet])
    func fixedPanelWidthOverridesAndRestoresThePlatformWidth(style: UIAlertController.Style) throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        let alert = AlertController(title: "Width", preferredStyle: style)
        let defaultWidth = try #require(alert.prepareForPresentation(from: host)?.panelSize.width)
        let horizontalMargin: CGFloat
        if #available(iOS 26, *) {
            #expect(defaultWidth == 320)
            horizontalMargin = 12
        } else if style == .alert {
            #expect(defaultWidth == 270)
            horizontalMargin = 12
        } else {
            #expect(defaultWidth == 584)
            horizontalMargin = 8
        }

        alert.panelWidth = .points(470)
        #expect(alert.prepareForPresentation(from: host)?.panelSize.width == 470)
        host.view.frame.size.width = 220
        #expect(alert.prepareForPresentation(from: host)?.panelSize.width == 220 - 2 * horizontalMargin)
        host.view.frame.size.width = 600
        #expect(alert.prepareForPresentation(from: host)?.panelSize.width == 470)

        alert.panelWidth = .points(10)
        #expect(alert.prepareForPresentation(from: host)?.panelSize.width == 33)
        alert.panelWidth = .automatic
        #expect(alert.prepareForPresentation(from: host)?.panelSize.width == defaultWidth)
        for invalidWidth in [CGFloat.zero, -10, .infinity, .nan] {
            alert.panelWidth = .points(invalidWidth)
            #expect(alert.prepareForPresentation(from: host)?.panelSize.width == defaultWidth)
        }
    }

    @Test func fixedPanelWidthRemeasuresEmbeddedContentAtTheResolvedWidth() throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(preferredStyle: .alert)
        alert.contentSizing = .sizeThatFits
        let content = UIViewController()
        content.view = WidthFittingView()
        alert.contentViewController = content
        alert.panelWidth = .points(300)
        #expect(alert.prepareForPresentation(from: host)?.contentSize == CGSize(width: 300, height: 150))

        alert.panelWidth = .points(900)
        host.view.frame.size.width = 240
        let layout = try #require(alert.prepareForPresentation(from: host))
        #expect(layout.panelSize.width == 216)
        #expect(layout.contentSize == CGSize(width: 216, height: 108))
        #expect(alert.contentViewControllerLayoutGuide.layoutFrame.width == 184)
    }

    @Test func panelWidthPoliciesShareOneCapAndUseTheCurrentRegion() throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 720, height: 800)
        let alert = AlertController(preferredStyle: .alert)
        func width() throws -> CGFloat { try #require(alert.prepareForPresentation(from: host)?.panelSize.width) }
        let automatic = try width()
        alert.maximumPanelWidth = 520
        #expect(try width() == automatic)
        alert.panelWidth = .fill
        #expect(try width() == 520)
        let body = UIViewController()
        body.preferredContentSize = CGSize(width: 540, height: 48)
        alert.contentViewController = body
        for policy: AlertController.PanelWidth in [.points(540), .content, .custom({ $0.availableWidth })] {
            alert.panelWidth = policy
            #expect(try width() == 520)
        }

        var lastContext: AlertController.PanelWidthContext?
        alert.panelWidth = .custom { context in
            lastContext = context
            return context.availableWidth * 0.5
        }
        #expect(try width() == 348)
        #expect(lastContext?.availableWidth == 696)
        #expect(lastContext?.automaticWidth == automatic)
        host.view.frame.size.width = 240
        #expect(try width() == 108)
        #expect(lastContext?.automaticWidth == 216)
        alert.maximumPanelWidth = 5
        #expect(try width() == 33)
        for invalid in [CGFloat.zero, -1, .nan, .infinity] {
            alert.maximumPanelWidth = invalid
            #expect(alert.maximumPanelWidth == nil)
            alert.panelWidth = .custom { _ in invalid }
            #expect(try width() == 216)
        }
        host.view.frame.size.width = 56
        #expect(alert.prepareForPresentation(from: host) == nil)
    }

    @Test func contentPolicyUsesDeclaredWidthsAndOnlyAddsBodyGuideInsets() throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 620, height: 800)
        let alert = AlertController(preferredStyle: .alert)
        func width() throws -> CGFloat { try #require(alert.prepareForPresentation(from: host)?.panelSize.width) }
        let automatic = try width()
        alert.panelWidth = .content
        let body = UIViewController()
        body.preferredContentSize.height = 44
        alert.contentViewController = body
        #expect(try width() == automatic)
        body.preferredContentSize.width = 300
        #expect(try width() == 300)
        alert.contentInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 20)
        let header = UIViewController()
        header.preferredContentSize = CGSize(width: 280, height: 30)
        alert.headerContentViewController = header
        #expect(try width() == 332)
        #expect(body.view.bounds.width == 300)
        alert.contentExtendsToPanelEdges = true
        #expect(try width() == 300)
        header.preferredContentSize.width = 420
        #expect(try width() == 420)
        #expect(body.view.bounds.width == 420)
        alert.headerContentViewController = nil
        #expect(try width() == 300)
        alert.headerContentViewController = header
        alert.contentViewController = nil
        #expect(try width() == 420)
        header.preferredContentSize.width = 0
        #expect(try width() == automatic)
    }

    @available(iOS 17.0, *)
    @Test func automaticPanelWidthTracksDynamicTypeWhilePointsStayFixed() throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 720, height: 800)
        let alert = AlertController(preferredStyle: .alert)
        func width() throws -> CGFloat { try #require(alert.prepareForPresentation(from: host)?.panelSize.width) }
        host.view.traitOverrides.preferredContentSizeCategory = .large
        host.view.updateTraitsIfNeeded()
        let normal = try width()
        var category: UIContentSizeCategory?
        alert.panelWidth = .custom { context in
            category = context.containerTraitCollection.preferredContentSizeCategory
            return context.automaticWidth
        }
        #expect(try width() == normal)
        #expect(category == .large)
        host.view.traitOverrides.preferredContentSizeCategory = .accessibilityLarge
        host.view.updateTraitsIfNeeded()
        let enlarged = try width()
        #expect(enlarged > normal)
        #expect(category == .accessibilityLarge)
        alert.panelWidth = .automatic
        #expect(try width() == enlarged)
        alert.maximumPanelWidth = normal
        #expect(try width() == normal)
        alert.panelWidth = .points(215)
        #expect(try width() == 215)
    }

    @Test func presentedCustomWidthStaysInsideTheAvailableRegion() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }

        let alert = AlertController(preferredStyle: .alert)
        let body = UIViewController()
        body.preferredContentSize.height = 80
        alert.contentViewController = body
        alert.contentExtendsToPanelEdges = true
        var availableWidth: CGFloat = 0
        alert.panelWidth = .custom { context in
            availableWidth = context.availableWidth
            return context.availableWidth * 0.75
        }
        await withCheckedContinuation { done in host.present(alert, animated: false) { done.resume() } }
        defer { host.dismiss(animated: false) }
        alert.view.layoutIfNeeded()
        let bounds = alert.view.safeAreaLayoutGuide.layoutFrame
        let frame = body.view.convert(body.view.bounds, to: alert.view)
        #expect(availableWidth > 0 && availableWidth <= bounds.width - 24 + 0.5)
        #expect(abs(frame.width - availableWidth * 0.75) < 0.5)
        #expect(bounds.contains(frame))
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            let divisions = alert.view.reservedRegions(kind: .division).map(\.frame)
            for division in divisions {
                #expect(!frame.intersects(division))
                if division.height >= bounds.height, division.midX > bounds.minX, division.midX < bounds.maxX {
                    let largerSide = max(division.minX - bounds.minX, bounds.maxX - division.maxX)
                    #expect(availableWidth <= largerSide - 24 + 0.5)
                }
            }
            print("Alert width in presented region:", availableWidth, "safe area:", bounds, "divisions:", divisions)
        }
        #endif
    }

    @Test func popoverUsesItsMeasuredWidthBeforeMeasuringEmbeddedContent() throws {
        guard #available(iOS 26, *) else { return }
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let anchor = UIBarButtonItem()
        let alert = AlertController(title: "Wheel Picker", message: "Choose a height", preferredStyle: .actionSheet)
        alert.setPopoverAnchor(anchor)
        alert.panelWidth = .points(240)
        alert.contentSizing = .sizeThatFits
        let body = UIViewController()
        let fittingView = WidthFittingView()
        body.view = fittingView
        alert.contentViewController = body
        alert.loadViewIfNeeded()

        let title = try #require(label("AlertController.titleLabel", in: alert.view))
        let panel = try #require(title.superview?.superview?.superview?.superview)
        var panelWidthDuringMeasurement: CGFloat?
        fittingView.onFit = { [weak panel] in
            panel?.layoutIfNeeded()
            panelWidthDuringMeasurement = panel?.bounds.width
        }

        let layout = try #require(withExtendedLifetime(anchor) { alert.prepareForPresentation(from: host) })
        #expect(panelWidthDuringMeasurement == layout.panelSize.width)
        #expect(layout.panelSize.width == 240)
        #expect(title.frame.width == 180)
    }

    @Test func presentedPopoverKeepsItsRequestedWidthWhenUIKitNarrowsIt() async throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        host.view.layoutIfNeeded()
        let alert = AlertController(preferredStyle: .actionSheet)
        let body = UIViewController()
        body.view = WidthFittingView()
        alert.contentViewController = body
        alert.contentExtendsToPanelEdges = true
        alert.contentSizing = .sizeThatFits
        alert.panelWidth = .custom { $0.availableWidth * 0.9 }
        let center = CGPoint(x: host.view.bounds.midX, y: host.view.bounds.midY)
        alert.setPopoverAnchor(host.view, sourceRect: CGRect(origin: center, size: CGSize(width: 1, height: 1)))
        alert.popoverPresentationController?.permittedArrowDirections = .left
        let planned = try #require(alert.prepareForPresentation(from: host))
        await withCheckedContinuation { done in host.present(alert, animated: false) { done.resume() } }
        defer { host.dismiss(animated: false) }
        for _ in 0..<3 {
            alert.invalidateContentSize()
            alert.view.layoutIfNeeded()
            let actual = try #require(alert.layoutSnapshot)
            #expect(actual.panelSize.width < planned.panelSize.width)
            #expect(alert.preferredContentSize.width == planned.panelSize.width)
            #expect(actual.contentSize.width == actual.panelSize.width)
            #expect(actual.contentSize.height == ceil(actual.panelSize.width / 2))
        }

        alert.panelWidth = .content
        body.preferredContentSize.width = 180
        #expect(alert.preferredContentSize.width == 180)
        let header = UIViewController()
        header.preferredContentSize = CGSize(width: 240, height: 40)
        alert.headerContentViewController = header
        #expect(alert.preferredContentSize.width == 240)
        alert.headerContentViewController = nil
        #expect(alert.preferredContentSize.width == 180)

        if #available(iOS 17.0, *) {
            alert.traitOverrides.preferredContentSizeCategory = .large
            alert.updateTraitsIfNeeded()
            alert.panelWidth = .automatic
            let normal = alert.preferredContentSize.width
            alert.traitOverrides.preferredContentSizeCategory = .accessibilityLarge
            alert.updateTraitsIfNeeded()
            alert.view.layoutIfNeeded()
            #expect(alert.preferredContentSize.width > normal)

            alert.traitOverrides.horizontalSizeClass = .regular
            alert.updateTraitsIfNeeded()
            alert.panelWidth = .custom { context in
                context.containerTraitCollection.horizontalSizeClass == .regular ? 260 : 180
            }
            #expect(alert.preferredContentSize.width == 260)
            alert.traitOverrides.horizontalSizeClass = .compact
            alert.updateTraitsIfNeeded()
            alert.view.layoutIfNeeded()
            #expect(alert.preferredContentSize.width == 180)
        }
    }

    @Test(arguments: [UIAlertController.Style.alert, .actionSheet])
    func customAlertBackdropHonorsDismissalSetting(style: UIAlertController.Style) async throws {
        let host = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }

        let alert = AlertController(title: "Backdrop", preferredStyle: style)
        #expect(alert.dismissesOnBackdropTap == (style == .actionSheet))
        if style == .actionSheet { alert.dismissesOnBackdropTap = false }
        var cancellations = 0
        alert.addAction(AlertAction(title: "Cancel", style: .cancel) { _ in cancellations += 1 })
        await withCheckedContinuation { done in host.presentAlert(alert, animated: false) { done.resume() } }
        defer { host.dismiss(animated: false) }

        alert.view.layoutIfNeeded()
        let outsidePanel = CGPoint(x: alert.view.bounds.minX + 1, y: alert.view.bounds.midY)
        let backdrop = try #require(alert.view.hitTest(outsidePanel, with: nil) as? UIControl)
        backdrop.sendActions(for: .touchUpInside)
        try #require(host.presentedViewController === alert && !alert.isBeingDismissed)
        #expect(cancellations == 0)

        alert.dismissesOnBackdropTap = true
        backdrop.sendActions(for: .touchUpInside)
        backdrop.sendActions(for: .touchUpInside)
        #expect(await waitForCondition { host.presentedViewController == nil && cancellations == 1 })
    }

    @Test func popoverDismissalNotifiesCancelOnce() throws {
        guard #available(iOS 26, *) else { return }
        let anchor = UIView()
        let alert = AlertController(preferredStyle: .actionSheet)
        var cancellations = 0
        alert.addAction(AlertAction(title: "Cancel", style: .cancel) { _ in cancellations += 1 })
        alert.setPopoverAnchor(anchor)
        let popover = try #require(alert.popoverPresentationController)
        alert.popoverPresentationControllerDidDismissPopover(popover)
        alert.presentationControllerDidDismiss(popover)
        #expect(cancellations == 1)
    }

    @Test func alertRegistersTextFieldsInOrderBeforeAndAfterLoading() throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(title: "Account", preferredStyle: .alert)
        #expect(alert.textFields == nil)
        #expect(AlertController(preferredStyle: .actionSheet).textFields == nil)

        var configuredField: UITextField?
        alert.addTextField { field in
            field.placeholder = "Email"
            field.keyboardType = .emailAddress
            configuredField = field
        }
        let first = try #require(alert.textFields?.first)
        #expect(first === configuredField)
        #expect(first.placeholder == "Email")
        #expect(first.keyboardType == .emailAddress)
        #expect(!alert.isViewLoaded)

        let content = UIViewController()
        content.preferredContentSize.height = 60
        alert.contentViewController = content
        let before = try #require(alert.prepareForPresentation(from: host))
        #expect(first.isDescendant(of: alert.view))
        alert.addTextField()
        let after = try #require(alert.prepareForPresentation(from: host))
        let fields = try #require(alert.textFields)
        #expect(fields.count == 2)
        #expect(fields[0] === first)
        let second = try #require(fields.last)
        #expect(second.isDescendant(of: alert.view))
        if #available(iOS 26, *) {
            #expect(second.bounds.width == alert.contentViewControllerLayoutGuide.layoutFrame.width - 28)
            #expect(second.bounds.height == 35)
        }
        #expect(after.contentSize == before.contentSize)
        #expect(after.panelSize.height > before.panelSize.height)
        let firstFrame = alert.view.convert(first.bounds, from: first)
        let secondFrame = alert.view.convert(second.bounds, from: second)
        #expect(firstFrame.maxY <= secondFrame.minY)
    }

    @Test func actionTitleAlignmentMovesTheRenderedTitle() throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(title: "Action", preferredStyle: .alert)
        let action = AlertAction(title: "Apply", attributedTitle: AttributedString("Apply changes"),
                                 titleTextAlignment: .left)
        alert.addAction(action)
        alert.prepareForPresentation(from: host)

        let button = try #require(self.button(in: alert.view))
        func titleCenter() -> CGFloat {
            button.layoutIfNeeded()
            guard let label = button.titleLabel else { return .nan }
            return button.convert(label.bounds, from: label).midX
        }
        #expect(button.configuration?.title == "Apply changes")
        #expect(button.configuration?.contentInsets.leading == 12)
        #expect(button.configuration?.contentInsets.trailing == 12)
        if #available(iOS 26, *) {
            #expect(button.configuration?.cornerStyle == .capsule)
            #expect(button.bounds.height >= 48)
        } else {
            #expect(button.configuration?.cornerStyle == .fixed)
            #expect(button.configuration?.background.cornerRadius == 0)
            #expect(button.bounds.height >= 44)
        }
        #expect(titleCenter() < button.bounds.midX - 20)
        action.titleTextAlignment = .right
        #expect(titleCenter() > button.bounds.midX + 20)

        button.semanticContentAttribute = .forceRightToLeft
        #expect(button.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        action.titleTextAlignment = .natural
        #expect(titleCenter() > button.bounds.midX + 20)
        action.titleTextAlignment = .left
        #expect(titleCenter() < button.bounds.midX - 20)
        action.titleTextAlignment = .center
        #expect(abs(titleCenter() - button.bounds.midX) < 2)
        action.titleTextAlignment = nil
        #expect(abs(titleCenter() - button.bounds.midX) < 2)
    }

    @Test func actionCanOverrideTheSystemVersionCornerStyle() throws {
        let alert = AlertController(preferredStyle: .alert)
        alert.addAction(AlertAction(title: "Apply", cornerStyle: .small))
        alert.loadViewIfNeeded()
        let button = try #require(self.button(in: alert.view))
        #expect(button.configuration?.cornerStyle == .small)
    }

    @Test func stackedAlertKeepsTheIconAtTheLeadingEdgeWhileTheTitleChangesAlignment() throws {
        guard #available(iOS 26, *) else { return }
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(title: "Actions", preferredStyle: .alert)
        alert.view.semanticContentAttribute = .forceLeftToRight
        let action = AlertAction(title: "Delete", style: .destructive, image: UIImage(systemName: "trash"),
                                 titleTextAlignment: .right)
        alert.addAction(action)
        alert.prepareForPresentation(from: host)

        let button = try #require(self.button(in: alert.view))
        let icon = try #require(button.subviews.compactMap { $0 as? UIImageView }.first { $0.image != nil })
        func titleFrame() -> CGRect {
            button.layoutIfNeeded()
            guard let title = button.titleLabel else { return .null }
            return button.convert(title.bounds, from: title)
        }

        #expect(abs(icon.frame.minX - 12) < 1)
        #expect(abs(button.bounds.maxX - titleFrame().maxX - 12) < 1)
        #expect(button.configuration?.baseBackgroundColor == .clear)

        action.titleTextAlignment = .left
        #expect(abs(titleFrame().minX - icon.frame.maxX - 12) < 1)
        #expect(abs(icon.frame.minX - 12) < 1)

        action.titleTextAlignment = nil
        let centeredTitle = titleFrame()
        #expect(abs(centeredTitle.midX - button.bounds.midX) < 1, "标题 \(centeredTitle)，按钮 \(button.bounds)")
        #expect(button.configuration?.baseBackgroundColor == .secondarySystemFill)
        action.isEnabled = false
        button.updateConfiguration()
        #expect(icon.tintColor == .tertiaryLabel)
    }

    @Test func modernAlertCentersStandaloneTitleAndHonorsExplicitInsets() throws {
        guard #available(iOS 26, *) else { return }
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(title: "Country Picker", preferredStyle: .alert)
        let content = UIViewController()
        content.preferredContentSize.height = 264
        alert.contentViewController = content
        let layout = try #require(alert.prepareForPresentation(from: host))
        let title = try #require(label("AlertController.titleLabel", in: alert.view))
        #expect(layout.contentSize == CGSize(width: 320, height: 264))
        #expect(alert.contentViewControllerLayoutGuide.layoutFrame.width == 288)
        #expect(title.textAlignment == .center)
        #expect(title.font == .preferredFont(forTextStyle: .body))
        #expect(title.bounds.width == 260)

        content.preferredContentSize.width = 120
        let fixedWidthLayout = alert.prepareForPresentation(from: host)
        #expect(fixedWidthLayout?.contentSize.width == 120)
        content.preferredContentSize.width = 310
        #expect(alert.prepareForPresentation(from: host)?.contentSize.width == 310)
        content.preferredContentSize.width = 0

        let guideInsets = alert.contentInsets
        alert.contentInsets = guideInsets
        alert.message = "Choose a country"
        let insetLayout = alert.prepareForPresentation(from: host)
        #expect(insetLayout?.contentSize.width == 288)
        #expect(title.textAlignment == .natural)
        #expect(title.bounds.width == 288)
        #expect(alert.contentViewControllerLayoutGuide.layoutFrame.width == 288)
    }

    @Test func fullWidthContentIsMeasuredAtPanelWidthWhileGuideKeepsItsInsets() throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(title: "List", preferredStyle: .alert)
        alert.contentInsets = UIEdgeInsets(top: 16, left: 24, bottom: 16, right: 12)
        alert.contentSizing = .sizeThatFits
        alert.contentExtendsToPanelEdges = true
        let content = UIViewController()
        let fittingView = WidthFittingView()
        content.view = fittingView
        alert.contentViewController = content

        let layout = try #require(alert.prepareForPresentation(from: host))
        let width = layout.panelSize.width
        #expect(layout.measurementWidth == width)
        #expect(fittingView.frame == CGRect(x: 0, y: 0, width: width, height: ceil(width / 2)))
        #expect(alert.contentViewControllerLayoutGuide.layoutFrame == CGRect(x: 24, y: 0, width: width - 36, height: ceil(width / 2)))

        alert.contentExtendsToPanelEdges = false
        content.preferredContentSize.width = 120
        alert.prepareForPresentation(from: host)
        #expect(fittingView.frame == CGRect(x: (width - 120) / 2 + 6, y: 0, width: 120, height: 60))
    }

    @Test(arguments: [UIAlertController.Style.alert, .actionSheet])
    func modernCenteredAlertIncludesDetailWithBottomPadding(style: UIAlertController.Style) throws {
        guard #available(iOS 26, *) else { return }
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let alert = AlertController(title: "Review", preferredStyle: style)
        alert.addAction(AlertAction(title: "Cancel", style: .cancel))
        let initial = try #require(alert.prepareForPresentation(from: host))

        alert.detailMessage = "稍后可在设置中修改。"
        let layout = try #require(alert.prepareForPresentation(from: host))
        let detail = try #require(label("AlertController.detailMessageLabel", in: alert.view))
        let panel = try #require(detail.superview)

        #expect(panel.subviews.contains { $0 is UIVisualEffectView })
        #expect(panel.bounds.size == layout.panelSize)
        #expect(layout.panelSize.height > initial.panelSize.height)
        #expect(detail.frame.minY > initial.panelSize.height)
        #expect(panel.bounds.contains(detail.frame))
        #expect(abs(panel.bounds.maxY - detail.frame.maxY - 12) < 0.5)
        #expect(detail.textColor == .label)
    }

    @Test func clearingAttributedTextRestoresPlainTextAndDefaultStyles() throws {
        let alert = AlertController(title: "Plain title", message: "Plain message", preferredStyle: .alert)
        alert.detailMessage = "Plain detail"
        alert.loadViewIfNeeded()

        let headings = try #require(label("AlertController.titleLabel", in: alert.view))
        let message = try #require(label("AlertController.messageLabel", in: alert.view))
        let detail = try #require(label("AlertController.detailMessageLabel", in: alert.view))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .natural
        paragraph.lineSpacing = 6
        let rich = NSAttributedString(string: "Rich", attributes: [
            .font: UIFont.boldSystemFont(ofSize: 26),
            .foregroundColor: UIColor.systemIndigo,
            .paragraphStyle: paragraph,
        ])

        alert.titleMaximumLineCount = 2
        alert.titleLineBreakMode = .byTruncatingMiddle
        alert.attributedTitle = rich
        alert.attributedMessage = rich
        alert.attributedDetailMessage = rich
        #expect(headings.numberOfLines == 2)
        #expect(headings.lineBreakMode == .byTruncatingMiddle)
        #expect(message.font.pointSize == 26)
        #expect(message.textColor == .systemIndigo)
        let style = message.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.lineSpacing == 6)
        #expect(style?.alignment == .natural)
        #expect(detail.text == "Rich")

        alert.attributedTitle = nil
        alert.attributedMessage = nil
        alert.attributedDetailMessage = nil
        #expect(headings.text == "Plain title")
        #expect(message.text == "Plain message")
        #expect(detail.text == "Plain detail")
        #expect(message.font == .preferredFont(forTextStyle: .subheadline))
        #expect(message.textColor == .secondaryLabel)
        let defaultAlignment: NSTextAlignment
        if #available(iOS 26, *) { defaultAlignment = .natural }
        else { defaultAlignment = .center }
        #expect(headings.textAlignment == defaultAlignment)
        #expect(message.textAlignment == defaultAlignment)
        #expect(detail.textAlignment == .center)
    }

    private func label(_ identifier: String, in view: UIView) -> UILabel? {
        if view.accessibilityIdentifier == identifier { return view as? UILabel }
        for child in view.subviews {
            if let match = label(identifier, in: child) { return match }
        }
        return nil
    }

    private func button(in view: UIView) -> UIButton? {
        if let button = view as? UIButton { return button }
        for child in view.subviews {
            if let match = button(in: child) { return match }
        }
        return nil
    }
}

private final class WidthFittingView: UIView {
    var onFit: (() -> Void)?

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        onFit?()
        return CGSize(width: size.width, height: size.width / 2)
    }
}
