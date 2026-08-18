import UIKit
import QuickLayout

/// A collection view cell whose content is described by QuickLayout.
open class QuickLayoutCollectionViewCell: UICollectionViewCell, HasBody, QuickLayoutUpdating, QuickLayoutEnvironmentUpdating {

    /// The semantic role used to resolve the cell's layout direction.
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    /// The cell's horizontal sizing flexibility.
    open var quickLayoutHorizontalFlexibility: Flexibility = .fullyFlexible

    /// The cell's vertical sizing flexibility.
    open var quickLayoutVerticalFlexibility: Flexibility = .fullyFlexible

    /// Views whose semantic direction follows the enclosing collection view.
    ///
    /// Subclasses can append direction-sensitive descendants that explicitly
    /// cache or override their semantic direction.
    open var quickLayoutDirectionViews: [UIView] {
        [self, contentView]
    }

    private var contentProvider: (() -> Layout)?
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Creates a cell with inline QuickLayout content.
    ///
    /// - Parameter content: A closure that returns the cell content.
    public convenience init(@LayoutBuilder content: @escaping () -> Layout) {
        self.init(frame: .zero)
        self.contentProvider = content
    }

    /// The QuickLayout content rendered in `contentView`.
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
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
        quickLayoutEnvironmentState.update(self)
    }

    open override func apply(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) {
        super.apply(layoutAttributes)
        // Direction changes invalidate the collection layout, but UIKit does
        // not guarantee layoutSubviews for every already-visible cell. The
        // layout-attributes callback is the reliable reuse/update boundary.
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
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
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutContainerSize(bounds.size) {
            _QuickLayoutViewImplementation.layoutSubviews(self)
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        quickLayoutSizeThatFits(size) ?? super.sizeThatFits(size)
    }

    open override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        if let size = quickLayoutSizeThatFits(layoutAttributes.size) {
            attributes.size = size
        }
        return attributes
    }

    open override func quickLayoutFlexibility(for axis: Axis) -> Flexibility {
        switch axis {
        case .horizontal:
            return quickLayoutHorizontalFlexibility
        case .vertical:
            return quickLayoutVerticalFlexibility
        }
    }

    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }

    /// Synchronizes semantic direction from the enclosing collection view.
    @discardableResult
    open func synchronizeLayoutDirectionFromCollectionViewIfNeeded() -> Bool {
        guard let collectionView = enclosingListView(
            of: UICollectionView.self
        ) else {
            return false
        }
        return applyQuickLayoutDirection(
            collectionView.effectiveUserInterfaceLayoutDirection,
            to: quickLayoutDirectionViews
        )
    }

    /// Responds to UIKit environment changes that can affect layout.
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
        quickLayoutEnvironmentState.update(self)
        let proposedSize = quickLayoutSizeLimit(proposed: size)
        return withQuickLayoutContainerSize(proposedSize) {
            _QuickLayoutViewImplementation.sizeThatFits(
                self,
                size: proposedSize
            )
        }
    }
}

/// A table view cell whose content is described by QuickLayout.
open class QuickLayoutTableViewCell: UITableViewCell, HasBody, QuickLayoutUpdating, QuickLayoutEnvironmentUpdating {

    /// The semantic role used to resolve the cell's layout direction.
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    private var contentProvider: (() -> Layout)?
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()

    /// Views whose semantic direction follows the enclosing table view.
    ///
    /// Subclasses can append direction-sensitive descendants that explicitly
    /// cache or override their semantic direction.
    open var quickLayoutDirectionViews: [UIView] {
        [self, contentView]
    }

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Creates a cell with inline QuickLayout content.
    ///
    /// - Parameters:
    ///   - style: The table cell style.
    ///   - reuseIdentifier: The reuse identifier.
    ///   - content: A closure that returns the cell content.
    public convenience init(
        style: UITableViewCell.CellStyle = .default,
        reuseIdentifier: String? = nil,
        @LayoutBuilder content: @escaping () -> Layout
    ) {
        self.init(style: style, reuseIdentifier: reuseIdentifier)
        self.contentProvider = content
    }

    /// The QuickLayout content rendered in `contentView`.
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
        synchronizeLayoutDirectionFromTableIfNeeded()
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
        synchronizeLayoutDirectionFromTableIfNeeded()
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutContainerSize(bounds.size) {
            _QuickLayoutViewImplementation.layoutSubviews(self)
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        quickLayoutSizeThatFits(size) ?? super.sizeThatFits(size)
    }

    open override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        quickLayoutSystemFittingSize(
            targetSize,
            horizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        ) ?? super.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        )
    }

    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }

    /// Synchronizes semantic direction from the enclosing table view.
    @discardableResult
    open func synchronizeLayoutDirectionFromTableIfNeeded() -> Bool {
        guard let tableView = enclosingListView(of: UITableView.self) else {
            return false
        }
        return applyQuickLayoutDirection(
            tableView.effectiveUserInterfaceLayoutDirection,
            to: quickLayoutDirectionViews
        )
    }

    /// Responds to UIKit environment changes that can affect layout.
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        synchronizeLayoutDirectionFromTableIfNeeded()
        quickLayoutEnvironmentState.update(self)
        return withQuickLayoutContainerSize(size) {
            _QuickLayoutViewImplementation.sizeThatFits(
                self,
                size: size
            )
        }
    }

    private func quickLayoutSystemFittingSize(
        _ targetSize: CGSize,
        horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize? {
        let proposedSize = CGSize(
            width: horizontalFittingPriority == .required
                ? targetSize.width
                : .infinity,
            height: verticalFittingPriority == .required
                ? targetSize.height
                : .infinity
        )
        guard var measuredSize = quickLayoutSizeThatFits(proposedSize)
        else {
            return nil
        }
        if horizontalFittingPriority == .required {
            measuredSize.width = targetSize.width
        }
        if verticalFittingPriority == .required {
            measuredSize.height = targetSize.height
        }
        return measuredSize
    }
}

/// A table view header or footer whose content is described by QuickLayout.
open class QuickLayoutTableViewHeaderFooterView: UITableViewHeaderFooterView, HasBody, QuickLayoutUpdating, QuickLayoutEnvironmentUpdating {

    /// The semantic role used to resolve the reusable view's layout direction.
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    private var contentProvider: (() -> Layout)?
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()

    /// Views whose semantic direction follows the enclosing table view.
    ///
    /// Subclasses can append direction-sensitive descendants that explicitly
    /// cache or override their semantic direction.
    open var quickLayoutDirectionViews: [UIView] {
        [self, contentView]
    }

    public override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Creates a reusable view with inline QuickLayout content.
    ///
    /// - Parameters:
    ///   - reuseIdentifier: The reuse identifier.
    ///   - content: A closure that returns the reusable content.
    public convenience init(
        reuseIdentifier: String? = nil,
        @LayoutBuilder content: @escaping () -> Layout
    ) {
        self.init(reuseIdentifier: reuseIdentifier)
        self.contentProvider = content
    }

    /// The QuickLayout content rendered in `contentView`.
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
        synchronizeLayoutDirectionFromTableIfNeeded()
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
        synchronizeLayoutDirectionFromTableIfNeeded()
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        let containerBounds = contentView.bounds
        QuickLayoutDiagnostics.recordLayoutPass(
            for: String(describing: Self.self),
            measuredSize: containerBounds.size
        )
        withQuickLayoutContainerSize(containerBounds.size) {
            _QuickLayoutViewImplementation.layoutSubviews(self)
            guard containerBounds != bounds else { return }
            // QuickLayout mounts this body in contentView, while its generic
            // bridge currently applies the frame using the reusable root's
            // bounds. Reapply the same layout in the actual container bounds;
            // the body keeps full control of its own sizing and alignment.
            let layoutDirection: LayoutDirection =
                effectiveUserInterfaceLayoutDirection == .rightToLeft
                ? .rightToLeft
                : .leftToRight
            body.applyFrame(
                containerBounds,
                alignment: .center,
                layoutDirection: layoutDirection
            )
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        quickLayoutSizeThatFits(size) ?? super.sizeThatFits(size)
    }

    open override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        quickLayoutSystemFittingSize(
            targetSize,
            horizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        ) ?? super.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        )
    }

    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }

    /// Synchronizes semantic direction from the enclosing table view.
    @discardableResult
    open func synchronizeLayoutDirectionFromTableIfNeeded() -> Bool {
        guard let tableView = enclosingListView(of: UITableView.self) else {
            return false
        }
        return applyQuickLayoutDirection(
            tableView.effectiveUserInterfaceLayoutDirection,
            to: quickLayoutDirectionViews
        )
    }

    /// Responds to UIKit environment changes that can affect layout.
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        synchronizeLayoutDirectionFromTableIfNeeded()
        quickLayoutEnvironmentState.update(self)
        return withQuickLayoutContainerSize(size) {
            _QuickLayoutViewImplementation.sizeThatFits(
                self,
                size: size
            )
        }
    }

    private func quickLayoutSystemFittingSize(
        _ targetSize: CGSize,
        horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize? {
        let proposedSize = CGSize(
            width: horizontalFittingPriority == .required
                ? targetSize.width
                : .infinity,
            height: verticalFittingPriority == .required
                ? targetSize.height
                : .infinity
        )
        guard var measuredSize = quickLayoutSizeThatFits(proposedSize)
        else {
            return nil
        }
        if horizontalFittingPriority == .required {
            measuredSize.width = targetSize.width
        }
        if verticalFittingPriority == .required {
            measuredSize.height = targetSize.height
        }
        return measuredSize
    }
}

/// A collection reusable view whose content is described by QuickLayout.
open class QuickLayoutCollectionReusableView: UICollectionReusableView, HasBody, QuickLayoutUpdating, QuickLayoutEnvironmentUpdating {

    /// The semantic role used to resolve the reusable view's layout direction.
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    private var contentProvider: (() -> Layout)?
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()

    /// Views whose semantic direction follows the enclosing collection view.
    ///
    /// Subclasses can append direction-sensitive descendants that explicitly
    /// cache or override their semantic direction.
    open var quickLayoutDirectionViews: [UIView] {
        [self]
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Creates a reusable view with inline QuickLayout content.
    ///
    /// - Parameter content: A closure that returns the view content.
    public convenience init(@LayoutBuilder content: @escaping () -> Layout) {
        self.init(frame: .zero)
        self.contentProvider = content
    }

    /// The QuickLayout content rendered by the reusable view.
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
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
        quickLayoutEnvironmentState.update(self)
    }

    open override func apply(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) {
        super.apply(layoutAttributes)
        // Supplementary views receive new attributes after collection layout
        // invalidation even when UIKit skips another layoutSubviews pass.
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
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
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutContainerSize(bounds.size) {
            _QuickLayoutViewImplementation.layoutSubviews(self)
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        quickLayoutSizeThatFits(size) ?? super.sizeThatFits(size)
    }

    open override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        if let size = quickLayoutSizeThatFits(layoutAttributes.size) {
            attributes.size = size
        }
        return attributes
    }

    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }

    /// Synchronizes semantic direction from the enclosing collection view.
    @discardableResult
    open func synchronizeLayoutDirectionFromCollectionViewIfNeeded() -> Bool {
        guard let collectionView = enclosingListView(
            of: UICollectionView.self
        ) else {
            return false
        }
        return applyQuickLayoutDirection(
            collectionView.effectiveUserInterfaceLayoutDirection,
            to: quickLayoutDirectionViews
        )
    }

    /// Responds to UIKit environment changes that can affect layout.
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
        quickLayoutEnvironmentState.update(self)
        return withQuickLayoutContainerSize(size) {
            _QuickLayoutViewImplementation.sizeThatFits(self, size: size)
        }
    }
}

private extension UIView {

    func enclosingListView<ListView: UIView>(
        of type: ListView.Type
    ) -> ListView? {
        var candidate = superview
        while let view = candidate {
            if let listView = view as? ListView {
                return listView
            }
            candidate = view.superview
        }
        return nil
    }

    @discardableResult
    func applyQuickLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection,
        to views: [UIView]
    ) -> Bool {
        let attribute: UISemanticContentAttribute = direction == .rightToLeft
            ? .forceRightToLeft
            : .forceLeftToRight
        // UIKit resolves effective direction through the hierarchy, but it
        // does not copy semanticContentAttribute into already materialized or
        // reused hosts. Stamp only the declared layout hosts so their cached
        // QuickLayout environment and self-sizing measurement are refreshed.
        let viewsToUpdate = views.filter {
            $0.semanticContentAttribute != attribute
        }
        guard !viewsToUpdate.isEmpty else { return false }

        // Avoid redundant assignments: changing semanticContentAttribute
        // itself publishes an environment change and schedules another layout.
        for view in viewsToUpdate {
            view.semanticContentAttribute = attribute
            view.setNeedsLayout()
        }
        return true
    }
}
