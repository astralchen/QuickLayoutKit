import UIKit
import QuickLayout

/// The source of QuickLayout content hosted by a reusable list view.
public enum QuickLayoutListContentSource: Equatable, Sendable {

    /// The reusable view lays out its own ``HasBody/body`` in UIKit's
    /// `contentView`.
    case body

    /// The reusable view measures the QuickLayout content view installed by
    /// its `UIContentConfiguration`.
    case contentConfiguration
}

/// A collection view cell whose content is described by QuickLayout.
open class QuickLayoutCollectionViewCell: UICollectionViewCell, HasBody, QuickLayoutUpdating {

    /// The source whose QuickLayout content is hosted by the cell.
    public typealias ContentSource = QuickLayoutListContentSource

    /// The source of the cell's QuickLayout content.
    ///
    /// Select the source when the cell is initialized. The source remains
    /// fixed for the lifetime of the cell because assigning a UIKit content
    /// configuration replaces the cell's `contentView`.
    public let quickLayoutContentSource: ContentSource

    /// The cell's horizontal sizing flexibility.
    open var quickLayoutHorizontalFlexibility: Flexibility = .fullyFlexible

    /// The cell's vertical sizing flexibility.
    open var quickLayoutVerticalFlexibility: Flexibility = .fullyFlexible

    private var contentProvider: (() -> Layout)?

    public override init(frame: CGRect) {
        self.quickLayoutContentSource = .body
        super.init(frame: frame)
    }

    /// Creates a cell that uses the specified source for QuickLayout content.
    ///
    /// - Parameters:
    ///   - frame: The initial frame of the cell.
    ///   - contentSource: The source whose QuickLayout content the cell lays
    ///     out and measures.
    public init(frame: CGRect, contentSource: ContentSource) {
        self.quickLayoutContentSource = contentSource
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        self.quickLayoutContentSource = .body
        super.init(coder: coder)
    }

    /// Creates a decoded cell that uses the specified source for QuickLayout
    /// content.
    ///
    /// - Parameters:
    ///   - coder: The coder used to initialize the cell.
    ///   - contentSource: The source whose QuickLayout content the cell lays
    ///     out and measures.
    public init?(coder: NSCoder, contentSource: ContentSource) {
        self.quickLayoutContentSource = contentSource
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
        quickLayoutContentSizeThatFits(size) ?? super.sizeThatFits(size)
    }

    open override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        if let size = quickLayoutContentSizeThatFits(layoutAttributes.size) {
            attributes.size = size
        }
        return attributes
    }

    open override var isBodyEnabled: Bool {
        super.isBodyEnabled && quickLayoutContentSource == .body && contentConfiguration == nil
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
        configuredQuickLayoutContentView?.setNeedsQuickLayout()
    }

    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
        configuredQuickLayoutContentView?.quickLayoutIfNeeded()
    }

    private var configuredQuickLayoutContentView: (UIView & QuickLayoutUpdating)? {
        guard
            quickLayoutContentSource == .contentConfiguration,
            contentConfiguration != nil
        else {
            return nil
        }
        return contentView as? (UIView & QuickLayoutUpdating)
    }

    private func quickLayoutContentSizeThatFits(_ size: CGSize) -> CGSize? {
        let proposedSize = quickLayoutSizeLimit(proposed: size)
        return withQuickLayoutContainerSize(proposedSize) {
            switch quickLayoutContentSource {
            case .body:
                guard contentConfiguration == nil else { return nil }
                return _QuickLayoutViewImplementation.sizeThatFits(
                    self,
                    size: proposedSize
                )

            case .contentConfiguration:
                return configuredQuickLayoutContentView?.sizeThatFits(
                    proposedSize
                )
            }
        }
    }
}

/// A table view cell whose content is described by QuickLayout.
open class QuickLayoutTableViewCell: UITableViewCell, HasBody, QuickLayoutUpdating {

    /// The source whose QuickLayout content is hosted by the cell.
    public typealias ContentSource = QuickLayoutListContentSource

    /// The source of the cell's QuickLayout content.
    ///
    /// Select the source when the cell is initialized. The source remains
    /// fixed for the lifetime of the cell because assigning a UIKit content
    /// configuration replaces the cell's `contentView`.
    public let quickLayoutContentSource: ContentSource

    private var contentProvider: (() -> Layout)?

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.quickLayoutContentSource = .body
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }

    /// Creates a cell that uses the specified source for QuickLayout content.
    ///
    /// - Parameters:
    ///   - style: The table cell style.
    ///   - reuseIdentifier: The reuse identifier.
    ///   - contentSource: The source whose QuickLayout content the cell lays
    ///     out and measures.
    public init(
        style: UITableViewCell.CellStyle,
        reuseIdentifier: String?,
        contentSource: ContentSource
    ) {
        self.quickLayoutContentSource = contentSource
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }

    public required init?(coder: NSCoder) {
        self.quickLayoutContentSource = .body
        super.init(coder: coder)
    }

    /// Creates a decoded cell that uses the specified source for QuickLayout
    /// content.
    ///
    /// - Parameters:
    ///   - coder: The coder used to initialize the cell.
    ///   - contentSource: The source whose QuickLayout content the cell lays
    ///     out and measures.
    public init?(coder: NSCoder, contentSource: ContentSource) {
        self.quickLayoutContentSource = contentSource
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
        quickLayoutContentSizeThatFits(size) ?? super.sizeThatFits(size)
    }

    open override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        quickLayoutContentSystemFittingSize(
            targetSize,
            horizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        ) ?? super.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        )
    }

    open override var isBodyEnabled: Bool {
        super.isBodyEnabled && quickLayoutContentSource == .body && contentConfiguration == nil
    }

    open func setNeedsQuickLayout() {
        setNeedsLayout()
        configuredQuickLayoutContentView?.setNeedsQuickLayout()
    }

    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
        configuredQuickLayoutContentView?.quickLayoutIfNeeded()
    }

    private var configuredQuickLayoutContentView: (UIView & QuickLayoutUpdating)? {
        guard
            quickLayoutContentSource == .contentConfiguration,
            contentConfiguration != nil
        else {
            return nil
        }
        return contentView as? (UIView & QuickLayoutUpdating)
    }

    private func quickLayoutContentSizeThatFits(_ size: CGSize) -> CGSize? {
        withQuickLayoutContainerSize(size) {
            switch quickLayoutContentSource {
            case .body:
                guard contentConfiguration == nil else { return nil }
                return _QuickLayoutViewImplementation.sizeThatFits(
                    self,
                    size: size
                )

            case .contentConfiguration:
                return configuredQuickLayoutContentView?.sizeThatFits(size)
            }
        }
    }

    private func quickLayoutContentSystemFittingSize(
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
        guard var measuredSize = quickLayoutContentSizeThatFits(proposedSize)
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

    /// The source whose QuickLayout content is hosted by the reusable view.
    public typealias ContentSource = QuickLayoutListContentSource

    /// The source of the reusable view's QuickLayout content.
    ///
    /// Select the source when the reusable view is initialized. The source
    /// remains fixed for its lifetime because assigning a UIKit content
    /// configuration replaces its `contentView`.
    public let quickLayoutContentSource: ContentSource

    private var contentProvider: (() -> Layout)?

    public override init(reuseIdentifier: String?) {
        self.quickLayoutContentSource = .body
        super.init(reuseIdentifier: reuseIdentifier)
    }

    /// Creates a reusable view that uses the specified source for QuickLayout
    /// content.
    ///
    /// - Parameters:
    ///   - reuseIdentifier: The reuse identifier.
    ///   - contentSource: The source whose QuickLayout content the reusable
    ///     view lays out and measures.
    public init(
        reuseIdentifier: String?,
        contentSource: ContentSource
    ) {
        self.quickLayoutContentSource = contentSource
        super.init(reuseIdentifier: reuseIdentifier)
    }

    public required init?(coder: NSCoder) {
        self.quickLayoutContentSource = .body
        super.init(coder: coder)
    }

    /// Creates a decoded reusable view that uses the specified source for
    /// QuickLayout content.
    ///
    /// - Parameters:
    ///   - coder: The coder used to initialize the reusable view.
    ///   - contentSource: The source whose QuickLayout content the reusable
    ///     view lays out and measures.
    public init?(coder: NSCoder, contentSource: ContentSource) {
        self.quickLayoutContentSource = contentSource
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
        quickLayoutContentSizeThatFits(size) ?? super.sizeThatFits(size)
    }

    open override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        quickLayoutContentSystemFittingSize(
            targetSize,
            horizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        ) ?? super.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        )
    }

    open override var isBodyEnabled: Bool {
        super.isBodyEnabled && quickLayoutContentSource == .body && contentConfiguration == nil
    }

    open func setNeedsQuickLayout() {
        setNeedsLayout()
        configuredQuickLayoutContentView?.setNeedsQuickLayout()
    }

    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
        configuredQuickLayoutContentView?.quickLayoutIfNeeded()
    }

    private var configuredQuickLayoutContentView: (UIView & QuickLayoutUpdating)? {
        guard
            quickLayoutContentSource == .contentConfiguration,
            contentConfiguration != nil
        else {
            return nil
        }
        return contentView as? (UIView & QuickLayoutUpdating)
    }

    private func quickLayoutContentSizeThatFits(_ size: CGSize) -> CGSize? {
        withQuickLayoutContainerSize(size) {
            switch quickLayoutContentSource {
            case .body:
                guard contentConfiguration == nil else { return nil }
                return _QuickLayoutViewImplementation.sizeThatFits(
                    self,
                    size: size
                )

            case .contentConfiguration:
                return configuredQuickLayoutContentView?.sizeThatFits(size)
            }
        }
    }

    private func quickLayoutContentSystemFittingSize(
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
        guard var measuredSize = quickLayoutContentSizeThatFits(proposedSize)
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
        withQuickLayoutContainerSize(size) {
            _QuickLayoutViewImplementation.sizeThatFits(self, size: size) ?? super.sizeThatFits(size)
        }
    }

    open override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        attributes.size = sizeThatFits(layoutAttributes.size)
        return attributes
    }

    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }
}
