import UIKit
import QuickLayout

/// 使用 QuickLayout 描述内容的集合视图单元格。
open class QuickLayoutCollectionViewCell: UICollectionViewCell, HasBody, QuickLayoutUpdating, QuickLayoutEnvironmentUpdating {

    /// 用于解析单元格布局方向的语义角色。
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    /// 单元格的水平尺寸弹性。
    open var quickLayoutHorizontalFlexibility: Flexibility = .fullyFlexible

    /// 单元格的垂直尺寸弹性。
    open var quickLayoutVerticalFlexibility: Flexibility = .fullyFlexible

    /// 语义方向跟随外层集合视图的视图。
    ///
    /// 子类可以追加显式缓存或覆盖语义方向的方向敏感子视图。
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

    /// 创建以内联方式提供 QuickLayout 内容的单元格。
    ///
    /// - Parameter content: 返回单元格内容的构建器闭包。
    public convenience init(@LayoutBuilder content: @escaping () -> Layout) {
        self.init(frame: .zero)
        self.contentProvider = content
    }

    /// 在 `contentView` 中渲染的 QuickLayout 内容。
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
        // 方向变化会使集合布局失效，但 UIKit 不保证每个可见单元格都会再次执行
        // layoutSubviews。布局属性回调是可靠的复用和更新边界。
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
        quickLayoutEnvironmentState.update(self)
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
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
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    open override func layoutSubviews() {
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(bounds.size) {
                _QuickLayoutViewImplementation.layoutSubviews(self)
            }
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

    /// 从外层集合视图同步语义方向。
    ///
    /// - Returns: 实际更新了至少一个视图时为 `true`；否则为 `false`。
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

    /// 响应可能影响布局的 UIKit 环境变化。
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
        return withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(proposedSize) {
                _QuickLayoutViewImplementation.sizeThatFits(
                    self,
                    size: proposedSize
                )
            }
        }
    }
}

/// 使用 QuickLayout 描述内容的表格视图单元格。
open class QuickLayoutTableViewCell: UITableViewCell, HasBody, QuickLayoutUpdating, QuickLayoutEnvironmentUpdating {

    /// 用于解析单元格布局方向的语义角色。
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    private var contentProvider: (() -> Layout)?
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()

    /// 语义方向跟随外层表格视图的视图。
    ///
    /// 子类可以追加显式缓存或覆盖语义方向的方向敏感子视图。
    open var quickLayoutDirectionViews: [UIView] {
        [self, contentView]
    }

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// 创建以内联方式提供 QuickLayout 内容的单元格。
    ///
    /// - Parameters:
    ///   - style: 表格视图单元格样式。
    ///   - reuseIdentifier: 单元格的复用标识符；`nil` 原样交给 UIKit，表示没有复用标识符。
    ///   - content: 返回单元格内容的构建器闭包。
    public convenience init(
        style: UITableViewCell.CellStyle = .default,
        reuseIdentifier: String? = nil,
        @LayoutBuilder content: @escaping () -> Layout
    ) {
        self.init(style: style, reuseIdentifier: reuseIdentifier)
        self.contentProvider = content
    }

    /// 在 `contentView` 中渲染的 QuickLayout 内容。
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
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    open override func layoutSubviews() {
        synchronizeLayoutDirectionFromTableIfNeeded()
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(bounds.size) {
                _QuickLayoutViewImplementation.layoutSubviews(self)
            }
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

    /// 从外层表格视图同步语义方向。
    ///
    /// - Returns: 实际更新了至少一个视图时为 `true`；否则为 `false`。
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

    /// 响应可能影响布局的 UIKit 环境变化。
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        synchronizeLayoutDirectionFromTableIfNeeded()
        quickLayoutEnvironmentState.update(self)
        return withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(size) {
                _QuickLayoutViewImplementation.sizeThatFits(
                    self,
                    size: size
                )
            }
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

/// 使用 QuickLayout 描述内容的表格视图页眉或页脚。
open class QuickLayoutTableViewHeaderFooterView: UITableViewHeaderFooterView, HasBody, QuickLayoutUpdating, QuickLayoutEnvironmentUpdating {

    /// 用于解析复用视图布局方向的语义角色。
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    private var contentProvider: (() -> Layout)?
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()

    /// 语义方向跟随外层表格视图的视图。
    ///
    /// 子类可以追加显式缓存或覆盖语义方向的方向敏感子视图。
    open var quickLayoutDirectionViews: [UIView] {
        [self, contentView]
    }

    public override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// 创建以内联方式提供 QuickLayout 内容的复用视图。
    ///
    /// - Parameters:
    ///   - reuseIdentifier: 复用视图的复用标识符；`nil` 原样交给 UIKit，表示没有复用标识符。
    ///   - content: 返回复用内容的构建器闭包。
    public convenience init(
        reuseIdentifier: String? = nil,
        @LayoutBuilder content: @escaping () -> Layout
    ) {
        self.init(reuseIdentifier: reuseIdentifier)
        self.contentProvider = content
    }

    /// 在 `contentView` 中渲染的 QuickLayout 内容。
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
        withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(containerBounds.size) {
                _QuickLayoutViewImplementation.layoutSubviews(self)
                guard containerBounds != bounds else { return }
                // QuickLayout 将 body 挂载到 contentView，但通用桥接当前使用复用根视图的
                // bounds 应用框架。这里按实际容器边界重新应用同一布局，同时让 body 继续
                // 完全控制自身尺寸和对齐方式。
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

    /// 从外层表格视图同步语义方向。
    ///
    /// - Returns: 实际更新了至少一个视图时为 `true`；否则为 `false`。
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

    /// 响应可能影响布局的 UIKit 环境变化。
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        synchronizeLayoutDirectionFromTableIfNeeded()
        quickLayoutEnvironmentState.update(self)
        return withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(size) {
                _QuickLayoutViewImplementation.sizeThatFits(
                    self,
                    size: size
                )
            }
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

/// 使用 QuickLayout 描述内容的集合复用视图。
open class QuickLayoutCollectionReusableView: UICollectionReusableView, HasBody, QuickLayoutUpdating, QuickLayoutEnvironmentUpdating {

    /// 用于解析复用视图布局方向的语义角色。
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    private var contentProvider: (() -> Layout)?
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()

    /// 语义方向跟随外层集合视图的视图。
    ///
    /// 子类可以追加显式缓存或覆盖语义方向的方向敏感子视图。
    open var quickLayoutDirectionViews: [UIView] {
        [self]
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// 创建以内联方式提供 QuickLayout 内容的复用视图。
    ///
    /// - Parameter content: 返回复用视图内容的构建器闭包。
    public convenience init(@LayoutBuilder content: @escaping () -> Layout) {
        self.init(frame: .zero)
        self.contentProvider = content
    }

    /// 复用视图渲染的 QuickLayout 内容。
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
        // 集合布局失效后，即使 UIKit 不再执行 layoutSubviews，补充视图仍会收到新的布局属性。
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
        quickLayoutEnvironmentState.update(self)
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
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
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    open override func layoutSubviews() {
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(bounds.size) {
                _QuickLayoutViewImplementation.layoutSubviews(self)
            }
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

    /// 从外层集合视图同步语义方向。
    ///
    /// - Returns: 实际更新了至少一个视图时为 `true`；否则为 `false`。
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

    /// 响应可能影响布局的 UIKit 环境变化。
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        synchronizeLayoutDirectionFromCollectionViewIfNeeded()
        quickLayoutEnvironmentState.update(self)
        return withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(size) {
                _QuickLayoutViewImplementation.sizeThatFits(self, size: size)
            }
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
        // UIKit 会通过视图层级解析有效方向，但不会把 semanticContentAttribute 复制到
        // 已经创建或复用的宿主。这里只更新已声明的布局宿主，使其缓存的 QuickLayout
        // 环境和自适应尺寸测量得到刷新。
        let viewsToUpdate = views.filter {
            $0.semanticContentAttribute != attribute
        }
        guard !viewsToUpdate.isEmpty else { return false }

        // 避免重复赋值：修改 semanticContentAttribute 本身会发布环境变化并安排新的布局。
        for view in viewsToUpdate {
            view.semanticContentAttribute = attribute
            view.setNeedsLayout()
        }
        return true
    }
}
