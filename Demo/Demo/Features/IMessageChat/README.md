# iOS 26 iMessage 风格聊天页

`IMessageChat` 是 Demo 内独立的一对一文本聊天页面，用来演示 QuickLayout、ListKit、AppLocalization 与 iOS 26 UIKit 原生玻璃 API 的组合使用。页面不复用或修改已有的 `UICollectionView` / `UITableView` 消息示例。

该模块仅用于界面和交互演示，不包含网络、持久化或真实消息服务。每次进入页面都会创建新的 `IMessageChatViewModel`，恢复与联系人 Alex 的固定示例会话。

## 文件职责

- `IMessageChatModel.swift`：内部消息模型、收发方向、送达状态、稳定时间线 ID 与渲染模型。
- `IMessageChatViewModel.swift`：初始会话、发送校验、时间分隔、输入中状态、模拟回复、已读状态和本地化物化。
- `IMessageConversationView.swift`：使用 `UICollectionView` 与 `CollectionListAdapter` 渲染时间线，并管理列表更新、滚底和运行时方向刷新。
- `IMessageChatCells.swift`：发送/接收气泡、时间标记、送达状态和输入中动画。
- `IMessageChatComposerView.swift`：iOS 26 Liquid Glass 输入栏、1–5 行文本输入、占位符和发送按钮。
- `IMessageContactTitleView.swift`：导航栏中的联系人头像、名称和 iMessage 副标题。
- `IMessageChatViewController.swift`：使用 QuickLayout 组合会话列表与输入栏，绑定 ViewModel，并协调键盘、本地化和 RTL 更新。
- `IMessageChatPreviewData.swift`：仅在 `DEBUG` 下提供各组件共享的确定性预览数据。

模块依赖方向保持为：

`ViewController / Views -> ViewModel -> Models`

ViewModel 不持有 UIKit 对象，View 不维护第二份消息业务状态。

## 消息与回复流程

1. 输入栏对发送内容执行首尾空白和换行裁剪；纯空白消息不会发送，正文内部换行保持原样。
2. 发送成功后追加稳定 ID 的本地消息，状态为“已送达”，同时显示输入中气泡。
3. ViewModel 通过可注入的 `Sleeper` 等待约 900 毫秒。
4. 延时结束后，最新发送消息变为“已读”，追加一条本地化模拟回复，并移除输入中气泡。
5. 页面销毁或显式取消时，待处理回复任务会被取消。

只有最新一条发送消息显示“已送达/已读”。时间线第一条消息必定带时间标记；后续消息与上一条间隔达到 5 分钟时插入新的时间标记。

固定示例和模拟回复使用 `.localized(key:)`，运行时切换语言后会重新解析；用户输入使用 `.userText`，切换语言不会改写其内容。

## 列表布局与滚动

- 气泡宽度以可用行宽的约 75% 为上限，文本支持多行和 Dynamic Type。
- 接收气泡位于语义 `leading`，发送气泡位于语义 `trailing`；RTL 下位置和尾角同时镜像。
- 送达状态放在发送气泡所在的 `VStack` 中，与该气泡的语义尾端对齐，不能使用屏幕边缘独立定位。
- 输入中气泡始终位于接收方向。
- 首次加载和主动发送后滚到底部；收到回复或本地化刷新时，只有用户原本接近底部才跟随滚动。
- 用户浏览历史记录时，本地化刷新保存并恢复可见锚点，避免跳动。
- 列表使用 `.interactive` 键盘收起模式。

运行时切换 LTR/RTL 时，`IMessageConversationView` 会重建列表布局，并刷新已经物化的 Cell，保证可见 Cell 与后续复用 Cell 使用同一方向。

## 输入栏与键盘

输入栏继承 `QuickLayoutView`，并使用 `QuickLayoutVisualEffectView` 承载两层玻璃内容。框架通过 `bodyContainerView` 自动把 QuickLayout body 安装到玻璃 API 要求的 `contentView`，控件布局由 `HStack`、`ZStack` 和 `onGeometryChange` 驱动。输入栏使用 `UIGlassContainerEffect`、`UIGlassEffect` 和 `UIButton.Configuration.prominentGlass()`，玻璃效果只用于输入控制层，不覆盖消息内容区域。

`UITextView` 的基础高度为 44 点，随内容扩展到最多 5 行，超过后在输入框内部滚动。纯空白输入时发送按钮禁用；发送成功后清空输入内容并恢复基础高度。

页面在 `super.viewDidLoad()` 前设置：

```swift
quickLayoutKeyboardSafeAreaBehavior = .docked(
    usesBottomSafeArea: true
)
```

输入栏因此跟随停靠键盘，并保留底部安全区。键盘高度或输入栏高度变化时，只有列表原本接近底部才自动保持最后一条消息可见。

## 导航标题

`IMessageContactTitleView` 使用 QuickLayout 的 `HStack` 与 `VStack` 组织内容，并通过明确的 `intrinsicContentSize` / `sizeThatFits(_:)` 桥接 `UINavigationBar` 的 UIKit 测量流程，避免导航栏只测量出头像宽度。标题最大宽度为 220 点、高度不超过 44 点，包含 30 × 30 点系统头像、联系人名称 Alex 和本地化副标题。

配置副标题后必须调用 `sizeToFit()` 再赋给或更新 `navigationItem.titleView`，确保名称与副标题参与导航栏测量。

## 本地化、RTL 与辅助功能

- 文案位于 `Demo/Demo/Localizable.xcstrings`，覆盖英语、简体中文和阿拉伯语。
- 文本统一使用自然对齐，收发位置使用语义 leading/trailing，不使用固定 left/right。
- 气泡、时间、送达状态、输入中状态、输入框和发送按钮均提供辅助功能文本或标识。
- 输入中动画在 Reduce Motion 开启时停止，保留静态圆点状态。
- 颜色使用系统语义色，适配浅色、深色与高对比度环境。

## 路由

页面通过以下 Demo 内部路由进入：

```swift
DemoRoute.imessageChat
```

路由由 `MainViewModel` 展示在 Demo 主列表，并由 `MainRouter` 创建 `IMessageChatViewController`。

## Xcode Preview

每个独立 `UIView`、`UICollectionViewCell` 与 `UIViewController` 都在自身源文件末尾声明 `#Preview`，统一放在 `#if DEBUG` 内。预览覆盖收发气泡、送达状态、时间标记、输入中动画、输入栏、联系人标题、会话列表与完整页面，并为方向敏感组件提供 RTL 变体。

预览数据只能来自 `IMessageChatPreviewData`。不要创建 `+Preview.swift` 文件或 `Previews` 目录，也不要在组件文件中临时构造会随时间变化的业务数据。

## 测试重点

相关测试位于 `Demo/DemoTests/DemoTests.swift`，主要覆盖：

- 发送、输入中、模拟回复和已读状态的确定性流程。
- 页面释放后取消待处理回复任务。
- 切换本地化时更新示例文案但保留用户原始输入。
- 输入栏扩展到 5 行、发送按钮状态和 RTL 镜像。
- LTR/RTL 下收发气泡、送达状态和输入中气泡的语义贴边。
- 导航标题完整测量头像、名称和副标题。

测试 ViewModel 时应注入固定 `Clock` 和受控 `Sleeper`，不要依赖真实时间或固定休眠。

## 维护约束

1. 模块保持 Demo 内部可见，不为 QuickLayoutKit 新增公开 API。
2. 不与现有 `MessageModel`、`MessageListViewModel` 或两种消息列表 Demo 合并。
3. 模拟消息只保存在当前页面生命周期内，不添加持久化或网络抽象。
4. 新增时间线内容必须提供稳定 ID，并补齐 ListKit 的刷新身份。
5. 修改气泡布局时必须同时验证短文本、长文本、LTR、RTL 和 Dynamic Type。
6. 修改输入栏时必须验证键盘展开、交互式收起、1–5 行高度和最后一条消息遮挡。
7. iOS 26 原生玻璃 API 只用于导航或输入控制层，消息内容层保持系统纯色背景。
8. 当前范围不包含图片、语音、附件、Tapback、内联回复或真实已读回执。
9. 新增独立 View 或 ViewController 时，必须在同一源文件补充基于 `IMessageChatPreviewData` 的 `#Preview`。

## 参考资料

- [Apple Messages 使用说明](https://support.apple.com/en-gb/guide/iphone/iph82fb73ba3/26/ios/26)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [UIKit appearance customization](https://developer.apple.com/documentation/uikit/appearance-customization)
