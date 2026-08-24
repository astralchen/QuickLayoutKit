import UIKit
import QuickLayout

/// A snapshot of UIKit state that can affect QuickLayout measurement and
/// placement.
public struct QuickLayoutEnvironment: Equatable {

    /// A discoverable spelling for environment change reasons scoped to an
    /// environment snapshot.
    public typealias ChangeReason = QuickLayoutEnvironmentChangeReason

    /// The effective QuickLayout layout direction.
    public let layoutDirection: LayoutDirection

    /// The current Dynamic Type content size category.
    public let preferredContentSizeCategory: UIContentSizeCategory

    /// The current horizontal size class.
    public let horizontalSizeClass: UIUserInterfaceSizeClass

    /// The current vertical size class.
    public let verticalSizeClass: UIUserInterfaceSizeClass

    /// The current interface style.
    public let userInterfaceStyle: UIUserInterfaceStyle

    /// The current display scale.
    public let displayScale: CGFloat

    /// Safe-area insets expressed in QuickLayout leading/trailing terms.
    public let safeAreaInsets: EdgeInsets

    /// Layout margins expressed in QuickLayout leading/trailing terms.
    public let layoutMargins: EdgeInsets

    /// The current bounds size of the QuickLayout host.
    public let containerSize: CGSize

    /// Creates an environment snapshot.
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

    /// Returns the environment values that differ from an earlier snapshot.
    ///
    /// - Parameter previous: The snapshot to compare with the receiver.
    /// - Returns: An option set describing every changed environment value.
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

/// Describes which parts of a `QuickLayoutEnvironment` changed.
public struct QuickLayoutEnvironmentChangeReason: OptionSet, Sendable {

    public let rawValue: Int

    /// Creates a change reason.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The effective layout direction changed.
    public static let layoutDirection = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 0)

    /// The Dynamic Type content size category changed.
    public static let preferredContentSizeCategory = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 1)

    /// The horizontal or vertical size class changed.
    public static let sizeClass = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 2)

    /// The interface style changed.
    public static let userInterfaceStyle = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 3)

    /// The display scale changed.
    public static let displayScale = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 4)

    /// The safe-area insets changed.
    public static let safeArea = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 5)

    /// The layout margins changed.
    public static let layoutMargins = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 6)

    /// The host's bounds size changed.
    public static let containerSize = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 7)

    /// UIKit reported a trait-collection change.
    ///
    /// This reason complements the individually tracked trait values so a new
    /// or otherwise unmodeled UIKit trait still invalidates QuickLayout.
    public static let traitCollection = QuickLayoutEnvironmentChangeReason(rawValue: 1 << 8)

    /// Every environment value tracked by QuickLayoutKit.
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

/// A type that can react to QuickLayout environment changes.
@MainActor
public protocol QuickLayoutEnvironmentUpdating: AnyObject {

    /// Called when UIKit state that affects QuickLayout changes.
    func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    )
}

@MainActor
/// Stores the last environment seen by one QuickLayout host.
///
/// Comparing snapshots prevents repeated layout invalidation when UIKit calls
/// several lifecycle hooks for the same language, trait, or direction change.
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

    /// The view's current QuickLayout environment.
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

    /// The view's effective layout direction expressed as QuickLayout direction.
    public var quickLayoutDirection: LayoutDirection {
        effectiveUserInterfaceLayoutDirection.quickLayoutDirection
    }
}

extension UIUserInterfaceLayoutDirection {

    /// The UIKit direction expressed as QuickLayout direction.
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
