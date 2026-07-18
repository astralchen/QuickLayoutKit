import UIKit
import QuickLayout

/// A reusable view that hosts QuickLayout content.
///
/// Use `QuickLayoutView` when a QuickLayout hierarchy needs to be embedded in
/// an existing UIKit view controller, table view cell, collection view cell, or
/// reusable view without introducing a dedicated view controller subclass.
open class QuickLayoutView: UIView, HasBody, QuickLayoutUpdating, QuickLayoutEnvironmentUpdating {

    private var contentProvider: (() -> Layout)?
    private var lastQuickLayoutEnvironment: QuickLayoutEnvironment?

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
        updateQuickLayoutEnvironment(explicitReason: [])
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateQuickLayoutEnvironment(explicitReason: [])
    }

    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateQuickLayoutEnvironment(explicitReason: .safeArea)
    }

    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        updateQuickLayoutEnvironment(explicitReason: .layoutMargins)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        updateQuickLayoutEnvironment(explicitReason: [])
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutContainerSize(bounds.size) {
            _QuickLayoutViewImplementation.layoutSubviews(self)
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        withQuickLayoutContainerSize(size) {
            _QuickLayoutViewImplementation.sizeThatFits(self, size: size) ?? super.sizeThatFits(size)
        }
    }

    open override func quick_flexibility(for axis: Axis) -> Flexibility {
        _QuickLayoutViewImplementation.quick_flexibility(self, for: axis) ?? super.quick_flexibility(for: axis)
    }

    /// Invalidates the hosted layout.
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

    @discardableResult
    private func updateQuickLayoutEnvironment(
        explicitReason: QuickLayoutEnvironmentChangeReason
    ) -> Bool {
        let environment = quickLayoutEnvironment
        let reason: QuickLayoutEnvironmentChangeReason

        if let lastQuickLayoutEnvironment {
            reason = environment
                .changes(from: lastQuickLayoutEnvironment)
                .union(explicitReason)
        } else {
            reason = explicitReason
        }

        self.lastQuickLayoutEnvironment = environment
        guard !reason.isEmpty else { return false }

        quickLayoutEnvironmentDidChange(environment, reason: reason)
        return true
    }
}
