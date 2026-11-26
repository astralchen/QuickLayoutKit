import UIKit

@MainActor private var navigationTitleRenameKey: UInt8 = 0

@available(iOS 16.0, *)
@MainActor
private final class NavigationTitleRenameHandler: UINavigationItemRenameDelegate {
    let onRename: (String) -> Void

    init(_ onRename: @escaping (String) -> Void) {
        self.onRename = onRename
    }

    func navigationItem(_ navigationItem: UINavigationItem, didEndRenamingWith title: String) {
        // UIKit 已提交标题，应用可以在回调中进一步校正它。
        onRename(title)
    }
}

/// 原生可定制栏项目组的位置。
@available(iOS 16.0, *)
public enum QuickLayoutToolbarGroupPlacement: Sendable {
    case topBarLeading
    case center
    case topBarTrailing
}

/// 溢出按钮和搜索按钮之后的固定组位置。
@available(iOS 16.0, *)
public enum QuickLayoutPinnedGroupPlacement: Sendable {
    case topBarPinnedTrailing
}

@available(iOS 16.0, *)
public extension UINavigationItem {
    /// 设置标题并接收系统已提交的重命名。导航项目持有回调，传入 nil 解除 DSL 安装的代理。
    @discardableResult
    func navigationTitle(_ title: String?, onRename: ((String) -> Void)?) -> Self {
        self.title = title
        if let onRename {
            let handler = NavigationTitleRenameHandler(onRename)
            objc_setAssociatedObject(self, &navigationTitleRenameKey, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            renameDelegate = handler
        } else {
            let handler = objc_getAssociatedObject(self, &navigationTitleRenameKey) as? NavigationTitleRenameHandler
            if let handler, renameDelegate === handler { renameDelegate = nil }
            objc_setAssociatedObject(self, &navigationTitleRenameKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return self
    }

    /// 安装文档元数据和调用方提供的共享、拖放配置。
    @discardableResult
    func navigationDocument(_ properties: UIDocumentProperties?) -> Self {
        documentProperties = properties
        return self
    }

    /// 让 UIKit 根据 URL 获取文档元数据。
    @discardableResult
    func navigationDocument(_ url: URL) -> Self {
        navigationDocument(UIDocumentProperties(url: url))
    }

    /// 自定义当前导航项目的系统返回操作。
    @discardableResult
    func navigationBarBackAction(_ action: UIAction?) -> Self {
        backAction = action
        return self
    }

    /// UIKit 通过此标识保存和恢复用户的工具栏定制。
    @discardableResult
    func toolbar(id: String?) -> Self {
        customizationIdentifier = id
        return self
    }

    /// 替换一个位置的原生组。UIKit 会以同侧的新组替换先前配置的普通按钮。
    @discardableResult
    func toolbar(
        placement: QuickLayoutToolbarGroupPlacement,
        @QuickLayoutBarContentBuilder<UIBarButtonItemGroup> content: () -> [UIBarButtonItemGroup]
    ) -> Self {
        let groups = content()
        switch placement {
        case .topBarLeading: leadingItemGroups = groups
        case .center: centerItemGroups = groups
        case .topBarTrailing: trailingItemGroups = groups
        }
        return self
    }

    /// 安装单个固定后缘组。返回 nil 清除该组。
    @discardableResult
    func toolbar(placement: QuickLayoutPinnedGroupPlacement, content: () -> UIBarButtonItemGroup?) -> Self {
        pinnedTrailingGroup = content()
        return self
    }

    /// 提供原生延迟菜单内容，传入 nil 恢复系统溢出行为。
    @discardableResult
    func toolbarOverflowMenu(_ element: UIDeferredMenuElement?) -> Self {
        additionalOverflowItems = element
        return self
    }

    /// 将声明的操作追加到系统溢出菜单。空内容清除这一配置。
    @discardableResult
    func toolbarOverflowMenu(
        @QuickLayoutBarContentBuilder<UIMenuElement> content: () -> [UIMenuElement]
    ) -> Self {
        let items = content()
        return toolbarOverflowMenu(items.isEmpty ? nil : UIDeferredMenuElement { completion in completion(items) })
    }
}

@available(iOS 17.0, *)
public extension UINavigationItem {
    /// 与 SwiftUI 同名的工具栏标题显示模式。
    @discardableResult
    func toolbarTitleDisplayMode(_ mode: QuickLayoutNavigationTitleDisplayMode) -> Self {
        navigationBarTitleDisplayMode(mode)
    }
}

/// 工具栏中搜索框收起时的展示偏好。
@available(iOS 26.0, *)
public enum QuickLayoutSearchToolbarBehavior: Sendable {
    case automatic
    case minimize
}

@available(iOS 26.0, *)
public enum QuickLayoutLargeTitlePlacement: Sendable {
    case largeTitle
}

@available(iOS 26.0, *)
public extension UIViewController {
    /// 设置展开时的大标题文本。返回 nil 恢复使用页面标题。
    @discardableResult
    func toolbar(placement: QuickLayoutLargeTitlePlacement, content: () -> String?) -> Self {
        navigationItem.largeTitle = content()
        return self
    }
}

@available(iOS 26.0, *)
public extension UINavigationItem {
    @discardableResult
    func navigationTitle(attributed title: AttributedString?) -> Self {
        attributedTitle = title
        return self
    }

    @discardableResult
    func navigationSubtitle(attributed subtitle: AttributedString?) -> Self {
        attributedSubtitle = subtitle
        return self
    }

    @discardableResult
    func navigationLargeSubtitle(_ subtitle: String?) -> Self {
        largeSubtitle = subtitle
        return self
    }

    @discardableResult
    func navigationLargeSubtitle(attributed subtitle: AttributedString?) -> Self {
        largeAttributedSubtitle = subtitle
        return self
    }

    /// 指定搜索布局偏好。与 searchable 的 placement 按调用顺序生效。
    @discardableResult
    func searchToolbarBehavior(_ behavior: QuickLayoutSearchToolbarBehavior) -> Self {
        preferredSearchBarPlacement = behavior == .minimize ? .integratedButton : .automatic
        return self
    }

    @discardableResult
    func searchToolbarIntegration(_ allowed: Bool) -> Self {
        searchBarPlacementAllowsToolbarIntegration = allowed
        return self
    }

    @discardableResult
    func searchExternalIntegration(_ allowed: Bool) -> Self {
        searchBarPlacementAllowsExternalIntegration = allowed
        return self
    }
}

#if compiler(>=6.4)
@available(iOS 27.0, *)
public extension UINavigationItem {
    @discardableResult
    func toolbarMinimizationBehavior(_ behavior: UIBarMinimizationBehavior) -> Self {
        navigationBarMinimization.minimizationBehavior = behavior
        return self
    }

    @discardableResult
    func toolbarMinimizationSafeAreaAdjustment(_ adjustment: UIBarMinimizationSafeAreaAdjustment) -> Self {
        navigationBarMinimization.safeAreaAdjustment = adjustment
        return self
    }

    @discardableResult
    func toolbarMinimizationRestoration(_ restoration: UIBarMinimizationRestorationBehavior) -> Self {
        navigationBarMinimization.restorationBehavior = restoration
        return self
    }
}
#endif

#if compiler(>=6.4.1)
/// 垂直栏空间不足时优先保留的内容，取值与 SwiftUI 的工具栏压缩策略一致。
@available(iOS 27.1, *)
public enum QuickLayoutToolbarVerticalCompressionBehavior: Sendable {
    case automatic
    case prefersToolbarItems
    case prefersTabBar
}

@available(iOS 27.1, *)
public extension UINavigationItem {
    @discardableResult
    func toolbarVerticalCompressionBehavior(_ behavior: QuickLayoutToolbarVerticalCompressionBehavior) -> Self {
        verticalBarCompressionBehavior = switch behavior {
        case .automatic: .automatic
        case .prefersToolbarItems: .prefersBarItems
        case .prefersTabBar: .prefersTabBar
        }
        return self
    }
}
#endif

#if compiler(>=6.4.2)
@available(iOS 27.2, *)
public extension UINavigationItem {
    @discardableResult
    func toolbarTitleAlignment(_ alignment: UINavigationItem.TitleAlignment) -> Self {
        titleAlignment = alignment
        return self
    }
}
#endif
