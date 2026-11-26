import UIKit

extension UIViewController {
    /// 将标签项关联到此页面，可直接在 `tabPages` 闭包中使用。
    @discardableResult
    public func tabItem(_ item: UITabBarItem) -> Self {
        tabBarItem = item
        return self
    }
}

extension UITabBarController {
    /// 替换控制器管理的页面，按声明顺序展示。重排时保留仍在列表中的选中页面。
    @discardableResult
    public func tabPages(
        animated: Bool = false,
        @QuickLayoutBarContentBuilder<UIViewController> content: () -> [UIViewController]
    ) -> Self {
        setViewControllers(content(), animated: animated)
        return self
    }

    /// 安装原生标签，支持 `UITabGroup` 和 `UISearchTab`。
    @available(iOS 18.0, *)
    @discardableResult
    public func tabs(
        animated: Bool = false,
        @QuickLayoutBarContentBuilder<UITab> content: () -> [UITab]
    ) -> Self {
        setTabs(content(), animated: animated)
        return self
    }
}

extension UITabBar {
    /// 替换独立标签栏的标签项。对于控制器管理的标签栏，请使用控制器上的 `tabPages` 或 `tabs`。
    @discardableResult
    public func items(
        animated: Bool = false,
        @QuickLayoutBarContentBuilder<UITabBarItem> content: () -> [UITabBarItem]
    ) -> Self {
        setItems(content(), animated: animated)
        return self
    }
}
