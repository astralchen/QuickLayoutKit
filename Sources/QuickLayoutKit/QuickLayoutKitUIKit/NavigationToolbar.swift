import UIKit

/// 单个导航项目的标题显示偏好。导航栏通过 `prefersLargeTitles` 启用大标题。
public enum QuickLayoutNavigationTitleDisplayMode: Sendable {
    case automatic
    case inline
    case large
    /// 同行显示大标题，由 UIKit 根据返回键和可用空间调整布局。
    @available(iOS 17.0, *)
    case inlineLarge
}

/// 控制当前页面导航栏的布局角色。
@available(iOS 16.0, *)
public enum QuickLayoutToolbarRole: Sendable {
    case navigationStack
    case browser
    case editor
}

/// 导航栏搜索框的位置，对应 SwiftUI 的搜索位置与抽屉显示模式。
public enum QuickLayoutSearchFieldPlacement: Sendable {
    public enum NavigationBarDrawerDisplayMode: Sendable {
        /// 允许搜索框随内容滚动收起。
        case automatic
        /// 滚动时保留搜索框。
        case always
    }

    /// 由 UIKit 选择位置，并允许随内容滚动收起。
    case automatic
    /// 将搜索框放在导航标题下方。
    case navigationBarDrawer(displayMode: NavigationBarDrawerDisplayMode = .automatic)

    /// 标题下方的默认抽屉，允许随滚动收起。
    public static var navigationBarDrawer: Self { .navigationBarDrawer(displayMode: .automatic) }

    /// 在栏项目中呈现搜索框，由 UIKit 根据容器决定实际位置。
    @available(iOS 26.0, *)
    case integrated
    @available(iOS 26.0, *)
    case integratedCentered
    @available(iOS 26.0, *)
    case integratedButton
}

extension UINavigationItem {
    /// 设置页面的导航标题。传入 `nil` 可清除指定的标题。
    @discardableResult
    public func navigationTitle(_ title: String?) -> Self {
        self.title = title
        return self
    }

    /// 设置标题下方的原生副标题。传入 `nil` 清除副标题文本。
    @available(iOS 26.0, *)
    @discardableResult
    public func navigationSubtitle(_ subtitle: String?) -> Self {
        self.subtitle = subtitle
        return self
    }

    /// 设置当前页面的标题模式。
    @discardableResult
    public func navigationBarTitleDisplayMode(_ mode: QuickLayoutNavigationTitleDisplayMode) -> Self {
        switch mode {
        case .automatic: largeTitleDisplayMode = .automatic
        case .inline: largeTitleDisplayMode = .never
        case .large: largeTitleDisplayMode = .always
        case .inlineLarge:
            if #available(iOS 17.0, *) { largeTitleDisplayMode = .inline }
        }
        return self
    }

    /// 设置当前页面是否隐藏系统返回按钮。
    @discardableResult
    public func navigationBarBackButtonHidden(_ hidden: Bool = true) -> Self {
        navigationBarBackButtonHidden(hidden, animated: false)
    }

    /// 使用 UIKit 指定的动画选项隐藏或显示返回键。
    @discardableResult
    public func navigationBarBackButtonHidden(_ hidden: Bool = true, animated: Bool) -> Self {
        setHidesBackButton(hidden, animated: animated)
        return self
    }

    /// 允许前缘按钮与系统返回键同时显示。传入 `false` 时前缘按钮占用返回键的位置。
    @discardableResult
    public func navigationBarLeadingItemsSupplementBackButton(_ supplement: Bool = true) -> Self {
        leftItemsSupplementBackButton = supplement
        return self
    }

    /// 设置导航栏布局角色。
    @available(iOS 16.0, *)
    @discardableResult
    public func toolbarRole(_ role: QuickLayoutToolbarRole) -> Self {
        style = switch role {
        case .navigationStack: .navigator
        case .browser: .browser
        case .editor: .editor
        }
        return self
    }

    /// 在 UIKit 请求标题菜单时构建菜单。闭包接收系统建议操作，传入 `nil` 移除提供者。
    @available(iOS 16.0, *)
    @discardableResult
    public func toolbarTitleMenu(_ provider: (([UIMenuElement]) -> UIMenu?)?) -> Self {
        titleMenuProvider = provider
        return self
    }

    /// 指定从下一页返回当前页时使用的按钮标题。传入 `nil` 恢复 UIKit 的标题选择。
    @discardableResult
    public func navigationBarBackButtonTitle(_ title: String?) -> Self {
        backButtonTitle = title
        return self
    }

    /// 设置从下一页返回当前页时的按钮标题显示模式。
    @discardableResult
    public func navigationBarBackButtonDisplayMode(_ mode: UINavigationItem.BackButtonDisplayMode) -> Self {
        backButtonDisplayMode = mode
        return self
    }

    /// 安装调用方配置的搜索控制器。传入 `nil` 移除搜索框。
    /// 提供 `prompt` 时更新占位文本，省略时沿用搜索框现有的文本。
    @discardableResult
    public func searchable(
        _ controller: UISearchController?,
        placement: QuickLayoutSearchFieldPlacement = .automatic,
        prompt: String? = nil
    ) -> Self {
        if let controller {
            switch placement {
            case .automatic:
                hidesSearchBarWhenScrolling = true
                if #available(iOS 16.0, *) { preferredSearchBarPlacement = .automatic }
            case .navigationBarDrawer(let displayMode):
                hidesSearchBarWhenScrolling = displayMode == .automatic
                if #available(iOS 16.0, *) { preferredSearchBarPlacement = .stacked }
            case .integrated:
                if #available(iOS 26.0, *) { preferredSearchBarPlacement = .integrated }
            case .integratedCentered:
                if #available(iOS 26.0, *) { preferredSearchBarPlacement = .integratedCentered }
            case .integratedButton:
                if #available(iOS 26.0, *) { preferredSearchBarPlacement = .integratedButton }
            }
            if let prompt { controller.searchBar.placeholder = prompt }
        }
        if searchController !== controller { searchController = controller }
        return self
    }

    /// 为当前页面的标准、紧凑以及各自的滚动边缘状态设置完整外观。
    /// 传入 `nil` 时四个状态均恢复继承导航栏的设置。
    @discardableResult
    public func navigationBarAppearance(_ appearance: UINavigationBarAppearance?) -> Self {
        standardAppearance = appearance
        compactAppearance = appearance
        scrollEdgeAppearance = appearance
        compactScrollEdgeAppearance = appearance
        return self
    }
}

/// 页面中可以放置一组原生栏按钮的位置。
public enum QuickLayoutBarButtonPlacement: Sendable {
    case topBarLeading
    case topBarTrailing
    case bottomBar
}

/// 页面中可以放置单个标题视图的位置。
public enum QuickLayoutTitleViewPlacement: Sendable {
    case principal
    /// 在标题位置显示自定义视图，与 `.principal` 共用 UIKit 的 `titleView`。
    public static var title: Self { .principal }
    @available(iOS 26.0, *)
    case subtitle
    @available(iOS 26.0, *)
    case largeSubtitle
}

/// 按声明顺序收集工具栏或标签栏的内容，支持条件和循环。
@resultBuilder
public enum QuickLayoutBarContentBuilder<Item> {
    public static func buildExpression(_ item: Item) -> [Item] {
        [item]
    }

    /// 可选项为 `nil` 时跳过该项。
    public static func buildExpression(_ item: Item?) -> [Item] {
        item.map { [$0] } ?? []
    }

    /// 允许空元组及返回 `Void` 的配置语句出现在内容中。
    public static func buildExpression(_: Void) -> [Item] {
        []
    }

    public static func buildBlock(_ components: [Item]...) -> [Item] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [Item]?) -> [Item] {
        component ?? []
    }

    public static func buildEither(first component: [Item]) -> [Item] {
        component
    }

    public static func buildEither(second component: [Item]) -> [Item] {
        component
    }

    public static func buildArray(_ components: [[Item]]) -> [Item] {
        components.flatMap { $0 }
    }
}

/// 用于原生工具栏按钮的构建器。
public typealias QuickLayoutBarButtonItemBuilder = QuickLayoutBarContentBuilder<UIBarButtonItem>

extension UIViewController {
    /// 声明本页在导航控制器底部工具栏中的按钮，支持在入栈前配置。
    /// 空内容清空本页按钮，动画参数原样传给 UIKit。
    @discardableResult
    public func toolbarItems(
        animated: Bool = false,
        @QuickLayoutBarButtonItemBuilder content: () -> [UIBarButtonItem]
    ) -> Self {
        setToolbarItems(content(), animated: animated)
        return self
    }

    /// 按 UIKit 数组顺序替换指定位置的按钮，空内容会清空该位置。
    /// 底部按钮属于本页面，底部栏显隐由导航控制器管理。
    @discardableResult
    public func toolbar(
        placement: QuickLayoutBarButtonPlacement,
        animated: Bool = false,
        @QuickLayoutBarButtonItemBuilder content: () -> [UIBarButtonItem]
    ) -> Self {
        switch placement {
        case .topBarLeading: navigationItem.setLeftBarButtonItems(content(), animated: animated)
        case .topBarTrailing: navigationItem.setRightBarButtonItems(content(), animated: animated)
        case .bottomBar: toolbarItems(animated: animated, content: content)
        }
        return self
    }

    /// 替换指定位置的标题或副标题视图。返回 `nil` 恢复该位置的系统文本展示。
    @discardableResult
    public func toolbar(placement: QuickLayoutTitleViewPlacement, content: () -> UIView?) -> Self {
        switch placement {
        case .principal: navigationItem.titleView = content()
        case .subtitle:
            if #available(iOS 26.0, *) { navigationItem.subtitleView = content() }
        case .largeSubtitle:
            if #available(iOS 26.0, *) { navigationItem.largeSubtitleView = content() }
        }
        return self
    }
}

/// 导航控制器可以独立显示或隐藏的系统栏。
public enum QuickLayoutNavigationBarPlacement: Sendable {
    case navigationBar
    case bottomBar
}

public enum QuickLayoutToolbarVisibility: Sendable {
    case visible
    case hidden
}

/// UIKit 自动收起导航栏和底部工具栏的条件，可以组合使用。
public struct QuickLayoutBarHidingBehavior: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let onSwipe = Self(rawValue: 1 << 0)
    public static let onTap = Self(rawValue: 1 << 1)
    public static let whenKeyboardAppears = Self(rawValue: 1 << 2)
    public static let whenVerticallyCompact = Self(rawValue: 1 << 3)
}

extension UINavigationController {
    /// 更新当前栈顶页面的底部按钮。空导航栈会跳过配置，空内容清空栈顶页面的按钮。
    @discardableResult
    public func toolbar(
        animated: Bool = false,
        @QuickLayoutBarButtonItemBuilder content: () -> [UIBarButtonItem]
    ) -> Self {
        topViewController?.toolbarItems(animated: animated, content: content)
        return self
    }

    /// 设置导航控制器管理的系统栏显隐，默认针对底部工具栏。
    @discardableResult
    public func toolbarVisibility(
        _ visibility: QuickLayoutToolbarVisibility,
        for placement: QuickLayoutNavigationBarPlacement = .bottomBar,
        animated: Bool = false
    ) -> Self {
        let hidden = visibility == .hidden
        switch placement {
        case .bottomBar: setToolbarHidden(hidden, animated: animated)
        case .navigationBar: setNavigationBarHidden(hidden, animated: animated)
        }
        return self
    }

    /// 为系统底部工具栏的标准、紧凑及对应滚动边缘状态提供相同外观。
    @discardableResult
    public func toolbarAppearance(_ appearance: UIToolbarAppearance) -> Self {
        toolbar.standardAppearance = appearance
        toolbar.compactAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance
        toolbar.compactScrollEdgeAppearance = appearance
        return self
    }

    /// 替换两条系统栏共享的自动收起条件。空集合关闭这些条件。
    @discardableResult
    public func barsHidingBehavior(_ behavior: QuickLayoutBarHidingBehavior) -> Self {
        hidesBarsOnSwipe = behavior.contains(.onSwipe)
        hidesBarsOnTap = behavior.contains(.onTap)
        hidesBarsWhenKeyboardAppears = behavior.contains(.whenKeyboardAppears)
        hidesBarsWhenVerticallyCompact = behavior.contains(.whenVerticallyCompact)
        return self
    }
}

extension UIToolbar {
    /// 按声明顺序替换工具栏上的按钮。空内容会清空工具栏。
    @discardableResult
    public func items(
        animated: Bool = false,
        @QuickLayoutBarButtonItemBuilder content: () -> [UIBarButtonItem]
    ) -> Self {
        setItems(content(), animated: animated)
        return self
    }
}
