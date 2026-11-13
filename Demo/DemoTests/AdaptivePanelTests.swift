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
                host.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceIdiom: idiom),
                    UITraitCollection(horizontalSizeClass: horizontal),
                    UITraitCollection(verticalSizeClass: vertical),
                ]), forChild: panel)
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
        await withCheckedContinuation { continuation in host.dismiss(animated: false) { continuation.resume() } }
    }
    @Test func customDetentsClampAndDeactivate() {
        let context = AdaptivePanelContext(containerBounds: CGRect(x: 0, y: 0, width: 400, height: 800),
            availableRegion: CGRect(x: 0, y: 0, width: 400, height: 600), divisionRegions: [],
            containerTraitCollection: UITraitCollection(verticalSizeClass: .compact), maximumDetentValue: 600,
            hingeAngle: .pi / 2, hingeState: .partiallyOpen)
        #expect(AdaptivePanelDetent.medium().resolvedValue(in: context) == nil)
        #expect(AdaptivePanelDetent.large().resolvedValue(in: context) == 600)
        #expect(AdaptivePanelDetent.custom(identifier: "oversized") { _ in 900 }.resolvedValue(in: context) == 600)
        #expect(AdaptivePanelDetent.custom(identifier: "invalid") { _ in .nan }.resolvedValue(in: context) == nil)
        #expect(AdaptivePanelDetent.custom(identifier: "fold") { $0.hingeAngle == .pi / 2 ? 240 : nil }.resolvedValue(in: context) == 240)
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
        #expect(!panel.backdrop.isHidden)
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
        host.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: .regular),
            UITraitCollection(verticalSizeClass: .regular),
        ]), forChild: panel)
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
        host.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: .compact),
            UITraitCollection(verticalSizeClass: .compact),
        ]), forChild: panel)
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
