import UIKit
import QuickLayout

/// A collection view cell whose content is described by QuickLayout.
open class QuickLayoutCollectionViewCell: UICollectionViewCell, HasBody, QuickLayoutUpdating {

    /// The cell's horizontal sizing flexibility.
    open var quickLayoutHorizontalFlexibility: Flexibility = .fullyFlexible

    /// The cell's vertical sizing flexibility.
    open var quickLayoutVerticalFlexibility: Flexibility = .fullyFlexible

    private var contentProvider: (() -> Layout)?

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

    open override func layoutSubviews() {
        super.layoutSubviews()
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

    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
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
open class QuickLayoutTableViewCell: UITableViewCell, HasBody, QuickLayoutUpdating {

    private var contentProvider: (() -> Layout)?

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

    open override func layoutSubviews() {
        super.layoutSubviews()
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

    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        withQuickLayoutContainerSize(size) {
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
open class QuickLayoutTableViewHeaderFooterView: UITableViewHeaderFooterView, HasBody, QuickLayoutUpdating {

    private var contentProvider: (() -> Layout)?

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

    open override func layoutSubviews() {
        super.layoutSubviews()
        QuickLayoutDiagnostics.recordLayoutPass(
            for: String(describing: Self.self),
            measuredSize: bounds.size
        )
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

    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        withQuickLayoutContainerSize(size) {
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
open class QuickLayoutCollectionReusableView: UICollectionReusableView, HasBody, QuickLayoutUpdating {

    private var contentProvider: (() -> Layout)?

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

    open override func layoutSubviews() {
        super.layoutSubviews()
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

    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        withQuickLayoutContainerSize(size) {
            _QuickLayoutViewImplementation.sizeThatFits(self, size: size)
        }
    }
}
