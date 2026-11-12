# 默认安全区域迁移

QuickLayoutKit 的普通宿主默认避让容器安全区与停靠键盘。此变更保留 QuickLayout 源码、依赖版本，以及 `safeAreaPadding` 的默认额外间距 `0`。

SwiftUI 对照、模拟器交互、已知基线问题和未验证范围见 [验证记录](DefaultSafeAreaValidation.md)。

## 调用方迁移

- 没有修饰符的普通内容默认位于安全区内，安全区变化会重新测量与放置。
- `safeAreaPadding()` 与 `safeAreaPadding(0)` 不再是启用安全区的必要步骤，保留它们不会重复扣减。
- `safeAreaPadding(.horizontal, 20)` 在默认安全区内额外增加左右 20 点；其他边仍默认避让。
- 全屏背景、媒体画布和覆盖层使用 `ignoresSafeArea(.container)`，需要同时忽略键盘时明确使用 `.all`。
- 手动读取 `safeAreaInsets` 添加 padding 的页面需要删除重复补偿，或明确保留由页面负责的完整画布。
- 使用自定义键盘协调器的页面显式设置 `quickLayoutKeyboardSafeAreaBehavior = .disabled`。默认策略为 `.followsDockedKeyboard(usesBottomSafeArea: false)`，隐藏键盘不额外发布容器底部安全区。

## 滚动与嵌套宿主

声明式 `ScrollView` 恢复可用的滚动外框，通过内容和指示器 inset 处理安全区域、额外安全区 padding 和插入栏。`contentMargins` 继续提供独立的额外内容/指示器间距。UIKit 已计入 `adjustedContentInset` 的部分不会再次进入内容布局；`.never` 下未被处理的部分仍需避让。

外层的 `contentMargins(.horizontal, 16, for: .scrollContent)` 会给滚动内容留出 16 pt。满宽的内层横向滚动视口仍可沿接触的边扩展到系统安全区域，扩展后保留这 16 pt。如果局部预览需要在背景边缘停止绘制和接收拖动，可以像几何示例一样给页面内容设置普通水平 padding，再用画布内的可用宽度布局内层视口。

原生 `UITableView`、`UICollectionView` 使用不带内容闭包的 `List(listView)` 入口声明滚动语义。它复用现有实例、数据源和布局，不增加外层滚动视图，默认填满父布局提供的有限空间；视口、内容边距和键盘区域采用与声明式滚动相同的规则，无需通过 `ignoresSafeArea` 启用完整视口。

```swift
List(collectionView) // UITableView 同样使用 List(tableView)
```

UIKit 已处理的自动 inset 不重复添加；`.never` 下由 Kit 补足声明要求的区域。调用方原有 `contentInset` 作为独立基线保留。`safeAreaPadding`、`safeAreaInset`、`contentMargins` 与按区域忽略安全区同样适用于此入口。

直接作为普通 UIKit 叶子放置的 `UIScrollView` 仍遵循父布局给出的外框，适用于自行管理布局的视图。原生全屏列表应使用上述滚动入口。

默认由最外层 Kit 宿主监听键盘，嵌套宿主和滚动项目继承该区域；不会按每个项目的可见位置独立重复避让。显式设置某个宿主的 `quickLayoutKeyboardSafeAreaBehavior` 仍可让它自行管理。

嵌套 Kit 宿主在测量与修饰符边界记录父级区域，独立布局时按实际视图坐标投影。双轴 `resizable()` 跳过测量时仍可传递忽略规则；重新挂载到其他视图树后不继续使用旧父级的区域。

普通 `.padding` 是内容间距，不视为系统安全区。`safeAreaPadding` 和 `safeAreaInset` 的组合顺序仍有意义，额外间距会累加。没有接触安全边界的固定尺寸内容不因忽略安全区而发生额外平移。

## 适用边界

默认行为由 QuickLayoutKit 宿主提供。直接使用上游 `@QuickLayout`、QuickLayout 自身的布局入口，或脱离 Kit 宿主独立测量元素时，不会凭空获得窗口安全区。Kit 不修改 UIKit 的全局安全区、上游宏或依赖源码。

`safeAreaPadding` 保留非可选零默认值，`safeAreaInset` 保留零默认 spacing；这些参数不采用 SwiftUI 平台默认间距。浮动和分离键盘仍需按输入框实际遮挡处理。

空 `ScrollView` 沿滚动轴填满提议、交叉轴保留零理想长度，这是 Kit 原有的尺寸契约；它不承诺与 SwiftUI 空滚动视图的双轴伸展一致。安全区不会单独撑开其交叉轴，显式 `resizable` 仍可要求伸展。
