import UIKit

/// 同一叠层共用宿主遮罩。每张被覆盖的卡片另有一层随其移动和裁切的遮罩。
@MainActor
final class SheetDimming {
    private let pageShade = UIView()
    private let cardShade = UIView()
    private weak var surface: UIView?
    private weak var lower: SheetDimming?
    private let covers = NSHashTable<SheetDimming>.weakObjects()
    private var combinedAmount: CGFloat = 0
    var amount: CGFloat = 0 {
        didSet { if oldValue != amount { render() } }
    }

    init() {
        for shade in [pageShade, cardShade] {
            shade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            shade.isUserInteractionEnabled = false
            shade.isAccessibilityElement = false
            shade.alpha = 0
        }
        pageShade.backgroundColor = UIColor.black.withAlphaComponent(0.20)
        cardShade.backgroundColor = UIColor.black.withAlphaComponent(0.12)
    }

    func install(in backdrop: UIView, surface: UIView, above lower: SheetDimming?) {
        self.surface = surface
        self.lower = lower
        if let lower {
            lower.covers.add(self)
            if let card = lower.surface, lower.cardShade.superview == nil {
                lower.cardShade.frame = card.bounds
                card.addSubview(lower.cardShade)
            }
        } else {
            pageShade.frame = backdrop.bounds
            backdrop.addSubview(pageShade)
        }
        render()
    }

    private func render() {
        let covering = covers.allObjects.map(\.combinedAmount).max() ?? 0
        cardShade.alpha = covering
        // 两层都需要遮罩时，窗口保留较深的一层；上层跨越免遮罩档位时只补足差额。
        let combined = max(amount, covering)
        pageShade.alpha = combined
        if combinedAmount != combined {
            combinedAmount = combined
            lower?.render()
        }
    }

    func remove() {
        if let lower {
            lower.covers.remove(self)
            if lower.covers.allObjects.isEmpty { lower.cardShade.removeFromSuperview() }
            lower.render()
        }
        self.lower = nil
        for cover in covers.allObjects { cover.lower = nil }
        covers.removeAllObjects()
        surface = nil
        pageShade.removeFromSuperview()
        cardShade.removeFromSuperview()
        amount = 0
    }
}
