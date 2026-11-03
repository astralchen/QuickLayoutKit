import Darwin
import ObjectiveC
import QuartzCore
import UIKit

/// Diagnostic-only app, with no AppLocalization or QuickLayoutKit dependency.
/// Read-only by default. --cache opts into a private layoutRTL setter experiment.
/// Never include this diagnostic target in a shipping app or reusable package.
@MainActor
struct TabDirectionProbe {
    func run(in window: UIWindow) async throws {
        let recovery = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--recovery=") })?.components(separatedBy: "=").last ?? "none"
        let cacheMode = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--cache=") })?.components(separatedBy: "=").last
        let semantics = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--semantics=") })?.components(separatedBy: "=").last ?? "explicit"
        let directionSource = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--direction-source=") })?.components(separatedBy: "=").last ?? "controller"
        let timing = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--timing=") })?.components(separatedBy: "=").last ?? "settled"
        let presentation = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--presentation=") })?.components(separatedBy: "=").last ?? "none"
        guard ["controller", "window", "scene"].contains(directionSource),
              ["settled", "before", "direction-layout", "next-turn", "atomic"].contains(timing),
              ["none", "hide", "sidebar", "compact", "fresh-tabs", "fresh-identifiers"].contains(presentation) else {
            throw NSError(domain: "PublicProbe.InvalidArguments", code: 1)
        }
        let initialRTL = ProcessInfo.processInfo.arguments.contains("--initial-rtl")
        let clearLegacyItems = ProcessInfo.processInfo.arguments.contains("--clear-legacy-items")
        let modernTabs = recovery.hasPrefix("tabs-") || ProcessInfo.processInfo.arguments.contains("--modern-tabs")
        let ownedControl = ProcessInfo.processInfo.arguments.contains("--owned-control")
        let page: UIViewController = ownedControl ? OwnedCollectionPage() : UIViewController()
        page.title = "Navigation Title"
        page.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Action", style: .plain, target: nil, action: nil)
        let navigation = UINavigationController(rootViewController: page)
        let tabs = UITabBarController()
        if initialRTL {
            if directionSource == "window" { window.traitOverrides.layoutDirection = .rightToLeft }
            if directionSource == "scene" { window.windowScene?.traitOverrides.layoutDirection = .rightToLeft }
            window.semanticContentAttribute = semantics == "traits" ? .unspecified : .forceRightToLeft
            for controller in [tabs, navigation] {
                if directionSource == "controller" { controller.traitOverrides.layoutDirection = .rightToLeft }
                controller.view.semanticContentAttribute = semantics == "explicit" ? .forceRightToLeft : .unspecified
            }
        }
        let otherPages = [UIViewController(), UIViewController()]
        let children = [navigation] + otherPages
        for (child, title) in zip(children, ["Alpha", "Beta", "Gamma"]) {
            child.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: "circle"), tag: 0)
        }
        if #available(iOS 18.0, *) { tabs.mode = .tabBar }
        if #available(iOS 18.0, *), modernTabs {
            tabs.tabs = zip(children, ["Alpha", "Beta", "Gamma"]).enumerated().map { index, pair in
                UITab(title: pair.1, image: UIImage(systemName: "circle"), identifier: "tab-\(index)") { _ in
                    if clearLegacyItems { pair.0.tabBarItem = nil }
                    return pair.0
                }
            }
            tabs.selectedTab = tabs.tabs.first
        } else {
            tabs.viewControllers = children
        }
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        tabs.view.frame = window.bounds
        window.layoutIfNeeded()
        if cacheMode != nil {
            let input = UITextView(frame: CGRect(x: 40, y: 220, width: 320, height: 90))
            input.accessibilityIdentifier = "cache-probe.input"
            input.text = "草稿 Draft مسودة"
            input.backgroundColor = .secondarySystemBackground
            page.view.addSubview(input)
            input.becomeFirstResponder()
            try await Task.sleep(for: .milliseconds(500))
        }
        if ProcessInfo.processInfo.arguments.contains("--debug-pause") { raise(SIGSTOP) }
        var snapshots: [[String: Any]] = []
        let refresh = ProcessInfo.processInfo.arguments.contains("--refresh")
        var cacheWrites: [[String: Any]] = []
        var replacementEvents: [[String: Any]] = []
        var replacementBlocked = false
        let directions = cacheMode != nil
            ? (0..<9).map { initialRTL ? $0.isMultiple(of: 2) : !$0.isMultiple(of: 2) }
            : [false, true, false, true, false]
        for (index, rtl) in directions.enumerated() {
            // Enter the alternative presentation BEFORE changing direction, unlike the recovery matrix.
            if index > 0, presentation != "none" {
                if #available(iOS 18.0, *) {
                    switch presentation {
                    case "hide": tabs.setTabBarHidden(true, animated: false)
                    case "sidebar": tabs.mode = .tabSidebar; tabs.sidebar.isHidden = false
                    case "compact": tabs.traitOverrides.horizontalSizeClass = .compact
                    case "fresh-tabs", "fresh-identifiers":
                        tabs.selectedTab = nil
                        tabs.setTabs([], animated: false)
                    default: break
                    }
                }
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-presentation-entered"))
                if #available(iOS 18.0, *), presentation.hasPrefix("fresh-") {
                    var remaining = children.compactMap { $0.tab }.map(id)
                    var releaseWaits = 0
                    while !remaining.isEmpty, releaseWaits < 10 {
                        try await Task.sleep(for: .milliseconds(200))
                        remaining = children.compactMap { $0.tab }.map(id)
                        releaseWaits += 1
                    }
                    replacementEvents.append(["stage": index, "remainingOldBindings": remaining,
                                              "additionalReleaseWaitMilliseconds": releaseWaits * 200])
                    if !remaining.isEmpty {
                        // No private association clearing, and no rebinding an already-owned controller.
                        replacementBlocked = true
                        break
                    }
                }
            }
            if timing == "before" {
                updateTitle(tabs: tabs, child: children[0], modern: modernTabs, rtl: rtl, index: index)
            }
            if cacheMode == "before" {
                cacheWrites += try synchronizeNativeLayoutCache(tabs.view, rtl: rtl, stage: "\(index)-before")
            }
            let attribute: UISemanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            window.semanticContentAttribute = semantics == "traits" ? .unspecified : attribute
            if directionSource == "window" { window.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight }
            if directionSource == "scene" { window.windowScene?.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight }
            for controller in [tabs, navigation] {
                if directionSource == "controller" {
                    controller.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight
                } else {
                    controller.traitOverrides.remove(UITraitLayoutDirection.self)
                }
                controller.view.semanticContentAttribute = semantics == "explicit" ? attribute : .unspecified
            }
            tabs.tabBar.semanticContentAttribute = semantics == "explicit" ? attribute : .unspecified
            navigation.navigationBar.semanticContentAttribute = semantics == "explicit" ? attribute : .unspecified
            page.view.semanticContentAttribute = semantics == "explicit" ? attribute : .unspecified
            if timing == "direction-layout" {
                window.layoutIfNeeded()
                updateTitle(tabs: tabs, child: children[0], modern: modernTabs, rtl: rtl, index: index)
            } else if timing == "next-turn" {
                // Enqueue onto the main dispatch queue; no arbitrary millisecond delay.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.main.async { continuation.resume() }
                }
                updateTitle(tabs: tabs, child: children[0], modern: modernTabs, rtl: rtl, index: index)
            } else if timing == "atomic" {
                // Same synchronous segment as direction assignments, without an explicit intermediate layout.
                updateTitle(tabs: tabs, child: children[0], modern: modernTabs, rtl: rtl, index: index)
            }
            if index > 0, presentation != "none" {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-presentation-directed"))
                if #available(iOS 18.0, *) {
                    switch presentation {
                    case "hide": tabs.setTabBarHidden(false, animated: false)
                    case "sidebar": tabs.sidebar.isHidden = true; tabs.mode = .tabBar
                    case "compact": tabs.traitOverrides.remove(UITraitHorizontalSizeClass.self)
                    case "fresh-tabs", "fresh-identifiers":
                        let generation = presentation == "fresh-identifiers" ? "-g\(index)" : ""
                        let titles = [rtl ? "الأمثلة" : "示例", "Beta", "Gamma"]
                        let fresh = children.enumerated().map { offset, child in
                            UITab(title: titles[offset], image: UIImage(systemName: "circle"), identifier: "tab-\(offset)\(generation)") { _ in child }
                        }
                        tabs.setTabs(fresh, animated: false)
                        tabs.selectedTab = fresh.first
                        replacementEvents.append(["stage": index, "newModels": fresh.map(id),
                                                  "selectedController": (tabs.selectedTab?.viewController).map(id) ?? ""])
                    default: break
                    }
                }
            }
            (page as? OwnedCollectionPage)?.collection.collectionViewLayout.invalidateLayout()
            if cacheMode == "after" {
                cacheWrites += try synchronizeNativeLayoutCache(tabs.view, rtl: rtl, stage: "\(index)-after")
            }
            if refresh {
                // Only public, app-owned boundaries; keep controller and native bar instances.
                for controller in [tabs, navigation, page] {
                    if #available(iOS 26.0, *) { controller.setNeedsUpdateProperties(); controller.updatePropertiesIfNeeded() }
                }
                for view in [window, tabs.view!, tabs.tabBar, navigation.view!, navigation.navigationBar, page.view!] {
                    view.setNeedsUpdateConstraints()
                    view.setNeedsLayout()
                    if #available(iOS 26.0, *) { view.setNeedsUpdateProperties(); view.updatePropertiesIfNeeded() }
                    view.updateConstraintsIfNeeded()
                    view.layoutIfNeeded()
                }
            }
            snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-\(rtl ? "rtl" : "ltr")-immediate"))
            window.layoutIfNeeded()
            snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-\(rtl ? "rtl" : "ltr")-layout"))
            try await Task.sleep(for: .milliseconds(600))
            snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-\(rtl ? "rtl" : "ltr")-settled"))
            if let cacheMode {
                if cacheMode == "late" {
                    cacheWrites += try synchronizeNativeLayoutCache(tabs.view, rtl: rtl, stage: "\(index)-late")
                }
                updateTitle(tabs: tabs, child: children[0], modern: modernTabs, rtl: rtl, index: index)
                // Force a subsequent content change even when the transition already updated the title/badge.
                if #available(iOS 18.0, *), modernTabs { tabs.tabs.first?.badgeValue = "s\(index)" }
                else { children[0].tabBarItem.badgeValue = "s\(index)" }
                for collection in nativeCollections(in: tabs.view) { collection.collectionViewLayout.invalidateLayout() }
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(300))
                snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-cache-content"))
                let oldBounds = window.bounds
                window.bounds.size.width = oldBounds.width - 80
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-cache-resized"))
                window.bounds = oldBounds
                window.layoutIfNeeded()
                let input = page.view.subviews.compactMap { $0 as? UITextView }.first
                input?.insertText("续")
                try await Task.sleep(for: .milliseconds(300))
                snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-cache-final"))
            }
            if index > 0, !rtl, let owned = page as? OwnedCollectionPage {
                for action in ["invalidate", "configuration", "reattach-layout", "fresh-layout"] {
                    owned.refresh(action)
                    window.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(300))
                    snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-owned-\(action)"))
                    owned.collection.collectionViewLayout.invalidateLayout()
                    window.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(300))
                    snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-owned-\(action)-stress"))
                }
            }
            if index > 0, !rtl, recovery != "none" {
                try await recover(recovery, tabs: tabs, window: window)
                try await Task.sleep(for: .milliseconds(400))
                window.layoutIfNeeded()
                snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-recovered"))
                // A candidate must survive a later native item/layout update.
                if #available(iOS 18.0, *), modernTabs {
                    tabs.tabs.first?.badgeValue = String(index)
                } else {
                    children[0].tabBarItem.badgeValue = String(index)
                }
                tabs.view.setNeedsLayout()
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(300))
                snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-stress"))
            }
        }
        let result: [String: Any] = [
            "cacheMode": cacheMode ?? "disabled", "initialRTL": initialRTL, "cacheWrites": cacheWrites,
            "clearLegacyItems": clearLegacyItems, "semantics": semantics,
            "directionSource": directionSource, "timing": timing, "presentation": presentation,
            "replacementEvents": replacementEvents, "replacementBlocked": replacementBlocked,
            "recovery": recovery, "modernTabs": modernTabs, "device": UIDevice.current.model, "os": UIDevice.current.systemVersion,
            "windowSize": [window.bounds.width, window.bounds.height], "snapshots": snapshots,
            "runtimeGeometryMethods": geometryMethods(in: window)
        ]
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(cacheMode != nil ? "cache-\(cacheMode!)-\(initialRTL ? "rtl" : "ltr")-\(modernTabs ? "modern" : "legacy").json" : ownedControl ? "owned-control.json" : recovery != "none" ? "recovery-\(recovery).json" : (refresh ? "tab-direction-refresh.json" : "tab-direction-layers.json"))
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: file)
        print("TAB_LAYER_DIAGNOSTICS_FILE=\(file.path)")
    }

    private func updateTitle(tabs: UITabBarController, child: UIViewController, modern: Bool, rtl: Bool, index: Int) {
        let title = rtl ? "الأمثلة" : "示例"
        if #available(iOS 18.0, *), modern {
            tabs.tabs.first?.title = title
            tabs.tabs.first?.badgeValue = String(index)
        } else {
            child.tabBarItem.title = title
            child.tabBarItem.badgeValue = String(index)
        }
    }

    private func nativeCollections(in root: UIView) -> [UICollectionView] {
        var result: [UICollectionView] = []
        func visit(_ view: UIView) {
            if let collection = view as? UICollectionView,
               NSStringFromClass(type(of: collection)) == "_UIFloatingTabBarCollectionView" { result.append(collection) }
            view.subviews.forEach(visit)
        }
        visit(root)
        return result
    }

    // Explicit opt-in diagnostic ONLY. No swizzling, axis setter, cell transform, or replacement layout.
    // Validate the runtime ABI before calling the observed private layoutRTL setter.
    private func synchronizeNativeLayoutCache(_ root: UIView, rtl: Bool, stage: String) throws -> [[String: Any]] {
        try nativeCollections(in: root).map { collection in
            let layout = collection.collectionViewLayout
            guard NSStringFromClass(type(of: layout)) == "_UIFloatingTabBarCollectionViewLayout",
                  let method = class_getInstanceMethod(type(of: layout), NSSelectorFromString("setLayoutRTL:")),
                  method_getNumberOfArguments(method) == 3 else {
                throw NSError(domain: "CacheProbe.UnsupportedLayout", code: 1)
            }
            let resultType = method_copyReturnType(method)
            let argumentType = method_copyArgumentType(method, 2)
            defer { free(resultType); free(argumentType) }
            guard String(cString: resultType) == "v", let argumentType, String(cString: argumentType) == "B" else {
                throw NSError(domain: "CacheProbe.UnsupportedABI", code: 2)
            }
            let previous = readGeometryFlag(layout, selector: "layoutRTL")
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
            setter(layout, NSSelectorFromString("setLayoutRTL:"), rtl)
            return ["stage": stage, "layout": id(layout), "targetRTL": rtl,
                    "previous": previous as Any? ?? NSNull(),
                    "after": readGeometryFlag(layout, selector: "layoutRTL") as Any? ?? NSNull()]
        }
    }

    // Public controller/view APIs only. Each process runs one candidate on the same root.
    private func recover(_ strategy: String, tabs: UITabBarController, window: UIWindow) async throws {
        switch strategy {
        case let name where name.hasPrefix("tabs-"):
            if #available(iOS 18.0, *) {
                let original = tabs.tabs
                let selected = tabs.selectedTab
                switch name {
                case "tabs-assign":
                    tabs.tabs = original
                case "tabs-set":
                    tabs.setTabs(original, animated: false)
                case "tabs-animated":
                    tabs.setTabs(original, animated: true)
                case "tabs-empty":
                    tabs.setTabs([], animated: false)
                    window.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(200))
                    tabs.setTabs(original, animated: false)
                case "tabs-reorder":
                    tabs.setTabs(Array(original.reversed()), animated: false)
                    window.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(200))
                    tabs.setTabs(original, animated: false)
                case "tabs-remove-unselected":
                    tabs.setTabs(original.filter { $0 === selected }, animated: false)
                    window.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(200))
                    tabs.setTabs(original, animated: false)
                case "tabs-reselect":
                    tabs.selectedTab = original.last
                    window.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(200))
                default:
                    break
                }
                tabs.selectedTab = selected
            }
        case "idiom", "compact-idiom":
            tabs.traitOverrides.userInterfaceIdiom = .phone
            if strategy == "compact-idiom" { tabs.traitOverrides.horizontalSizeClass = .compact }
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            tabs.traitOverrides.remove(UITraitUserInterfaceIdiom.self)
            tabs.traitOverrides.remove(UITraitHorizontalSizeClass.self)
        case "sidebar":
            if #available(iOS 18.0, *) {
                tabs.mode = .tabSidebar
                tabs.sidebar.isHidden = false
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                tabs.sidebar.isHidden = true
                tabs.mode = .tabBar
            }
        case "hide":
            if #available(iOS 18.0, *) {
                tabs.setTabBarHidden(true, animated: false)
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                tabs.setTabBarHidden(false, animated: false)
            }
        case "items":
            let children = tabs.viewControllers ?? []
            let selected = tabs.selectedViewController
            let extra = UIViewController()
            extra.tabBarItem = UITabBarItem(title: "Temporary", image: nil, tag: 99)
            tabs.setViewControllers(children + [extra], animated: false)
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            tabs.setViewControllers(children, animated: false)
            tabs.selectedViewController = selected
        case "appearance":
            let original = tabs.tabBar.standardAppearance
            let changed = original.copy()
            changed.stackedItemPositioning = .fill
            tabs.tabBar.standardAppearance = changed
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            tabs.tabBar.standardAppearance = original
        case "batch":
            if #available(iOS 27.0, *) {
                tabs.performBatchUpdates {
                    tabs.viewControllers?.forEach { $0.tabBarItem.badgeValue = "1" }
                }
            }
        case "minimize":
            if #available(iOS 26.0, *) {
                tabs.tabBarMinimizeBehavior = .onScrollDown
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                tabs.tabBarMinimizeBehavior = .never
            }
        case "content-size":
            tabs.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            tabs.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
        default:
            break
        }
        tabs.view.setNeedsLayout()
        window.layoutIfNeeded()
    }

    private func snapshot(_ window: UIWindow, tabs: UITabBarController, navigation: UINavigationController, name: String) -> [String: Any] {
        var views: [[String: Any]] = []
        var owners: [ObjectIdentifier: String] = [:]
        func visit(_ view: UIView, path: String) {
            let origin = view.convert(CGPoint.zero, to: window)
            let x = view.convert(CGPoint(x: 10, y: 0), to: window)
            let y = view.convert(CGPoint(x: 0, y: 10), to: window)
            let p0 = view.convert(CGPoint.zero, to: view.superview)
            let px = view.convert(CGPoint(x: 10, y: 0), to: view.superview)
            let py = view.convert(CGPoint(x: 0, y: 10), to: view.superview)
            var info: [String: Any] = [
                "id": id(view), "path": path, "class": NSStringFromClass(type(of: view)),
                "parent": view.superview.map(id) ?? "", "layer": id(view.layer),
                "semantic": view.semanticContentAttribute.rawValue,
                "effectiveDirection": view.effectiveUserInterfaceLayoutDirection.rawValue,
                "traitDirection": view.traitCollection.layoutDirection.rawValue,
                "transform": affine(view.transform), "transform3D": matrix(view.transform3D), "bounds": rect(view.bounds), "frame": rect(view.frame),
                "toWindow": [origin.x, origin.y, x.x-origin.x, x.y-origin.y, y.x-origin.x, y.y-origin.y],
                "toParent": [p0.x, p0.y, px.x-p0.x, px.y-p0.y, py.x-p0.x, py.y-p0.y],
                "accessibilityID": view.accessibilityIdentifier ?? "", "hidden": view.isHidden, "alpha": view.alpha,
                "diagnosticHorizontalAxisFlip": readGeometryFlag(view, selector: "_flipsHorizontalAxis") as Any? ?? NSNull(),
                "diagnosticRenderedHorizontalFlip": readGeometryFlag(view, selector: "_isRenderedHorizontallyFlipped") as Any? ?? NSNull(),
                "accessibilityHidden": view.accessibilityElementsHidden, "accessibilityModal": view.accessibilityViewIsModal,
                "text": (view as? UILabel)?.text ?? ""
            ]
            if let input = view as? UITextView, input.accessibilityIdentifier == "cache-probe.input" {
                info["inputText"] = input.text ?? ""
                info["firstResponder"] = input.isFirstResponder
                info["selection"] = [input.selectedRange.location, input.selectedRange.length]
                info["hasMarkedText"] = input.markedTextRange != nil
            }
            if let collection = view as? UICollectionView {
                let layout = collection.collectionViewLayout
                info["collectionLayout"] = [
                    "id": id(layout), "class": NSStringFromClass(type(of: layout)),
                    "flipsHorizontally": layout.flipsHorizontallyInOppositeLayoutDirection,
                    "developmentDirection": layout.developmentLayoutDirection.rawValue,
                    "diagnosticLayoutRTL": readGeometryFlag(layout, selector: "layoutRTL") as Any? ?? NSNull(),
                    "contentSize": [layout.collectionViewContentSize.width, layout.collectionViewContentSize.height]
                ]
            }
            owners[ObjectIdentifier(view.layer)] = id(view)
            views.append(info)
            for (index, child) in view.subviews.enumerated() { visit(child, path: "\(path)/\(index):\(NSStringFromClass(type(of: child)))") }
        }
        visit(window, path: "window")
        var layers: [[String: Any]] = []
        func visitLayer(_ layer: CALayer, path: String) {
            let origin = layer.convert(CGPoint.zero, to: window.layer)
            let x = layer.convert(CGPoint(x: 10, y: 0), to: window.layer)
            let y = layer.convert(CGPoint(x: 0, y: 10), to: window.layer)
            var info: [String: Any] = [
                "id": id(layer), "path": path, "class": NSStringFromClass(type(of: layer)),
                "parent": layer.superlayer.map(id) ?? "", "view": owners[ObjectIdentifier(layer)] ?? "",
                "name": layer.name ?? "", "transform": matrix(layer.transform),
                "diagnosticHorizontalAxisFlip": readGeometryFlag(layer, selector: "flipsHorizontalAxis") as Any? ?? NSNull(),
                "sublayerTransform": matrix(layer.sublayerTransform), "geometryFlipped": layer.isGeometryFlipped,
                "bounds": rect(layer.bounds), "position": [layer.position.x, layer.position.y],
                "anchorPoint": [layer.anchorPoint.x, layer.anchorPoint.y],
                "toWindow": [origin.x, origin.y, x.x-origin.x, x.y-origin.y, y.x-origin.x, y.y-origin.y],
                "animations": layer.animationKeys() ?? []
            ]
            if let presentation = layer.presentation() {
                info["presentationTransform"] = matrix(presentation.transform)
                info["presentationSublayerTransform"] = matrix(presentation.sublayerTransform)
            }
            layers.append(info)
            for (index, child) in (layer.sublayers ?? []).enumerated() { visitLayer(child, path: "\(path)/\(index):\(NSStringFromClass(type(of: child)))") }
        }
        visitLayer(window.layer, path: "windowLayer")
        let labels = views.filter { ["Alpha", "Beta", "Gamma", "示例", "الأمثلة", "Navigation Title", "Action"].contains($0["text"] as? String ?? "") }
        print("TAB_LAYER_STAGE \(name) labels=\(labels.map { "\($0["text"] ?? ""): \($0["toWindow"] ?? "")" })")
        var tabState: [String: Any] = [:]
        if #available(iOS 18.0, *), ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--recovery=tabs-") || $0 == "--modern-tabs" }) {
            tabState = ["models": tabs.tabs.map(id), "selectedTab": tabs.selectedTab.map(id) ?? "",
                        "selectedController": (tabs.selectedTab?.viewController).map(id) ?? "",
                        "page": navigation.viewControllers.first.map(id) ?? ""]
        }
        return ["name": name, "modernTabState": tabState, "tabs": id(tabs), "navigation": id(navigation),
                "tabControllerTrait": tabs.traitCollection.layoutDirection.rawValue,
                "windowTrait": window.traitCollection.layoutDirection.rawValue,
                "sceneTrait": window.windowScene?.traitCollection.layoutDirection.rawValue ?? -1,
                "navControllerTrait": navigation.traitCollection.layoutDirection.rawValue,
                "tabBarView": id(tabs.tabBar), "navigationBarView": id(navigation.navigationBar),
                "views": views, "layers": layers]
    }

    // 仅诊断 target：读取已从运行时元数据确认的 BOOL getter，不调用 setter。
    // 这些不是公开 API，不用于正式应用的布局实现。
    private func readGeometryFlag(_ object: NSObject, selector name: String) -> Bool? {
        let selector = NSSelectorFromString(name)
        guard let cls = object_getClass(object),
              let method = class_getInstanceMethod(cls, selector),
              method_getNumberOfArguments(method) == 2 else { return nil }
        let resultType = method_copyReturnType(method)
        defer { free(resultType) }
        guard String(cString: resultType) == "B" else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return getter(object, selector)
    }

    private func geometryMethods(in root: UIView) -> [[String: Any]] {
        var classes: [String: AnyClass] = [:]
        func collect(_ object: AnyObject) {
            var cls: AnyClass? = object_getClass(object)
            while let current = cls {
                let name = NSStringFromClass(current)
                if classes[name] != nil { break }
                classes[name] = current
                cls = class_getSuperclass(current)
            }
        }
        func visit(_ view: UIView) {
            collect(view)
            collect(view.layer)
            view.subviews.forEach(visit)
        }
        visit(root)
        return classes.sorted { $0.key < $1.key }.compactMap { name, cls in
            var count: UInt32 = 0
            guard let methods = class_copyMethodList(cls, &count) else { return nil }
            defer { free(methods) }
            let matches: [[String: String]] = (0..<Int(count)).compactMap { index in
                let selector = NSStringFromSelector(method_getName(methods[index]))
                let lower = selector.lowercased()
                guard ["mirror", "flip", "transform", "geometry"].contains(where: lower.contains) else { return nil }
                return ["selector": selector, "encoding": method_getTypeEncoding(methods[index]).map { String(cString: $0) } ?? ""]
            }
            return matches.isEmpty ? nil : ["class": name, "methods": matches]
        }
    }

    private func id(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }
    private func rect(_ r: CGRect) -> [CGFloat] { [r.origin.x, r.origin.y, r.size.width, r.size.height] }
    private func affine(_ t: CGAffineTransform) -> [CGFloat] { [t.a, t.b, t.c, t.d, t.tx, t.ty] }
    private func matrix(_ t: CATransform3D) -> [CGFloat] {
        [t.m11,t.m12,t.m13,t.m14,t.m21,t.m22,t.m23,t.m24,t.m31,t.m32,t.m33,t.m34,t.m41,t.m42,t.m43,t.m44]
    }
}


/// Positive control: app-owned compositional layout with a public factory.
/// This does not access or replace the system floating tab bar's collection view.
@MainActor
private final class OwnedCollectionPage: UIViewController, UICollectionViewDataSource {
    private(set) var collection: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        collection = UICollectionView(frame: CGRect(x: 40, y: 200, width: 500, height: 100), collectionViewLayout: Self.makeLayout())
        collection.accessibilityIdentifier = "owned.collection"
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collection.dataSource = self
        view.addSubview(collection)
    }

    static func makeLayout() -> UICollectionViewCompositionalLayout {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(130), heightDimension: .absolute(60)), subitems: [item])
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .horizontal
        return UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: group), configuration: config)
    }

    func refresh(_ action: String) {
        let layout = collection.collectionViewLayout as! UICollectionViewCompositionalLayout
        switch action {
        case "invalidate": layout.invalidateLayout()
        case "configuration":
            let configuration = layout.configuration
            configuration.interSectionSpacing += 1
            layout.configuration = configuration
        case "reattach-layout":
            collection.setCollectionViewLayout(UICollectionViewFlowLayout(), animated: false)
            collection.layoutIfNeeded()
            collection.setCollectionViewLayout(layout, animated: false)
        case "fresh-layout": collection.setCollectionViewLayout(Self.makeLayout(), animated: false)
        default: break
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 3 }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.cell()
        content.text = "Owned \(indexPath.item)"
        cell.contentConfiguration = content
        return cell
    }
}
