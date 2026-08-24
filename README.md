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

| API 或取值 | 当前契约 |
| --- | --- |
| `VStack`、`HStack`、网格和 `Spacer` | 保持 QuickLayout 的测量、间距和弹性语义 |
| 普通可选数值 | `nil` 通常表示不增加额外数值，并按 `0` 处理 |
| `safeAreaPadding(..., nil)` | 消耗继承的安全区域，但不添加额外间距 |
| `safeAreaInset(..., spacing: nil)` | 为插入内容和安全区域预留空间，额外间距为 `0` |
| `contentMargins(..., nil)` | 表示不指定所选边缘，不覆盖同一位置的既有边距 |
| `ProposedSize` 中的 `nil` | 表示该轴未指定，不表示数值零 |
| 弹性 `frame` 中的理想尺寸 | 仅在父元素没有给出有限建议尺寸时作为备用值 |
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

### `QuickLayoutView`

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

无参数调用或传入 `nil` 会消耗继承的安全区域，但额外间距为零。安全区域值会在每次测量和
布局时重新读取，因此旋转、系统栏、容器尺寸、键盘和 RTL 变化都使用当前环境。

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

### 容器相对尺寸

`containerRelativeFrame` 根据最近的 QuickLayoutKit 容器确定尺寸。普通宿主使用扣除
安全区域后的建议尺寸；滚动视图使用扣除调整后内容边距的可见视口。

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

## 诊断

```swift
QuickLayoutDiagnostics.isEnabled = true
QuickLayoutDiagnostics.reset()

let snapshot = QuickLayoutDiagnostics.snapshot()
print(snapshot.totalLayoutPasses)
```

诊断默认关闭，只应在调试或测试时启用。

## Demo 与测试

Demo 展示全屏集合视图根布局、背景与垂直滚动页面、外层垂直滚动与内层横向轮播、横屏和
安全区域、动态字体、等高卡片、列表自适应尺寸、运行时 LTR/RTL 切换、键盘避让和子控制器
包含关系。

运行 Swift Package 测试：

```sh
swift test
```

验证 Demo 构建：

```sh
Scripts/verify-demo-build.sh
```

Demo 的单元测试和界面测试通过 `Demo/Demo.xcodeproj` 中的共享 `Demo` scheme 运行。编译、
单元测试、界面测试、模拟器运行和真机验证属于不同验证层级，应分别记录结果。

## 许可证

详见 [LICENSE](LICENSE)。
