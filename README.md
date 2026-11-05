# QuickLayoutKit

QuickLayoutKit 是面向 UIKit 的 [QuickLayout](https://github.com/facebookincubator/QuickLayout)
支持库。它保留 UIKit 的视图、控制器和生命周期模型，同时提供声明式布局宿主、滚动视图、
安全区域、内容边距、自适应尺寸、键盘避让和列表复用支持。

## 目录

- [模块与要求](#模块与要求)
- [安装](#安装)
- [设计约定](#设计约定)
- [快速开始](#快速开始)
- [控制器根布局](#控制器根布局)
- [宿主视图与按钮](#宿主视图与按钮)
- [滚动视图](#滚动视图)
- [内容边距与安全区域](#内容边距与安全区域)
- [核心布局能力](#核心布局能力)
- [环境、动态字体与布局方向](#环境动态字体与布局方向)
- [列表与内容配置](#列表与内容配置)
- [子视图控制器](#子视图控制器)
- [键盘处理](#键盘处理)
- [诊断](#诊断)
- [Demo 与测试](#demo-与测试)

## 模块与要求

软件包包含三个模块：

- `QuickLayoutKit`：公开产品，重新导出 QuickLayout、核心扩展和 UIKit 集成类型。
- `QuickLayoutKitCore`：不依赖具体宿主的布局算法、尺寸建议、安全区域和布局修饰符。
- `QuickLayoutKitUIKit`：控制器、视图、滚动视图、列表、键盘和 UIKit 环境集成。

运行要求：

- iOS 15.0 或更高版本
- Swift 6.2 或更高版本
- QuickLayout，版本由 `Package.swift` 中的固定 revision 决定

## 安装

在 Swift Package 依赖中加入本仓库：

```swift
dependencies: [
    .package(
        url: "https://github.com/astralchen/QuickLayoutKit.git",
        branch: "main"
    )
]
```

为应用目标添加 `QuickLayoutKit` 产品：

```swift
.target(
    name: "App",
    dependencies: [
        "QuickLayoutKit"
    ]
)
```

使用时导入：

```swift
import UIKit
import QuickLayout
import QuickLayoutKit
```

## 设计约定

QuickLayoutKit 使用部分与 SwiftUI 相同的 API 名称和重载形式，目的是让 UIKit 布局代码
更容易阅读。这些名称不表示框架会复制 SwiftUI 的运行时默认间距或逐像素布局结果。
尤其不要为所有可选参数套用同一种 `nil` 解释；`nil` 的含义由各 API 的 QuickLayout
契约决定。

| API 或取值 | 当前契约 |
| --- | --- |
| `VStack`、`HStack`、`Grid / GridRow` 和 `Spacer` | 保持 QuickLayout 的测量、间距和弹性语义 |
| `HGrid`、`VGrid` 和 `GridItem` | 参照 SwiftUI 的网格尺寸与对齐语义，采用非懒加载内容 |
| 直接对 `StackElement` 调用 `fixedSize(axis:)` | 固定交叉轴时内部启用 `idealLayout`，协调可伸展子元素的理想尺寸；只固定主轴时保留原有行为 |
| `aspectRatio(nil, contentMode:)` | 从元素的理想尺寸推导宽高比 |
| 弹性 `frame` 的最小、理想、最大尺寸为 `nil` | 不为对应项目提供约束；理想尺寸只在父级没有有限建议时作为备用值 |
| `ProposedSize` 的维度为 `nil` | 该轴未指定；转换为 QuickLayout 提案时使用无穷大，不表示数值零 |
| `safeAreaPadding(..., length: CGFloat = 0)` | 消耗选中边缘继承的安全区域，额外间距为非可选值，默认 `0` |
| `safeAreaInset(..., spacing: CGFloat = 0)` | 为插入内容和安全区域预留空间，间距为非可选值，默认 `0` |
| `safeAreaInset` 内容构建结果为 `nil` | 使用空布局；选中边缘继承的安全区域仍会被消费和预留 |
| `contentMargins(..., nil)` | 不指定所选边缘，不覆盖同一 placement 的既有边距或容器默认值 |
| `QuickLayoutView` 的显式尺寸弹性为 `nil` | 从 `body` 推导对应轴的弹性 |
| `QuickLayoutVisualEffectView` 的 `body` | 自动安装到 `UIVisualEffectView.contentView`，不直接添加到视觉效果视图本身 |
| `QuickLayoutButton.role == nil` | 不发布 destructive/cancel 语义角色，也不会产生隐式样式 |
| 状态或事件 handler 为 `nil` | 不发送相应应用回调；框架自身生命周期继续运行 |
| `performLayoutUpdate(..., animations: nil)` | 只执行 QuickLayout 失效与布局，不追加应用动画闭包 |
| `performLayoutUpdate(..., completion: nil)` | 动画完成后不发送应用完成回调 |
| `QuickLayoutViewControllerRepresentable.setViewController(nil)` | 移除当前子控制器及其视图 |
| representable 的 `DetailedEvent` 可选上下文为 `nil` | 当前事件不涉及该控制器或没有附加诊断原因 |
| `QuickLayoutKeyboardContext(notification:)` 返回 `nil` | 通知缺少 UIKit 的键盘结束 frame，无法建立有效上下文 |
| `QuickLayoutKeyboardAvoider.setActiveView(nil)` | 清除需要自动滚动到键盘上方的目标视图 |
| 列表复用标识符为 `nil` | 原样交给 UIKit，表示该实例没有复用标识符 |
| `QuickLayoutButton` 外观 | 完全由应用的 `body` 和状态回调提供，没有隐式按钮样式 |

当设计要求固定距离时，应明确传入堆栈间距、内边距、内容边距和安全区域附加值。

## 快速开始

创建 `QuickLayoutHostingController` 子类并重写 `body`：

```swift
final class CounterViewController: QuickLayoutHostingController {

    private var count = 0
    private let countLabel = UILabel()
    private let incrementButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        countLabel.font = .preferredFont(forTextStyle: .largeTitle)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textAlignment = .center

        incrementButton.setTitle("Increment", for: .normal)
        incrementButton.addTarget(
            self,
            action: #selector(increment),
            for: .touchUpInside
        )
        updateContent()
    }

    override var body: Layout {
        VStack(alignment: .center, spacing: 24) {
            Spacer()
            countLabel
            incrementButton
            Spacer()
        }
        .safeAreaPadding(.all, 24)
    }

    @objc private func increment() {
        count += 1
        updateContent()
    }

    private func updateContent() {
        countLabel.text = "\(count)"
        setNeedsQuickLayout()
    }
}
```

影响 `body` 测量或元素组成的状态发生变化后，调用 `setNeedsQuickLayout()`。需要在当前调用栈
立即完成布局时，再调用 `quickLayoutIfNeeded()`。

对于不需要子类和生命周期处理的简单内容，可以使用闭包初始化方法：

```swift
let titleLabel = UILabel()
titleLabel.text = "Quick Setup"

let viewController = QuickLayoutHostingController {
    VStack(spacing: 12) {
        titleLabel
    }
    .safeAreaPadding(.all, 20)
}
```

## 控制器根布局

`QuickLayoutHostingController` 的根视图是内部 `QuickLayoutView`。控制器的 `body` 会在整个
根视图边界内测量和放置；安全区域通过 QuickLayout 环境向下传递，但不会自动为所有内容
添加内边距。应根据根内容的所有者选择下列布局方式。

### 全屏 UIKit 视图

当 `UICollectionView`、`UITableView` 或其他 UIKit 容器负责自身内容边距和安全区域调整时，
可以直接让它成为根内容：

```swift
override var body: Layout {
    collectionView
        .resizable()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

此模式适用于 `contentInsetAdjustmentBehavior = .automatic` 的系统滚动容器。不要再为同一层级
重复添加 `safeAreaPadding`，否则可能造成双重安全区域间距。

对于需要明确触控高度的 UIKit 控件，应先声明对应轴可伸缩，再设置布局框，例如
`submitButton.resizable().frame(height: 50)`。仅使用 `.frame(height:)`，或仅声明横向
`.resizable(axis: .horizontal)`，不会强制控件本身放弃纵向固有尺寸；布局框高度与实际
按钮高度可能不同。多行文本通常保留纵向固有尺寸，仅允许横向伸缩。

### 背景与页面滚动内容

背景需要延伸到安全区域之外，而页面内容需要滚动时，将背景和滚动视图放入 `ZStack`：

```swift
private let scrollView = QuickLayoutScrollView()
private let backgroundView = UIView()

override var body: Layout {
    ZStack {
        backgroundView
            .resizable()
            .containerRelativeFrame([.horizontal, .vertical])
            .ignoresSafeArea(.container)

        ScrollView(scrollView) {
            VStack(alignment: .leading, spacing: 20) {
                profileView
                overviewView
                activityView
            }
            .padding(.vertical, 12)
        }
        .contentMargins(.horizontal, 16)
        .contentMargins(.bottom, 24)
    }
}
```

背景使用 `ignoresSafeArea`，滚动内容则使用 `contentMargins`。滚动视图仍占据完整根视图，
不会因为内容边距而缩小背景或可滚动区域。

### 外层垂直滚动与内层横向滚动

页面同时包含页眉、横向轮播和页脚时，尤其是在横屏或大字体环境下，应让三者共同位于外层
垂直滚动视图中。不要只让中间轮播滚动，否则页眉或页脚可能超出可见高度且无法到达。

```swift
private let pageScrollView = QuickLayoutScrollView()
private let carouselScrollView = QuickLayoutScrollView(
    .horizontal,
    showsIndicators: false
)

override var body: Layout {
    ScrollView(pageScrollView) {
        VStack(alignment: .leading, spacing: 20) {
            headerLayout
                .safeAreaPadding(.horizontal, 20)

            ScrollView(
                carouselScrollView,
                .horizontal,
                showsIndicators: false
            ) {
                cardsLayout
                    .fixedSize(axis: .vertical)
            }
            .resizable(axis: .horizontal)
            .contentMargins(.horizontal, 16)

            footerLayout
                .safeAreaPadding(.horizontal, 20)
        }
        .padding(.vertical, 16)
    }
}
```

这里的职责划分是：

- 外层垂直滚动视图负责页面在紧凑高度和动态字体下的可达性。
- 页眉和页脚使用 `safeAreaPadding`，因为它们不是横向滚动内容。
- 内层横向滚动视图使用 `contentMargins`，使首尾卡片在安全区域内可达。
- 横向内容使用自然高度；需要等高卡片时，可以先执行理想尺寸布局，再固定交叉轴尺寸。

## 宿主视图与按钮

### 栈的 `fixedSize`

导入 `QuickLayoutKit` 后，直接对 `HStack` 调用 `.fixedSize(axis: .vertical)`
会命中 `StackElement` 专用重载。内部复用官方 `idealLayout(true)`，先测量卡片的自然
高度，再向可伸展卡片提出最高卡片的高度建议。`VStack` 固定水平轴时对称地实现等宽。
固定尺寸子元素仍保持自身尺寸，只有接受有限尺寸建议的子元素才会伸展。

```swift
HStack(alignment: .top, spacing: 16) {
    ForEach(cards) { card in
        card.resizable(axis: .vertical)
            .frame(width: 260)
            .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}
.fixedSize(axis: .vertical)
.padding(20)
```

修饰符顺序和静态类型决定重载选择：先调用 `.padding(...)`，或先擦除为 `Element` /
`Layout`，再调用 `fixedSize`，仍使用上游通用实现，不额外协调等高。仅固定主轴或传入
空轴集合也保持原有策略；已有 `.idealLayout()` 与专用重载组合不会嵌套额外的理想栈。
这是一项栈专用兼容扩展，不表示整个布局系统与 SwiftUI 完全等价。

Demo 首页的 **FixedSize 实验室** 使用自然高度、撑满容器、内容等高三个状态展示差异。
示例参考 [SwiftDifferently 的 fixedSize 用例](https://www.swiftdifferently.com/blog/swiftui/fixedsize-usecase)。

### `QuickLayoutView`

需要使用 QuickLayoutKit 的 `safeAreaPadding`、`containerRelativeFrame` 或几何环境时，
可复用组件应继承 `QuickLayoutView` 并重写 `body`。上游 `@QuickLayout` 修饰的普通
`UIView` 只安装 QuickLayout 的布局生命周期，不会在自身每次测量／布局时建立
QuickLayoutKit 的安全区与容器上下文；即使外层是 `QuickLayoutHostingController`，
也不能依赖外层临时上下文跨越子视图独立的 `layoutSubviews` 调用。

例如，把 `@QuickLayout class ContentView: UIView` 改为
`class ContentView: QuickLayoutView`，并将 `var body: Layout` 改为
`override var body: Layout`。不要再叠加 `@QuickLayout` 宏。分栏的左右安全区可能不相等，
应在宿主中按边使用 `safeAreaPadding`；滚动页面则使用 `contentMargins`，由滚动宿主
负责视口安全区，避免对同一内容重复扣减。

现有 UIKit 控制器中只有局部区域需要 QuickLayout 时，使用 `QuickLayoutView`：

```swift
let titleLabel = UILabel()
let hostedView = QuickLayoutView {
    VStack(spacing: 8) {
        titleLabel
    }
    .padding(.all, 16)
}

let measuredSize = hostedView.sizeThatFits(
    in: CGSize(width: 320, height: .infinity)
)
```

也可以创建子类并重写 `body`。`quickLayoutHorizontalFlexibility` 和
`quickLayoutVerticalFlexibility` 默认为 `nil`，表示从 `body` 推导尺寸弹性；仅在宿主本身
需要覆盖内容尺寸契约时设置它们。

### `QuickLayoutVisualEffectView`

需要在模糊、材质或玻璃效果中承载 QuickLayout 内容时，使用
`QuickLayoutVisualEffectView`。内容会自动安装到 UIKit 要求的 `contentView`：

```swift
let titleLabel = UILabel()
let materialView = QuickLayoutVisualEffectView(
    effect: UIBlurEffect(style: .systemMaterial)
) {
    titleLabel.padding(16)
}
```

该类型接受任意 `UIVisualEffect`，不提供默认效果或样式。也可以创建子类并重写 `body`；
本地化、状态或效果变化影响布局时，调用 `setNeedsQuickLayout()`。

### `QuickLayoutButton`

`QuickLayoutButton` 是 `UIControl` 和 `HasBody` 宿主。它负责主要操作、按压/启用/选中状态、
辅助功能语义、测量和布局，但不提供默认视觉样式。

```swift
let titleLabel = UILabel()
let backgroundView = UIView()

let button = QuickLayoutButton(
    role: .destructive,
    action: deleteItem
) {
    titleLabel
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background { backgroundView }
}

button.accessibilityLabel = titleLabel.text
button.stateUpdateHandler = { [weak backgroundView] state in
    backgroundView?.alpha = state.isPressed ? 0.72 : 1
}
```

`role` 只提供语义状态，不会自动改变颜色。状态或本地化文字变化影响尺寸时，应调用
`setNeedsQuickLayout()`。

## 滚动视图

### 稳定的 UIKit 实例

控制器应持有 `QuickLayoutScrollView`，并在 `body` 中传给 `ScrollView` 函数：

```swift
private let scrollView = QuickLayoutScrollView()

override var body: Layout {
    ScrollView(scrollView, .vertical) {
        contentLayout
    }
}
```

显式实例提供稳定的 UIKit 对象标识，便于设置代理、滚动位置、键盘避让、语义方向和其他
`UIScrollView` 属性。每次重新计算 `body` 时，`ScrollView` 会使用当前构建器内容重新配置
该实例。

也可以直接构建滚动视图：

```swift
let scrollView = QuickLayoutScrollView(
    .vertical,
    showsIndicators: false
) {
    contentLayout
}
```

`QuickLayoutScrollView` 一次只支持一个滚动轴。多个根元素会按滚动轴放入零间距的隐式
`VStack` 或 `HStack`。需要具体间距和对齐方式时，应在构建器中显式提供堆栈。

### 交叉轴尺寸

垂直滚动视图使用容器宽度并让内容决定滚动高度。水平滚动视图使用容器宽度作为视口宽度，
同时根据内容的自然高度确定视口高度。这使本地化文本和动态字体能够决定轮播高度。

### 滚动到边缘

```swift
scrollView.scrollTo(.top, animated: true)
scrollView.scrollTo(.bottom, animated: true)
scrollView.scrollTo(.leading, animated: false)
scrollView.scrollTo(.trailing, animated: true)
```

边缘必须与当前滚动轴匹配。内容尚未测量时，请求会延迟到下一次成功布局。水平方向的
`.leading` 和 `.trailing` 会根据当前有效布局方向解析。

## 内容边距与安全区域

### `contentMargins`

`contentMargins` 为滚动视图视口与内容或滚动指示器之间增加距离，不需要用 `padding`
包裹整个滚动内容：

```swift
ScrollView(scrollView) {
    contentLayout
}
.contentMargins(.horizontal, 16)
.contentMargins(.bottom, 24)
```

支持三种位置：

- `.automatic`：同时应用到滚动内容和当前滚动轴的指示器。
- `.scrollContent`：仅应用到滚动内容。
- `.scrollIndicators`：仅应用到滚动指示器。

解析规则与 SwiftUI 一致：同一 placement 的多次调用按所选边缘合并，后一次调用覆盖
同一边缘；一旦为 `.scrollContent` 或 `.scrollIndicators` 提供了显式值，该位置整体使用
显式 placement，不再逐边继承 `.automatic`。例如：

```swift
ScrollView(scrollView) {
    contentLayout
}
.contentMargins(.horizontal, 16, for: .scrollContent)
.contentMargins(.bottom, 24)
```

这段代码为滚动内容设置左右 `16`，为指示器设置底部 `24`；内容不会再从
`.automatic` 继承底部 `24`。如果内容底部也需要 `24`，应再对 `.scrollContent`
显式设置 `.bottom`。

前缘和后缘会根据 `effectiveUserInterfaceLayoutDirection` 解析。滚动视图会把与其相交的
安全区域合并到有效内容边距，因此显式边距是在对应安全区域基础上继续增加的距离。
`containerRelativeFrame` 使用扣除有效边距后的可见视口进行计算。

可选长度重载中的 `nil` 表示不指定所选边缘，不会清除同一位置上更早的值。要明确清除边距，
传入 `0`。有限负值会被保留，非有限值按 `0` 处理。

### `safeAreaPadding`

`safeAreaPadding` 消耗传递到当前元素的安全区域，并可添加额外间距：

```swift
contentLayout
    .safeAreaPadding(.horizontal, 20)
    .safeAreaPadding(.bottom, 12)
```

连续调用会按修饰器顺序逐边累加；不同边缘彼此独立。同一边缘先增加 `8`、再增加 `12`，
最终会在继承安全区域之外再增加 `20`。负值与非有限值按 `0` 处理，不会把内容推出原始
安全区域。

`length` 为非可选 `CGFloat`，默认 `0`。无参数调用或只指定边缘会消耗继承的安全区域，
额外间距为零，不采用 SwiftUI 的平台默认间距。安全区域值会在每次测量和布局时重新读取，
因此旋转、系统栏、容器尺寸、键盘和 RTL 变化都使用当前环境。

### `safeAreaInset` 与 `ignoresSafeArea`

```swift
contentLayout.safeAreaInset(edge: .bottom, spacing: 8) {
    actionBar
}

backgroundView
    .resizable()
    .ignoresSafeArea(.container, edges: .all)
```

`.container` 表示宿主或滚动视口提供的安全区域；`.keyboard` 表示由
`QuickLayoutKeyboardAvoider` 发布的键盘区域。

## 核心布局能力

### HGrid 与 VGrid

`VGrid(columns:)` 按行填充，`HGrid(rows:)` 按列填充。尺寸与对齐规则参照 SwiftUI
`LazyVGrid` / `LazyHGrid`，间距参数遵循 QuickLayout 的非可选 `CGFloat = 0` 约定。
内容在构建时全部创建，每轮布局测量全部子元素。
使用现有 `ScrollView` 提供滚动，适合数量有限的卡片、工具面板和表单选项。

```swift
let columns: [GridItem] = [
    GridItem(.fixed(72), spacing: 12, alignment: .topLeading),
    GridItem(.flexible(minimum: 80, maximum: 240)),
]

VGrid(columns: columns, alignment: .leading, spacing: 16) {
    for card in cards {
        card.resizable().frame(height: 64)
    }
}

// 根据实际可用宽度自动决定列数。
VGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
    for card in cards {
        card.resizable().frame(height: 80)
    }
}

HGrid(rows: [GridItem(.fixed(56)), GridItem(.fixed(56))], spacing: 12) {
    for card in cards {
        card.resizable().frame(width: 100)
    }
}
```

- `.fixed` 保留指定尺寸；`.flexible` 在上下限内分配剩余空间，默认最小值为 10。
- `.adaptive` 在分配到的空间内展开多个等宽列或等高行，`maximum` 限制每个单元格的尺寸。
- `GridItem.spacing` 控制到下一列／行的间距；网格的 `spacing` 控制增长方向的行／列间距。
  两者均为非可选 `CGFloat`，默认 0；与 QuickLayout `Grid` 一致，负数和非有限值
  在布局时按 0 处理。末尾没有额外间距。
- `GridItem.alignment` 可以覆盖网格的默认对齐方式。布局遵循当前 LTR / RTL 方向，
  末行或末列不足时保留前面轨道的位置和尺寸。
- 网格接纳交叉轴的可用空间，固定轨道或受 `maximum` 限制的轨道按网格对齐方式放置。
  无界交叉轴建议使用理想尺寸；自适应轨道的理想尺寸为 10 点，`minimum` 用于计算
  有限空间内的重复数量。
- 空内容保留已声明轨道的交叉轴空间，增长轴长度为零；空轨道数组返回零尺寸布局。
- 与现有 `Grid / GridRow` 并存；这里的接口不包含 Section、固定标题或 `pinnedViews`。
  同时导入 SwiftUI 时，可用 `QuickLayoutKitCore.GridItem` 区分同名类型。

兼容边界（2026-11-05，iOS 27.2 模拟器与原生 SwiftUI 对照）：

- 这是 QuickLayout 的非懒加载布局函数，使用 `Element` 构建器；不是 SwiftUI `View` 的可直接替换类型。
  `GridItem.Size` 支持 `Equatable`，但 `GridItem` 尚未实现 SwiftUI 在 iOS 26 新增的
  `Equatable` 一致性。当前依赖的 QuickLayout `Alignment` 不公开其两个轴，也不支持相等比较，
  因此不能用可靠的公开 API 合成同等比较。
- 单元格的 `center` 参考线偏移按原生网格的方向叠加；内部参考线不向网格外层传播。
  稀疏 adaptive 内容显式返回默认参考线时不会额外居中；网格自身的 `alignmentGuide`
  仍可用于父栈对齐。自定义水平轨道对齐按 LTR / RTL 镜像。
  内置对齐、组合参考线、嵌套父栈以及自定义 `AlignmentID` 均有原生矩形对照。
- 本库为 `Layout` 和 `LeafElement` 提供参考线修饰器重载，每次测量先计算参考线值再传播，
  避免上游重复执行 `d[guide] + offset` 导致偏移累计；同轴的后续修饰器可读取前一个值。
  接收者若先擦除为仅有 `Element` 的类型，仍会选择上游通用重载；需要保留 `Layout`
  或 `LeafElement` 的静态类型才能使用本库实现。
- 水平参考线闭包读取逻辑坐标，向 RTL 父栈提供物理坐标时进行方向转换。
  正负偏移、绝对参考线值、连续同轴修饰、跨轴读取，以及 frame / padding 包装后的值
  均有原生对照；网格内部读取参考线时同步转换，避免 RTL 单元格偏移反向。
- 本库的 `HStack` / `VStack` 入口在单元素时增加容器适配：消费六个内置参考线，
  保留自定义参考线，并将参考线超出子元素尺寸的情况计入容器边界。
  返回类型仍为 `StackElement`，`spacing: CGFloat = 0`、`fixedSize` / `idealLayout` 接口保留。
  `import QuickLayoutKit` 会选择本库入口；只同时导入 `QuickLayout` 与 `QuickLayoutKitCore` 时，
  使用 `QuickLayoutKitCore.HStack` / `QuickLayoutKitCore.VStack`，或显式 `import func` 消除同名歧义。
  QuickLayout 源码和固定版本没有修改；直接调用 `QuickLayout.HStack` / `QuickLayout.VStack`
  或构造 `StackElement` 仍使用上游行为。
- RTL 下自定义水平参考线经容器聚合后，后续修饰器仍读取逻辑坐标。
  显式参考线标记随布局节点保留，并从最终返回的节点树读取：`ViewThatFits` 丢弃的候选项
  不污染外层参考线，缓存节点的首次与后续读取保持一致，网格消费内部参考线时也消费标记。
  单元素栈会区分显式参考线与自定义默认值，正确转换 RTL 下非中心默认值的坐标。
  单元素原生对照统一使用 `AnyView` 包装内容，对应本库的 `Element` 类型擦除；
  不将结果推广到 SwiftUI 可能消除容器的具体单元素类型优化路径。
- 混合轨道溢出时分别保留报告尺寸与放置结果：先按交叉轴建议尺寸确定报告范围，再按报告的
  交叉轴尺寸重新分配轨道。报告分组与放置分组分别使用最终测量的内容尺寸，
  adaptive 展开数量变化不覆盖报告阶段的行列分组；增长轴报告长度向上取整，
  放置保留分数尺寸，RTL 定位以报告边界镜像。内容按最终轨道只测量一次，
  支持随宽度换行或保持宽高比的内容。父容器可直接提交缓存节点，无需依赖再次测量。
  两阶段轨道分配参考 [objc.io 的原生网格分析](https://www.objc.io/blog/2020/11/23/grid-layout/)。
- 部分混合轨道的最小尺寸超出建议空间时，原生懒网格的报告尺寸与完整测量结果不同。
  例如宽度 120、轨道为 `flexible(10...100)`（spacing 9）、`flexible(80...120)`、`fixed(30)`，
  11 个内容高度依次为 `20 + index * 3`、行间距 11 时，本库报告高度 188，原生报告 182。
  同一组内容放进横向 / 纵向 ScrollView 后，原生分别报告 187 / 185，但实际内容仍延伸到 188。
  这是当前系统下观察到的容器相关报告长度差异，不能用固定偏移修正，也不能据此推广到其他系统版本。
  RTL 的水平网格仍会因这部分报告宽度差异产生定位偏差，尚未宣称完全对齐。
- 本库多元素 `VStack` 的自定义水平对齐使用私有放置参考线，分别处理显式值与默认值，
  不把默认值发布为用户的显式参考线。对齐原点计入容器边界，支持正负值与越界值，
  并保留子元素的弹性、优先级、spacing 和 `fixedSize` 测量流程。
  LTR / RTL、默认值与显式值混合，以及缓存后嵌套父栈均有原生矩形对照。
  直接构造上游 `StackElement` 或调用 `QuickLayout.VStack` 仍不经过本库适配。
- 上述估算相关差异仅在增长轴报告尺寸及受其影响的 RTL x 坐标断言中使用 `withKnownIssue`；
  交叉轴尺寸、其他坐标和单元格尺寸仍必须通过普通断言，测试运行成功不代表已知案例已对齐。
  原生对照会扩大可见区域并检查子元素已创建；全部创建仍不能保证 LazyGrid 的报告长度没有估算。
  混合轨道的缓存提交测试覆盖两个方向、LTR / RTL、三种对齐、adaptive 轨道数量变化及父栈兄弟元素。

Demo 的“布局 → HGrid 与 VGrid”页面提供方向、尺寸规则、对齐方式、LTR / RTL
和可用空间控制。网格原生对照位于 `Demo/DemoTests/DirectionalGridTests.swift`；
`AlignmentGuidePropagationTests` 覆盖候选项选择与缓存传播，`SingleChildStackGuideTests`、
`MultiChildStackGuideTests` 和 `ViewThatFitsGuideTests` 提供对应的原生 SwiftUI 矩形对照。
运行网格单元测试、原生对照和页面 UI 回归：

```sh
sh Scripts/verify-grids.sh
```

脚本通过 `Demo` scheme 的命令行筛选执行 Swift Testing 套件，再通过 `GridRegression`
scheme 执行页面 UI 测试。可用 `GRID_TEST_DESTINATION` 指定其他已安装的模拟器。

### 容器相对尺寸

`containerRelativeFrame` 根据最近的 QuickLayoutKit 容器确定尺寸。控制器根视图和最外层
宿主使用扣除安全区域后的尺寸；滚动视图使用扣除有效边距后的可见视口。普通嵌套
`QuickLayoutView`、栈、`frame` 和 `padding` 继承最近容器，不会替换参考尺寸。
嵌套滚动使用内层视口，宿主独立重排和移动到另一个容器后也会重新读取所属容器。
`count/span` 重载的 `spacing` 遵循 QuickLayout 规则，默认为 `0`。

```swift
heroView.containerRelativeFrame(.horizontal)

cardView.containerRelativeFrame(
    .horizontal,
    count: 3,
    span: 1,
    spacing: 16
)

panelView.containerRelativeFrame(.horizontal) { length, _ in
    max(0, length - 32)
}
```

没有 QuickLayoutKit 宿主时，该修饰符使用直接父元素提出的尺寸作为备用值。
需要按局部预览台或中间 `frame` 的宽度计算比例时，应使用 `GeometryReader` 读取该区域，
而不是将普通嵌套宿主当作新的 `containerRelativeFrame` 容器。

`Demo/DemoTests/ContainerRelativeFrameParityTests.swift` 用原生 SwiftUI 对照最近容器、
双向嵌套滚动、内容边距、安全区域及修饰符顺序，并在 LTR／RTL 下改变尺寸和物理安全边距。
嵌套滚动夹具明确约束非滚动轴，避免双轴相对内容参与自然视口尺寸的循环求解。

### 容器相对尺寸上限

`containerRelativeSize` 将容器相对上限传给内容测量，允许短内容自然收紧，适用于阅读区域、
卡片、媒体、侧栏和面板。构建函数与修饰符均提供基础、逐轴计算、完整尺寸计算三组能力。
固定尺寸、最小尺寸、对齐和实际内容宽高比可与 `frame`、`aspectRatio` 等 API 组合使用。

```swift
// 基础形式：所选轴使用容器上限；省略 axes 时修饰符默认选择双轴。
contentView.containerRelativeSize(.horizontal)

// 逐轴计算：阅读内容限制行宽，保留水平留白。
article.containerRelativeSize(.horizontal) { width, _ in
    min(720, width - 32)
}

// 根据容器宽度选择侧栏上限。
sidebar.containerRelativeSize(.horizontal) { width, _ in
    width < 600 ? width * 0.85 : 320
}

// 完整尺寸计算：同时读取同一个容器的宽高，只应用高度上限。
preview.containerRelativeSize(.vertical, maxSize: { container in
    CGSize(
        width: .infinity,
        height: min(container.height * 0.6, container.width * 9 / 16)
    )
})
```

大写 `ContainerRelativeSize` 声明共享参照容器，以自身收到的父布局建议尺寸为基准，
仅为标记了 `.containerRelativeSize` 的子元素提供上限。

声明保留内容在各轴上的尺寸弹性，使内容正常参与栈的空间分配和布局优先级处理。
最终尺寸由父布局分配、上限与内容测量共同决定。栈可能先预测量，再用新的建议尺寸
重新测量；每次均重新计算上限，不缓存前一次测量结果。

```swift
// 基础声明：使用完整容器长度。
ContainerRelativeSize(.horizontal) {
    title.containerRelativeSize(.horizontal)
}

// 逐轴声明：多个元素共享相同上限。
ContainerRelativeSize(.horizontal, length: { width, _ in
    min(560, width * 0.9)
}) {
    VStack {
        title.containerRelativeSize(.horizontal)
        detail.containerRelativeSize(.horizontal)
    }
}

// 完整尺寸声明：统一计算两个轴的上限。
ContainerRelativeSize([.horizontal, .vertical], maxSize: { container in
    CGSize(width: min(560, container.width - 32), height: container.height * 0.8)
}) {
    panel.containerRelativeSize()
}
```

修饰符优先参照最近有效的显式容器，其次使用最近 QuickLayoutKit 宿主的容器尺寸，
最后回退到直接父布局建议尺寸。该上限 API 保留最近宿主的局部尺寸语义，并遵循
安全区域规则；滚动宿主使用有效可见视口，不使用滚动内容长度。

基础修饰符使用显式容器提供的上限；没有显式声明时，以参照容器长度作为上限。
自定义修饰符基于容器原始尺寸计算，结果同时受到显式上限和父布局可用空间的约束。
嵌套声明建立新的完整参照容器，只覆盖所选轴的上限，其他轴继承外层上限，退出后恢复。
空轴集合完全透明，不调用闭包，也不改变后代查找参照容器的结果。

`length` 接收 `(CGFloat, Axis)`，每次测量对每个所选轴调用一次；`maxSize` 接收 `CGSize`，
每次测量调用一次，返回值只应用选中的轴。容器改变尺寸后重新计算，内容只在构建时生成一次。
闭包应无副作用。无界输入也会传入闭包，允许返回有限回退；结果逐轴将负数及负无穷归零，
NaN 和正无穷表示无界。

比例、封顶和等分都由闭包表达，不提供专用重载。例如 `min(420, width * 0.75)` 表示比例封顶，
`(width - 10 * 3) / 4 * 2 + 10` 表示四等分中两份的上限。这里的间距仅参与计算，
实际元素间距由栈等布局负责。`max(140, width * 0.75)` 设置的是计算所得上限的下界，
不会强制短内容达到 140。

上限通过测量建议传递，不创建固定占位框架或裁剪内容；显式固定尺寸及拒绝收缩的子元素
仍遵循自身布局规则。修饰符顺序决定上限是否包含 padding 等附加空间。

### 弹性框架、宽高比与自适应布局

```swift
cardView.frame(
    minWidth: 240,
    idealWidth: 320,
    maxWidth: 480,
    minHeight: 160,
    alignment: .topLeading
)

videoView.aspectRatio(16.0 / 9.0, contentMode: .fit)
imageView.scaledToFill()

ViewThatFits(in: .horizontal) {
    horizontalLayout
    verticalLayout
}
```

父元素给出的有限尺寸建议优先于理想尺寸，之后再应用最小值和最大值。`ViewThatFits`
按声明顺序选择在指定轴上能够容纳的第一个理想布局，最后一个布局作为备用项。

### 几何变化

`onGeometryChange` 先把已应用的几何信息转换为 `Equatable` 值，仅在结果变化时执行操作：

```swift
cardView.onGeometryChange(for: CGFloat.self) { geometry in
    geometry.size.width
} action: { [weak cardView] width in
    cardView?.layer.cornerRadius = min(24, width * 0.08)
}
```

首次应用几何信息时会调用一次。仅执行 `sizeThatFits` 测量不会触发操作。

### 自定义布局算法

自定义值类型可以遵循 `LayoutAlgorithm`，在测量阶段返回容器尺寸，再在放置阶段设置每个
`LayoutSubview` 的位置和尺寸建议。使用 `LayoutValueKey` 和
`layoutValue(key:value:)` 可以为直接子元素附加元数据。

`position(_:)` 用于设置元素中心位置，`zIndex(_:)` 用于控制重叠顺序。QuickLayoutKit 宿主
会在移除 `zIndex` 或转移宿主时恢复视图原有的 `layer.zPosition`。

## 环境、动态字体与布局方向

`QuickLayoutEnvironment` 包含有效布局方向、动态字体内容尺寸类别、尺寸类别、界面样式、
显示比例、安全区域边距、布局边距和宿主容器尺寸。遵循
`QuickLayoutEnvironmentUpdating` 的宿主会在环境变化时收到
`quickLayoutEnvironmentDidChange(_:reason:)`。

独立的 `QuickLayoutView`、`QuickLayoutButton` 和 `QuickLayoutScrollView` 默认使用
`.preserve`，避免覆盖播放、空间等局部固定语义。普通应用内容可能被移除并重新附加时，
应显式跟随外层容器：

```swift
hostingView.quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
scrollView.quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
button.quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
```

应用在运行时切换语言时，还应在 UIKit 拥有行为的边界设置 `semanticContentAttribute`，例如
滚动视图、导航栏、集合视图和系统控件。QuickLayout 管理的前缘/后缘布局则使用
`.layoutDirection(...)`，文本视图通常保持 `.natural` 对齐。

## 列表与内容配置

框架提供 `QuickLayoutCollectionViewCell`、`QuickLayoutTableViewCell`、
`QuickLayoutTableViewHeaderFooterView` 和 `QuickLayoutCollectionReusableView`。它们支持
QuickLayout `body`、自适应尺寸、环境更新和从外层列表恢复布局方向。

`QuickLayoutCollectionViewCell` 和 `QuickLayoutCollectionReusableView` 使用相同的
`quickLayoutHorizontalFlexibility`、`quickLayoutVerticalFlexibility` 测量配置，默认均为
`.fullyFlexible`。对于宽度由列表决定、高度随内容变化的单元格或分组标题，将水平弹性设为
`.fixedSize`，垂直弹性保留 `.fullyFlexible`，即可由基类完成自适应测量，无需重写
`preferredLayoutAttributesFitting(_:)`。

集合单元格通过 UIKit 默认的拟合流程调用 `sizeThatFits(_:)`；补充视图在布局属性副本上
使用同一个测量入口更新尺寸。需要调整测量结果时，可重写 `sizeThatFits(_:)` 并调用
`super`，框架不会再用一次额外的 `body` 测量覆盖该结果。

```swift
final class MessageCell: QuickLayoutCollectionViewCell {
    private let titleLabel = UILabel()

    override var body: Layout {
        titleLabel
            .padding(.all, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func configure(title: String) {
        titleLabel.text = title
        setNeedsQuickLayout()
    }
}
```

自定义 `UIContentConfiguration` 使用 `QuickLayoutContentView`。子类在初始化末尾调用一次
`applyCurrentContentConfiguration()`，并重写 `applyContentConfiguration(_:)` 验证具体配置
类型、更新内容，最后调用 `super`。

`QuickLayoutContentView` 默认由容器提供宽度、内容决定高度。基类将 UIKit 的
`intrinsicContentSize` 测量转发到公开的 `sizeThatFits(_:)`，并在宽度变化或调用
`setNeedsQuickLayout()` 时使固有尺寸失效，因此子类无需重复实现这些适配。尚未获得
有效宽度时先按不受限宽度测量。其他策略可通过继承的双轴弹性属性配置：纵向自适应使用
水平 `.fixedSize`、垂直 `.fullyFlexible`，横向则相反。固定轴不提供固有尺寸，弹性轴通过
公开测量提供结果；双轴固定时不进行固有尺寸测量。只有约束轴变化才触发尺寸失效，
不向上查找 cell，也不从 `body` 的布局弹性推断 UIKit 的尺寸策略。

Demo 主菜单的「内容配置瀑布流」使用原生 `UICollectionViewListCell` 承载图文卡片。
切换纵向／横向滚动、点击展开正文、切换语言或系统字号，可以验证自适应尺寸及复用。
页面根据容器自动计算行列数并显示当前数量：纵向最小列宽约 160pt、横向最小行高约 200pt，
最小尺寸随 Dynamic Type 缩放。方向控件保留在顶部，背景及内容 inset 避免滚动内容遮挡控件。
页面将 40 条内容分成四个带标题和圆角背景的 section，每组 10 条。
`UICollectionViewWaterfallLayout` 位于框架的 `QuickLayoutKitUIKit` 模块，`import QuickLayoutKit` 即可使用。
该类型支持继承，UIKit 布局查询和失效覆写点为 `open`。
其构造方式参考 `UICollectionViewCompositionalLayout`：
`init(section:configuration:)` 对所有分组使用同一配置，
`init(sectionProvider:configuration:)` 按 section 返回配置。provider 接收原生
`NSCollectionLayoutEnvironment`，通过 `container.effectiveContentSize` 和 `traitCollection`
设置经 UIFontMetrics 缩放的 `.adaptive(minimum:)`；列数由布局统一解析。全局 `Configuration` 包含 `scrollDirection`、`interSectionSpacing` 和 `contentInsetsReference`。

`Section` 包含 `lanes`、`contentInsets`、`interItemSpacing`、`interLaneSpacing`、
`itemLengthDimension`、`boundarySupplementaryItems` 和 `decorationItems`。
`lanes` 支持混合 `.fixed`、`.flexible`、`.adaptive`，默认两条 `.flexible()`；通过 `resolvedLaneCount(in:)` 查询实际列／行数。
`LaneSize` 遵循 `Sendable`，UIKit 布局、Section 和 provider 保持主 actor 隔离。长度在纵向表示高度、横向表示宽度。
`itemLengthDimension` 使用原生 `NSCollectionLayoutDimension`：`.absolute(50)` 固定长度，
`.estimated(240)` 启用自适应，也支持容器宽高比例；`itemLengthDimensionProvider` 可按条目覆盖。
provider 返回完整配置，返回 nil 时使用 `Section()` 默认值。没有无参初始化或布局级 section 指标。
页面使用 12pt 间距和边距、240pt 估算长度。
布局日志使用系统 `Logger`（`QuickLayoutKit` / `WaterfallLayout`）；DEBUG 下开启 `QuickLayoutDiagnostics.isEnabled` 可查看常规失效日志，非法配置保留警告。
实现、迁移和 1,000／10,000 条性能记录见 [瀑布流布局说明](Docs/WaterfallLayout.md)。

```swift
let background = NSCollectionLayoutDecorationItem.background(elementKind: "section.background")
var section = UICollectionViewWaterfallLayout.Section()
section.lanes = [.adaptive(minimum: 160)]
section.itemLengthDimension = .estimated(240)
section.decorationItems = [background]
let layout = UICollectionViewWaterfallLayout(
    section: section,
    configuration: .init(scrollDirection: .vertical, interSectionSpacing: 12)
)
layout.register(MyBackgroundView.self, forDecorationViewOfKind: "section.background")
```

布局通过 `sizingForItem(at:)` 统一生成 `ItemSizing`：确定的交叉轴约束、无限的自适应
主轴约束以及双轴 `Flexibility`。CellRegistration 将其写入内容配置，卡片设置继承的弹性
属性并在 `body` 固定相应宽度或高度。布局属性仍使用有限估算长度，实际主轴长度由 UIKit
拟合回调返回；页面与布局不提前测量内容。横向卡片使用最多 96pt 高的封面，
文本通过 `ViewThatFits(in: .vertical)` 在不同栏宽中选择能容纳完整内容的布局。

布局支持多 section、边界补充视图固定效果、原生 `UIContentInsetsReference` 和 RTL。
`boundarySupplementaryItems` 使用原生 `NSCollectionLayoutBoundarySupplementaryItem`，
支持主轴两端各一个元素及自定义 kind：纵向 top/bottom、横向 leading/trailing，交叉轴铺满，
主轴使用 absolute 长度；通过 `pinToVisibleBounds` 固定。当前不支持补充视图 estimated、
非零 offset/contentInsets 或 extendsBoundary=false，遇到这些描述会忽略并输出 DEBUG 诊断。
`.automatic` 的 section 边距参考继承全局配置；全局默认 `.none`，仍尊重 adjustedContentInset。
section 与背景使用 `NSDirectionalEdgeInsets`，leading / trailing 随布局方向解析。
`decorationItems` 直接使用 UIKit 描述类型，支持 elementKind、contentInsets 和 zIndex；
背景覆盖 section 自然范围，不随固定 header/footer 移动，不参与内容测量。
配置及装饰描述在解析时复制，外部数据变化后调用 `invalidateSectionConfigurations(reason:)` 重新解析，
仅装饰变化会保留有效测量。整体测量环境可通过 `invalidateMeasurements(reason:)` 强制失效。
`itemMetadataProvider` 提供稳定 ID 和内容版本，与 collection view delegate 解耦。缓存按稳定 ID、内容版本、
约束、尺寸模式、方向和环境区分；内容配置按条目 ID 比较策略并重新配置受影响项。
Debug 控制台筛选 `[ContentWaterfall]` 可查看条目 ID、方向、交叉轴长度、估算与拟合长度、
失效原因；日志不额外测量。

`quickLayoutDirectionViews` 只应包含需要跟随外层列表的公开视图。不要遍历 UIKit 私有子视图；
具有固定播放或空间语义的子视图也不应加入该数组。

## 子视图控制器

使用 `QuickLayoutViewControllerRepresentable` 将已经创建的子视图控制器放入 QuickLayout
`body`：

```swift
final class ParentViewController: QuickLayoutHostingController {
    private let child = ChildViewController()
    private lazy var childView =
        QuickLayoutViewControllerRepresentable(child, parent: self)

    override var body: Layout {
        childView
            .resizable()
            .frame(maxWidth: .infinity)
    }
}
```

未明确传入父控制器时，representable 视图会进入层级后从 UIKit 响应者链解析父控制器。
需要延迟创建子控制器时，使用 QuickLayout 的 `LazyView`。子控制器的
`preferredContentSize` 变化后，调用 `invalidateChildLayout()` 触发重新测量。

## 键盘处理

`QuickLayoutKeyboardObserver` 观察 UIKit 键盘通知并发布 `QuickLayoutKeyboardContext`。
键盘通知中的框架是屏幕坐标；调用 `resolved(in:)` 后才会得到相对于具体视图或滚动视图的
实际相交高度，从而正确处理浮动键盘、分离键盘、iPad 多窗口和外接键盘切换。

普通 `QuickLayoutView` 和 `QuickLayoutHostingController` 可以选择自动把底部停靠键盘
发布为 `.keyboard` 安全区域：

```swift
quickLayoutKeyboardSafeAreaBehavior = .followsDockedKeyboard(
    usesBottomSafeArea: true
)
```

`usesBottomSafeArea` 为 `true` 时，键盘隐藏、浮动、分离或未与宿主相交时，键盘区域
使用宿主的底部安全区域；为 `false` 时使用宿主底边。停靠键盘显示时，两种配置都会
发布键盘与宿主的完整相交高度。该能力不添加额外视觉间距，需要时应在布局中显式使用
`padding`。

宿主仍使用 `QuickLayoutKeyboardContext` 提供键盘高度与动画参数；内部只借助系统
`UIKeyboardLayoutGuide` 判断键盘是否确实停靠在当前窗口，从而区分贴底的分离键盘，
并避免其他窗口的键盘通知污染当前宿主。该 Layout Guide 不承载 QuickLayout 页面布局。

iOS 17 起，可以设置 `quickLayoutKeyboardDismissPadding`，扩大键盘上方可提前开始滚动
收起手势的区域。该属性直接转发 `UIKeyboardLayoutGuide.keyboardDismissPadding`，不改变
`.keyboard` 安全区域，也不添加布局间距；滚动视图仍需按需要设置
`keyboardDismissMode`，例如 `.interactive`：

```swift
scrollView.keyboardDismissMode = .interactive
quickLayoutKeyboardDismissPadding = inputBar.bounds.height
```

布局可以分别选择容器与键盘区域。例如，下列底部内容只采用键盘区域，不重复采用容器
底部安全区域：

```swift
actionBar
    .safeAreaPadding(.bottom, 0)
    .ignoresSafeArea(.container, edges: .bottom)
```

`QuickLayoutKeyboardAvoider` 把键盘相交高度应用到滚动视图边距，并保持当前输入视图可见：

```swift
let avoider = QuickLayoutKeyboardAvoider(scrollView: scrollView)
avoider.safeAreaStrategy = .ignore
avoider.extraBottomPadding = 12
avoider.setActiveView(textField)
```

可用安全区域策略：

- `.ignore`：只使用解析后的键盘相交高度。
- `.add`：在键盘高度上增加滚动视图底部安全区域。
- `.subtractExisting`：从键盘高度中减去现有底部安全区域。

如果外部代码修改了滚动视图基础边距，应调用 `captureCurrentInsetsAsBase()`，再让避让器继续
叠加键盘值。

宿主需要持有避让器。`QuickLayoutScrollView` 在每次布局后自动检查当前容器几何，即使
窗口缩放没有产生新键盘通知，也会重新计算遮挡与安全区域。普通 `UIScrollView` 的宿主应在
`viewDidLayoutSubviews()` 或 `layoutSubviews()` 中调用 `avoider.refreshGeometry()`。
单纯滚动且避让量未改变时不会重新定位输入框。

## 诊断

```swift
QuickLayoutDiagnostics.isEnabled = true
QuickLayoutDiagnostics.reset()

let snapshot = QuickLayoutDiagnostics.snapshot()
print(snapshot.totalLayoutPasses)
```

诊断默认关闭，只应在调试或测试时启用。

## Demo 与测试

本地开发统一打开仓库根目录的 `QuickLayoutKit.xcworkspace`，在同一工作空间中管理
QuickLayoutKit Swift Package 和 Demo 工程：

```sh
open QuickLayoutKit.xcworkspace
```

选择 `Demo` scheme 运行示例应用；选择 `QuickLayoutKit` scheme 构建库或运行库测试。
工作空间同时提供 `ChatRegression`、`MediaBenchmark`、`RoomPK` 和
`VoiceRoomGiftEffects` 共享 scheme，用于对应功能的回归与性能验证。
Demo 通过本地路径依赖根目录的软件包，修改库源码会直接参与 Demo 构建。
工作空间的依赖版本记录在 `QuickLayoutKit.xcworkspace/xcshareddata/swiftpm/Package.resolved`；
根目录的 `Package.resolved` 用于独立使用 Swift Package 的场景。

Demo 应用支持 iOS 15.0 及以上版本。`Chat` 功能使用 iOS 26 API，仅在 iOS 26
及以上显示入口；其他演示页面保留 iOS 15 兼容路径。Xcode 预览要求 iOS 17，聊天预览要求
iOS 26。Demo 单元测试和 UI 测试目标同样支持 iOS 15；聊天相关用例在 iOS 26 以下明确跳过，
普通布局、菜单和本地化测试继续运行。

Demo 展示全屏集合视图根布局、背景与垂直滚动页面、外层垂直滚动与内层横向轮播、横屏和
安全区域、动态字体、等高卡片、列表自适应尺寸、运行时 LTR/RTL 切换、键盘避让和子控制器
包含关系。`SafeAreaPaddingViewController` 提供 10 种 `safeAreaPadding` 组合，并显示实时
安全区域与页面 frame；`ContentMarginsViewController` 分别验证内容和滚动指示器的
placement、覆盖顺序及 QuickLayout `nil` 契约。

运行 Swift Package 测试：

```sh
swift test
```

验证 Demo 构建：

```sh
Scripts/verify-demo-build.sh
```

Demo 的单元测试和界面测试通过工作空间中的共享 `Demo` scheme 运行，例如：

```sh
xcodebuild -workspace QuickLayoutKit.xcworkspace -scheme Demo \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

模拟器名称请按本机已安装的设备调整。编译、
单元测试、界面测试、模拟器运行和真机验证属于不同验证层级，应分别记录结果。

## 二维几何查询与 iPhone Duo

### GeometryReader

`GeometryReader` 根据自身的实际几何构建内容，支持条件、循环和多个直接子元素：

```swift
GeometryReader { proxy in
    card.resizable()
        .frame(width: proxy.size.width * 0.5, height: proxy.size.height * 0.6)
}
.frame(height: 240)
```

它接受父布局的有限尺寸建议，未指定的轴使用 **10 点**理想长度；子内容不会撑大
Reader。多个直接子元素分别按顶部前缘叠放，RTL 时前缘位于右侧；默认不裁剪溢出。
放在垂直滚动内容中时，通常需要 `.frame(height:)`；只包一层 Reader 不会自动获得
整个滚动视口的高度。`.fixedSize()` 则使用 10 × 10 的理想尺寸。

闭包在主线程测量阶段执行，每次 Reader 测量生成完整内容节点树；不会在应用阶段再次
测量内容，业务视图直接挂在外层宿主。父布局（如 Grid）仍可能用不同建议多次测量。
`size` 和局部矩形立即对应本轮建议；安全区域、其他坐标空间及 Anchor 查询使用最近一次
已应用的快照，首次测量时按缺失信息回退。实际几何变化会使宿主在后续布局周期更新。
内容闭包应只返回布局声明，不执行挂载视图或修改业务状态等副作用。
Reader 使用现有不可变 `GeometryProxy` 快照，不提供 SwiftUI 的属性图或 `@State` 协调；
业务 UIView 应保存在控制器或宿主属性中，避免每次构建都创建新视图。需要捕获拥有该
Reader 的对象时使用弱引用，避免闭包循环持有。只需观察既有元素时使用 `.onGeometryChange`。

同时导入 SwiftUI 时，使用 `QuickLayoutKit.GeometryReader` 或
`QuickLayoutKitUIKit.GeometryReader` 区分同名类型。Demo 的 Geometry 页面包含
GeometryReader 场景，可调宽度并切换 LTR/RTL；另有“自适应网格”场景，用 Reader 的
可用宽度把 6 张卡片排成 1～4 列。卡片目标最小宽度为 104 点、间距为 12 点，
可通过宽度和内边距滑杆观察换列，末行保留空列，RTL 从右侧开始排列。

### 几何快照与变化观察

`GeometryProxy` 是布局应用后的不可变 `Sendable` 快照。`transform` 不访问实时 UIKit 状态，
可把几何数据转换为业务需要的 `Equatable & Sendable` 值；不要把不断变化的完整快照用于
不需要逐帧更新的业务。尺寸测量不会发送通知，首次应用会回调一次，后续只在转换结果变化时回调。

```swift
card.resizable()
    .onGeometryChange(for: CGRect.self) { proxy in
        proxy.frame(in: .named("content"))
    } action: { oldFrame, newFrame in
        // 首次调用 oldFrame == newFrame。
    }
    .coordinateSpace(.named("content"))
```

坐标空间支持 `.local`、`.global`、`.named(...)`、`.scrollView` 和 `.scrollView(axis:)`。
名称需要满足 `Hashable & Sendable`；最近的同名祖先作用域生效，纯布局元素也可以声明空间。
`frame(in:)` 将元素边界转换到目标坐标空间；`bounds(of:)` 则把目标空间边界转换回元素的局部空间。
找不到空间时，前者使用全局空间，后者返回 `nil`。全局空间以当前 UIKit 窗口为参考，窗口之间不互相解析。
QuickLayout 滚动容器使用声明的滚动轴，普通 `UIScrollView` 使用可滚动范围及对应 bounce 设置识别轴。
几何坐标使用 UIKit 的二维方向：x 向右、y 向下；当前元素的 `.local` 原点归零。
坐标查询不会因为 RTL 自动镜像。Anchor 的固定点/矩形使用来源坐标，单位点的 leading/trailing
遵循来源方向：UIView 使用有效 UIKit 方向，纯布局绑定使用 QuickLayout 方向。

原生 Anchor 不依赖 SwiftUI 的 Preference 系统。UIView 可以调用 `geometryAnchor(.bounds)`；
纯布局先保存一个稳定的 `Anchor<CGRect>(.bounds)`，再以 `.geometryAnchor(anchor)` 绑定元素。
在 `transform` 中使用 `proxy[anchor]` 或 `proxy.resolve(anchor)` 查询。下标要求来源仍在当前有效视图树中；
来源可能已卸载或迁移到其他窗口时使用 `resolve(_:)`，它会返回 `nil`。支持矩形、点、单位点和数组/可选 Source。
不要在每次 body 重建时创建新的 Anchor；旧快照冻结当时的坐标，不会随来源视图移动而变化。

```swift
let marker = Anchor<CGRect>(.bounds) // 由宿主持有
// body:
content.geometryAnchor(marker)
// onGeometryChange 的 transform 中：
let markerFrame = proxy.resolve(marker)
```

容器信息通过 `.geometryContainer(GeometryContainerValues(...))` 显式提供，该修饰符不修改绘制和布局。
每个字段分别使用最近的非 nil 祖先配置。`contentMargins` 未配置时，查询最近 UIKit 宿主的 `layoutMarginsGuide`；
这与滚动容器 `.contentMargins(..., for: .scrollContent)` 的配置入口不同，后者的既有行为保持不变。

| 查询 | 最低系统 | 原生数据来源 |
|---|---|---|
| `size`、`safeAreaInsets`、坐标空间、Anchor | iOS 15 | 已应用布局及 UIKit 视图树 |
| `containerCornerInsets` | iOS 26 | 显式声明的四角区域与当前元素的重叠；未提供时为零 |
| `concentricCornerRadii`、`concentricCornerRadii(in:)` | iOS 27 | 显式圆角或 UIKit 可确认的有效圆角；缺少来源时为 nil |
| `contentMargins(for: .container, edges:)` | iOS 27.1 | 声明的容器内容范围或宿主布局边距；未选择的边缘为零 |
| `reservedRegions(kind:options:layoutDirectionBehavior:)` | iOS 27.1 | UIKit 真实系统保留区域 |

圆角查询不读取私有屏幕参数，也不根据安全区推算设备圆角。原生同心圆角使用相邻边中较大的内缩距离，
结果限制在查询矩形短边的一半；它不实现 SwiftUI 任意 `Shape` 的几何推导。
容器圆角元数据以查询坐标中的点值使用，适合轴对齐容器；跨缩放或旋转容器时不保证系统形状的同心性。
UIKit 的有效圆角无法完整表达 SwiftUI 的窗口控件等系统角内缩，调用方需要时应显式提供元数据。
这些边界意味着调用形式和可用的二维几何语义对齐，并不保证所有 SwiftUI 系统容器返回完全相同的数值。

```swift
if #available(iOS 27.1, *) {
    canvas.onGeometryChange(for: [ReservedRegion].self) { proxy in
        proxy.reservedRegions(
            kind: .division,
            options: .includeInactive,
            layoutDirectionBehavior: .fixed
        )
    } action: { regions in
        // 根据 isActive 决定是否避让；frame 已包含 margins，不要再次 inset。
    }
}
```

`.occlusion` 表示遮挡，`.division` 表示分隔；默认只返回活动区域，`.includeInactive` 可以查询非活动区域。
区域 ID 映射系统的稳定值标识，不使用位置或数组下标。镜像默认在 RTL 下执行；`.fixed` 保留 UIKit 物理坐标，
`.mirrors(in:)` 指定执行镜像的布局方向。按物理坐标在 UIKit 上绘制区域时应使用 `.fixed`。

观察器会响应布局、安全区、方向、边距、窗口迁移、滚动及 Duo 区域变化。每个活动窗口共享一个显示链接，
用来发现祖先移动等未触发子视图布局的变化；几何不变时不会再次执行 transform，结果相等时不会执行 action。
进入后台或移除最后一个观察者后停止显示链接。action 造成的重入会合并到后续更新。

Demo 的“几何观察”入口提供坐标空间、Anchor、容器和 Duo 四组实验，支持调整内容宽度、边距、RTL 和查询选项。
容器场景使用显式数据；Duo 场景只展示真实系统结果，空列表表示当前画布没有相交的保留区域，不能据此推断设备没有该区域。
同时导入 SwiftUI 时，可使用 `QuickLayoutKitCore.GeometryProxy`、`QuickLayoutKitCore.Anchor` 等模块限定名消除同名类型歧义。
自动化结果、已知基线失败及设备姿态验证边界见 [二维几何验证记录](Docs/GeometryValidation.md)。

## 许可证

详见 [LICENSE](LICENSE)。
