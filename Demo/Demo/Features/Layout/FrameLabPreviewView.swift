import QuickLayout
import QuickLayoutKit
import UIKit

/// frame API 的六类实验；声明顺序用于场景导航，rawValue 用于拼接本地化键。
enum FrameLabScenario: String, CaseIterable {
    case fixed, bounds, ideal, fill, alignment, composition

    /// 当前场景的选项顺序，与 state.option 和示例代码分支保持对应；对齐场景单独使用九个位置。
    var optionKeys: [String] {
        switch self {
        case .fixed: ["widthOnly", "heightOnly", "both"]
        case .bounds: ["minimum", "maximum", "range"]
        case .ideal: ["finite", "unspecified"]
        case .fill: ["horizontal", "both"]
        case .alignment: []
        case .composition: ["mixed", "paddingFirst", "frameFirst"]
        }
    }
}

/// 单页实验的值类型状态；页面负责修改，预览接收快照用于实际布局。
struct FrameLabState {
    var scenario: FrameLabScenario = .fixed
    /// 当前场景 optionKeys 的索引；对齐场景使用 alignmentIndex，此值不参与选择。
    var option = 2
    var stretchesContent = false
    /// 相对预览舞台的宽度比例，由页面限制在 0.5...1。
    var widthFraction: CGFloat = 1
    /// 预览容器高度，单位 pt；由页面限制在 140...280。
    var containerHeight: CGFloat = 200
    /// 下方两组对齐映射的共同索引，默认指向 center。
    var alignmentIndex = 4

    /// 按行排列的逻辑位置名称；与 alignments 一一对应，RTL 只改变显示位置。
    static let alignmentNames = [
        "topLeading", "top", "topTrailing", "leading", "center", "trailing",
        "bottomLeading", "bottom", "bottomTrailing",
    ]
    static let alignments: [Alignment] = [
        .topLeading, .top, .topTrailing, .leading, .center, .trailing,
        .bottomLeading, .bottom, .bottomTrailing,
    ]

    /// 只有固定尺寸、边界和撑满实验允许用户独立切换 resizable。
    var supportsStretching: Bool {
        scenario == .fixed || scenario == .bounds || scenario == .fill
    }

    /// 生成与预览 example 分支对应的示例代码；容器尺寸是外部提议，不写入代码。
    var code: String {
        let prefix = "label" + (stretchesContent || scenario == .ideal ? ".resizable()" : "")
        let modifier: String
        switch scenario {
        case .fixed:
            modifier = [".frame(width: 120)", ".frame(height: 64)",
                        ".frame(width: 120, height: 64)"][option]
        case .bounds:
            modifier = [".frame(minWidth: 100, minHeight: 48)",
                        ".frame(maxWidth: 240, maxHeight: 120)",
                        ".frame(minWidth: 100, maxWidth: 240,\n         minHeight: 48, maxHeight: 120)"][option]
        case .ideal:
            modifier = ".frame(idealWidth: 120, idealHeight: 64)"
                + (option == 1 ? "\n  .fixedSize()" : "")
        case .fill:
            modifier = option == 0 ? ".frame(maxWidth: .infinity)"
                : ".frame(maxWidth: .infinity,\n         maxHeight: .infinity)"
        case .alignment:
            modifier = ".frame(maxWidth: .infinity,\n         maxHeight: .infinity,\n         alignment: .\(Self.alignmentNames[alignmentIndex]))"
        case .composition:
            modifier = [".frame(minWidth: 100, maxWidth: 240)\n  .frame(height: 64)",
                        ".padding(12)\n  .frame(width: 120, height: 64)",
                        ".frame(width: 120, height: 64)\n  .padding(12)"][option]
        }
        return prefix + "\n  " + modifier
    }
}

/// 背景标记参与真实布局，避免用推算的矩形冒充 frame 测量结果。
final class FrameLabPreviewView: QuickLayoutView {
    var state = FrameLabState() { didSet { setNeedsQuickLayout() } }
    let sample = FrameLabSampleLabel()
    /// 蓝色边界测量 frame 包装后的尺寸，可能与橙色内容尺寸不同。
    let frameMarker = FrameLabBoundaryView(color: .systemBlue)
    /// 整条修饰链的最终尺寸；在链式实验中包含 frame 之外的 padding。
    let resultMarker = UIView()
    private let containerBorder = FrameLabBoundaryView(color: .secondaryLabel, dashed: true)
    /// 在 super.layoutSubviews 完成后通知读数方，此时可以读取真实几何尺寸。
    var didLayout: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        accessibilityIdentifier = "frame.preview"
        sample.accessibilityIdentifier = "frame.sample"
        frameMarker.accessibilityIdentifier = "frame.frame"
        resultMarker.accessibilityIdentifier = "frame.result"
        containerBorder.isUserInteractionEnabled = false
        frameMarker.backgroundColor = .systemBlue.withAlphaComponent(0.04)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var body: Layout {
        example.background { resultMarker.resizable() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { containerBorder.resizable() }
    }

    @LayoutBuilder private var content: Layout {
        if state.stretchesContent || state.scenario == .ideal {
            sample.resizable()
        } else {
            sample
        }
    }

    /// 各分支直接组合被演示的 API；修改语义时需同步 FrameLabState.code。
    @LayoutBuilder private var example: Layout {
        switch state.scenario {
        case .fixed:
            content.frame(width: state.option == 1 ? nil : 120,
                          height: state.option == 0 ? nil : 64)
                .background { frameMarker.resizable() }
        case .bounds:
            content.frame(minWidth: state.option == 1 ? nil : 100,
                          maxWidth: state.option == 0 ? nil : 240,
                          minHeight: state.option == 1 ? nil : 48,
                          maxHeight: state.option == 0 ? nil : 120)
                .background { frameMarker.resizable() }
        case .ideal:
            if state.option == 1 {
                content.frame(idealWidth: 120, idealHeight: 64).fixedSize()
                    .background { frameMarker.resizable() }
            } else {
                content.frame(idealWidth: 120, idealHeight: 64)
                    .background { frameMarker.resizable() }
            }
        case .fill:
            content.frame(maxWidth: .infinity, maxHeight: state.option == 1 ? .infinity : nil)
                .background { frameMarker.resizable() }
        case .alignment:
            content.frame(maxWidth: .infinity, maxHeight: .infinity,
                          alignment: FrameLabState.alignments[state.alignmentIndex])
                .background { frameMarker.resizable() }
        case .composition:
            if state.option == 0 {
                content.frame(minWidth: 100, maxWidth: 240).frame(height: 64)
                    .background { frameMarker.resizable() }
            } else if state.option == 1 {
                content.padding(12).frame(width: 120, height: 64)
                    .background { frameMarker.resizable() }
            } else {
                content.frame(width: 120, height: 64)
                    .background { frameMarker.resizable() }.padding(12)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        didLayout?()
    }
}

/// 保留 UILabel 自然测量，橙色边界同时包含文本内边距。
final class FrameLabSampleLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        text = "Hello"
        textAlignment = .center
        font = .preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        backgroundColor = .systemOrange.withAlphaComponent(0.25)
        layer.borderWidth = 1
        updateBorder()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let textSize = super.sizeThatFits(CGSize(width: max(0, size.width - 16), height: max(0, size.height - 8)))
        return CGSize(width: textSize.width + 16, height: textSize.height + 8)
    }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 8, dy: 4)) }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBorder()
    }

    private func updateBorder() { layer.borderColor = UIColor.systemOrange.resolvedColor(with: traitCollection).cgColor }
}

/// 在自身 bounds 内绘制实线或虚线边界，不参与示例的尺寸决策。
final class FrameLabBoundaryView: UIView {
    private let shape = CAShapeLayer()
    private let color: UIColor

    init(color: UIColor, dashed: Bool = false) {
        self.color = color
        super.init(frame: .zero)
        shape.fillColor = UIColor.clear.cgColor
        shape.lineWidth = 1
        shape.lineDashPattern = dashed ? [5, 4] : nil
        layer.addSublayer(shape)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 这里只绘制边界，不介入被演示视图的尺寸计算。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.path = UIBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).cgPath
        shape.strokeColor = color.resolvedColor(with: traitCollection).cgColor
        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("真实布局 · 固定尺寸") {
    let preview = FrameLabPreviewView()
    return QuickLayoutView {
        preview.resizable().frame(height: 200).padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@available(iOS 17.0, *)
#Preview("真实布局 · RTL 前缘对齐") {
    let preview = FrameLabPreviewView()
    preview.state = FrameLabPresentation.guided.initialState
    preview.semanticContentAttribute = .forceRightToLeft
    return QuickLayoutView {
        preview.resizable().frame(height: 180).padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
