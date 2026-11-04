# Demo iPad 导航与布局适配

## 层级和 MVVM 边界

```text
SceneDelegate → AppTabBarController
├─ 示例 → ExampleSplitViewController（doubleColumn）
│  ├─ primary → UINavigationController → MainViewController
│  └─ secondary → UINavigationController → 示例详情／未选择占位页
├─ 聊天 → FeatureNavigationController → ChatViewController（iOS 26+）
└─ 语音房 → FeatureNavigationController → VoiceRoomViewController
```

`AppNavigationViewModel` 管理可用功能、选中 Tab 和本地化标题；`ExampleNavigationViewModel` 管理详情路由身份。控制器负责 UIKit 容器、生命周期和布局，`MainRouter` 负责创建页面及分发导航。继续复用各功能已有的 ViewModel，不把 UIKit 控制器存入 ViewModel。

分栏容器按业务命名：示例使用 `ExampleSplitViewController`；后续聊天引入分栏时使用 `ChatSplitViewController`。当前示例容器保留自己的菜单、路由与占位页职责。

用户点击 Tab 时由 UIKit 完成原生选择，在 `didSelect` 中同步 ViewModel；程序导航由 ViewModel 状态驱动控制器选择。重复点击保留 UIKit 默认行为，状态同步不会重复清理或重建页面。

Tab 项在设置 `viewControllers` 前一次性配置完整标题、图标和辅助功能标识；选中状态变化不再重复设置图标，本地化只更新实际变化的标题。这修复了 iPhone 浮动 Tab Bar 未选中项目标题偏低的问题，已用横竖屏截图确认。

示例目录共 26 页，分为布局（8）、滚动与输入（4）、列表（3）、示例页面（3）、控制器承载（1）、本地化（7）。聊天和语音房升级为根功能。旧路由仍可切换到对应 Tab。

使用 UIKit 分栏折叠机制适应窄宽度；选中的详情及搜索状态不随 Tab 切换重建。布局以容器安全区和可用宽高为依据，不以设备型号分支。多窗口同时运行不在本次范围内；保留现有 Scene 会话配置。

## 实施阶段

| 阶段 | 优先级 | 本次落地 | 验证状态 |
| --- | --- | --- | --- |
| 导航与状态 | P0 | 根 Tab、示例双栏、页面分类、MVVM 选择状态、懒加载及切换生命周期 | iPad 9 项控制器及 2 项 UI 回归通过；iPhone 8 项适用控制器及 2 项 UI 回归通过 |
| 尺寸与浮层 | P0 | 聊天输入高度预算、照片浮动面板完成按钮及遮挡判断、礼物与资料卡限高滚动、矮窗口舞台滚动 | 已做单文件诊断；待窗口尺寸实测 |
| 大屏与交互 | P1 | Profile／表单阅读宽度，Dashboard／Frame Lab 宽窗口双列，Cmd-F 搜索、Cmd-Return 发送、Esc 关闭资料卡、输入栏按钮指针交互 | 已做单文件诊断；待键盘、指针及辅助功能实测 |
| 回归验收 | P0 | 新增 9 个导航／布局回归测试和 2 个跨设备 UI 测试，更新现有菜单及 UI 测试入口 | 应用构建、iPad 11 项及 iPhone 10 项适用回归通过；完整手动清单待完成 |

## 当前验证限制

2026-10-31 使用 Xcode MCP 完成应用构建，修复 `AppTabBarController` 原生选择回调后再次构建通过，未报告编译错误。当前 Xcode 26.5 SDK 缺少的原生保留区域／铰链 API 已通过 `#if compiler(>=6.4)` 按项目的配套 Xcode / SDK 约定隔离，详见 [SDKCompatibility.md](SDKCompatibility.md)。

首次 iPad mini 测试在用例执行前因 LLDB 附加失败退出。将 Demo 和专用回归 Scheme 的 TestAction 配置为不附加调试器、关闭测试目标并行执行后，经 Xcode MCP 启动的下一轮测试虽然超过 MCP 的 300 秒等待上限，但 Xcode 随后完成了测试：**9 个 AppNavigationTests 全部通过，0 失败、0 跳过**。设备为 iPad mini (A17 Pro)，iOS Simulator 26.5；结果包为 `Test-Demo-2026.10.31_12-00-17-+0800.xcresult`。

已通过的控制器测试覆盖 Tab 原生选择与 ViewModel 同步、目录路由完整性、分栏折叠／展开后详情实例保留、搜索与 Tab 切换状态保留、聊天草稿保留、输入栏高度预算及浮动面板遮挡分类。

重开工作区后，通过 Apple 官方 `mcpbridge` 恢复 Xcode MCP 连接，并在 `AdaptiveNavigationRegression` Scheme 串行执行 UI 回归。修复了 `ChatMessageMenuUITests.bluePixels` 在当前编译器下的类型检查超时，将复合表达式拆成等价的局部变量和计数循环；同时将根 Tab 的 UI 查询改为 `matching(identifier:).firstMatch`，兼容 iPad 浮动 Tab 栏父子节点重复暴露同一标识的情况。

| 设备与验证 | 结果 |
| --- | --- |
| iPad mini (A17 Pro)，iOS 26.5，9 项控制器／布局测试 | 9 通过、0 失败 |
| iPad mini (A17 Pro)，2 项 UI 测试 | 2 通过、0 失败：分栏／横竖屏、语音房往返、聊天草稿保留；完整屏幕截图复核正常 |
| iPhone 17 Pro，iOS 26.5，8 项适用的控制器测试与 2 项 UI 测试 | 10 项通过；iPad 专属展开测试的条件修复后，单独复跑确认跳过 |

iPhone 首轮原始结果包记录 `Timed out waiting for AX loaded notification`，虽然 MCP 的结构化摘要误返回了之前的 2 项通过结果，但本轮实际未执行 UI 用例。验收以对应设备和时间的原始 `.xcresult`、控制台日志及截图交叉核验为准。

iPhone 的通过用例位于 `Test-AdaptiveNavigationRegression-2026.10.31_13-48-07-+0800.xcresult`：8 项控制器测试、2 项 UI 测试通过。该轮有 1 项不适用于 iPhone 的强制展开测试失败，随后为它增加异步 `.enabled` 条件限定 iPad；`Test-AdaptiveNavigationRegression-2026.10.31_13-54-17-+0800.xcresult` 确认该用例在 iPhone 上跳过，0 失败。未将原始失败结果包描述为整轮通过。

UI 用例等待搜索输入焦点，交互式收起键盘时将手势拖至键盘下方；横屏矮窗口允许先滚动再验证详情按钮可点击。附件改用 `XCUIScreen.main.screenshot()` 捕获完整屏幕，iPhone 横屏截图已确认无裁切。

最终 iPad 结果包为 `Test-AdaptiveNavigationRegression-2026.10.31_13-58-18-+0800.xcresult`，9 项控制器测试与 2 项 UI 测试共 11 项全部通过，0 失败、0 跳过。MCP 摘要包含的另外 882 项是此专用 Scheme 未选择的测试，并未运行。原始 `.xcresult` 已核验设备及 11 项通过结果；完整屏幕横屏截图无此前的裁切问题。窗口手动缩放、键盘／指针、RTL 和辅助字体仍按下面的完整清单单独验收。

使用 `AdaptiveNavigationRegression` Scheme 串行执行控制器和 UI 导航回归，分别选择 iPad 与 iPhone 模拟器。已在 Xcode Scheme 编辑器中修复套件选择，并通过 MCP 确认启用 11 项测试（9 项控制器测试 + 2 项 UI 测试）。完成以下验收后，再认定 iPad 支持完成。

## 验收清单

- [x] 当前 Xcode 26.5 下应用与回归测试构建通过；专用 Scheme 的 iPad 11 项、iPhone 10 项适用测试通过，iPad 专属展开测试在 iPhone 上明确跳过。
- [x] Tab Bar 选中和未选中项目图标／标题对齐，横竖屏截图正常。
- [ ] 完整 DemoTests 与其余聊天／语音房 UI 套件回归（本轮只运行专用导航 Scheme）。
- [x] iPhone 竖屏首先显示示例目录；选择、返回、搜索、重选同一示例正常；横屏切换不丢详情状态，详情操作可滚动到达。
- [x] iPad 横竖屏分栏显示正确；目录选中项与详情一致；控制器测试验证折叠、展开后保留同一详情。
- [ ] 未选择时占位页、多任务窗口连续缩放及窗口恢复的完整手动检查。
- [ ] 分屏及窗口连续缩放（约 320／375／600／768／1024／1366 pt 宽），目录折叠与展开后详情实例和搜索内容保留，无重复导航栏或空白详情。
- [x] 示例与语音房往返保留详情状态；聊天与示例往返保留输入草稿。
- [ ] 附件保留、录音／播放停止及语音房订阅恢复的完整业务回归。
- [ ] 页面在大屏限制阅读宽度；Dashboard／Frame Lab 达到宽度阈值时双列，窄窗口和辅助字体回到单列。
- [ ] 聊天长文本、附件、键盘弹出及窗口缩放后输入栏可见且可滚动；消息列表仍填满所属页面。
- [ ] 停靠键盘、浮动键盘、外接键盘分别验证；照片浮动面板不会把整条输入栏顶起，完成按钮可关闭并保留选择。
- [ ] 礼物面板、用户资料卡和舞台在矮窗口可滚动，操作按钮可到达；菜单和 Popover 锚定正确。
- [ ] Cmd-F、Cmd-Return、Esc、指针点击／滚动及 VoiceOver 顺序可用；输入法组词期间不会误发送。
- [ ] 中英阿语言切换，尤其 RTL 分栏方向、导航返回方向及目录选中态正确；大字体下无内容截断。
- [ ] 保持 iOS 15 最低版本行为，低于 iOS 26 时不显示聊天 Tab，其他功能正常。

## 几何观察页面遮挡回归（2026-10-31）

用户反馈 iPad 竖屏下详情左侧被目录遮挡。该页原先用根视图 `view.bounds.width` 固定画布宽度，同时在滚动内容内消费水平安全区，不能正确表达分栏详情的实际滚动视口。

调整为滚动宿主的 `contentMargins(.horizontal, 16, for: .scrollContent)`，画布通过 `containerRelativeFrame` 按该宿主扣除安全区及内容边距后的可用宽度计算比例。不新增设备型号判断，保留画布内部用于演示坐标空间的横向滚动。

扩展 `GeometryDemoUITests/testGeometryScenariosAndDirection()`，检查默认／最大画布宽度、横竖屏及场景切换后，按钮、滑块、画布、指标和代码说明不越过目录或窗口的水平边界，并保存完整屏幕截图。该用例已加入专用 Scheme，启用测试数由 11 增加到 12。

Xcode MCP 发起的构建通过。首轮 UI 运行器在准备阶段异常退出，未执行用例；串行重试后，iPad mini (A17 Pro)、iOS 26.5 的该专项测试 **1 项通过、0 失败**，原始结果包为 `Test-AdaptiveNavigationRegression-2026.10.31_14-32-34-+0800.xcresult`。已核对横竖屏截图，详情内容均处于侧栏右侧。

iPhone 17 Pro 的同一用例尚未验收：`14-50-27` 轮在应用启动后黑屏，日志停在自动化界面快照请求，未进入几何观察页面；`15-00-38` 串行重试仍阻塞在准备阶段，同时 Xcode 界面读取超时。两轮均已停止，MCP 返回 `Test execution was cancelled.`，不计为通过。需恢复模拟器运行环境后补验；之前的 iPhone 导航回归结果不代替本次页面回归。

## 键盘布局页面横向压缩（2026-10-31）

`AnimatedKeyboardResponsiveView` 原先将 `maximumHorizontalInset` 同时用作左右内边距，在分栏仅有一侧安全区时重复扣减宽度。改为 `safeAreaPadding(.horizontal, 20)` 逐边消费安全区，并为诊断文字、输入框及提交按钮声明横向伸展；保留原有底部输入排列和键盘动画。

新增 `DemoTests/keyboardLayoutUsesAsymmetricSafeArea()`，覆盖左右侧栏、横竖屏尺寸和 LTR／RTL，检查三个控件共享可用区域的左右边界及垂直顺序。

验证状态：`git diff --check` 通过。Xcode MCP 构建持续停在 `7/61`，316.768 秒后由本次任务主动取消，返回无编译错误但未完成构建；专项测试及修复后截图尚未取得，不计为验收通过。环境恢复后需运行新增边界测试、现有 `keyboardControllerUpdatesItsNestedViewWithoutMovingVerticalContent()`，并验证 iPad 分栏下软键盘显示／收起及 iPhone 横竖屏。

## 按 Kit 宿主约定修正示例页面（2026-10-31）

后续截图证实上述键盘页调整不完整：`AnimatedKeyboardResponsiveView` 仍是上游 `@QuickLayout UIView`，内部独立布局没有建立 QuickLayoutKit 安全区上下文。现已改为继承 `QuickLayoutView` 并重写 `body`，保留逐边消费安全区和原有键盘观察逻辑。

UIKit 本地化、方向导航、语义手势及刷新边界页面原先仅将顶部约束到安全区，左右仍使用整个根视图边界。现统一采用 `LocalizedQuickLayoutHostingController` + `QuickLayoutScrollView`，通过 `contentMargins(20, for: .scrollContent)` 管理内容边距。正文最大宽度 720 点，居中于安全视口；手势卡片最小高度 180 点，文本增多时可增长。关联 Modal 同样采用滚动宿主，保留原来的本地化刷新与交互入口。

不以固定侧栏宽度、`UIScreen` 或设备型号作为布局依据，不在滚动内容上重复叠加安全区。新增 `localizationPagesRespectDetailViewport()` 检查左右侧栏及窄窗口；UI 用例 `testDemoContentStaysInsideDetailColumn()` 覆盖五个截图页面和键盘输入／收起／旋转。

API 评估：目前未确认安全区计算算法缺陷；已确认上游宏宿主与 Kit 宿主能力不同，缺少 Kit 上下文时 `safeAreaPadding` 按零继承边距继续布局，容易被误用。README 已补充宿主选型规则。后续可考虑仅在调试环境增加缺失宿主的诊断，不应直接修改无上下文时的默认行为，以免影响独立测量等既有用途。

本轮应用构建已通过（Xcode MCP，92.893 秒，0 编译错误）。iPad mini (A17 Pro)、iOS 26.5 上专项单元测试先取得 4 项通过：页面安全边界、键盘非对称安全区、键盘 RTL 切换及语义方向；旧集合视图方向测试因在首次布局前查询视图而失败，补上声明式宿主的首次布局步骤后单独重跑通过。原始结果分别为 `Test-Demo-2026.10.31_17-34-31-+0800.xcresult` 和 `Test-Demo-2026.10.31_17-45-22-+0800.xcresult`，这 5 项均已验证通过。

五页面 UI 回归尚未验收：iPhone 17 Pro 运行停在启动黑屏，日志报告应用空闲通知未收到、搜索框无法查询；停止后，`Test-AdaptiveNavigationRegression-2026.10.31_17-53-52-+0800.xcresult` 记录 0 通过、1 取消失败（`Testing was canceled`），不能算布局断言失败或通过。切换并确认 iPad mini 后，新请求被 Xcode 的“Replace test?”弹窗阻塞，未产生新的测试结果；退出弹窗后 MCP 日志查询也未返回。保留专项 UI 用例，待 Xcode 测试通道恢复后串行验证五页面、键盘输入／收起／旋转与 iPhone 返回导航。

## 全量布局改动复审（2026-10-31，动态窗口）

复审范围为当前工作区所有未提交的布局、导航及配套测试改动，保留既有业务和 SDK 条件编译改动。

| 区域 | 结论与处理 |
| --- | --- |
| Tab / Split / 原生列表 | 保留 UIKit 容器负责分栏和折叠；不按设备宽度自行切换层级。保留页面身份、搜索状态和原生返回行为；需串行导航回归确认。 |
| Dashboard / Frame 实验室 | 使用 `ViewThatFits` 在布局测量阶段选择宽／窄组合；900 点表示双列内容的设计下限，不是设备宽度推测。Frame 选项区不再接受推算的 `pageWidth`，改用自身提议选择排列；滚动边距由 `contentMargins` 管理。 |
| 礼物面板 / 用户卡片 | 删除基于控制器根宽度的预先测高。新增 Demo 层 `ContentFittingScroll`，在同一实际宽度提议下测量内容并限制视口高度；空间不足时滚动。礼物面板底部安全区仍由其操作区消费，避免背景离开底边。 |
| 语音房 | 舞台始终使用稳定的滚动宿主，按实际剩余提议限制最大高度；不再用根视图高度推算滚动视口。消息区可收缩，主体最大宽度统一为 720，避免宽度断点造成跳变。 |
| 键盘示例 | 保留底部对齐，改为可收缩的滚动内容；顶部与左右按真实安全区留白。键盘出现后滚至底部，短窗口下仍可到达输入框及提交按钮。 |
| 照片选择器 | UIKit 子控制器继续用原生约束，工具栏使用固有尺寸及语义方向约束；移除手工 frame 分配。面板是否贴底依据实际坐标转换结果，不再以小于 600 点推断。 |
| 聊天输入与文档卡片 | 保留实际内容视口高度与文本宽度变化驱动的测量、有限最大卡片宽度；未恢复屏幕尺寸兜底。 |
| Profile / 表单 / 几何 / 本地化 | 保留可收缩最大宽度、滚动内容边距、实际容器参照宽度及 Kit 宿主；不新增固定侧栏宽度补偿。 |
| SDK 兼容 | 保留 `#if compiler(>=6.4)` 与运行时 availability 组合，不因布局调整改变兼容策略。 |

API 能力说明：垂直 `ScrollView` 的现有语义是填满收到的视口提议，尚无公开的“自然高度与可用高度取较小值”选项。Demo 的 `ContentFittingScroll` 只补充该测量策略，并复用 Kit 滚动宿主；未改变库的默认滚动语义，也未使用设备尺寸估算。后续若多个项目需要，可考虑把该策略作为显式选项加入库并补足安全区／测量测试。

新增同一实例连续缩放回归，覆盖滚动视口自然高度／高度上限、Dashboard 宽窄排列及侧栏安全区、Frame 控件边界与选择状态、键盘短容器可达性。语法检查与 `git diff --check` 已通过。本轮通过 Xcode MCP 构建应用及测试包，`GetBuildLog` 均确认成功、0 编译错误。不能沿用上一轮通过结果作为本轮运行验收。


本轮环境与执行记录：

- `AdaptiveNavigationRegression` 的 MCP 清单把单元测试标记为禁用（仅 4 项 UI 用例启用）；切换 `Demo` Scheme 后 767 项单元测试均可选。本轮明确选择四项 `AppNavigationTests` 动态布局用例，按串行请求执行。
- iPad 首轮 `Test-Demo-2026.10.31_18-49-03-+0800.xcresult`：测试包构建成功，但启动日志停在 `TESTMANAGERD_SIM_SOCK` 查询，应用未启动。停止后结果为 0 通过、1 次 `Testing was canceled`，不是布局断言失败。
- 重启 iPad mini 和重新打开 Simulator 后，仍出现 `Unable to boot the Simulator`。CoreSimulator 日志在 19:08:46 记录 `Failed to start launchd_sim: could not bind to session`、`launchd failed to respond`（POSIX 60）。第二轮 `19-07-33` 请求在确认设备无法启动后停止，MCP 返回 `Test execution was cancelled.`。
- 礼物面板原有三处固定滚动视图数量断言改为检查业务滚动区有实际尺寸且仍在宿主内；保留原有边界、列数和滚动行为检查。
- iPhone 17 Pro 串行运行 `Test-Demo-2026.10.31_19-14-12-+0800.xcresult`：MCP 返回四项均 `notRun`，0 通过、0 断言失败。控制台明确报告 `Failed to prepare device` / `Timed out trying to boot simulator after waiting 60.00s.`，并非布局断言结果。
- 当前运行验收被模拟器启动故障阻塞。真实 iPad 窗口拖动缩放、分栏折叠／恢复、iPhone 返回导航及 Tab 图文对齐均未完成本轮验收；需恢复 Simulator 启动后，先运行四项动态布局测试，再串行执行相关页面单元测试和 `AdaptiveNavigationUITests`。未清除模拟器数据。

## 恢复执行后的回归（2026-10-31 晚间）

通过 Xcode 官方 `mcpbridge` 恢复 MCP 调用，构建与测试仍交由 Xcode 执行，测试请求串行提交。

- iPhone 17 Pro / iOS 26.5：`Test-Demo-2026.10.31_19-33-08-+0800.xcresult` 的四项动态布局测试中，滚动视口、Dashboard、Frame 实验室通过；键盘短窗口测试发现提交按钮实际高度约 34.33 点，小于外层布局框的 50 点。
- 将键盘页输入框、按钮从仅横向伸缩改为 `.resizable()`，再分别指定 44、50 点高度。该调整采用 Kit 声明式布局，不增加设备或窗口尺寸推测。新增输入框实际高度断言，保留按钮及短窗口可达性断言。
- `Test-Demo-2026.10.31_19-44-35-+0800.xcresult` 单独复测键盘用例，1 通过、0 失败；四项动态布局专项均已有通过结果。README 补充布局框与 UIKit 控件固有尺寸的区别。
- 新增 `AdaptiveNavigationUITests/testTabSelectionKeepsItemsAligned()`，检查各 Tab 选中态、点击区域及横竖屏项目边界，并保存截图用于人工核对图标和文字。项目边界断言不能代替图文基线的视觉验收。
- 上述单元测试结果不代表 iPad 系统窗口拖动缩放、iPhone 导航或 Tab 视觉验收已完成。
