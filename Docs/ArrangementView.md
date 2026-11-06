# ArrangementView

`QuickLayoutKit.ArrangementView` 用两个 QuickLayout 内容闭包构建 UIKit 页面。所有支持的系统版本都由 QuickLayout 自行测量、排版并更新 UIKit 内容。SwiftUI 仅用作测试里的参考实现。语音房采用 `.split`，输入栏跟随公屏的实际水平范围。

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

在包含新 API 的 SDK 和 iOS 27.1 及以上系统中，组件读取 UIKit 活动的 `.division` 保留区。分隔区贯穿容器时，两个区域分别放在其两侧；overlay 允许按逻辑边缘交换两块内容。没有可用分隔区时，overlay 把主内容放在辅助内容上。软件不推断设备型号或铰链位置。

这是独立实现，并不调用系统排列控制器。原生的全部选轴阈值、尺寸冲突规则和转场未公开；对照测试只说明已测场景的结果。

参考 Apple 的 [ArrangementView](https://developer.apple.com/documentation/swiftui/arrangementview)、[SwiftUI 布局基础](https://developer.apple.com/documentation/swiftui/layout-fundamentals) 和 [iPhone Duo 自适应布局讲解](https://developer.apple.com/videos/play/tech-talks/111463/)。

## 同窗口对照

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
