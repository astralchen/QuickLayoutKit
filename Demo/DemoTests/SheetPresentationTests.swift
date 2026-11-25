import Testing
import UIKit
import QuickLayoutKit
@testable import Demo

@Suite(.serialized)
@MainActor
struct SheetPresentationTests {
    /// 在当前模拟器的真实窗口呈现，Device Hub 可在每轮开始前切换姿态。
    @Test func comparesDetentsInCurrentDevicePose() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        host.view.backgroundColor = .systemGroupedBackground
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        var pose = ArrangementDevicePose.unknown
        var angle: CGFloat?
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            window.addInteraction(UIHingeInteraction { _, update in
                angle = update.hinge?.angle
                switch update.hinge?.status {
                case .closed: pose = .closed
                case .fullyOpen: pose = .open
                case .partiallyOpen: pose = .partial
                default: pose = .unknown
                }
            })
        }
        #endif
        var reference: [CGRect] = []
        var bottomInsets: [CGFloat] = []
        for native in [true, false] {
            let content = SheetExampleContent()
            content.custom.isHidden = true
            var divisor: CGFloat = 3
            let ids: [SheetPresentationController.Detent.Identifier] = ["third", .medium, .large]
            if native {
                content.modalPresentationStyle = .pageSheet
                let sheet = try #require(content.sheetPresentationController)
                sheet.detents = [.custom(identifier: .init("third")) { context in
                    context.maximumDetentValue / divisor
                }, .medium(), .large()]
                sheet.prefersPageSizing = true
                sheet.prefersEdgeAttachedInCompactHeight = true
                await withCheckedContinuation { continuation in
                    host.present(content, animated: false) { continuation.resume() }
                }
            } else {
                await withCheckedContinuation { continuation in
                    host.presentSheet(content, animated: false) { sheet in
                        sheet.detents = [.custom(identifier: "third") { $0.maximumDetentValue / divisor }, .medium(), .large()]
                        sheet.prefersPageSizing = true
                        sheet.prefersEdgeAttachedInCompactHeight = true
                    } completion: { continuation.resume() }
                }
            }
            // 等待首次铰链更新，也让旋转后的系统安全区稳定。
            try await Task.sleep(for: .milliseconds(350))
            let system = native ? content.sheetPresentationController : nil
            let custom = content.customSheetPresentationController
            #expect(native || custom != nil)
            let nativeIDs: [UISheetPresentationController.Detent.Identifier] = [.init("third"), .medium, .large]
            // 普通测试对照当前姿态。联动 Device Hub 时，保持同一个模态实例跨姿态取样。
            let poses = ProcessInfo.processInfo.environment["SHEET_TEST_POSES"]?.components(separatedBy: ",") ?? ["current"]
            for (sampleIndex, requested) in poses.enumerated() {
                @MainActor func currentPose() -> String {
                    // 外屏切换中可能先收到 closed，但 scene 仍属于内屏。按测试设备的
                    // 实际屏幕短边复核，只有确认活动显示器后才接受姿态。
                    let name = pose.resolved(in: window).rawValue
                    let key = name == "closed" ? "SHEET_OUTER_SHORT_SIDE" : "SHEET_INNER_SHORT_SIDE"
                    if let raw = ProcessInfo.processInfo.environment[key], let length = Double(raw),
                       abs(min(window.bounds.width, window.bounds.height) - length) > 1 { return "switchingDisplay" }
                    if name == "closed" { return window.bounds.width > window.bounds.height ? "closedLandscape" : "closedPortrait" }
                    if name == "openPortrait" && window.bounds.width > window.bounds.height { return "switchingDisplay" }
                    if name == "openLandscape" && window.bounds.width < window.bounds.height { return "switchingDisplay" }
                    return name
                }
                if requested != "current" {
                    print("SHEET_WAIT \(native ? "UIKit" : "Custom") \(requested)")
                    let deadline = Date().addingTimeInterval(75)
                    var stableSince = Date()
                    var lastRequest = Date.distantPast
                    var priorBounds = window.bounds
                    var priorInsets = window.safeAreaInsets
                    // 铰链常先于内外屏切换上报。等窗口、安全区和姿态同时稳定后取样。
                    while Date() < deadline {
                        let observed = currentPose()
                        if observed != requested && observed != "switchingDisplay" && observed != "unknown"
                            && Date().timeIntervalSince(lastRequest) >= 8 {
                            print("SHEET_ADJUST \(requested) \(observed)")
                            lastRequest = Date()
                        }
                        if observed != requested || window.bounds != priorBounds || window.safeAreaInsets != priorInsets {
                            stableSince = Date()
                            priorBounds = window.bounds
                            priorInsets = window.safeAreaInsets
                        }
                        if Date().timeIntervalSince(stableSince) >= 2 { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    try #require(currentPose() == requested && Date().timeIntervalSince(stableSince) >= 2)
                    print("SHEET_REACHED \(native ? "UIKit" : "Custom") \(requested)")
                }
                divisor = 3
                system?.invalidateDetents()
                custom?.invalidateDetents()
                for (index, id) in (ids + [ids[0]]).enumerated() {
                    if index == 3 {
                        divisor = 4
                        system?.invalidateDetents()
                        custom?.invalidateDetents()
                    }
                    system?.selectedDetentIdentifier = nativeIDs[index % 3]
                    custom?.selectedDetentIdentifier = id
                    content.presentationController?.containerView?.layoutIfNeeded()
                    // UIKit 在紧凑高度中从全高回到自定义档位时会再布局内容安全区。
                    if window.traitCollection.verticalSizeClass == .compact {
                        try await Task.sleep(for: .milliseconds(650))
                    } else {
                        try await Task.sleep(for: .milliseconds(180))
                    }
                    if requested != "current" { try #require(currentPose() == requested) }
                    let rect = content.view.convert(content.view.bounds, to: window)
                    let degrees = angle.map { String(format: "%.1f", $0 * 180 / .pi) } ?? "—"
                    print("SHEET_POSE \(native ? "UIKit" : "Custom") \(pose.resolved(in: window).rawValue) \(degrees) window=\(window.bounds) \(id.rawValue) divisor=\(divisor) frame=\(rect)")
                    if requested != "current" && id == .medium {
                        print("SHEET_CAPTURE \(native ? "UIKit" : "Custom") \(requested)")
                        try await Task.sleep(for: .seconds(1))
                    }
                    if native {
                        reference.append(rect)
                        bottomInsets.append(content.view.safeAreaInsets.bottom)
                    } else {
                        if window.traitCollection.userInterfaceIdiom == .pad {
                            let expectedInset = bottomInsets[sampleIndex * 4 + index]
                            let actualInset = content.view.safeAreaInsets.bottom
                            #expect(abs(actualInset - expectedInset) <= 1,
                                    "content bottom \(actualInset), UIKit \(expectedInset), additional \(content.additionalSafeAreaInsets.bottom)")
                        }
                        let expected = reference[sampleIndex * 4 + index]
                        #expect(abs(rect.minX - expected.minX) <= 1)
                        #expect(abs(rect.minY - expected.minY) <= 1)
                        #expect(abs(rect.width - expected.width) <= 1)
                        #expect(abs(rect.height - expected.height) <= 1)
                    }
                }
            }
            if let custom, poses == ["current"], pose == .unknown,
               window.traitCollection.userInterfaceIdiom == .phone,
               window.traitCollection.horizontalSizeClass == .compact,
               window.traitCollection.verticalSizeClass == .regular {
                let defaultGap: CGFloat
                if #available(iOS 26, *) { defaultGap = 8 } else { defaultGap = 0 }
                #expect(custom.horizontalInset == defaultGap)
                #expect(custom.bottomInset == defaultGap)
                custom.selectedDetentIdentifier = .medium
                func checkGaps(left: CGFloat, bottom: CGFloat) {
                    custom.containerView?.layoutIfNeeded()
                    let frame = content.view.convert(content.view.bounds, to: window)
                    #expect(abs(frame.minX - left) <= 1)
                    #expect(abs(window.bounds.maxX - frame.maxX - left) <= 1)
                    #expect(abs(window.bounds.maxY - frame.maxY - bottom) <= 1)
                }
                checkGaps(left: defaultGap, bottom: defaultGap)
                custom.horizontalInset = 21
                checkGaps(left: 21, bottom: defaultGap)
                custom.bottomInset = 13
                checkGaps(left: 21, bottom: 13)
                custom.selectedDetentIdentifier = .large
                checkGaps(left: 0, bottom: 0)
            }
            await withCheckedContinuation { continuation in
                content.dismiss(animated: false) { continuation.resume() }
            }
            #expect(host.presentedViewController == nil)
        }
    }

    @Test func comparesFormSizingPlacementAndAnchor() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let anchor = UIView(frame: CGRect(x: 12, y: 100, width: 44, height: 44))
        host.view.addSubview(anchor)
        let preferredSize = CGSize(width: 360, height: 500)
        var sizes = Array(repeating: preferredSize, count: 5) + [.zero]
        var engines = ["UIKit", "Sheet"]
        if #available(iOS 27.1, *), window.traitCollection.userInterfaceIdiom == .phone,
           window.traitCollection.horizontalSizeClass == .regular {
            sizes += [CGSize(width: 0, height: 500), CGSize(width: 360, height: 0)]
            engines.append("Panel")
        }
        sizes.append(preferredSize)
        var reference: [CGRect] = []
        for engine in engines {
            let content = UIViewController()
            content.preferredContentSize = preferredSize
            let panel: AdaptivePanelController?
            if engine == "UIKit" {
                panel = nil
                content.modalPresentationStyle = .formSheet
                let sheet = try #require(content.sheetPresentationController)
                sheet.prefersPageSizing = false
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16
                await withCheckedContinuation { continuation in
                    host.present(content, animated: false) { continuation.resume() }
                }
            } else if engine == "Sheet" {
                panel = nil
                await withCheckedContinuation { continuation in
                    host.presentSheet(content, animated: false) { sheet in
                        sheet.prefersPageSizing = false
                        sheet.prefersGrabberVisible = true
                        sheet.preferredCornerRadius = 16
                    } completion: { continuation.resume() }
                }
            } else {
                let controller = AdaptivePanelController(contentViewController: content)
                controller.safeAreaSource = .window
                controller.prefersPageSizing = false
                controller.preferredCornerRadius = 16
                controller.show(in: host, animated: false)
                panel = controller
            }
            for (index, size) in sizes.enumerated() {
                let source = index == 3 ? anchor : nil
                if content.preferredContentSize != size { content.preferredContentSize = size }
                let position = min(index, 3)
                if let panel {
                    panel.sourceView = source
                    panel.prefersGrabberVisible = index < 4
                    panel.preferredPlacement = [.leading, .center, .trailing, .trailing][position]
                } else if engine == "UIKit" {
                    let sheet = try #require(content.sheetPresentationController)
                    sheet.sourceView = source
                    sheet.prefersGrabberVisible = index < 4
                    #if compiler(>=6.4)
                    if #available(iOS 27, *) { sheet.preferredPlacement = [.leading, .center, .trailing, .trailing][position] }
                    #endif
                } else {
                    let sheet = try #require(content.customSheetPresentationController)
                    sheet.sourceView = source
                    sheet.prefersGrabberVisible = index < 4
                    if #available(iOS 27, *) { sheet.preferredPlacement = [.leading, .center, .trailing, .trailing][position] }
                }
                try await Task.sleep(for: .milliseconds(400))
                let rect = panel.map { $0.view.convert($0.panelFrame, to: window) }
                    ?? content.view.convert(content.view.bounds, to: window)
                print("SHEET_FORM \(engine) \(index) window=\(window.bounds) frame=\(rect) preferred=\(size)")
                if engine == "UIKit" { reference.append(rect) }
                else {
                    let expected = reference[index]
                    #expect(abs(rect.minX - expected.minX) <= 1)
                    #expect(abs(rect.minY - expected.minY) <= 1)
                    #expect(abs(rect.width - expected.width) <= 1)
                    #expect(abs(rect.height - expected.height) <= 1)
                }
            }
            if let panel { panel.dismiss(animated: false) }
            else { await withCheckedContinuation { continuation in content.dismiss(animated: false) { continuation.resume() } } }
        }
        if engines.contains("Panel") {
            let local = UIView(frame: CGRect(x: 20, y: 100, width: 360, height: 320))
            host.view.addSubview(local)
            let content = UIViewController()
            content.preferredContentSize = CGSize(width: 180, height: 240)
            let panel = AdaptivePanelController(contentViewController: content)
            panel.safeAreaSource = .window
            panel.prefersPageSizing = false
            panel.show(in: host, containerView: local, animated: false)
            defer { panel.dismiss(animated: false) }
            try await Task.sleep(for: .milliseconds(200))
            #expect(panel.panelFrame.size == content.preferredContentSize)
            #expect(local.bounds.contains(panel.panelFrame))
        }
    }

    @Test func panelDefersTableLayoutUntilWindowAttachment() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 400, height: 700)
        let table = PanelTestTable(frame: .zero, style: .plain)
        let controller = UITableViewController(style: .plain)
        controller.tableView = table
        let panel = AdaptivePanelController(contentViewController: controller)
        panel.show(in: host, animated: false)
        defer { panel.dismiss(animated: false) }
        #expect(panel.panelFrame.height > 0)
        #expect(table.detachedLayoutCount == 0)

        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        window.layoutIfNeeded()
        #expect(table.bounds.height > 0)
        #expect(table.detachedLayoutCount == 0)
    }

    @Test func detentSubclassResolverAndLiveMaterial() async throws {
        final class CustomDetent: SheetPresentationController.Detent {}
        final class Context: NSObject, SheetPresentationControllerDetentResolutionContext {
            let containerTraitCollection = UITraitCollection()
            let maximumDetentValue: CGFloat = 480
        }
        let context = Context()
        let medium: CustomDetent = .medium()
        let large: CustomDetent = .large()
        let custom: CustomDetent = .custom(identifier: "custom") { supplied in
            #expect(supplied === context)
            return CustomDetent.large().resolvedValue(in: supplied).map { $0 / 3 }
        }
        #expect(medium.identifier == .medium)
        #expect(large.identifier == .large)
        #expect(custom.resolvedValue(in: context) == 160)
        let window = UIWindow(windowScene: try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first))
        let previous = window.windowScene?.keyWindow
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        // 横屏时系统 medium 失活。用在两种高度下都有效的自定义档位验证材质。
        let materialDetent = CustomDetent.custom(identifier: "material") { $0.maximumDetentValue / 2 }
        materialDetent.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        let sharedDetents: [AdaptivePanelController.Detent] = [materialDetent, large]
        let placement: SheetPresentationController.Placement = .center
        let panel = AdaptivePanelController(contentView: UIView())
        panel.detents = sharedDetents
        panel.preferredPlacement = placement
        panel.selectedDetentIdentifier = materialDetent.identifier
        panel.show(in: host, animated: false)
        defer { panel.dismiss(animated: false) }
        let content = UIViewController()
        await withCheckedContinuation { continuation in
            host.presentSheet(content, animated: false) { sheet in
                sheet.detents = sharedDetents
                sheet.preferredPlacement = panel.preferredPlacement
                sheet.selectedDetentIdentifier = materialDetent.identifier
            } completion: { continuation.resume() }
        }
        let sheet = try #require(content.customSheetPresentationController)
        #expect(sheet.preferredPlacement == placement)
        let background = try #require(sheet.presentedView?.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        #expect(background.effect is UIBlurEffect)
        panel.view.layoutIfNeeded()
        let panelSurface = try #require(panel.contentViewController.view.superview)
        #expect(panelSurface.subviews.contains { $0 is UIVisualEffectView })
        materialDetent.backgroundEffect = nil
        sheet.containerView?.layoutIfNeeded()
        panel.view.layoutIfNeeded()
        #expect(background.effect == nil)
        #expect(!panelSurface.subviews.contains { $0 is UIVisualEffectView })
        large.backgroundEffect = UIBlurEffect(style: .dark)
        sheet.selectedDetentIdentifier = .large
        sheet.containerView?.layoutIfNeeded()
        #expect(background.effect is UIBlurEffect)
        await withCheckedContinuation { continuation in content.dismiss(animated: false) { continuation.resume() } }
    }

}

private final class PanelTestTable: UITableView {
    private(set) var detachedLayoutCount = 0

    override func layoutSubviews() {
        if window == nil { detachedLayoutCount += 1 }
        super.layoutSubviews()
    }
}
