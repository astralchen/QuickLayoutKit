# ArrangementView

`QuickLayoutKit.ArrangementView` 用两个 QuickLayout 内容闭包构建 UIKit 页面。所有支持的系统版本都由 QuickLayout 自行测量、排版并更新 UIKit 内容。示例页和测试使用 SwiftUI 的原生实现作对照。语音房采用 `.split`，输入栏跟随公屏的实际水平范围。

## 在示例应用中体验

打开「示例 → 基础布局 → ArrangementView 排列」。在场景菜单中选择用法，预览下方会给出相应的代码。iOS 27.1 及以上可以切换 QuickLayoutKit 和 SwiftUI，两种实现使用相同的主、辅内容和预览尺寸。较早系统直接显示 QuickLayoutKit 预览。选择「在完整窗口中预览」会打开独立页面，沿用当前场景和实现，将整个窗口内容区交给排列组件。可旋转设备或改变 Duo 姿态，观察窗口、安全区和系统分隔区的作用。

- **自动排列与轴限制**。拖动高度滑块或调整窗口大小，观察每块内容上显示的实际分割轴。选择「仅允许水平分割」或「仅允许垂直分割」，可观察当前环境无法沿指定轴排列时的结果。无活动分隔区时，辅助内容收起，主内容仍显示环境选中的轴。
- **分割尺寸**。在「首选比例」中让主内容请求 65% 的空间，再换成「分轴比例范围」「点数尺寸范围」或「内容理想尺寸」，观察同一容器中分界线的位置。
- **浮层与分隔边缘**。靛蓝实线标出主内容，橙色虚线标出辅助内容。两层重叠时，辅助层绘制橙色斜纹，主层绘制半透明靛蓝色块。色块露出部分底纹，同一条斜纹在色块内外连续可见；两张读数卡分居对角。色块仅用于说明遮盖关系，不改变两层的实际尺寸。宽高取各区域的实际 bounds。只有系统活动分隔区贯穿预览时，才能看到 `.overlayArrangementEdge` 指定的尾侧或底部位置。
- **自定义样式**。`FloatingStyle` 通过 `ArrangementView(configuration)` 转发主、辅内容，使用 `.overlay.axes([])` 保持叠放。

## 在不同设备姿势下观察同一页面

在「自动排列」中打开全窗口预览，保持同一个示例，依次合拢、半展开、展平并旋转设备。页面顶部显示容器的水平、垂直 size class。每个子区域显示自己的实际尺寸、分割轴、层级和可容纳的尺寸类别文字。实验页的滑块控制局部预览高度，窗口变化时按新安全区的可用高度重新计算；全窗口页则始终把实际内容区域交给当前实现。

Duo 外屏通常是紧凑宽度，内屏可提供常规宽度。两者都要结合本地容器的可用高度和安全区来判断排列方向。在半展开的内屏上，若系统活动分隔区贯穿容器，分界线跟随分隔区；把设备展平后，再观察可用区域如何重新分配。窗口缩放、分屏和旋转复用同一套规则。[Apple 的 iPhone Duo 设计指南](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)

iOS 27.2 的 Duo 模拟器在同一全窗口「自动排列」页面得到以下结果。表中尺寸是窗口点数，实际排列会扣除安全区。尺寸类别按水平、垂直顺序列出。

| 活动显示屏与姿势 | 窗口 | 容器尺寸类别 | 主、辅内容 |
| --- | --- | --- | --- |
| 合拢，外屏纵向 | 466 × 678 | compact / regular | 上下排列 |
| 合拢或部分张开仍使用外屏，横向 | 678 × 466 | compact / compact | 只显示主内容，报告水平轴 |
| 展平，内屏纵向 | 669 × 951 | regular / regular | 上下排列 |
| 展平，内屏横向 | 951 × 669 | regular / regular | 左右排列 |
| 半展开，内屏有横向分隔带 | 669 × 951 | regular / regular | 两块内容在分隔带上下 |
| 半展开，内屏有纵向分隔带 | 951 × 669 | regular / regular | 两块内容在分隔带左右 |

在这次实测中，8 次姿态采样均对照了自动排列、水平受限、垂直受限和浮层四种配置。两种实现的主辅区域出现状态相同，位置、宽度和高度差均在 1 点以内，分割轴、浮层层级和子区域尺寸类别一致。最后一次采样返回初始的展平姿势。

## 公开接口对照

| SwiftUI API | QuickLayoutKit |
| --- | --- |
| `ArrangementView { … } secondary: { … }` | 相同的闭包标签，使用 QuickLayout 的 `@LayoutBuilder` |
| `ArrangementView(configuration)` | 支持在自定义样式内重新使用主、辅内容 |
| `ArrangementViewStyle`、`makeBody(configuration:)` | 支持自定义样式，返回遵循 QuickLayout `Layout` 的布局 |
| `ArrangementViewStyleConfiguration.Primary` / `.Secondary` | 两个具名布局类型，可通过 `configuration.primary` / `.secondary` 获取 |
| `.arrangementViewStyle(_:)` | 可用于组件或祖先布局，较近的样式优先 |
| `.automatic`、`.split.axes(_:)`、`.overlay.axes(_:)` | 支持；轴参数使用 QuickLayout 的 `AxisSet` |
| `.splitArrangementLayoutRatio(_:)` 和六参数比例范围重载 | 支持单一比例以及各轴的最小、理想和最大比例 |
| `.splitArrangementLayoutSize(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:)` | 支持绝对尺寸，单位为点 |
| `.splitArrangementFixedLayoutSize(horizontal:vertical:)` | 支持按轴表达固有尺寸偏好，两个参数默认均为 `true` |
| `.overlayArrangementEdge(_:)` | 支持水平、垂直可选边缘，影响分隔后的排列 |
| `@Environment(\.splitArrangementAxis)` / `@Environment(\.overlayArrangementZIndex)` | UIKit 后代通过 `view.splitArrangementAxis` / `view.overlayArrangementZIndex` 读取最近宿主的值；自定义布局在测量期间可读 `ArrangementLayoutContext` 的同名属性 |

SwiftUI 的类型保留 `Primary`、`Secondary` 泛型参数。QuickLayout 的构建器返回类型擦除的 `Layout`，这里公开的 `ArrangementView` 使用同一调用语法，并保留两个 UIKit 内容实例。UIKit 组件在主线程构建和排列。尺寸、比例和边缘修饰符应写在对应内容块的最外层，使排列组件能读取它们。QuickLayout 的测量上下文按作用域读取；SwiftUI 的 `@Environment` 属性包装器仍属于 SwiftUI 视图。

## 系统版本

从 iOS 15 开始共用一套排版规则。内置 split 根据容器安全区、水平和垂直 size class 以及可用空间选择轴。在两个方向都宽松时，比较安全区内的宽高；轴受样式限制或空间不足时可以只显示主区。双方同时声明理想比例时优先使用主区偏好，受两侧最小和最大尺寸约束。两区共用一条边界，不额外加入栈间距。应用可以通过 padding 表达内容间距。

从 iOS 17 开始，QuickLayoutKit 用 UIKit 的子视图 trait 覆盖，使分割方向上的子区域获得 `compact`，另一方向继承外层容器；浮层遇到活动分隔区时也遵循这条规则。重新叠放后恢复继承。iOS 15 和 16 的子视图沿用容器的尺寸类别。

在包含新 API 的 SDK 和 iOS 27.1 及以上系统中，组件读取 UIKit 活动的 `.division` 保留区。分隔区贯穿容器时，两个区域分别放在其两侧；overlay 允许按逻辑边缘交换两块内容。没有可用分隔区时，overlay 把主内容放在辅助内容上。软件不推断设备型号或铰链位置。

这是独立实现，并不调用系统排列控制器。原生的全部选轴阈值、尺寸冲突规则和转场未公开；对照测试只说明已测场景的结果。

参考 Apple 的 [ArrangementView](https://developer.apple.com/documentation/swiftui/arrangementview)、[SwiftUI 布局基础](https://developer.apple.com/documentation/swiftui/layout-fundamentals) 和 [iPhone Duo 自适应布局讲解](https://developer.apple.com/videos/play/tech-talks/111463/)。

## 同窗口对照

在 Xcode 选择 `ArrangementRegression` 方案可以运行实验页和全窗口页面的 UI 回归。组件和同窗口对照测试位于 `Demo` 方案。`ArrangementExamplePageTests` 按菜单顺序切换全部九种场景，使用全窗口、320 × 200 和 320 × 400 点的局部容器，检查两种实现的区域、尺寸类别、分割轴和层级。

`DemoTests/ArrangementViewTests` 把组件和直接使用 SwiftUI 的参考视图放在同一个窗口，依次更改两者的容器大小，比较主、辅区域的 x、y、宽、高，容差为 1 点。还覆盖受限轴、浮层、尺寸约束、自定义样式转发，以及模拟活动分隔区与 RTL 边缘映射。

iOS 27.2 模拟器的实测结果说明，仅凭宽度无法替代系统决策。以下对照保持设备竖向，仅改变局部宿主的尺寸。

| 局部容器 | iPhone 18 Pro Max | iPhone Duo 展开 | iPad mini |
| --- | --- | --- | --- |
| 669 × 830 点 | 上下 | 上下 | 上下 |
| 669 × 720 点 | 上下 | 左右 | 上下 |
| 844 × 300 点 | 上下 | 左右 | 左右 |

在展开的 Duo 上，还有一个竖向窗口可左右排列的例子：局部容器为 669 × 720 点，顶部安全区占 82 点，实际排版区域为 669 × 638 点，主、辅区域左右并排。保持同一宽度，把容器加高到 830 点就变回上下排列。

在 Device Hub 中实测语音房：半展开时，九个麦位都在折痕上方，公屏和输入栏在折痕下方；合拢后封面屏只显示主区；重新展开后公屏和输入栏恢复。局部容器对照、整机旋转和折叠姿态是三类独立验证，均在模拟器上完成。

本次 iOS 27.2 定向回归覆盖 26 项设备用例：iPhone 18 Pro Max 8 项、iPhone Duo 10 项、iPad mini 8 项均通过。Duo 的 UI 自动化在并行启动时超时，3 项 UI 用例单独复跑全部通过。未在 iOS 15 运行时或实体设备验证。
