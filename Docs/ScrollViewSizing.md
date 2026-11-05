# ScrollView 尺寸测量

`QuickLayoutScrollView.sizeThatFits(_:)` 是公开测量入口。直接把视图放进布局和使用
`ScrollView(scrollView, axis) { ... }` 均由依赖库 QuickLayout 的 `ScrollViewLayout`
桥接到该方法。内容测量仍使用 `_QuickLayoutViewImplementation.sizeThatFits`，
父容器的分配、修饰符及节点构建仍由 QuickLayout 完成。

## 测量规则

- 内容提议仅解除滚动轴约束；交叉轴继续接收父容器提议，并扣除实际内容边距。
- 滚动轴接收有限的视口提议，且至少容纳该轴两端内容边距；未指定时采用内容的理想长度。
- 交叉轴返回内容测量值及边距。提议不是硬性上限，固定尺寸内容可以超出提议。
- 滚动轴的 QuickLayout 弹性为 `fullyFlexible`，交叉轴从内容推导，至少为 `partial`。空滚动视图仍参与栈的间距分配，不能像零尺寸的固定节点一样被省略。
- 不从上一次布局的 `bounds` 或 `contentSize` 获取理想尺寸，避免首次测量、重用和
  嵌套滚动依赖布局历史。
- 安全区改变时，两种滚动方向都会通知父布局重新测量。垂直视口的宽度和水平视口的
  高度都可能随边距变化，不能只刷新滚动内容。
- 视口测量与内容滚动范围分开处理。布局阶段仍将交叉轴 `contentSize` 固定为扣除
  实际边距后的视口长度，避免固定内容溢出时启用另一方向的滚动。

例如，内容为固定 `80 × 60` 时，系统 SwiftUI 的实测结果如下（单位：点，无边距）：

| 提议 | 垂直 ScrollView | 水平 ScrollView |
| --- | --- | --- |
| 300 × 200 | 80 × 200 | 300 × 60 |
| 30 × 20 | 80 × 20 | 30 × 60 |
| 0 × 0 | 80 × 0 | 0 × 60 |
| 未指定 × 未指定 | 80 × 60 | 80 × 60 |
| 300 × 未指定 | 80 × 60 | 300 × 60 |
| 未指定 × 200 | 80 × 200 | 80 × 60 |

## 对照方法

环境：Xcode 26.5（17F42），iOS 26.5 模拟器。依赖 QuickLayout 修订
`62310c0a7f4ec43f3ea6ff89f3824ef6b23b2bb3`。

2026-11-01 在 iPad mini (A17 Pro) 模拟器中运行 Demo scheme 的 12 项定向测试，
全部通过，无跳过或预期失败。包含本文的 4 项尺寸测试及 8 项现有轮播、安全区、
动态滚动、内容居中、多根内容和边距稳定性回归。主矩阵 1,152 组全部一致，
执行耗时约 4 秒（不含构建和启动）；另有 72 组内容边距对照。
为控制机器负载，未运行全量 Demo 测试或 UI 自动化；其他 iOS 版本仍需另行验证。

同日修复安全区变化未使垂直滚动视图的父布局失效的问题，并更新空内容尺寸和交叉轴
弹性的旧测试预期。新增双方向回归依次将交叉轴安全区从 `0` 改为 `10`、`20`、`0`，
不手动标记父布局失效，检查实际视口、`sizeThatFits` 和交叉轴内容范围。
修复后以单任务、单模拟器方式执行 8 项包级测试（参数展开后 11 个用例），全部通过；
覆盖新回归、旧预期、嵌套滚动、溢出内容、自动调整边距及滚动位置保持。
随后重跑 5 项 Demo 测试，全部通过，包括 1,152 组尺寸和 72 组边距对照、横屏安全区、
安全区动态变化和滚动／重建时边距稳定性。

包级验证使用 `.swiftpm/xcode/package.xcworkspace` 的 `QuickLayoutKit` scheme，
设置 `-jobs 1 -parallel-testing-enabled NO -enableCodeCoverage NO ONLY_ACTIVE_ARCH=YES`。
现有 `GeometryProxyTests.swift` 使用了需要 iOS 16 的 API，导致默认 iOS 15 测试目标
无法编译，因此本轮仅在测试命令中指定 `IPHONEOS_DEPLOYMENT_TARGET=16.0`；
未修改项目最低版本，实际运行系统为 iOS 26.5。默认 iOS 15 测试目标及全量测试未验证通过。

后续同日已修复 Geometry 测试的 API 兼容性：取消上述命令行版本覆盖后，iOS 15
测试目标编译成功，5 项 Geometry 定向测试通过。详见
[Geometry 验证记录](GeometryValidation.md#ios-15-测试源码兼容修复2026-11-01)。
这次后续验证未重跑 ScrollView 或全量测试。

回归位于 `Demo/DemoTests/ApplicationTests+ScrollSizing.swift`。自定义 SwiftUI `Layout`
直接向 `LayoutSubview` 传递所需提议，再通过 `UIHostingController` 驱动测量。
这样未指定尺寸不会被 hosting controller 的输入转换替代，也不混入窗口安全区。
测试逐次释放 hosting controller，适合在单个模拟器中运行。

主矩阵包含两种滚动方向、六类内容（小于容器、大于容器、弹性、空、带 padding、
带弹性 frame）、六种提议和十六种容器／修饰符，共 1,152 组：直接使用、VStack、
HStack、ZStack、padding、固定／弹性 frame、双轴／单轴 fixedSize、同轴／交叉轴
嵌套滚动，以及带固定／弹性兄弟节点的 VStack／HStack。

附加用例验证公开方法、QuickLayout 视图桥接和构建器的一致性，旧 bounds／contentSize
不参与理想尺寸测量，以及轴、内容、边距变化后的重新测量。

## 兼容边界

QuickLayout 的 `CGSize.infinity` 同时承担无界／理想尺寸提议，`fixedSize` 也依赖
这一约定。因此对照时将它映射为 SwiftUI 的 `ProposedViewSize` 中的 `nil`。
SwiftUI 的显式 `.infinity` 是最大尺寸请求，属于不同语义；不能在当前 `CGSize`
协议下同时表达这两种意图。系统探针已确认固定内容在显式无限提议下的滚动轴返回无限，
而在未指定提议下返回内容理想长度。参见
[Apple ProposedViewSize 文档](https://developer.apple.com/documentation/swiftui/proposedviewsize)。

当前 API 只接受单一 `QuickLayout.Axis`，不支持 SwiftUI 的双向滚动轴集合。
多根内容依旧按项目约定组成零间距的 VStack／HStack，不在此次修改中改变构建器语义。

参考检查了 OpenSwiftUI 提交 `e1f080c5653c4d7304ab1f2ebd6da89bd21d9a27`：
其 [ProposedSize](https://github.com/OpenSwiftUIProject/OpenSwiftUI/blob/e1f080c5653c4d7304ab1f2ebd6da89bd21d9a27/Sources/OpenSwiftUICore/Layout/Geometry/ProposedSize.swift)
区分未指定和无限尺寸；但
[HostingScrollView](https://github.com/OpenSwiftUIProject/OpenSwiftUI/blob/e1f080c5653c4d7304ab1f2ebd6da89bd21d9a27/Sources/OpenSwiftUI/View/Scroll/HostingScrollView.swift)
仍为 WIP，未提供完整的 ScrollView 测量实现。本次滚动尺寸规则来自系统 SwiftUI 实测。
