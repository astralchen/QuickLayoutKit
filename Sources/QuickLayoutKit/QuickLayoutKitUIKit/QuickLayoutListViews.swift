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


    /// 以内联初始化方式提供内容的构建闭包；未设置时由 `body` 的默认实现返回空布局。
    private var contentProvider: (() -> Layout)?
    /// 记录上一次环境快照，并向宿主合并发布实际环境变化。
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()

    /// 使用指定初始矩形创建列表复用视图。
    ///
    /// - Parameter frame: 视图的初始矩形。
    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    /// 从 UIKit 归档创建列表复用视图。
    ///
    /// - Parameter coder: 包含视图状态的归档解码器。
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

    /// 在窗口归属变化前通知 QuickLayout 桥接层更新宿主。
    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        _QuickLayoutViewImplementation.willMove(self, toWindow: newWindow)
    }

    /// 加入或离开窗口后，刷新原生继承的环境快照。
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        quickLayoutEnvironmentState.update(self)
    }

    /// 在应用集合布局属性时刷新复用视图环境，覆盖未再次触发布局的更新。
    open override func apply(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) {
        super.apply(layoutAttributes)
        // 方向变化会使集合布局失效，但 UIKit 不保证每个可见单元格都会再次执行
        // layoutSubviews。布局属性回调是可靠的复用和更新边界。
        quickLayoutEnvironmentState.update(self)
    }

    /// 将 UIKit 特征变化发布给宿主环境，触发依赖环境的内容更新。
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .traitCollection
        )
    }

    /// 将安全区域变化发布给宿主环境。
    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)
    }

    /// 将布局边距变化发布给宿主环境。
    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    /// 读取 UIKit 有效环境后，在受管理状态与容器作用域中应用内容布局。
    open override func layoutSubviews() {
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(bounds.size) {
                _QuickLayoutViewImplementation.layoutSubviews(self)
            }
        }
    }

    /// 通过统一的 QuickLayout 测量入口计算尺寸，无法测量时使用 UIKit 默认实现。
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        quickLayoutSizeThatFits(size) ?? super.sizeThatFits(size)
    }

    /// 通过子类可重写的测量入口拟合尺寸，并保留集合布局提供的原始属性。
    open override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        // 不调用 super，避免 UIKit 的拟合路径绕过 sizeThatFits 或重复测量 body。
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        attributes.size = sizeThatFits(layoutAttributes.size)
        return attributes
    }

    /// UIKit 自适应测量使用与 body 布局相同的尺寸入口。
    open override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        // 保留集合布局的 proposal；固定轴与弹性轴由 cell 的 flexibility 统一解析。
        guard var size = quickLayoutSizeThatFits(targetSize) else {
            return super.systemLayoutSizeFitting(
                targetSize,
                withHorizontalFittingPriority: horizontalFittingPriority,
                verticalFittingPriority: verticalFittingPriority
            )
        }
        if horizontalFittingPriority == .required { size.width = targetSize.width }
        if verticalFittingPriority == .required { size.height = targetSize.height }
        return size
    }

    /// 返回指定轴上显式配置的尺寸弹性。
    open override func quickLayoutFlexibility(for axis: Axis) -> Flexibility {
        switch axis {
        case .horizontal:
            return quickLayoutHorizontalFlexibility
        case .vertical:
            return quickLayoutVerticalFlexibility
        }
    }

    /// 标记宿主内容需要在后续 UIKit 布局周期更新。
    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    /// 在宿主布局已失效时立即执行布局。
    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }


    /// 响应可能影响布局的 UIKit 环境变化。
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    /// 读取 UIKit 有效环境后，在宿主状态与容器作用域中测量内容。测量建议先按宿主各轴弹性解析。
    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
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

    /// 以内联初始化方式提供内容的构建闭包；未设置时由 `body` 的默认实现返回空布局。
    private var contentProvider: (() -> Layout)?
    /// 记录上一次环境快照，并向宿主合并发布实际环境变化。
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()


    /// 使用 UIKit 样式和复用标识创建单元格。
    ///
    /// - Parameters:
    ///   - style: 单元格样式。
    ///   - reuseIdentifier: 复用标识；`nil` 表示不指定。
    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }

    /// 从 UIKit 归档创建列表复用视图。
    ///
    /// - Parameter coder: 包含视图状态的归档解码器。
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

    /// 在窗口归属变化前通知 QuickLayout 桥接层更新宿主。
    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        _QuickLayoutViewImplementation.willMove(self, toWindow: newWindow)
    }

    /// 加入或离开窗口后，刷新原生继承的环境快照。
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        quickLayoutEnvironmentState.update(self)
    }

    /// 将 UIKit 特征变化发布给宿主环境，触发依赖环境的内容更新。
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .traitCollection
        )
    }

    /// 将安全区域变化发布给宿主环境。
    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)
    }

    /// 将布局边距变化发布给宿主环境。
    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    /// 读取 UIKit 有效环境后，在受管理状态与容器作用域中应用内容布局。
    open override func layoutSubviews() {
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(bounds.size) {
                _QuickLayoutViewImplementation.layoutSubviews(self)
            }
        }
    }

    /// 通过统一的 QuickLayout 测量入口计算尺寸，无法测量时使用 UIKit 默认实现。
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        quickLayoutSizeThatFits(size) ?? super.sizeThatFits(size)
    }

    /// 按 UIKit fitting 优先级测量内容，无法测量时回退到父类实现。
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

    /// 标记宿主内容需要在后续 UIKit 布局周期更新。
    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    /// 在宿主布局已失效时立即执行布局。
    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }


    /// 响应可能影响布局的 UIKit 环境变化。
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    /// 读取 UIKit 有效环境后，在宿主状态与容器作用域中测量内容。
    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
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

    /// 仅在 `.required` 轴使用目标长度，其余轴查询理想尺寸；测量后恢复固定轴的目标值。
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

    /// 以内联初始化方式提供内容的构建闭包；未设置时由 `body` 的默认实现返回空布局。
    private var contentProvider: (() -> Layout)?
    /// 记录上一次环境快照，并向宿主合并发布实际环境变化。
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()


    /// 使用 UIKit 复用标识创建页眉或页脚。
    ///
    /// - Parameter reuseIdentifier: 复用标识；`nil` 表示不指定。
    public override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
    }

    /// 从 UIKit 归档创建列表复用视图。
    ///
    /// - Parameter coder: 包含视图状态的归档解码器。
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

    /// 在窗口归属变化前通知 QuickLayout 桥接层更新宿主。
    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        _QuickLayoutViewImplementation.willMove(self, toWindow: newWindow)
    }

    /// 加入或离开窗口后，刷新原生继承的环境快照。
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        quickLayoutEnvironmentState.update(self)
    }

    /// 将 UIKit 特征变化发布给宿主环境，触发依赖环境的内容更新。
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .traitCollection
        )
    }

    /// 将安全区域变化发布给宿主环境。
    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)
    }

    /// 将布局边距变化发布给宿主环境。
    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    /// 读取 UIKit 有效环境后，在受管理状态与容器作用域中应用内容布局。根视图与 `contentView` 边界不同时按实际内容容器重新应用布局。
    open override func layoutSubviews() {
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

    /// 通过统一的 QuickLayout 测量入口计算尺寸，无法测量时使用 UIKit 默认实现。
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        quickLayoutSizeThatFits(size) ?? super.sizeThatFits(size)
    }

    /// 按 UIKit fitting 优先级测量内容，无法测量时回退到父类实现。
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

    /// 标记宿主内容需要在后续 UIKit 布局周期更新。
    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    /// 在宿主布局已失效时立即执行布局。
    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }


    /// 响应可能影响布局的 UIKit 环境变化。
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    /// 读取 UIKit 有效环境后，在宿主状态与容器作用域中测量内容。
    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        quickLayoutEnvironmentState.update(self)

        // UIKit 提供整个 header/footer 的宽度，但 insetGrouped 和安全区域会缩窄
        // contentView。首次 fitting 时它还可能没有 frame，先让 UIKit 布置容器。
        if bounds.width > 0, size.width.isFinite {
            layoutIfNeeded()
        }
        let horizontalInset = contentView.bounds.width > 0
            ? max(0, bounds.width - contentView.bounds.width) : 0
        let contentSize = CGSize(width: max(0, size.width - horizontalInset),
                                 height: size.height)
        guard var measured = withQuickLayoutManagedViewState({
            withQuickLayoutContainerSize(contentSize) {
                _QuickLayoutViewImplementation.sizeThatFits(self, size: contentSize)
            }
        }) else { return nil }
        measured.width += horizontalInset
        return measured
    }

    /// 仅在 `.required` 轴使用目标长度，其余轴查询理想尺寸；测量后恢复固定轴的目标值。
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

    /// 复用视图的水平尺寸弹性。
    open var quickLayoutHorizontalFlexibility: Flexibility = .fullyFlexible

    /// 复用视图的垂直尺寸弹性。
    open var quickLayoutVerticalFlexibility: Flexibility = .fullyFlexible

    /// 用于解析复用视图布局方向的语义角色。
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    /// 以内联初始化方式提供内容的构建闭包；未设置时由 `body` 的默认实现返回空布局。
    private var contentProvider: (() -> Layout)?
    /// 记录上一次环境快照，并向宿主合并发布实际环境变化。
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()


    /// 使用指定初始矩形创建列表复用视图。
    ///
    /// - Parameter frame: 视图的初始矩形。
    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    /// 从 UIKit 归档创建列表复用视图。
    ///
    /// - Parameter coder: 包含视图状态的归档解码器。
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

    /// 在窗口归属变化前通知 QuickLayout 桥接层更新宿主。
    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        _QuickLayoutViewImplementation.willMove(self, toWindow: newWindow)
    }

    /// 加入或离开窗口后，刷新原生继承的环境快照。
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        quickLayoutEnvironmentState.update(self)
    }

    /// 在应用集合布局属性时刷新复用视图环境，覆盖未再次触发布局的更新。
    open override func apply(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) {
        super.apply(layoutAttributes)
        // 集合布局失效后，即使 UIKit 不再执行 layoutSubviews，补充视图仍会收到新的布局属性。
        quickLayoutEnvironmentState.update(self)
    }

    /// 将 UIKit 特征变化发布给宿主环境，触发依赖环境的内容更新。
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .traitCollection
        )
    }

    /// 将安全区域变化发布给宿主环境。
    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)
    }

    /// 将布局边距变化发布给宿主环境。
    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    /// 读取 UIKit 有效环境后，在受管理状态与容器作用域中应用内容布局。
    open override func layoutSubviews() {
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(bounds.size) {
                _QuickLayoutViewImplementation.layoutSubviews(self)
            }
        }
    }

    /// 通过统一的 QuickLayout 测量入口计算尺寸，无法测量时使用 UIKit 默认实现。
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        quickLayoutSizeThatFits(size) ?? super.sizeThatFits(size)
    }

    /// 返回适合当前内容尺寸的集合复用视图布局属性。
    ///
    /// 复制传入属性，并通过 `sizeThatFits(_:)` 更新尺寸，以保留其他属性及子类测量行为。
    ///
    /// - Parameter layoutAttributes: 集合布局提供的原始属性。
    /// - Returns: 包含内容测量尺寸的属性副本。
    open override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        // 保留布局提供的属性，并通过公开测量入口尊重子类的尺寸调整。
        // 不先调用 super，以免 UIKit 已经调用 sizeThatFits 后再次测量内容。
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        attributes.size = sizeThatFits(layoutAttributes.size)
        return attributes
    }

    /// 返回指定轴上显式配置的尺寸弹性。
    open override func quickLayoutFlexibility(for axis: Axis) -> Flexibility {
        switch axis {
        case .horizontal:
            return quickLayoutHorizontalFlexibility
        case .vertical:
            return quickLayoutVerticalFlexibility
        }
    }

    /// 标记宿主内容需要在后续 UIKit 布局周期更新。
    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    /// 在宿主布局已失效时立即执行布局。
    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }


    /// 响应可能影响布局的 UIKit 环境变化。
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    /// 读取 UIKit 有效环境后，在宿主状态与容器作用域中测量内容。测量建议先按宿主各轴弹性解析。
    private func quickLayoutSizeThatFits(_ size: CGSize) -> CGSize? {
        quickLayoutEnvironmentState.update(self)
        let proposedSize = quickLayoutSizeLimit(proposed: size)
        return withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(proposedSize) {
                _QuickLayoutViewImplementation.sizeThatFits(self, size: proposedSize)
            }
        }
    }
}
