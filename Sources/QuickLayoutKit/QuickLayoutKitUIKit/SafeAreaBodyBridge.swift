import ObjectiveC
import QuickLayout
import QuickLayoutKitCore
import UIKit

/// 私有内容提供者复用 QuickLayout 的子视图差异更新与出现动画。
/// 自身不加入视图树；所有内容仍挂载在真实宿主的内容容器中。
@MainActor
private final class SafeAreaBodyProvider: UIView, HasBody {
    weak var owner: (UIView & HasBody)?
    override var bodyContainerView: UIView { owner?.bodyContainerView ?? self }
    override var isBodyEnabled: Bool { owner?.isBodyEnabled ?? false }
    // 代理只接收本轮已测量布局，不能让上游作用域缓存覆盖刚解析的候选选择。
    override var isCachingEnabled: Bool { false }
    var preparedBody: Layout = EmptyLayout()
    override func layoutSubviews() {
        super.layoutSubviews()
        // 上游缓存刷新的是代理节点，实际子视图仍须由真实宿主完成放置。
        owner?.layoutIfNeeded()
    }
    var body: Layout { PreparedBodyReference(provider: self) }
}

/// 即使外层原生 QuickLayout 开启作用域缓存，缓存的引用仍读取本轮准备结果。
@MainActor
private struct PreparedBodyReference: @MainActor Layout {
    weak var provider: SafeAreaBodyProvider?
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        provider?.preparedBody.quick_layoutThatFits(proposedSize) ?? .empty
    }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        provider?.preparedBody.quick_extractViewsIntoArray(&views)
    }
}

private enum SafeAreaBodyKeys {
    nonisolated(unsafe) static var provider: UInt8 = 0
}

/// Kit 非滚动宿主的测量与放置共用此入口，保证两阶段采用相同的安全区规则。
@MainActor
enum QuickLayoutSafeAreaBodyBridge {
    private static func provider(for view: UIView & HasBody) -> SafeAreaBodyProvider {
        let provider: SafeAreaBodyProvider
        if let existing = objc_getAssociatedObject(view, &SafeAreaBodyKeys.provider) as? SafeAreaBodyProvider {
            provider = existing
        } else {
            provider = SafeAreaBodyProvider()
            provider.owner = view
            objc_setAssociatedObject(view, &SafeAreaBodyKeys.provider, provider, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        // 效果视图动画期间 contentView 可能尚未同步新尺寸，沿用上游以宿主 bounds 布局的契约。
        // 表格页眉页脚的内容容器可被 UIKit 真实收窄，继续使用其独立尺寸。
        provider.bounds = view is UITableViewHeaderFooterView ? view.bodyContainerView.bounds : view.bounds
        provider.semanticContentAttribute = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? .forceRightToLeft : .forceLeftToRight
        return provider
    }

    static func willMove(_ view: UIView & HasBody, toWindow window: UIWindow?) {
        _QuickLayoutViewImplementation.willMove(provider(for: view), toWindow: window)
    }

    static func layoutSubviews(_ view: UIView & HasBody) {
        let provider = provider(for: view)
        guard view.isBodyEnabled else {
            commit(EmptyLayout(), using: provider)
            return
        }
        let element = QuickLayoutDefaultSafeAreaElement(child: view.body)
        let direction: LayoutDirection = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        let node = element.layoutThatFits(provider.bounds.size, layoutDirection: direction)
        commit(QuickLayoutMeasuredLayout(element: element, node: node), using: provider)
    }

    /// 滚动宿主使用内容坐标和自己的对齐方式，层级同步仍由同一代理负责。
    static func apply(_ element: Layout, on view: UIView & HasBody, frame: CGRect,
                      alignment: Alignment, direction: LayoutDirection) {
        let provider = provider(for: view)
        provider.bounds = frame
        let node = element.layoutThatFits(frame.size, layoutDirection: direction)
        let measured = QuickLayoutMeasuredLayout(element: element, node: node)
        // 上游宿主固定按中心放置；先在指定矩形中完成内容对齐，再固定包装层的中心参考线。
        let positioned = AlignmentGuideElement(
            child: AlignmentGuideElement(
                child: FixedFrameElement(child: measured, width: frame.width, height: frame.height, alignment: alignment),
                horizontalAlignment: .center, computeValue: { $0.width / 2 }),
            verticalAlignment: .center, computeValue: { $0.height / 2 })
        commit(positioned, using: provider)
    }

    /// 准备完成后才交给上游比较视图列表并应用布局；提交期间不会重新测量候选。
    private static func commit(_ body: Layout, using provider: SafeAreaBodyProvider) {
        provider.preparedBody = body
        defer { provider.preparedBody = EmptyLayout() }
        // 提交已测量的节点时，UIKit 可能同步布局子宿主。让子宿主读取其修饰符
        // 捕获的安全区，避免误用父宿主尚未消费的根作用域。
        QuickLayoutSafeAreaContext.$current.withValue(nil) {
            _QuickLayoutViewImplementation.layoutSubviews(provider)
        }
    }

    static func sizeThatFits(_ view: UIView & HasBody, size: CGSize) -> CGSize? {
        // 私有代理不是 UICollectionViewCell，需保留上游对未使用自适应尺寸布局的保护。
        if BodyCoordinationExperiments.preventUnusedCollectionViewCellSizing,
           view is UICollectionViewCell, let collection = view.superview as? UICollectionView {
            let selector = #selector(UICollectionViewLayout.shouldInvalidateLayout(forPreferredLayoutAttributes:withOriginalAttributes:))
            if collection.collectionViewLayout.method(for: selector) == UICollectionViewLayout.instanceMethod(for: selector) {
                return nil
            }
        }
        guard view.isBodyEnabled else { return nil }
        let direction: LayoutDirection = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        // 上游 sizeThatFits 会同步子视图；Kit 的纯测量必须绕开这一步，避免试探时挂载候选。
        return QuickLayoutDefaultSafeAreaElement(child: view.body)
            .layoutThatFits(size, layoutDirection: direction).size
    }
}
