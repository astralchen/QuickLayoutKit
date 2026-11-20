import UIKit

/// 浮起的中档卡片连同内容一起缩放，内部仍以展开时的逻辑宽度排版。
final class SheetSurface: UIView {
    private let contentContainer = UIView()
    weak var content: UIView? {
        didSet {
            if let content {
                addSubview(contentContainer)
                contentContainer.addSubview(content)
            }
        }
    }
    var logicalWidth: CGFloat = 0

    func place(in rect: CGRect) {
        bounds.size = rect.size
        center = CGPoint(x: rect.midX, y: rect.midY)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let content, logicalWidth > 0, bounds.width > 0 else { return }
        let scale = bounds.width / logicalWidth
        contentContainer.bounds = CGRect(x: 0, y: 0, width: logicalWidth, height: bounds.height / scale)
        contentContainer.center = CGPoint(x: bounds.midX, y: bounds.midY)
        contentContainer.transform = CGAffineTransform(scaleX: scale, y: scale)
        content.frame = contentContainer.bounds
    }
}

/// UIKit 的转场容器位于 presenting view 上方，未遮暗的区域将命中测试交回原视图。
final class SheetBackdrop: UIControl {
    weak var passthroughView: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let target = passthroughView {
            return target.hitTest(convert(point, to: target), with: event)
        }
        return super.hitTest(point, with: event)
    }
}
