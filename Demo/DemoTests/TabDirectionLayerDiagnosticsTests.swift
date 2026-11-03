import ObjectiveC
import QuartzCore
import Testing
import UIKit

/// 只读采样；测试通过仅表示采样完成，不表示系统镜像缺陷修复。
@MainActor
@Suite(.serialized)
struct TabDirectionLayerDiagnosticsTests {
    @Test func compareNativeBarsAcrossDirectionRoundTrip() async throws {
        let page = UIViewController()
        page.title = "Navigation Title"
        page.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Action", style: .plain, target: nil, action: nil)
        let navigation = UINavigationController(rootViewController: page)
        let tabs = UITabBarController()
        let otherPages = [UIViewController(), UIViewController()]
        let children = [navigation] + otherPages
        for (child, title) in zip(children, ["Alpha", "Beta", "Gamma"]) {
            child.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: "circle"), tag: 0)
        }
        if #available(iOS 18.0, *) { tabs.mode = .tabBar }
        tabs.viewControllers = children
        let window = try makeVisibleTestWindow(rootViewController: tabs)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        var snapshots: [[String: Any]] = []
        for (index, rtl) in [false, true, false, true, false].enumerated() {
            let attribute: UISemanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            window.semanticContentAttribute = attribute
            for controller in [tabs, navigation] {
                controller.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight
                controller.view.semanticContentAttribute = attribute
            }
            tabs.tabBar.semanticContentAttribute = attribute
            navigation.navigationBar.semanticContentAttribute = attribute
            page.view.semanticContentAttribute = attribute
            snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-\(rtl ? "rtl" : "ltr")-immediate"))
            window.layoutIfNeeded()
            snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-\(rtl ? "rtl" : "ltr")-layout"))
            try await Task.sleep(for: .milliseconds(600))
            snapshots.append(snapshot(window, tabs: tabs, navigation: navigation, name: "\(index)-\(rtl ? "rtl" : "ltr")-settled"))
        }
        let result: [String: Any] = [
            "device": UIDevice.current.model, "os": UIDevice.current.systemVersion,
            "windowSize": [window.bounds.width, window.bounds.height], "snapshots": snapshots,
            "runtimeGeometryMethods": geometryMethods(in: window)
        ]
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tab-direction-layers.json")
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: file)
        print("TAB_LAYER_DIAGNOSTICS_FILE=\(file.path)")
        #expect(snapshots.count == 15)
        #expect(window.rootViewController === tabs)
        #expect(tabs.selectedViewController === navigation)
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
                "hidden": view.isHidden, "alpha": view.alpha,
                "diagnosticHorizontalAxisFlip": readGeometryFlag(view, selector: "_flipsHorizontalAxis") as Any? ?? NSNull(),
                "diagnosticRenderedHorizontalFlip": readGeometryFlag(view, selector: "_isRenderedHorizontallyFlipped") as Any? ?? NSNull(),
                "accessibilityHidden": view.accessibilityElementsHidden, "accessibilityModal": view.accessibilityViewIsModal,
                "text": (view as? UILabel)?.text ?? ""
            ]
            if let collection = view as? UICollectionView {
                let layout = collection.collectionViewLayout
                info["collectionLayout"] = [
                    "id": id(layout), "class": NSStringFromClass(type(of: layout)),
                    "flipsHorizontally": layout.flipsHorizontallyInOppositeLayoutDirection,
                    "developmentDirection": layout.developmentLayoutDirection.rawValue,
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
        let labels = views.filter { ["Alpha", "Beta", "Gamma", "Navigation Title", "Action"].contains($0["text"] as? String ?? "") }
        print("TAB_LAYER_STAGE \(name) labels=\(labels.map { "\($0["text"] ?? ""): \($0["toWindow"] ?? "")" })")
        return ["name": name, "tabs": id(tabs), "navigation": id(navigation),
                "tabControllerTrait": tabs.traitCollection.layoutDirection.rawValue,
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
