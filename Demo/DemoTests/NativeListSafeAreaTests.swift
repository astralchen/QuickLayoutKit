import AppLocalization
import QuickLayout
import QuickLayoutKit
import SwiftUI
import Testing
import UIKit
@testable import Demo

/// 与原生 SwiftUI.List 对照滚动视口，覆盖 UIKit 原生列表适配路径。
@MainActor
@Suite(.serialized)
struct NativeListSafeAreaTests {
    @Test func nativeListsMatchSwiftUIViewportAndSafeContent() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for rtl in [false, true] {
            let controller = UIViewController()
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 13, left: 21, bottom: 17, right: 33)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            let reference = UIHostingController(rootView: List(0..<80, id: \.self) { index in
                Text("Row \(index)").frame(height: 44).listRowInsets(.init())
            }.listStyle(.plain).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
            controller.addChild(reference)
            controller.view.addSubview(reference.view)
            reference.didMove(toParent: controller)
            reference.view.frame = controller.view.bounds
            let table = UITableView(frame: .zero, style: .plain)
            let source = NativeListRows()
            table.dataSource = source
            table.rowHeight = 44
            table.contentInsetAdjustmentBehavior = .always
            let kit = QuickLayoutView { QuickLayoutKit.List(table) }
            kit.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            controller.view.addSubview(kit)
            kit.frame = controller.view.bounds
            for _ in 0..<10 {
                controller.view.layoutIfNeeded()
                kit.setNeedsLayout()
                try await Task.sleep(for: .milliseconds(30))
            }
            let native = try #require(findScroll(reference.view))
            let expected = native.convert(native.bounds, to: reference.view)
            let actual = table.convert(table.bounds, to: kit)
            #expect(abs(actual.minY - expected.minY) < 1)
            #expect(abs(actual.height - expected.height) < 1)
            #expect(abs(actual.minX - expected.minX) < 1)
            #expect(abs(actual.width - expected.width) < 1)
            #expect(table.adjustedContentInset.top >= kit.safeAreaInsets.top)
            #expect(table.adjustedContentInset.bottom >= kit.safeAreaInsets.bottom)
            #expect(table.contentInset == .zero, "UIKit 已承担安全区，Kit 不得重复添加")
            let before = table.adjustedContentInset
            for _ in 0..<5 { kit.setNeedsLayout(); kit.layoutIfNeeded() }
            #expect(table.adjustedContentInset == before)
            table.scrollToRow(at: IndexPath(row: 79, section: 0), at: .bottom, animated: false)
            table.layoutIfNeeded()
            let last = table.convert(table.rectForRow(at: IndexPath(row: 79, section: 0)), to: kit)
            #expect(last.maxY <= kit.bounds.maxY - kit.safeAreaInsets.bottom + 1)
            #expect(last.minY >= kit.safeAreaInsets.top)
            withExtendedLifetime(source) {}
        }
    }

    /// 在同一列内对照原生分组列表，右侧工具栏的安全区不应产生横向滚动行程。
    @Test func catalogRTLColumnMatchesNativeGroupedList() async throws {
        let original = Localization.localizationController.currentLocale.identifier
        Localization.setLocale(identifier: "ar")
        defer { Localization.setLocale(identifier: original) }
        let menu = MainViewController()
        let nav = UINavigationController(rootViewController: menu)
        let window = try makeVisibleTestWindow(rootViewController: nav,
            size: CGSize(width: 350, height: 669), semanticContentAttribute: .forceRightToLeft)
        defer { window.isHidden = true }
        menu.additionalSafeAreaInsets.right = 84
        let control = UIHostingController(rootView: SwiftUI.List(0..<80, id: \.self) { index in
            Text("صف \(index)")
        }.listStyle(.insetGrouped).environment(\.layoutDirection, .rightToLeft))
        menu.addChild(control)
        menu.view.addSubview(control.view)
        control.view.frame = menu.view.bounds
        control.didMove(toParent: menu)
        for _ in 0..<8 { window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(30)) }
        let native = try #require(findScroll(control.view))
        for list in [menu.collectionView as UIScrollView, native] {
            let inset = list.adjustedContentInset
            let rect = list.convert(list.bounds, to: menu.view)
            let range = list.contentSize.width + inset.left + inset.right - list.bounds.width
            print("CatalogRange kit=\(list === menu.collectionView) rect=\(rect) root=\(menu.view.bounds) safe=\(list.safeAreaInsets) rootSafe=\(menu.view.safeAreaInsets) inset=\(inset) custom=\(list.contentInset) indicator=\(list.verticalScrollIndicatorInsets) transform=\(list.transform.a) dx=\(list.convert(CGPoint(x: 1, y: 0), to: menu.view).x - list.convert(CGPoint.zero, to: menu.view).x) offset=\(list.contentOffset) range=\(range)")
            #expect(abs(rect.minX) <= 1 && abs(rect.width - menu.view.bounds.width) <= 1)
            #expect(range <= 1)
            #expect(list.verticalScrollIndicatorInsets.left == 0 && list.verticalScrollIndicatorInsets.right == 0)
            #expect(abs(list.contentOffset.x + inset.left) <= 1)
        }
    }

    /// RTL 原生组合列表中，语义前缘的留白应出现在画面右边。
    @Test func leadingMarginUsesMirroredListCoordinates() async throws {
        let configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        let list = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
        list.semanticContentAttribute = .forceRightToLeft
        var margin: CGFloat = 0
        let host = QuickLayoutView {
            QuickLayoutKit.List(list).contentMargins(.leading, margin)
        }
        host.semanticContentAttribute = .forceRightToLeft
        let controller = UIViewController()
        controller.view = host
        let window = try makeVisibleTestWindow(rootViewController: controller,
            size: CGSize(width: 350, height: 669), semanticContentAttribute: .forceRightToLeft)
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        host.layoutIfNeeded()
        #expect(list.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        // 同一窗口验证两种局部横轴。UIKit 是否自动镜像集合视图取决于布局和系统版本。
        for scale in [CGFloat(1), -1] {
            list.transform = CGAffineTransform(scaleX: scale, y: 1)
            margin = 0
            host.setNeedsLayout()
            host.layoutIfNeeded()
            let content = list.contentInset
            let indicator = list.verticalScrollIndicatorInsets
            margin = 19
            host.setNeedsLayout()
            host.layoutIfNeeded()
            let mirrored = list.convert(CGPoint(x: 1, y: 0), to: window).x < list.convert(CGPoint.zero, to: window).x
            let right: KeyPath<UIEdgeInsets, CGFloat> = mirrored ? \.left : \.right
            let left: KeyPath<UIEdgeInsets, CGFloat> = mirrored ? \.right : \.left
            #expect(list.contentInset[keyPath: right] - content[keyPath: right] == 19)
            #expect(list.contentInset[keyPath: left] == content[keyPath: left])
            #expect(list.verticalScrollIndicatorInsets[keyPath: right] - indicator[keyPath: right] == 19)
            #expect(list.verticalScrollIndicatorInsets[keyPath: left] == indicator[keyPath: left])
        }
    }

    /// 手动关闭自动 inset、嵌套宿主和声明移除也必须只消费一次。
    @Test func nativeInsetsDoNotAccumulateAndDeclarationsCanBeRemoved() {
        let scroll = UITableView()
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset = UIEdgeInsets(top: 5, left: 0, bottom: 7, right: 0)
        var extra = true
        var usesAdapter = true
        let nested = QuickLayoutView {
            if !usesAdapter {
                scroll.resizable()
            } else if extra {
                QuickLayoutKit.List(scroll)
                    .safeAreaPadding(.bottom, 12).contentMargins(.top, 8)
            } else {
                QuickLayoutKit.List(scroll)
            }
        }
        let host = NativeSafeAreaHost { nested.resizable() }
        host.quickLayoutKeyboardSafeAreaBehavior = .disabled
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 600)
        for _ in 0..<5 { host.setNeedsLayout(); host.layoutIfNeeded(); nested.setNeedsLayout(); nested.layoutIfNeeded() }
        #expect(scroll.convert(scroll.bounds, to: host) == host.bounds)
        #expect(abs(scroll.adjustedContentInset.top - CGFloat(20 + 5 + 8)) < 0.001)
        #expect(abs(scroll.adjustedContentInset.bottom - CGFloat(34 + 7 + 12)) < 0.001)
        extra = false
        for _ in 0..<5 { host.setNeedsLayout(); host.layoutIfNeeded(); nested.setNeedsLayout(); nested.layoutIfNeeded() }
        #expect(abs(scroll.adjustedContentInset.top - CGFloat(20 + 5)) < 0.001)
        #expect(abs(scroll.adjustedContentInset.bottom - CGFloat(34 + 7)) < 0.001)
        usesAdapter = false
        nested.setNeedsLayout()
        nested.layoutIfNeeded()
        #expect(scroll.contentInset == UIEdgeInsets(top: 5, left: 0, bottom: 7, right: 0))
    }

    /// 列表显式忽略容器后，UIKit 的局部 safeAreaInsets 不能在项目内部重新生效。
    @Test func ignoredListSafeAreaDoesNotReappearInsideItems() {
        let table = UITableView()
        table.contentInsetAdjustmentBehavior = .never
        let host = NativeSafeAreaHost { QuickLayoutKit.List(table).ignoresSafeArea(.container) }
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 600)
        host.layoutIfNeeded()
        let item = NativeSafeAreaHost { UIView().frame(width: 100, height: 40) }
        table.addSubview(item)
        #expect(item.sizeThatFits(CGSize(width: 300, height: CGFloat.infinity)).height == 40)
        #expect(table.adjustedContentInset == .zero)
    }

    /// 自行管理遮挡的原生滚动视图仍继承业务声明，不被 List 的内容边界接管。
    @Test func unmanagedScrollPreservesExplicitIgnoredContext() {
        let scroll = UIScrollView()
        scroll.contentInsetAdjustmentBehavior = .never
        let host = NativeSafeAreaHost { scroll.resizable().ignoresSafeArea(.all) }
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 600)
        host.layoutIfNeeded()
        let item = NativeSafeAreaHost { UIView().frame(width: 100, height: 40) }
        scroll.addSubview(item)
        item.frame = CGRect(x: 0, y: 0, width: 300, height: 40)
        #expect(item.sizeThatFits(CGSize(width: 300, height: CGFloat.infinity)).height == 40)
    }

    /// 插入栏保持在安全内容边界，预留量由原生列表 inset 承担。
    @Test func listSafeAreaInsetReservesContentWithoutShrinkingViewport() {
        let table = UITableView()
        table.contentInsetAdjustmentBehavior = .never
        let bar = UIView()
        let host = NativeSafeAreaHost {
            QuickLayoutKit.List(table).safeAreaInset(edge: .bottom, spacing: 8) {
                bar.resizable(axis: .horizontal).frame(height: 30)
            }
        }
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 600)
        for _ in 0..<4 { host.setNeedsLayout(); host.layoutIfNeeded() }
        #expect(table.convert(table.bounds, to: host) == host.bounds)
        #expect(abs(table.adjustedContentInset.bottom - 72) < 0.001)
        #expect(abs(bar.frame.maxY - 566) < 0.001)
    }

    /// 首页原生集合视图必须覆盖控制器，而非只覆盖其安全矩形。
    @Test func catalogViewportExtendsBehindSystemBars() async throws {
        let tabs = AppTabBarController(viewModel: AppNavigationViewModel(chatAvailable: false))
        let window = try makeVisibleTestWindow(rootViewController: tabs, size: CGSize(width: 402, height: 874))
        defer { window.isHidden = true }
        let split = try #require(tabs.featureControllers[.examples] as? ExampleSplitViewController)
        let menu = split.menuController
        for _ in 0..<8 { window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(30)) }
        let list = menu.collectionView
        let rect = list.convert(list.bounds, to: menu.view)
        #expect(abs(rect.minY - menu.view.bounds.minY) < 1)
        #expect(abs(rect.maxY - menu.view.bounds.maxY) < 1)
        #expect(list.adjustedContentInset.top >= menu.view.safeAreaInsets.top)
        #expect(list.adjustedContentInset.bottom >= menu.view.safeAreaInsets.bottom)
        #expect(list.contentInset == .zero)
    }

    /// 滚动到系统栏后方的补充视图不能把遮挡高度加入自身的自然尺寸。
    @Test func catalogHeaderHeightRemainsStableWhileScrolling() async throws {
        let controller = UINavigationController(rootViewController: MainViewController())
        let window = try makeVisibleTestWindow(rootViewController: controller)
        defer { window.isHidden = true }
        let menu = try #require(controller.viewControllers.first as? MainViewController)
        for _ in 0..<8 { window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(30)) }
        let list = menu.collectionView
        let header = try #require(list.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader).first as? MainMenuSectionHeaderView)
        let proposed = CGSize(width: header.bounds.width, height: CGFloat.infinity)
        let reference = header.sizeThatFits(proposed).height
        #expect(abs(reference - header.listContentView.sizeThatFits(proposed).height) < 1,
                "原生列表已处理安全边距，分组标题的自然高度不能再包含窗口安全区")
        for offset in [100.0, 300.0, 600.0, 0.0] {
            list.contentOffset.y = offset
            list.layoutIfNeeded()
            #expect(abs(header.sizeThatFits(proposed).height - reference) < 1,
                    "分组标题不能随滚动位置改变高度")
        }
    }

    /// 列表全屏视口与内容布局必须使用同一水平宽度，旋转后不能产生横向滚动范围。
    @Test func catalogCrossAxisRangeRemainsEmptyAcrossSafeAreaChanges() async throws {
        let menu = MainViewController()
        let navigation = UINavigationController(rootViewController: menu)
        let window = try makeVisibleTestWindow(rootViewController: navigation)
        defer { window.isHidden = true }
        for (size, side): (CGSize, CGFloat) in [
            (CGSize(width: 402, height: 874), 0),
            (CGSize(width: 874, height: 402), 62),
            (CGSize(width: 402, height: 874), 0),
        ] {
            window.frame.size = size
            navigation.view.frame = window.bounds
            menu.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: side, bottom: 0, right: side)
            for _ in 0..<8 {
                window.layoutIfNeeded()
                navigation.view.layoutIfNeeded()
                menu.view.setNeedsLayout()
                try await Task.sleep(for: .milliseconds(30))
            }
            let list = menu.collectionView
            let inset = list.adjustedContentInset
            let range = list.contentSize.width + inset.left + inset.right - list.bounds.width
            let info = "size=\(size) bounds=\(list.bounds) content=\(list.contentSize) inset=\(list.contentInset) adjusted=\(inset) safe=\(list.safeAreaInsets) offset=\(list.contentOffset)"
            #expect(range <= 1, "\(info)")
            #expect(abs(list.contentOffset.x + inset.left) <= 1, "\(info)")
        }
    }

    /// 与未包装的原生组合布局对照，交叉轴安全区不能重复添加；主滚动轴仍可滚动。
    @Test(arguments: [false, true])
    func compositionalCrossAxisMatchesNativeLayout(horizontal: Bool) async throws {
        let controller = UIViewController()
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 13, left: 21, bottom: 17, right: 33)
        let window = try makeVisibleTestWindow(rootViewController: controller)
        defer { window.isHidden = true }
        for reference: UIContentInsetsReference in [.automatic, .safeArea, .layoutMargins, .readableContent] {
            for adjustment: UIScrollView.ContentInsetAdjustmentBehavior in [.automatic, .always, .never] {
                func makeCollection() -> UICollectionView {
                    let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
                    let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(
                        widthDimension: horizontal ? .absolute(120) : .fractionalWidth(1),
                        heightDimension: horizontal ? .fractionalHeight(1) : .absolute(44)), subitems: [item])
                    let configuration = UICollectionViewCompositionalLayoutConfiguration()
                    configuration.scrollDirection = horizontal ? .horizontal : .vertical
                    configuration.contentInsetsReference = reference
                    let layout = UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: group), configuration: configuration)
                    let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
                    collection.contentInsetAdjustmentBehavior = adjustment
                    collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "row")
                    return collection
                }
                let native = makeCollection(), actual = makeCollection()
                let source = NativeCollectionRows()
                native.dataSource = source
                actual.dataSource = source
                let host = QuickLayoutView { QuickLayoutKit.List(actual) }
                controller.view.addSubview(native)
                controller.view.addSubview(host)
                native.frame = controller.view.bounds
                host.frame = controller.view.bounds
                for _ in 0..<6 {
                    controller.view.layoutIfNeeded()
                    host.setNeedsLayout()
                    try await Task.sleep(for: .milliseconds(20))
                }
                let inset = actual.adjustedContentInset
                let crossRange = horizontal
                    ? actual.contentSize.height + inset.top + inset.bottom - actual.bounds.height
                    : actual.contentSize.width + inset.left + inset.right - actual.bounds.width
                let info = "horizontal=\(horizontal) reference=\(reference.rawValue) adjustment=\(adjustment.rawValue) actual=\(actual.contentSize) / \(inset) native=\(native.contentSize) / \(native.adjustedContentInset)"
                let nativeInsets = native.adjustedContentInset
                let nativeRange = horizontal
                    ? native.contentSize.height + nativeInsets.top + nativeInsets.bottom - native.bounds.height
                    : native.contentSize.width + nativeInsets.left + nativeInsets.right - native.bounds.width
                #expect(abs(crossRange - nativeRange) < 1, "\(info)")
                let first = try #require(actual.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
                let referenceFirst = try #require(native.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
                #expect(abs((horizontal ? first.frame.minY : first.frame.minX) - (horizontal ? referenceFirst.frame.minY : referenceFirst.frame.minX)) < 1, "\(info)")
                #expect(horizontal ? actual.contentSize.width > actual.bounds.width : actual.contentSize.height > actual.bounds.height)
                host.removeFromSuperview()
                native.removeFromSuperview()
                withExtendedLifetime(source) {}
            }
        }
    }

    private func findScroll(_ root: UIView) -> UIScrollView? {
        if let scroll = root as? UIScrollView { return scroll }
        return root.subviews.lazy.compactMap { findScroll($0) }.first
    }
}

private final class NativeListRows: NSObject, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 80 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row") ?? UITableViewCell(style: .default, reuseIdentifier: "row")
        cell.textLabel?.text = "Row \(indexPath.row)"
        return cell
    }
}

private final class NativeSafeAreaHost: QuickLayoutView {
    override var safeAreaInsets: UIEdgeInsets { UIEdgeInsets(top: 20, left: 0, bottom: 34, right: 0) }
}

private final class NativeCollectionRows: NSObject, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 80 }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "row", for: indexPath)
    }
}
