//
//  MediaMessageView.swift
//  Demo
//

import AVKit
import ImageIO
import QuickLayout
import QuickLayoutKit
import UIKit

/// 显示单张媒体或可横向切换的媒体堆叠的消息视图。
final class MediaMessageView: UIView, UIGestureRecognizerDelegate {
    /// 单张媒体气泡与多媒体堆叠共用的布局尺寸。
    enum Metrics {
        /// 单张媒体允许的最大宽度，单位为点。
        static let singleMaximumWidth: CGFloat = 252
        /// 单张媒体允许的最大高度，单位为点。
        static let singleMaximumHeight: CGFloat = 360
        /// 单张媒体布局的最小边长约束，单位为点。
        static let singleMinimumEdge: CGFloat = 120
        /// 媒体堆叠中每张卡片的基准尺寸。
        static let groupCardSize = CGSize(width: 216, height: 300)
        /// 媒体堆叠相邻层的水平与垂直偏移量。
        static let groupOffset = CGPoint(x: 8, y: 6)
        /// 媒体数量标题行的高度，单位为点。
        static let titleHeight: CGFloat = 24
        /// 媒体数量标题与堆叠卡片之间的间距，单位为点。
        static let titleSpacing: CGFloat = 8
        /// 媒体卡片的圆角半径，单位为点。
        static let cornerRadius: CGFloat = 22
    }

    /// 显示媒体组总项目数的标签。
    let itemCountLabel = UILabel()
    /// 与项目数量配套显示的媒体网格符号。
    let itemCountIcon = UIImageView(image: UIImage(systemName: "square.grid.2x2.fill"))
    /// 裁剪单张媒体气泡轮廓的形状遮罩。
    let singleMaskLayer = CAShapeLayer()
    /// 用于显示有限媒体窗口的可复用卡片集合。
    var cards: [CardView] = []
    /// 驱动媒体封面切换的水平拖动手势。
    lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    /// 打开被点击媒体项目预览的轻点手势。
    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))

    /// 当前媒体消息的稳定标识符。
    var messageID = 0
    /// 当前消息的接收或发出方向，用于确定气泡外观与语义对齐。
    var direction: MessageDirection = .incoming
    /// 当前显示的有序媒体组；未配置或重置后为 `nil`。
    var group: MediaGroupAttachment?
    /// 当前媒体内容的本地化文字集合。
    var strings: MediaStrings?
    /// 当前位于堆叠最前方的媒体项目索引。
    var frontMediaIndex = 0
    /// 指示封面切换动画尚未结束的布尔值，用于限制手势重入。
    var isAnimating = false
    /// 当前尚未提交的拖动预览；收尾和静止阶段为 `nil`。
    var interaction: MediaStackPolicy.Interaction?
    /// 使取消、重新绑定之前的动画完成回调失效的递增令牌。
    var transitionGeneration: UInt = 0
    /// 最近布局使用的边界尺寸，用于取消几何已失效的交互。
    private var laidOutSize: CGSize = .zero
    /// 最近布局使用的界面方向；变化后重新建立静止几何。
    private var laidOutDirection: UIUserInterfaceLayoutDirection?
    /// 根据当前单张媒体或堆叠内容计算的固有尺寸。
    var resolvedSize = CGSize(width: 252, height: 252)

    /// 封面位置改变后调用的闭包，参数依次为消息身份与媒体索引。
    var frontIndexDidChange: ((Int, Int) -> Void)?
    /// 用户请求预览媒体时调用的闭包，参数为消息身份、媒体组与起始索引。
    var previewRequested: ((Int, MediaGroupAttachment, Int) -> Void)?

    /// 从当前封面生成匹配转场，不包含背后的堆叠卡片。
    var previewSourceView: UIView? {
        guard let group, group.items.indices.contains(frontMediaIndex) else { return nil }
        return cards.first { $0.represents(messageID: messageID, groupID: group.id, itemID: group.items[frontMediaIndex].id) }
    }

    /// 使用指定初始边框创建 `MediaMessageView`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        itemCountLabel.font = .preferredFont(forTextStyle: .headline)
        itemCountLabel.adjustsFontForContentSizeCategory = true
        itemCountLabel.textColor = .systemBlue
        itemCountLabel.textAlignment = .natural
        itemCountIcon.tintColor = .systemBlue
        addSubview(itemCountIcon)
        addSubview(itemCountLabel)
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
        tapGesture.require(toFail: panGesture)
        addGestureRecognizer(tapGesture)
        isAccessibilityElement = true
        accessibilityTraits = [.image, .button, .adjustable]
        accessibilityIdentifier = "imessage.media.message"
    }

    /// 不支持从归档创建 `MediaMessageView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `MediaMessageView` 在当前内容与布局约束下的固有尺寸。
    override var intrinsicContentSize: CGSize { resolvedSize }

    /// 根据当前边界更新 `MediaMessageView` 的子视图布局与图层几何。
    override func layoutSubviews() {
        super.layoutSubviews()
        if laidOutSize != bounds.size || laidOutDirection != effectiveUserInterfaceLayoutDirection {
            invalidateInteraction()
            laidOutSize = bounds.size
            laidOutDirection = effectiveUserInterfaceLayoutDirection
            bindCards()
        }
        guard !isAnimating else { return }
        layoutCards()
        applyInteraction()
    }

    /// 离开窗口时取消尚未确认的拖动，并清理正在收尾的动画。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            invalidateInteraction()
            bindCards()
            layoutCards()
        }
    }

    /// 绑定有序媒体组与封面位置，更新卡片数量、固有尺寸和辅助功能信息。
    func configure(
        messageID: Int,
        direction: MessageDirection,
        group: MediaGroupAttachment,
        frontIndex: Int,
        strings: MediaStrings
    ) {
        let resolvedIndex = min(max(0, frontIndex), max(0, group.items.count - 1))
        let keepsBinding = self.messageID == messageID && self.group == group
            && self.direction == direction && frontMediaIndex == resolvedIndex
        if !keepsBinding { invalidateInteraction() }
        self.messageID = messageID
        self.direction = direction
        self.group = group
        self.strings = strings
        frontMediaIndex = resolvedIndex
        ensureCardCount(
            min(
                group.items.count,
                MediaStackPolicy.maximumVisibleCardCount
            )
        )
        let previousSize = resolvedSize
        resolvedSize = Self.size(for: group)
        if previousSize != resolvedSize { invalidateIntrinsicContentSize() }
        panGesture.isEnabled = group.items.count > 1
        itemCountLabel.isHidden = group.items.count == 1
        itemCountIcon.isHidden = group.items.count == 1
        itemCountLabel.text = String(format: strings.itemsFormat, group.items.count)
        accessibilityValue = String(
            format: strings.positionFormat,
            frontMediaIndex + 1,
            group.items.count
        )
        accessibilityHint = strings.openPreview
        updateAccessibilityLabel()
        if interaction == nil && !isAnimating { bindCards() }
        setNeedsLayout()
    }

    /// 清空媒体绑定、标题、遮罩和辅助功能状态，并重置全部卡片。
    func reset() {
        invalidateInteraction()
        group = nil
        strings = nil
        messageID = 0
        frontMediaIndex = 0
        isAnimating = false
        itemCountLabel.text = nil
        itemCountIcon.isHidden = true
        itemCountLabel.isHidden = true
        singleMaskLayer.path = nil
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityHint = nil
        cards.forEach { $0.reset(); $0.isHidden = true }
        panGesture.isEnabled = false
    }

    /// 通过辅助功能递增操作切换到下一媒体项目。
    override func accessibilityIncrement() {
        move(to: frontMediaIndex + 1, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// 通过辅助功能递减操作切换到上一媒体项目。
    override func accessibilityDecrement() {
        move(to: frontMediaIndex - 1, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// 仅在有多个项目、没有切换动画且手势以水平运动为主时允许拖动。
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture,
              let group,
              group.items.count > 1,
              !isAnimating, interaction == nil else { return false }
        let velocity = panGesture.velocity(in: self)
        return MediaStackPolicy.isHorizontalPan(velocity: velocity)
    }

    /// 返回当前已绑定媒体卡片的布局 frame，供页面内布局回归测试使用。
    func visibleCardFrame(forMediaIndex index: Int) -> CGRect? {
        cards.first { !$0.isHidden && $0.mediaIndex == index }?.restingFrame
    }

    /// 返回当前已绑定媒体卡片的展示层级，供页面内布局回归测试使用。
    func visibleCardZPosition(forMediaIndex index: Int) -> CGFloat? {
        cards.first { !$0.isHidden && $0.mediaIndex == index }?.layer.zPosition
    }

    /// 返回当前已绑定媒体卡片的静态扇形变换。
    func visibleCardRestingTransform(forMediaIndex index: Int) -> CGAffineTransform? {
        cards.first { !$0.isHidden && $0.mediaIndex == index }?.restingTransform
    }

    /// 返回包含当前交互缩放和旋转的卡片变换，供交互回归测试使用。
    func visibleCardTransform(forMediaIndex index: Int) -> CGAffineTransform? {
        cards.first { !$0.isHidden && $0.mediaIndex == index }?.transform
    }

    /// 返回当前交互卡片的中心位置，供连续拖动和布局回归测试使用。
    func visibleCardCenter(forMediaIndex index: Int) -> CGPoint? {
        cards.first { !$0.isHidden && $0.mediaIndex == index }?.center
    }

    /// 当前参与展示的卡片层数。
    var visibleCardCount: Int {
        cards.lazy.filter { !$0.isHidden }.count
    }

    /// 返回指定媒体当前绑定的 CardView 身份，供重用回归测试使用。
    func visibleCardObjectIdentifier(forMediaIndex index: Int) -> ObjectIdentifier? {
        cards.first { !$0.isHidden && $0.mediaIndex == index }.map(ObjectIdentifier.init)
    }
}
