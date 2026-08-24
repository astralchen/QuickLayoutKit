import UIKit

/// A QuickLayout implementation base for UIKit content configurations.
///
/// Subclass this type when a `UIContentConfiguration` renders QuickLayout
/// content. The base class restores direction from the nearest public reusable
/// owner before configuration, measurement, layout, and attachment work. This
/// covers UIKit's intermediate configuration hosts without inspecting or
/// modifying their private view hierarchy.
open class QuickLayoutContentView: QuickLayoutView, UIContentView {

    private var storedConfiguration: UIContentConfiguration

    /// The UIKit configuration represented by this content view.
    ///
    /// UIKit writes through this property as cells update configuration state.
    /// Every assignment restores reusable-owner direction before invoking
    /// ``applyContentConfiguration(_:)``. Business subclasses validate their
    /// concrete configuration type at that single boundary, matching UIKit's
    /// native type-erased `UIContentView` contract.
    public final var configuration: UIContentConfiguration {
        get {
            storedConfiguration
        }
        set {
            storedConfiguration = newValue
            synchronizeConfiguredDirectionIfNeeded()
            applyContentConfiguration(newValue)
        }
    }

    /// Creates QuickLayout content for a UIKit content configuration.
    public init(configuration: UIContentConfiguration) {
        storedConfiguration = configuration
        super.init(frame: .zero)
        quickLayoutSemanticDirectionBehavior =
            .followEnclosingReusableView
    }

    @available(*, unavailable, message: "Use init(configuration:) instead.")
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Applies the current configuration after subclass initialization.
    ///
    /// Call this once at the end of a subclass initializer, after its content
    /// views have been configured. Later `configuration` assignments invoke
    /// the same override automatically.
    public final func applyCurrentContentConfiguration() {
        synchronizeConfiguredDirectionIfNeeded()
        applyContentConfiguration(storedConfiguration)
    }

    /// Responds when `configuration` changes.
    ///
    /// Subclasses validate the concrete configuration type, update their
    /// application-owned content, and then call `super`. Keeping the parameter
    /// type-erased here mirrors `UIContentView` instead of introducing a
    /// parallel generic type system. The default implementation invalidates
    /// QuickLayout measurement and placement.
    open func applyContentConfiguration(
        _ configuration: UIContentConfiguration
    ) {
        setNeedsQuickLayout()
    }

    @discardableResult
    private func synchronizeConfiguredDirectionIfNeeded() -> Bool {
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
    }
}
