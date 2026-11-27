import Testing
import UIKit
@testable import QuickLayoutKitUIKit
@testable import Demo

@MainActor
struct AdaptivePanelTests {
    /// 覆盖宿主缩放与尺寸类别切换，不把设备名称或屏幕分辨率用于组件布局。
    @Test func containerMatrixPreservesBoundsAndContent() {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 951, height: 669)
        let field = UITextField()
        field.text = "旋转与缩放后保留"
        let panel = AdaptivePanelController(contentView: field)
        panel.detents = [.custom(identifier: "small") { $0.maximumDetentValue / 3 }, .medium(), .large()]
        panel.show(in: host, animated: false)
        defer { panel.dismiss(animated: false) }
        for idiom in [UIUserInterfaceIdiom.phone, .pad] {
            for size in [CGSize(width: 320, height: 568), CGSize(width: 874, height: 402),
                         CGSize(width: 951, height: 669), CGSize(width: 669, height: 951),
                         CGSize(width: 834, height: 1194), CGSize(width: 1194, height: 834),
                         CGSize(width: 540, height: 720), CGSize(width: 320, height: 180)] {
                let horizontal: UIUserInterfaceSizeClass = size.width < 600 ? .compact : .regular
                let vertical: UIUserInterfaceSizeClass = size.height < 500 ? .compact : .regular
                panel.traitOverrides.userInterfaceIdiom = idiom
                panel.traitOverrides.horizontalSizeClass = horizontal
                panel.traitOverrides.verticalSizeClass = vertical
                host.view.frame.size = size
                host.view.layoutIfNeeded()
                let identifiers: [AdaptivePanelDetent.Identifier] = ["small", .medium, .large]
                for identifier in identifiers {
                    panel.selectDetent(identifier, animated: false)
                    #expect(panel.panelFrame.width > 0 && panel.panelFrame.height > 0)
                    #expect(host.view.bounds.contains(panel.panelFrame))
                    #expect(panel.context?.containerTraitCollection.horizontalSizeClass == horizontal)
                    #expect(panel.context?.containerTraitCollection.verticalSizeClass == vertical)
                    #expect(field.text == "旋转与缩放后保留")
                    if vertical == .compact { #expect(panel.selectedDetentIdentifier != .medium) }
                }
            }
        }
    }

    /// 在真实 presentation 的解析回调中比较内建档位，避免伪造系统上下文。
    @Test func nativeGeometryProbe() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let content = UIViewController()
        content.modalPresentationStyle = .pageSheet
        let sheet = try #require(content.sheetPresentationController)
        sheet.prefersPageSizing = true
        sheet.prefersEdgeAttachedInCompactHeight = true
        var maximum: CGFloat = 0
        var nativeMedium: CGFloat?
        sheet.detents = [.custom(identifier: .init("probe")) { context in
            maximum = context.maximumDetentValue
            nativeMedium = UISheetPresentationController.Detent.medium().resolvedValue(in: context)
            var divisions: [CGRect] = []
            if #available(iOS 27.1, *) { divisions = host.view.reservedRegions(kind: .division, options: .includeInactive).map(\.frame) }
            let comparison = AdaptivePanelContext(containerBounds: window.bounds, availableRegion: window.safeAreaLayoutGuide.layoutFrame,
                divisionRegions: divisions, containerTraitCollection: context.containerTraitCollection,
                maximumDetentValue: maximum, hingeAngle: nil, hingeState: .unavailable)
            let panelMedium = AdaptivePanelDetent.medium().resolvedValue(in: comparison)
            #expect(abs((nativeMedium ?? 0) - (panelMedium ?? 0)) < 0.5)
            return context.maximumDetentValue / 3
        }, .medium(), .large()]
        sheet.selectedDetentIdentifier = .medium
        await withCheckedContinuation { continuation in
            host.present(content, animated: false) { continuation.resume() }
        }
        let container = try #require(sheet.containerView)
        #expect(maximum > 0)
        print("NATIVE_RESOLVE maximum=\(maximum) medium=\(String(describing: nativeMedium))")
        print("NATIVE_PROBE frame=\(content.view.convert(content.view.bounds, to: container)) container=\(container.bounds) safe=\(container.safeAreaInsets) contentSafe=\(content.view.safeAreaInsets) windowSafe=\(window.safeAreaInsets) readable=\(container.readableContentGuide.layoutFrame) contentTraits=\(content.traitCollection)")
        let nativeIDs: [UISheetPresentationController.Detent.Identifier] = [.init("probe"), .medium, .large]
        var nativeFrames: [CGRect] = []
        for id in nativeIDs {
            sheet.selectedDetentIdentifier = id
            container.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            nativeFrames.append(content.view.convert(content.view.bounds, to: window))
        }
        // iOS 26 的系统 sheet 分两层裁切上下角。按窗口坐标的可见半径逐角比较。
        func corners(of view: UIView) -> [CGFloat] {
            let scale = view.convert(view.bounds, to: window).width / max(1, view.bounds.width)
            if #available(iOS 26, *) {
                return [UIRectCorner.topLeft, .topRight, .bottomLeft, .bottomRight].map { view.effectiveRadius(corner: $0) * scale }
            }
            return [CACornerMask.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                .map { view.layer.maskedCorners.contains($0) ? view.layer.cornerRadius * scale : 0 }
        }
        let preferences: [CGFloat?] = [nil, 24]
        let cornerIDs: [UISheetPresentationController.Detent.Identifier] = [.medium, .large]
        var nativeCorners: [[CGFloat]] = []
        for preference in preferences {
            sheet.preferredCornerRadius = preference
            for id in cornerIDs {
                sheet.selectedDetentIdentifier = id
                container.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(160))
                var ancestor: UIView? = content.view
                let frame = content.view.convert(content.view.bounds, to: window)
                var radii = Array(repeating: CGFloat.zero, count: 4)
                while let view = ancestor, view !== window {
                    if view.layer.masksToBounds, view.convert(view.bounds, to: window).equalTo(frame) {
                        radii = zip(radii, corners(of: view)).map(max)
                    }
                    ancestor = view.superview
                }
                nativeCorners.append(radii)
                print("NATIVE_CORNERS \(id.rawValue) preference=\(String(describing: preference)) radii=\(radii)")
            }
        }
        await withCheckedContinuation { continuation in host.dismiss(animated: false) { continuation.resume() } }

        let customContent = UIViewController()
        await withCheckedContinuation { continuation in
            host.presentSheet(customContent, animated: false) { sheet in
                sheet.prefersPageSizing = true
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.detents = [.custom(identifier: "probe") { $0.maximumDetentValue / 3 }, .medium(), .large()]
            } completion: { continuation.resume() }
        }
        let customSheet = try #require(customContent.customSheetPresentationController)
        let surface = try #require(customSheet.presentedView)
        let customIDs: [SheetPresentationController.Detent.Identifier] = [.medium, .large]
        for (p, preference) in preferences.enumerated() {
            customSheet.preferredCornerRadius = preference
            for (d, id) in customIDs.enumerated() {
                customSheet.selectedDetentIdentifier = id
                customSheet.containerView?.layoutIfNeeded()
                let actual = corners(of: surface)
                let expected = nativeCorners[p * cornerIDs.count + d]
                print("CUSTOM_CORNERS \(id.rawValue) preference=\(String(describing: preference)) radii=\(actual)")
                for (a, b) in zip(actual, expected) { #expect(abs(a - b) <= 1) }
            }
        }
        await withCheckedContinuation { continuation in customContent.dismiss(animated: false) { continuation.resume() } }
        let panel = AdaptivePanelController(contentView: UIView())
        panel.safeAreaSource = .window
        panel.detents = [.custom(identifier: "probe") { $0.maximumDetentValue / 3 }, .medium(), .large()]
        panel.show(in: host, animated: false)
        defer { panel.dismiss(animated: false) }
        let ids: [AdaptivePanelDetent.Identifier] = ["probe", .medium, .large]
        try await Task.sleep(for: .milliseconds(350))
        for (id, expected) in zip(ids, nativeFrames) {
            panel.selectDetent(id, animated: false)
            panel.view.layoutIfNeeded()
            let actual = panel.view.convert(panel.panelFrame, to: window)
            print("PANEL_EDGES \(id.rawValue) UIKit=\(expected) panel=\(actual)")
            if id == .medium || id == .large {
                for (p, preference) in preferences.enumerated() {
                    panel.preferredCornerRadius = preference
                    panel.view.layoutIfNeeded()
                    let expectedCorners = nativeCorners[p * cornerIDs.count + (id == .medium ? 0 : 1)]
                    let actualCorners = corners(of: panel.surface)
                    print("PANEL_CORNERS \(id.rawValue) preference=\(String(describing: preference)) radii=\(actualCorners)")
                    for (a, b) in zip(actualCorners, expectedCorners) { #expect(abs(a - b) <= 1) }
                }
            }
            #expect(abs(actual.minX - expected.minX) <= 1)
            #expect(abs(actual.maxX - expected.maxX) <= 1)
            #expect(abs(actual.minY - expected.minY) <= 1)
            #expect(abs(actual.maxY - expected.maxY) <= 1)
        }
        if window.traitCollection.horizontalSizeClass == .compact, window.traitCollection.verticalSizeClass == .regular,
           window.traitCollection.userInterfaceIdiom == .phone, panel.context?.hingeState == .unavailable {
            panel.selectDetent(.medium, animated: false)
            let reference = nativeFrames[1]
            panel.horizontalInset = 21
            panel.view.layoutIfNeeded()
            #expect(abs(panel.panelFrame.minX - 21) <= 1)
            #expect(abs(panel.panelFrame.maxY - reference.maxY) <= 1)
            panel.bottomInset = 13
            panel.view.layoutIfNeeded()
            #expect(abs(panel.panelFrame.width - (window.bounds.width - 42)) <= 1)
            #expect(abs(panel.panelFrame.maxY - (window.bounds.maxY - 13)) <= 1)
        }
    }
    @Test func detentsAcceptAnIndependentResolutionContext() {
        final class Context: NSObject, SheetPresentationControllerDetentResolutionContext {
            var containerTraitCollection = UITraitCollection(verticalSizeClass: .regular)
            let maximumDetentValue: CGFloat = 600
        }
        final class Subclass: AdaptivePanelController.Detent {}
        let context = Context()
        let anonymous = AdaptivePanelController.Detent.custom { $0.maximumDetentValue / 3 }
        let explicitNil = AdaptivePanelController.Detent.custom(identifier: nil) { _ in nil }
        let quarter: (any SheetPresentationControllerDetentResolutionContext) -> CGFloat? = { $0.maximumDetentValue / 4 }
        let named = AdaptivePanelController.Detent.custom(identifier: .init("quarter"), resolver: quarter)
        let sheetDetent: SheetPresentationController.Detent = named
        let sharedID: SheetPresentationController.Detent.Identifier = named.identifier
        #expect(sheetDetent === named)
        #expect(sharedID == "quarter")
        let medium: Subclass = .medium()
        let large: Subclass = .large()
        #expect(medium.identifier == .medium)
        #expect(large.identifier == .large)
        #expect(anonymous.identifier != explicitNil.identifier)
        #expect(anonymous.resolvedValue(in: context) == 200)
        #expect(explicitNil.resolvedValue(in: context) == nil)
        #expect(named.identifier.rawValue == "quarter")
        #expect(named.resolvedValue(in: context) == 150)
        #expect(large.resolvedValue(in: context) == 600)
        #expect(medium.resolvedValue(in: context) != nil)
        context.containerTraitCollection = UITraitCollection(verticalSizeClass: .compact)
        #expect(medium.resolvedValue(in: context) == nil)
    }

    @Test func backgroundEffectTracksTheSelectedDetentInAWindow() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        let panel = AdaptivePanelController(contentView: UIView())
        let compact = AdaptivePanelController.Detent.custom { $0.maximumDetentValue / 3 }
        let large = AdaptivePanelController.Detent.large()
        panel.detents = [compact, large]
        panel.selectedDetentIdentifier = compact.identifier
        panel.show(in: host, animated: false)
        defer { panel.dismiss(animated: false) }
        func material() -> UIVisualEffectView? {
            panel.view.layoutIfNeeded()
            return panel.surface.subviews.compactMap { $0 as? UIVisualEffectView }.first
        }
        #expect(material() == nil)
        large.backgroundEffect = UIBlurEffect(style: .dark)
        #expect(material() == nil)
        compact.backgroundEffect = UIBlurEffect(style: .light)
        let current = try #require(material())
        #expect(current.effect is UIBlurEffect)
        #expect(panel.surface.subviews.first === current)
        #expect(!current.isUserInteractionEnabled)
        #expect(current.frame == panel.surface.bounds)
        compact.backgroundEffect = nil
        #expect(material() == nil)
        panel.selectDetent(.large, animated: false)
        #expect(material()?.effect is UIBlurEffect)
        panel.detents = [.custom(identifier: .large) { _ in nil }]
        #expect(material() == nil)
        #expect(panel.surface.backgroundColor == .secondarySystemGroupedBackground)

        panel.view.traitOverrides.verticalSizeClass = .compact
        panel.contentViewController.view.traitOverrides.verticalSizeClass = .regular
        panel.invalidateDetents()
        panel.view.layoutIfNeeded()
        let context = try #require(panel.context)
        #expect(context.containerTraitCollection.verticalSizeClass == .compact)
        #expect(AdaptivePanelController.Detent.medium().resolvedValue(in: context) == nil)
        let sheetDetent = SheetPresentationController.Detent.custom { $0.maximumDetentValue / 3 }
        #expect(sheetDetent.resolvedValue(in: context) == compact.resolvedValue(in: context))
    }

    @Test func customDetentsClampAndDeactivate() {
        let division = CGRect(x: 0, y: 224, width: 400, height: 16)
        let context = AdaptivePanelContext(containerBounds: CGRect(x: 0, y: 0, width: 400, height: 800),
            availableRegion: CGRect(x: 0, y: 0, width: 400, height: 600), divisionRegions: [division],
            containerTraitCollection: UITraitCollection(verticalSizeClass: .compact), maximumDetentValue: 600,
            hingeAngle: .pi / 2, hingeState: .partiallyOpen)
        #expect(AdaptivePanelDetent.medium().resolvedValue(in: context) == nil)
        #expect(AdaptivePanelDetent.large().resolvedValue(in: context) == 600)
        #expect(AdaptivePanelDetent.custom(identifier: "oversized") { _ in 900 }.resolvedValue(in: context) == 600)
        #expect(AdaptivePanelDetent.custom(identifier: "invalid") { _ in .nan }.resolvedValue(in: context) == nil)
        let folded = AdaptivePanelDetent.custom(identifier: "fold") { context in
            context.hingeAngle == .pi / 2 ? context.divisionRegions.first?.maxY : nil
        }
        let sheetContext = SheetDetentContext(availableRegion: context.availableRegion, divisionRegions: [division],
            maximumDetentValue: context.maximumDetentValue, containerTraitCollection: context.containerTraitCollection)
        #expect(folded.resolvedValue(in: context) == 240)
        #expect(folded.resolvedValue(in: sheetContext) == nil)
    }

    @Test func divisionsRespectHostCoordinatesAndVisibleExtent() {
        let bounds = CGRect(x: 20, y: 40, width: 800, height: 600)
        let vertical = CGRect(x: 400, y: 0, width: 40, height: 900)
        let regions = AdaptivePanelContext.regions(in: bounds, divisions: [vertical])
        #expect(regions == [CGRect(x: 20, y: 40, width: 380, height: 600), CGRect(x: 440, y: 40, width: 380, height: 600)])
        let horizontal = CGRect(x: 0, y: 300, width: 1000, height: 40)
        #expect(AdaptivePanelContext.regions(in: bounds, divisions: [horizontal]).map(\.height) == [260, 300])
        #expect(AdaptivePanelContext.regions(in: bounds, divisions: [CGRect(x: 400, y: 60, width: 40, height: 100)]) == [bounds])
        // division 去除系统建议边距后可能只剩分隔线，仍需按宿主坐标切分。
        #expect(AdaptivePanelContext.regions(in: bounds, divisions: [CGRect(x: 420, y: 0, width: 0, height: 900)])
            == [CGRect(x: 20, y: 40, width: 400, height: 600), CGRect(x: 420, y: 40, width: 400, height: 600)])
        #expect(AdaptivePanelContext.regions(in: bounds, divisions: [CGRect(x: 0, y: 320, width: 1000, height: 0)]).map(\.height) == [280, 320])
    }

    @Test func embeddedPanelPassesThroughBackgroundAndRetainsContentWhenResized() throws {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        let content = UIViewController()
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        field.text = "保留输入"
        content.view.addSubview(field)
        let panel = AdaptivePanelController(contentViewController: content)
        panel.detents = [.custom(identifier: "small") { _ in 200 }, .large()]
        panel.selectedDetentIdentifier = "small"
        panel.show(in: host, animated: false)
        host.view.layoutIfNeeded()
        panel.view.layoutIfNeeded()
        #expect(panel.parent === host)
        #expect(content.parent === panel)
        // 自定义档位约定的是逻辑内容高度；页面卡片的最终显示边界另由容器决定。
        #expect(panel.currentHeight == 200)
        #expect(panel.view.hitTest(CGPoint(x: 20, y: 20), with: nil) == nil)
        #expect(panel.view.hitTest(CGPoint(x: 200, y: 700), with: nil) != nil)
        panel.largestUndimmedDetentIdentifier = "small"
        panel.selectDetent(.large, animated: false)
        #expect(panel.selectedDetentIdentifier == .large)
        #expect(panel.backdrop.isUserInteractionEnabled)
        #expect(panel.surface.accessibilityViewIsModal)
        host.view.frame.size = CGSize(width: 700, height: 500)
        host.view.layoutIfNeeded()
        panel.view.layoutIfNeeded()
        #expect(panel.contentViewController === content)
        #expect(field.text == "保留输入")
        #expect(panel.panelFrame.maxY <= 500)
        panel.dismiss(animated: false)
        #expect(panel.parent == nil)
        #expect(panel.view.superview == nil)
        panel.show(in: host, animated: false)
        #expect(panel.parent === host)
        #expect(content.parent === panel)
        panel.dismiss(animated: false)
    }

    @Test func invalidSelectionFallsBackAndDismissVetoPreservesPanel() {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 400, height: 700)
        let panel = AdaptivePanelController(contentView: UIView())
        panel.detents = [.custom(identifier: "small") { _ in 180 }, .large()]
        panel.selectedDetentIdentifier = "removed"
        panel.show(in: host, animated: false)
        #expect(panel.selectedDetentIdentifier == "small")
        panel.shouldDismiss = { false }
        var attempts = 0
        panel.onDismissAttempt = { attempts += 1 }
        panel.attemptDismiss()
        #expect(attempts == 1)
        #expect(panel.parent === host)
        panel.detents = [.custom(identifier: "inactive") { _ in nil }]
        panel.view.layoutIfNeeded()
        #expect(panel.selectedDetentIdentifier == .large)
        panel.dismiss(animated: false)
    }

    @Test func routeBuildsIndependentComparisonPage() {
        #expect(MainRouter().makeViewController(for: .adaptivePanel) is AdaptivePanelExampleViewController)
    }

    @Test func floatingWidthFollowsContainerAndExplicitContentPreference() {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 900, height: 800)
        let content = UIViewController()
        let panel = AdaptivePanelController(contentViewController: content)
        panel.show(in: host, animated: false)
        panel.traitOverrides.horizontalSizeClass = .regular
        panel.traitOverrides.verticalSizeClass = .regular
        panel.view.layoutIfNeeded()
        let wide = panel.panelFrame.width
        host.view.frame.size = CGSize(width: 360, height: 520)
        host.view.layoutIfNeeded()
        panel.view.layoutIfNeeded()
        #expect(panel.panelFrame.width < wide)
        #expect(host.view.bounds.contains(panel.panelFrame))
        // 只有调用方明确选择表单模式时，内容声明的宽度才成为目标。
        content.preferredContentSize = CGSize(width: 180, height: 240)
        panel.prefersPageSizing = false
        panel.view.layoutIfNeeded()
        #expect(panel.panelFrame.width == 180)
        #expect(panel.panelFrame.height == 240)
        panel.traitOverrides.horizontalSizeClass = .compact
        panel.traitOverrides.verticalSizeClass = .compact
        panel.prefersPageSizing = true
        panel.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        panel.view.layoutIfNeeded()
        #expect(panel.panelFrame.width == 180)
        panel.widthFollowsPreferredContentSizeWhenEdgeAttached = false
        panel.view.layoutIfNeeded()
        #expect(panel.panelFrame.width == panel.context?.availableRegion.width)
        panel.dismiss(animated: false)
    }
}
