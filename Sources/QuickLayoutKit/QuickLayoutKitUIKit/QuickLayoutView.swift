import UIKit
import QuickLayout

/// A reusable view that hosts QuickLayout content.
///
/// Use `QuickLayoutView` when a QuickLayout hierarchy needs to be embedded in
/// an existing UIKit view controller, table view cell, collection view cell, or
/// reusable view without introducing a dedicated view controller subclass.
open class QuickLayoutView: UIView, HasBody, QuickLayoutUpdating, QuickLayoutEnvironmentUpdating {

    private var contentProvider: (() -> Layout)?
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()

    /// The semantic role used to resolve the hosted layout direction.
    ///
    /// App-level language switching commonly updates this property directly.
    /// Publish the new effective direction immediately and invalidate the
    /// hosted body instead of waiting for a later trait or layout callback.
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    /// Creates a hosting view with no content.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    /// Creates a hosting view from Interface Builder.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }

    /// Creates a hosting view with inline QuickLayout content.
    ///
    /// - Parameter content: A closure that returns the hosted layout.
    public convenience init(@LayoutBuilder content: @escaping () -> Layout) {
        self.init(frame: .zero)
        self.contentProvider = content
    }

    /// The QuickLayout content hosted by the view.
    ///
    /// Subclasses can override this property to provide their own layout.
    @LayoutBuilder
    open var body: Layout {
        if let contentProvider {
            contentProvider()
        } else {
            EmptyLayout()
        }
    }

    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        _QuickLayoutViewImplementation.willMove(self, toWindow: newWindow)
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        quickLayoutEnvironmentState.update(self)
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(self)
    }

    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)
    }

    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutContainerSize(bounds.size) {
            _QuickLayoutViewImplementation.layoutSubviews(self)
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        // Self-sizing can run before the next layout pass after a locale or
        // direction switch, so measurement must observe the latest environment.
        quickLayoutEnvironmentState.update(self)
        return withQuickLayoutContainerSize(size) {
            _QuickLayoutViewImplementation.sizeThatFits(self, size: size) ?? super.sizeThatFits(size)
        }
    }

    open override func quick_flexibility(for axis: Axis) -> Flexibility {
        _QuickLayoutViewImplementation.quick_flexibility(self, for: axis) ?? super.quick_flexibility(for: axis)
    }

    /// Invalidates the hosted layout.
    ///
    /// Call this after localized content changes without changing layout
    /// direction, because UIKit has no notification for an app-specific locale.
    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    /// Lays out the hosted QuickLayout content immediately if needed.
    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }

    /// Returns the size that best fits the specified constraints.
    ///
    /// - Parameter size: The maximum size available to the hosted content.
    /// - Returns: The size that fits the hosted layout.
    open func sizeThatFits(in size: CGSize) -> CGSize {
        sizeThatFits(size)
    }

    /// Responds to UIKit environment changes that can affect layout.
    ///
    /// The default implementation invalidates the hosted QuickLayout content.
    /// Subclasses can override this method to synchronize additional state.
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

}
