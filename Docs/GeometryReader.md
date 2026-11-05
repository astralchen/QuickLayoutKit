# GeometryReader

`GeometryReader` 位于 `QuickLayoutKitUIKit`，统一导入 `QuickLayoutKit` 即可使用。
最低部署目标保持 iOS 15。

```swift
GeometryReader { proxy in
    card.resizable()
        .frame(width: proxy.size.width / 2, height: 80)
}
.frame(height: 160)
```

## 布局约定

- 有限的父建议成为 Reader 自身尺寸，子内容不影响其所需尺寸。
- 未指定轴使用 10 点理想长度。QuickLayout 用正无穷表达未指定，最大有限长度哨兵同样按未指定处理；非法负数与 NaN 归零。
- `.fixedSize()` 的结果为 10 × 10；只固定一个轴时，另一轴继续接受父建议。
- 每个直接子元素独立收到 Reader 的完整尺寸建议，并叠放在顶部前缘。LTR 前缘在左，RTL 在右；子元素的自定义 alignment guide 不改变该位置。
- 空内容仍占用 Reader 的尺寸；大于 Reader 的内容不会撑大 Reader，也不会自动裁剪。
- 垂直滚动内容的未指定高度为 10，水平滚动内容的未指定宽度为 10。需要更大滚动内容时显式指定该轴尺寸。
- 放在 `.background` / `.overlay` 中时，以主内容提供的尺寸布局，不改变主内容的测量结果。

## 测量、节点与视图层级

每次 `quick_layoutThatFits` 根据尺寸建议构建一次内容，并测量每个直接子元素一次，
返回包含所有后代的 `LayoutNode` 树。对齐包装器复用已测量节点；应用缓存节点时不调用
内容闭包，也不再执行子元素测量。Grid、Stack 等父算法可以按自身规则提出多次建议，
因此“一次测量生成完整子树”不意味着一次宿主布局只允许调用 Reader 一次。

已移除内部 `GeometryReaderHost`。业务 UIView、嵌套 Reader 的内容与外层宿主直接相连；
每个 Reader 只挂载一个无交互观察标记，不引入承载内容的 UIView 容器。

QuickLayout 先调用 `views()` 收集视图，之后才测量。Reader 在 `views()` 中只提供稳定标记，
由每份测量节点携带的提交记录在应用时协调动态视图集合。完整业务子树已包含在测量结果中。
QuickLayout 当前公开的 `LayoutNode` 没有提交回调，所以提交记录以一个**不挂载到视图层级**
的内部 UIView 节点实现：引擎写入其 `center` 时只提交成员集合与方向元数据，不测量内容。
这一桥接保留了 QuickLayout 的测量/应用分离，但并非零辅助对象的数学纯函数。

提交记录独立保存本次测量的视图集合、输入快照和方向。测量 B 不会提前改变已应用的 A；
之后应用 A 的缓存仍使用 A 的子节点和分支。Reader 移除时同步清理自己管理的同级视图。
视图复用依赖声明位置及同位置出现顺序；业务 UIView 身份仍由调用方维护。

## 几何快照的时间边界

测量时 `proxy.size` 与 `.local` 矩形立即对应当前尺寸建议。此时父布局尚未确定 Reader 的
最终位置，其他坐标空间、安全区域和 Anchor 使用最近一次已应用的快照；首次测量时
安全区域为零，找不到的空间遵循原有回退规则，`resolve` 可返回 nil。

观察标记在实际应用后生成新快照。快照变化会使外层宿主重新布局，后续测量取得更新值；
读取几何的闭包必须能处理首次信息尚未完整的状态。没有 SwiftUI 属性图依赖追踪，
所以纯位置变化也可能重新构建只读取尺寸的内容。需要立即查询已完成布局结果时，使用
`.onGeometryChange`。测量闭包应无业务副作用，不能在其中挂载或移除视图。

Reader 保持主线程计算约束，因为内容可以包含真实 UIView；不提供后台纯 ViewProxy 测量。
不引入 OpenSwiftUI 运行时依赖，不修改 QuickLayout 依赖源码，也不调用私有系统 API。

## SwiftUI 参考

参考 [OpenSwiftUI GeometryReader 实现](https://github.com/OpenSwiftUIProject/OpenSwiftUI/blob/main/Sources/OpenSwiftUICore/Layout/Geometry/GeometryReader.swift)
的内容闭包、弹性容器、独立子元素放置模型。OpenSwiftUI 内部的 `GeometryReaderLayout`
与外层根几何、默认 layout computer 共同决定行为，不能将内部未指定轴的零值直接当成
公开 Reader 的理想尺寸。本项目使用真实系统 SwiftUI 的宿主测试核对理想尺寸、滚动轴、
比例布局和 RTL 放置。

## 验证入口

- `Demo/DemoTests/GeometryReaderTests.swift`：尺寸规则、完整子树测量、扁平视图层级、Grid、
  layoutPriority、缓存复用、嵌套、释放、坐标空间、安全区域、滚动以及系统 SwiftUI 对照。
- `Demo/DemoUITests/GeometryUITests.swift`：GeometryReader 场景的宽度滑杆、比例尺寸、
  LTR/RTL 前缘位置，以及原有 Geometry 场景。
- Demo → Geometry → GeometryReader：宽度为 Reader 的 50%、高度为 60% 的卡片。
- Demo → Geometry → 自适应网格：6 张稳定身份的卡片，按扣除内边距后的容器宽度排列成
  1～4 列；目标最小列宽 104 点、间距 12 点。窄于目标宽度时仍保留一列，卡片缩窄；
  最后一行补齐空列，卡片宽度保持一致。宽度与内边距滑杆、LTR/RTL 都可交互调整。
  `GeometryAdaptiveGridTests` 验证列数边界、实际卡片矩形、视图复用、内边距和 RTL；
  `GeometryUITests.testAdaptiveGridChangesColumnsAndDirection` 验证真实滑杆与场景切换。

## 本次扁平实现验证记录（2026-11-04）

| 验证 | 结果 | 范围 |
| --- | --- | --- |
| GeometryReader 测试与系统 SwiftUI 对照 | 22/22 通过 | iPhone 18 Pro Max，iOS 27.2 |
| 原有几何回归 | 24/24 通过 | iPhone Duo，iOS 27.2；16 项 GeometryProxyTests 与 8 项几何观察测试；当前 Sources/Tests 的独立 Swift Package 快照 |
| Geometry Demo UI 回归 | 1/1 通过 | iPhone 18 Pro Max，iOS 27.2；滑杆、比例尺寸、RTL、场景切换和横屏边界 |

新增覆盖包括：单次测量生成完整子树且不挂载视图；候选 B 测量不改变已应用的 A；
A → B → A 缓存回放恢复对应分支、方向、回调和命名空间；Grid 单元格及 RTL；
Stack/Grid 的 layoutPriority；启用宿主缓存时的扁平层级、尺寸与方向更新。
缓存应用期间内容闭包与子视图测量计数保持不变。

本次没有运行完整包测试集、iOS 15、iPad 或真机验证，也没有重跑 Duo 的完整横屏 UI 流程。
普通 iPhone UI 测试的 RTL 截图已导出检查。

本机证据：

- `/private/tmp/qlk-reader-flat-accepted.log`、`/private/tmp/qlk-reader-flat-accepted.xcresult`
- `/private/tmp/qlk-reader-flat-core-verified.log`、`/private/tmp/qlk-reader-flat-core-verified.xcresult`
- `/private/tmp/qlk-reader-flat-ui.log`、`/private/tmp/qlk-reader-flat-ui.xcresult`
- `/private/tmp/qlk-reader-flat-ui-attachments/`：UI 测试截图

## 自适应网格 Demo 验证（2026-11-04）

- iPhone 18 Pro Max / iOS 27.2：3 项 `GeometryAdaptiveGridTests` 与 22 项
  `GeometryReaderTests` 共 25/25 通过。实际宿主宽度覆盖 180、280、400、600 点，
  验证 1～4 列、末行等宽、卡片身份复用、内边距换列和 RTL；宽容器测试不等同于 iPad 实机验证。
- 新增网格 UI 用例通过：宽度滑杆从多列切为单列、恢复多列、切换 RTL、切出再返回；
  导出的 RTL 截图已检查。
- 原有 Geometry UI 用例第一次运行失败；日志记录另一个 `UIKitTestHost` App 切到前台，
  返回后未打开场景菜单。保留失败结果，未修改断言；单独重跑该用例通过，包括横屏边界。
- 本次只增加 Demo、文案、测试和说明，不修改 QuickLayout 源码、依赖版本或节点应用流程。

本机证据：

- `/private/tmp/qlk-adaptive-grid-tests-final.log`、`/private/tmp/qlk-adaptive-grid-tests-final.xcresult`
- `/private/tmp/qlk-adaptive-grid-ui.log`、`/private/tmp/qlk-adaptive-grid-ui.xcresult`：网格通过，原有用例失败
- `/private/tmp/qlk-adaptive-grid-ui-regression.log`、`/private/tmp/qlk-adaptive-grid-ui-regression.xcresult`：原有用例单独重跑通过
- `/private/tmp/qlk-adaptive-grid-ui-attachments/`：网格截图与首次失败现场

## 早期宿主版本验证记录（不代表本次扁平实现）

| 验证 | 结果 | 范围 |
| --- | --- | --- |
| GeometryReader 宿主与系统 SwiftUI 对照 | 15/15 通过 | iPhone 18 Pro Max，iOS 27.2；包括几何稳定后不持续重建 |
| 原有 GeometryProxy 回归 | 16/16 通过 | iPhone Duo，iOS 27.2；当前 Sources/Tests 的独立 Swift Package 快照 |
| Geometry Demo UI 回归 | 1/1 通过 | iPhone 18 Pro Max，iOS 27.2；实际滑杆操作、Reader 比例与 RTL、原有场景、横屏边界 |
| 较早的 Duo Reader 宿主测试 | 14/14 通过 | 未包含最后增加的稳定性用例；框架实现与最终版本一致 |
| 较早的 Duo 完整 Demo UI 回归 | 未通过 | 指标文字越界、横屏方向及窗口边界断言失败，导出横屏截图为黑屏；不视为完整视觉验证 |

已修正指标文字的换行和水平尺寸约束；修正后完整 UI 测试在普通 iPhone 上通过。
未重新完成 Duo 的整轮横屏 UI 验证，黑屏与横屏窗口结果的根因未在本任务中定位。
没有运行 iOS 15 模拟器、iPad 或真机测试；工程最低部署目标仍为 iOS 15，使用当前 SDK 编译通过。

系统 SwiftUI 的命名空间坐标在本次宿主中出现约 0.167 点的取整差异。跨引擎对照的位置
容差为一个物理像素（由测试窗口的 `displayScale` 决定），尺寸保持精确比较。

本机证据：

- `/private/tmp/qlk-reader-tests-iphone.log`、`/private/tmp/qlk-reader-tests-iphone.xcresult`
- `/private/tmp/qlk-reader-core-final.log`、`/private/tmp/qlk-reader-core-final.xcresult`
- `/private/tmp/qlk-reader-ui-iphone.log`、`/private/tmp/qlk-reader-ui-iphone.xcresult`
- `/private/tmp/qlk-reader-tests-final.log`：较早的 Duo 14 项宿主测试
- `/private/tmp/qlk-reader-ui.log`、`/private/tmp/qlk-reader-ui.xcresult`：未通过的 Duo 完整 UI 回归

重跑新用例：

```sh
xcodebuild -workspace QuickLayoutKit.xcworkspace -scheme Demo \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -only-testing:DemoTests/GeometryReaderTests -parallel-testing-enabled NO test
```

重跑 Demo UI：

```sh
xcodebuild -workspace QuickLayoutKit.xcworkspace -scheme GeometryRegression \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -parallel-testing-enabled NO test
```
