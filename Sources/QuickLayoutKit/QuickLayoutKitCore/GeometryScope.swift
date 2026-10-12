import QuickLayout
import UIKit
import ObjectiveC

/// UIKit 容器向 Core 层提供声明的滚动轴，避免 Core 反向依赖 UIKit 模块。
package protocol GeometryScrollAxisProviding: AnyObject {
    /// 容器显式声明的单一滚动轴，由主线程读取。
    @MainActor var geometryScrollAxis: Axis { get }
}

/// 持有透明几何标记视图，并同步声明元数据的持久作用域。
@MainActor
final class GeometryScope: @unchecked Sendable {
    /// 承载纯布局矩形并参与 UIKit 坐标转换的透明标记。
    let view = GeometryScopeView()
    /// 此作用域声明的空间标识；`nil` 表示不声明命名空间。
    var name: GeometryCoordinateSpace?
    /// 此作用域声明的容器元数据；`nil` 表示不覆盖容器信息。
    var container: GeometryContainerValues?

    /// 创建标记视图并安装弱捕获回调，在布局应用时同步元数据。
    init(name: GeometryCoordinateSpace? = nil, container: GeometryContainerValues? = nil,
         anchorID: UUID? = nil) {
        self.name = name
        self.container = container
        view.anchorID = anchorID
        view.name = name
        view.container = container
        view.applyMetadata = { [weak self] in
            guard let self else { return }
            self.view.name = self.name
            self.view.container = self.container
        }
    }

    /// 更新声明内容；锚点身份变化时解除旧绑定并在已挂载视图上绑定新身份。
    func update(name: GeometryCoordinateSpace?, container: GeometryContainerValues?, anchorID: UUID?) {
        self.name = name
        self.container = container
        if view.anchorID != anchorID {
            if let previous = view.anchorID { GeometryAnchorStore.unbind(previous, from: view) }
            view.anchorID = anchorID
            if view.superview != nil, let anchorID { GeometryAnchorStore.bind(anchorID, to: view) }
        }
    }
}

/// 由调用位置和子视图身份构成的作用域复用键。
struct GeometryScopeKey: Hashable {
    /// 作用域声明的源文件标识。
    let file: String
    /// 作用域声明所在的源码行。
    let line: UInt
    /// 作用域声明所在的源码列。
    let column: UInt
    /// 声明类别，区分坐标空间、容器元数据和锚点。
    let kind: Int
    /// 首个实际子视图的身份；纯布局元素为 `nil`。
    let childView: ObjectIdentifier?
    /// 同一调用位置的匿名声明在本轮构建中的出现序号。
    var occurrence = 0
}

/// 在嵌套测量期间传递显式几何作用域的任务局部上下文。
enum GeometryScopeContext {
    /// 当前测量链上的作用域，按由外到内的顺序排列。
    @TaskLocal static var scopes: [GeometryScope] = []
}

/// 显式作用域穿过 UIKit 宿主边界时，记录到布局节点对应的视图。
@MainActor
enum GeometryInheritedScopes {
    /// 视图继承作用域数组的 Objective-C 关联键。
    private static var key: UInt8 = 0
    /// 递归记录节点继承的作用域，保留本轮已经写入的更深层声明。
    static func record(_ scopes: [GeometryScope], in node: LayoutNode) {
        if let view = node.view, !(view is GeometryScopeView), !(view is GeometryObserverView) {
            let existing = (objc_getAssociatedObject(view, &key) as? [GeometryScope]) ?? []
            // 外层包装器在内层之后返回，不能覆盖本轮已记录的更深作用域。
            if scopes.isEmpty || !existing.contains(where: { $0 === scopes.last }) {
                objc_setAssociatedObject(view, &key, scopes, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
        for child in node.children { record(scopes, in: child.layout) }
    }
    /// 沿祖先链由外到内收集关联作用域，并按对象身份去重。
    static func scopes(for view: UIView) -> [GeometryScope] {
        var ancestry: [UIView] = []
        var current: UIView? = view.superview
        while let ancestor = current { ancestry.append(ancestor); current = ancestor.superview }
        var result: [GeometryScope] = []
        for ancestor in ancestry.reversed() {
            for scope in (objc_getAssociatedObject(ancestor, &key) as? [GeometryScope]) ?? [] {
                if !result.contains(where: { $0 === scope }) { result.append(scope) }
            }
        }
        return result
    }
}

/// 不参与交互和辅助功能的透明视图，为纯布局元素提供实际几何边界。
@MainActor
final class GeometryScopeView: UIView {
    /// 当前绑定的锚点身份；卸载后延迟解除绑定。
    var anchorID: UUID?
    /// 最近一次布局应用时提交的方向。
    var layoutDirection: LayoutDirection = .leftToRight
    /// 测量阶段暂存、等待布局应用时提交的方向。
    var pendingLayoutDirection: LayoutDirection = .leftToRight
    /// 已提交的命名空间标识。
    var name: GeometryCoordinateSpace?
    /// 已提交的容器查询元数据。
    var container: GeometryContainerValues?
    /// 布局设置中心位置时同步声明元数据的回调。
    var applyMetadata: (() -> Void)?
    /// 确认卸载后通知注册表移除持久状态的回调。
    var onDetach: (() -> Void)?
    /// 通过布局应用阶段的中心赋值，提交方向与元数据。
    override var center: CGPoint {
        didSet {
            layoutDirection = pendingLayoutDirection
            applyMetadata?()
        }
    }
    /// 创建透明标记视图，并关闭交互及辅助功能遍历。
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
    }
    /// 不支持从归档创建内部几何标记视图；调用会终止执行。
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// 挂载时绑定锚点；移除后延迟确认，避免临时重挂载丢失状态。
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil, let anchorID { GeometryAnchorStore.bind(anchorID, to: self) }
        if superview == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.superview == nil else { return }
                if let id = self.anchorID { GeometryAnchorStore.unbind(id, from: self) }
                self.onDetach?()
            }
        }
    }
}

public extension Element {
    /// 为当前布局元素声明坐标空间。
    ///
    /// 元素不需要独立的 UIKit 视图。嵌套声明使用相同名称时，后代查询采用最近的有效声明。
    ///
    /// - Parameters:
    ///   - space: 要声明的命名或滚动空间描述。
    ///   - _fileID: 自动记录的调用文件，用于复用作用域。
    ///   - _line: 自动记录的调用行。
    ///   - _column: 自动记录的调用列。
    /// - Returns: 向后代提供该坐标空间的布局元素。
    ///
    /// 通常应保留调用位置参数的默认值。
    @MainActor
    func coordinateSpace(_ space: NamedCoordinateSpace, _fileID: StaticString = #fileID,
                         _line: UInt = #line, _column: UInt = #column) -> Element & Layout {
        geometryScope(kind: 0, name: space.coordinateSpace, file: _fileID, line: _line, column: _column)
    }

    /// 为后代几何查询声明容器元数据。
    ///
    /// 此方法仅提供查询信息，不修改容器绘制或内容边距布局。
    ///
    /// - Parameters:
    ///   - values: 容器边距与圆角信息，未提供的项目继续向外查找。
    ///   - _fileID: 自动记录的调用文件，用于复用作用域。
    ///   - _line: 自动记录的调用行。
    ///   - _column: 自动记录的调用列。
    /// - Returns: 提供容器查询信息的布局元素。
    @MainActor
    func geometryContainer(_ values: GeometryContainerValues, _fileID: StaticString = #fileID,
                           _line: UInt = #line, _column: UInt = #column) -> Element & Layout {
        geometryScope(kind: 1, container: values, file: _fileID, line: _line, column: _column)
    }

    /// 将已有锚点绑定到当前元素的最终布局矩形。
    ///
    /// - Parameters:
    ///   - anchor: 预先创建并由调用方保持身份稳定的锚点。
    ///   - _fileID: 自动记录的调用文件，用于复用作用域。
    ///   - _line: 自动记录的调用行。
    ///   - _column: 自动记录的调用列。
    /// - Returns: 为该锚点提供实际几何来源的布局元素。
    ///
    /// 来源确认卸载后解除绑定。对于可能失效的来源，使用 `GeometryProxy.resolve(_:)` 查询。
    @MainActor
    func geometryAnchor<Value>(_ anchor: Anchor<Value>, _fileID: StaticString = #fileID,
                               _line: UInt = #line, _column: UInt = #column) -> Element & Layout {
        geometryScope(kind: 2, anchorID: anchor.id, file: _fileID, line: _line, column: _column)
    }

    /// 按调用位置及实际子视图身份复用作用域，无宿主注册表时独立创建。
    @MainActor
    private func geometryScope(kind: Int, name: GeometryCoordinateSpace? = nil,
                               container: GeometryContainerValues? = nil, anchorID: UUID? = nil,
                               file: StaticString, line: UInt, column: UInt) -> Element & Layout {
        var views: [UIView] = []
        quick_extractViewsIntoArray(&views)
        let child = views.first { !($0 is GeometryScopeView) && !($0 is GeometryObserverView) }
        let key = GeometryScopeKey(file: String(describing: file), line: line, column: column,
                                   kind: kind, childView: child.map(ObjectIdentifier.init))
        let scope = QuickLayoutGeometryObservationContext.current?.scope(for: key, name: name, container: container, anchorID: anchorID)
            ?? GeometryScope(name: name, container: container, anchorID: anchorID)
        return GeometryScopeElement(child: self, scope: scope)
    }
}

/// 在子元素测量期间发布作用域，并先应用标记视图的布局包装器。
@MainActor
private struct GeometryScopeElement: @MainActor Layout {
    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 当前布局声明使用的持久作用域。
    let scope: GeometryScope

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility { child.quick_flexibility(for: axis) }
    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }

    /// 冻结待提交方向，记录继承作用域，并把标记节点置于内容节点之前。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        scope.view.pendingLayoutDirection = LayoutContext.layoutDirection
        let scopes = GeometryScopeContext.scopes + [scope]
        let layout = GeometryScopeContext.$scopes.withValue(scopes) {
            child.quick_layoutThatFits(proposedSize)
        }
        GeometryInheritedScopes.record(scopes, in: layout)
        // 先应用作用域标记，再应用后代，保证回调读取到已应用的作用域边界。
        return ZStackElement(children: [
            GeometryFixedNode(node: LayoutNode(view: scope.view, dimensions: ElementDimensions(layout.size))),
            GeometryFixedNode(node: layout),
        ], alignment: .topLeading).quick_layoutThatFits(proposedSize)
    }

    /// 先加入作用域标记视图，再提取内容视图，保持布局应用所需的顺序。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        views.append(scope.view)
        child.quick_extractViewsIntoArray(&views)
    }
}

/// 包装固定几何节点，不重复执行原始内容的测量。
private struct GeometryFixedNode: Layout {
    /// 需要直接复用的已测量节点。
    let node: LayoutNode
    /// 以固定尺寸参与父布局，不要求额外伸缩空间。
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    /// 使用默认布局优先级，不额外影响父布局的空间分配。
    func quick_layoutPriority() -> CGFloat { 0 }
    /// 直接返回已测量的节点，忽略包装层的新尺寸建议。
    func quick_layoutThatFits(_ size: CGSize) -> LayoutNode { node }
    /// 不重复提取视图；实际视图由原内容或布局节点管理。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}
