import UIKit
import QuickLayout

/// 可能影响 QuickLayout 测量和放置的 UIKit 状态快照。
public struct QuickLayoutEnvironment: Equatable {

    /// 当前环境快照对应的环境变化原因类型。
    public typealias ChangeReason = QuickLayoutEnvironmentChangeReason

    /// 当前有效的 QuickLayout 布局方向。
    public let layoutDirection: LayoutDirection

    /// 当前动态字体内容尺寸类别。
    public let preferredContentSizeCategory: UIContentSizeCategory

    /// 当前水平尺寸类别。
    public let horizontalSizeClass: UIUserInterfaceSizeClass

    /// 当前垂直尺寸类别。
    public let verticalSizeClass: UIUserInterfaceSizeClass

    /// 当前用户界面样式。
    public let userInterfaceStyle: UIUserInterfaceStyle

    /// 当前显示比例。
    public let displayScale: CGFloat

    /// 使用 QuickLayout 前缘和后缘语义表示的安全区域边距。
    public let safeAreaInsets: EdgeInsets

    /// 使用 QuickLayout 前缘和后缘语义表示的布局边距。
    public let layoutMargins: EdgeInsets

    /// QuickLayout 宿主当前的边界尺寸。
    public let containerSize: CGSize

    /// 创建环境快照。
    ///
    /// - Parameters:
    ///   - layoutDirection: 当前有效的布局方向。
    ///   - preferredContentSizeCategory: 当前动态字体内容尺寸类别。
    ///   - horizontalSizeClass: 当前水平尺寸类别。
    ///   - verticalSizeClass: 当前垂直尺寸类别。
    ///   - userInterfaceStyle: 当前用户界面样式。
    ///   - displayScale: 当前显示比例。
    ///   - safeAreaInsets: 使用方向性语义表示的安全区域边距。
    ///   - layoutMargins: 使用方向性语义表示的布局边距。
    ///   - containerSize: 宿主当前的边界尺寸。
    public init(
        layoutDirection: LayoutDirection,
        preferredContentSizeCategory: UIContentSizeCategory,
        horizontalSizeClass: UIUserInterfaceSizeClass,
        verticalSizeClass: UIUserInterfaceSizeClass,
        userInterfaceStyle: UIUserInterfaceStyle,
        displayScale: CGFloat,
        safeAreaInsets: EdgeInsets,
        layoutMargins: EdgeInsets,
        containerSize: CGSize
    ) {
        self.layoutDirection = layoutDirection
        self.preferredContentSizeCategory = preferredContentSizeCategory
        self.horizontalSizeClass = horizontalSizeClass
        self.verticalSizeClass = verticalSizeClass
        self.userInterfaceStyle = userInterfaceStyle
        self.displayScale = displayScale
        self.safeAreaInsets = safeAreaInsets
        self.layoutMargins = layoutMargins
        self.containerSize = containerSize
    }

    public static func == (lhs: QuickLayoutEnvironment, rhs: QuickLayoutEnvironment) -> Bool {
        lhs.layoutDirection == rhs.layoutDirection
            && lhs.preferredContentSizeCategory == rhs.preferredContentSizeCategory
            && lhs.horizontalSizeClass == rhs.horizontalSizeClass
            && lhs.verticalSizeClass == rhs.verticalSizeClass
            && lhs.userInterfaceStyle == rhs.userInterfaceStyle
            && lhs.displayScale == rhs.displayScale
            && lhs.safeAreaInsets.quickLayout_isEqual(to: rhs.safeAreaInsets)
            && lhs.layoutMargins.quickLayout_isEqual(to: rhs.layoutMargins)
            && lhs.containerSize == rhs.containerSize
    }

    /// 返回与先前快照不同的环境值。
    ///
    /// - Parameter previous: 要与当前值比较的先前快照。
    /// - Returns: 描述所有已变化环境值的选项集合。
    public func changes(from previous: QuickLayoutEnvironment) -> ChangeReason {
        var reason: ChangeReason = []

        if layoutDirection != previous.layoutDirection {
            reason.insert(.layoutDirection)
        }
        if preferredContentSizeCategory != previous.preferredContentSizeCategory {
            reason.insert(.preferredContentSizeCategory)
        }
        if horizontalSizeClass != previous.horizontalSizeClass || verticalSizeClass != previous.verticalSizeClass {
            reason.insert(.sizeClass)
        }
        if userInterfaceStyle != previous.userInterfaceStyle {
            reason.insert(.userInterfaceStyle)
        }
        if displayScale != previous.displayScale {
            reason.insert(.displayScale)
        }
        if !safeAreaInsets.quickLayout_isEqual(to: previous.safeAreaInsets) {
            reason.insert(.safeArea)
        }
        if !layoutMargins.quickLayout_isEqual(to: previous.layoutMargins) {
            reason.insert(.layoutMargins)
        }
        if containerSize != previous.containerSize {
            reason.insert(.containerSize)
        }

        return reason
    }
}

/// 描述 `QuickLayoutEnvironment` 中发生变化的部分。
public struct QuickLayoutEnvironmentChangeReason: OptionSet, Sendable {

    /// 变化原因选项集合的原始位掩码。
    public let rawValue: Int

    /// 使用原始值创建环境变化原因。
    ///
    /// - Parameter rawValue: 变化原因的位掩码。
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// 有效布局方向发生变化。
    public static let layoutDirection = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 0)

    /// 动态字体内容尺寸类别发生变化。
    public static let preferredContentSizeCategory = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 1)

    /// 水平或垂直尺寸类别发生变化。
    public static let sizeClass = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 2)

    /// 用户界面样式发生变化。
    public static let userInterfaceStyle = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 3)

    /// 显示比例发生变化。
    public static let displayScale = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 4)

    /// 安全区域边距发生变化。
    public static let safeArea = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 5)

    /// 布局边距发生变化。
    public static let layoutMargins = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 6)

    /// 宿主边界尺寸发生变化。
    public static let containerSize = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 7)

    /// UIKit 报告特征集合发生变化。
    ///
    /// 此原因用于补充单独跟踪的特征值，使新增或尚未建模的 UIKit 特征仍能使
    /// QuickLayout 布局失效。
    public static let traitCollection = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 8)

    /// QuickLayoutKit 跟踪的所有环境值。
    public static let all: QuickLayoutEnvironmentChangeReason = [
        .layoutDirection,
        .preferredContentSizeCategory,
        .sizeClass,
        .userInterfaceStyle,
        .displayScale,
        .safeArea,
        .layoutMargins,
        .containerSize,
        .traitCollection,
    ]
}

/// 能够响应 QuickLayout 环境变化的类型。
@MainActor
public protocol QuickLayoutEnvironmentUpdating: AnyObject {

    /// 影响 QuickLayout 的 UIKit 状态发生变化时调用。
    ///
    /// - Parameters:
    ///   - environment: 变化后的当前环境快照。
    ///   - reason: 描述发生变化部分的原因集合。
    func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    )
}

@MainActor
/// 存储单个 QuickLayout 宿主最近一次观察到的环境。
///
/// 当 UIKit 因同一次语言、特征或方向变化调用多个生命周期方法时，通过比较快照避免重复
/// 使布局失效。
final class _QuickLayoutEnvironmentState {

    private var lastEnvironment: QuickLayoutEnvironment?

    @discardableResult
    func update(
        _ host: UIView & QuickLayoutEnvironmentUpdating,
        explicitReason: QuickLayoutEnvironmentChangeReason = []
    ) -> Bool {
        let environment = host.quickLayoutEnvironment
        let reason: QuickLayoutEnvironmentChangeReason

        if let lastEnvironment {
            reason = environment
                .changes(from: lastEnvironment)
                .union(explicitReason)
        } else {
            reason = explicitReason
        }

        self.lastEnvironment = environment
        guard !reason.isEmpty else { return false }

        host.quickLayoutEnvironmentDidChange(environment, reason: reason)
        return true
    }
}

extension UIView {

    /// 视图当前的 QuickLayout 环境。
    public var quickLayoutEnvironment: QuickLayoutEnvironment {
        QuickLayoutEnvironment(
            layoutDirection: quickLayoutDirection,
            preferredContentSizeCategory: traitCollection.preferredContentSizeCategory,
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            verticalSizeClass: traitCollection.verticalSizeClass,
            userInterfaceStyle: traitCollection.userInterfaceStyle,
            displayScale: traitCollection.displayScale,
            safeAreaInsets: quickLayoutSafeAreaInsets,
            layoutMargins: quickLayoutDirectionalLayoutMargins,
            containerSize: bounds.size
        )
    }

    /// 使用 QuickLayout 方向表示的视图有效布局方向。
    public var quickLayoutDirection: LayoutDirection {
        effectiveUserInterfaceLayoutDirection.quickLayoutDirection
    }
}

extension UIUserInterfaceLayoutDirection {

    /// 使用 QuickLayout 方向表示的 UIKit 布局方向。
    public var quickLayoutDirection: LayoutDirection {
        switch self {
        case .rightToLeft:
            return .rightToLeft
        case .leftToRight:
            return .leftToRight
        @unknown default:
            return .leftToRight
        }
    }
}

private extension EdgeInsets {

    func quickLayout_isEqual(to other: EdgeInsets) -> Bool {
        top == other.top
            && leading == other.leading
            && bottom == other.bottom
            && trailing == other.trailing
    }
}
