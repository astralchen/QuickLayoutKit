import UIKit
import QuickLayout

/// The semantic role of an action exposed by ``QuickLayoutButton``.
///
/// A role does not apply visual styling. It is published as part of
/// ``QuickLayoutButtonState`` so application-owned UI can choose an
/// appropriate appearance.
public enum QuickLayoutButtonRole: Equatable, Sendable {
    /// An action that deletes data or performs another destructive operation.
    case destructive

    /// An action that cancels the current operation.
    case cancel
}

/// A snapshot of the interaction state published by a ``QuickLayoutButton``.
public struct QuickLayoutButtonState: Equatable, Sendable {
    /// Whether an active pointer or touch is pressing inside the button.
    public let isPressed: Bool

    /// Whether the button can currently perform its action.
    public let isEnabled: Bool

    /// Whether the button is selected.
    public let isSelected: Bool

    /// The semantic action role, if one was supplied.
    public let role: QuickLayoutButtonRole?

    /// Creates a button-state snapshot.
    public init(
        isPressed: Bool,
        isEnabled: Bool,
        isSelected: Bool,
        role: QuickLayoutButtonRole?
    ) {
        self.isPressed = isPressed
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.role = role
    }
}

/// A UIKit control whose complete visual hierarchy is authored with
/// QuickLayout.
///
/// `QuickLayoutButton` is itself a ``HasBody`` host. Applications can supply a
/// label through the layout-builder initializer or subclass the control and
/// override ``body``. The control owns interaction, accessibility semantics,
/// measurement, and layout; every visual detail remains application-owned.
///
/// The control deliberately supplies no default padding, foreground color,
/// background, corner radius, pressed animation, or disabled appearance.
/// Supply those through ``body`` and ``stateUpdateHandler``.
@MainActor
open class QuickLayoutButton:
    UIControl,
    HasBody,
    QuickLayoutUpdating,
    QuickLayoutEnvironmentUpdating {

    /// The action performed for the primary control event.
    public typealias Action = @MainActor () -> Void

    /// A callback used by application-owned UI to render control state.
    public typealias StateUpdateHandler =
        @MainActor (QuickLayoutButtonState) -> Void

    private var contentProvider: (() -> Layout)?
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()
    private var lastPublishedState: QuickLayoutButtonState?

    /// The action performed when the control emits `primaryActionTriggered`.
    public var action: Action

    /// The semantic action role exposed to ``stateUpdateHandler``.
    open var role: QuickLayoutButtonRole? {
        didSet {
            guard role != oldValue else { return }
            publishButtonState()
        }
    }

    /// Controls semantic-direction recovery when the button is attached,
    /// measured, or laid out.
    ///
    /// The default preserves local playback or spatial semantics, matching
    /// ``QuickLayoutView``. Choose `.followEnclosingContainer` for ordinary
    /// application content that can be detached and reattached.
    open var quickLayoutSemanticDirectionBehavior:
        QuickLayoutSemanticDirectionBehavior = .preserve {
        didSet {
            guard quickLayoutSemanticDirectionBehavior != oldValue else {
                return
            }
            synchronizeDirectionIfNeeded()
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    /// Receives the initial state when installed and every distinct state
    /// thereafter.
    ///
    /// This callback is the only built-in bridge to pressed, disabled,
    /// selected, and role-based visuals. Avoid strongly capturing the button
    /// from its own handler.
    public var stateUpdateHandler: StateUpdateHandler? {
        didSet {
            publishButtonState(force: true)
        }
    }

    /// The current immutable interaction-state snapshot.
    public var buttonState: QuickLayoutButtonState {
        QuickLayoutButtonState(
            isPressed: isHighlighted,
            isEnabled: isEnabled,
            isSelected: isSelected,
            role: role
        )
    }

    /// The complete application-owned visual hierarchy of the button.
    ///
    /// Subclasses can override this property. The default implementation uses
    /// the hierarchy supplied to ``init(role:action:label:)`` or renders no
    /// content when the button was created with `init(frame:)`.
    @LayoutBuilder
    open var body: Layout {
        if let contentProvider {
            contentProvider()
        } else {
            EmptyLayout()
        }
    }

    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    open override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled {
                isHighlighted = false
            }
            updateAccessibilityTraits()
            publishButtonState()
        }
    }

    open override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            publishButtonState()
        }
    }

    open override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            publishButtonState()
        }
    }

    /// Creates an empty button host for subclassing or later configuration.
    public override init(frame: CGRect) {
        action = {}
        role = nil
        super.init(frame: frame)
        configureControl()
    }

    /// Creates an empty button host from Interface Builder.
    ///
    /// A subclass using this initializer supplies ``body`` and assigns
    /// ``action`` itself.
    public required init?(coder: NSCoder) {
        action = {}
        role = nil
        super.init(coder: coder)
        configureControl()
    }

    /// Creates a button whose visual hierarchy is supplied by a subclass.
    ///
    /// - Parameters:
    ///   - role: An optional semantic action role. It does not apply styling.
    ///   - action: The primary action.
    public init(
        role: QuickLayoutButtonRole? = nil,
        action: @escaping Action
    ) {
        self.action = action
        self.role = role
        super.init(frame: .zero)
        configureControl()
    }

    /// Creates a button with an application-owned QuickLayout hierarchy.
    ///
    /// - Parameters:
    ///   - role: An optional semantic action role. It does not apply styling.
    ///   - action: The primary action.
    ///   - label: The complete visual hierarchy. It receives no implicit
    ///     styling or padding from the framework.
    public convenience init(
        role: QuickLayoutButtonRole? = nil,
        action: @escaping Action,
        @LayoutBuilder label: @escaping () -> Layout
    ) {
        self.init(role: role, action: action)
        contentProvider = label
    }

    /// Sends the primary action when the button is enabled.
    ///
    /// Registered `primaryActionTriggered` targets are notified through the
    /// normal `UIControl` event path.
    open func performAction() {
        guard isEnabled else { return }
        sendActions(for: .primaryActionTriggered)
    }

    open override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        performAction()
        return true
    }

    /// Keeps interaction at the control boundary even when application-owned
    /// label views normally accept touches.
    open override func hitTest(
        _ point: CGPoint,
        with event: UIEvent?
    ) -> UIView? {
        guard super.hitTest(point, with: event) != nil else { return nil }
        return self
    }

    open override func beginTracking(
        _ touch: UITouch,
        with event: UIEvent?
    ) -> Bool {
        guard isEnabled else { return false }
        isHighlighted = true
        sendActions(for: .touchDown)
        return true
    }

    open override func continueTracking(
        _ touch: UITouch,
        with event: UIEvent?
    ) -> Bool {
        guard isEnabled else { return false }

        let wasInside = isHighlighted
        let isInside = bounds.contains(touch.location(in: self))
        isHighlighted = isInside

        if isInside {
            sendActions(for: wasInside ? .touchDragInside : .touchDragEnter)
        } else {
            sendActions(for: wasInside ? .touchDragExit : .touchDragOutside)
        }
        return true
    }

    open override func endTracking(
        _ touch: UITouch?,
        with event: UIEvent?
    ) {
        let isInside = touch.map {
            bounds.contains($0.location(in: self))
        } ?? false
        isHighlighted = false

        if isEnabled && isInside {
            sendActions(for: .touchUpInside)
            performAction()
        } else {
            sendActions(for: .touchUpOutside)
        }
    }

    open override func cancelTracking(with event: UIEvent?) {
        isHighlighted = false
        sendActions(for: .touchCancel)
    }

    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        _QuickLayoutViewImplementation.willMove(self, toWindow: newWindow)
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        synchronizeDirectionIfNeeded()
        quickLayoutEnvironmentState.update(self)
    }

    open override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .traitCollection
        )
    }

    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)
    }

    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .layoutMargins
        )
    }

    open override func layoutSubviews() {
        synchronizeDirectionIfNeeded()
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(
            for: String(describing: Self.self),
            measuredSize: bounds.size
        )
        withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(bounds.size) {
                _QuickLayoutViewImplementation.layoutSubviews(self)
            }
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        synchronizeDirectionIfNeeded()
        quickLayoutEnvironmentState.update(self)
        return withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(size) {
                _QuickLayoutViewImplementation.sizeThatFits(
                    self,
                    size: size
                ) ?? super.sizeThatFits(size)
            }
        }
    }

    open override var intrinsicContentSize: CGSize {
        let measured = sizeThatFits(
            CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        return CGSize(
            width: intrinsicDimension(
                measured.width,
                flexibility: quick_flexibility(for: .horizontal)
            ),
            height: intrinsicDimension(
                measured.height,
                flexibility: quick_flexibility(for: .vertical)
            )
        )
    }

    open override func quick_flexibility(for axis: Axis) -> Flexibility {
        _QuickLayoutViewImplementation.quick_flexibility(self, for: axis)
            ?? super.quick_flexibility(for: axis)
    }

    /// Invalidates body measurement and placement.
    open func setNeedsQuickLayout() {
        setNeedsLayout()
        invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
    }

    /// Immediately lays out the control when needed.
    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }

    /// Responds to a distinct enabled, selected, pressed, or role state.
    ///
    /// Subclasses can override this hook to update application-owned UI. The
    /// default implementation invokes ``stateUpdateHandler``.
    open func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        stateUpdateHandler?(state)
    }

    /// Responds to UIKit environment changes that can affect ``body``.
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    private func configureControl() {
        isAccessibilityElement = true
        accessibilityTraits.insert(.button)

        addTarget(
            self,
            action: #selector(handlePrimaryAction),
            for: .primaryActionTriggered
        )
        updateAccessibilityTraits()
    }

    @objc private func handlePrimaryAction() {
        action()
    }

    private func synchronizeDirectionIfNeeded() {
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
    }

    private func updateAccessibilityTraits() {
        if isEnabled {
            accessibilityTraits.remove(.notEnabled)
        } else {
            accessibilityTraits.insert(.notEnabled)
        }
    }

    private func publishButtonState(force: Bool = false) {
        let state = buttonState
        guard force || state != lastPublishedState else { return }
        lastPublishedState = state
        quickLayoutButtonStateDidChange(state)
    }

    private func intrinsicDimension(
        _ measured: CGFloat,
        flexibility: Flexibility
    ) -> CGFloat {
        flexibility == .fullyFlexible
            ? UIView.noIntrinsicMetric
            : measured
    }
}
