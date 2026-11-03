# 动态容器布局审查（2026-11-02）

## 范围与判定原则

检查 Sources 的布局提议、安全区、容器相对尺寸、宿主环境、滚动视口、控制器承载和集合布局失效路径，以及 Demo 的 26 个目录入口、根 Tab / Split / Navigation、聊天、语音房和浮层。布局以父级提议或当前容器的实际几何为依据。侧栏的 UIKit 最小／最大设计宽度不用于推算详情宽度。

源码审查、控制器尺寸测试和系统窗口交互是不同证据。测试中调整 UIWindow / UIView 的尺寸不等于完成 iPad 系统分屏或自由窗口拖动验收；目录遍历也不等于每个页面的全部交互均已验证。

开始时 Git 工作区干净。本次不提交 Git，不更改业务 ViewModel、导航层级、依赖版本或最低系统版本。

## 问题与修复

| 位置 | 分类与根因 | 修复 |
| --- | --- | --- |
| `ContentFittingScroll` | Demo 辅助布局错误：直接测量内部 content，跳过滚动宿主的 contentInset 和 containerRelativeFrame / safe-area 上下文；自然高度可能与最终内容高度不同。 | 自然高度和受限视口都通过同一个 `ScrollView` 节点测量，继续复用稳定的滚动视图。 |
| `RoomHeaderView` | 示例使用错误：`body` 用旧 `bounds.width` 决定是否构建宽排列，导致相同提议的测量结果依赖此前布局。 | 保留 `ViewThatFits`，将单行排列的 360 点设计下限声明为候选布局的 minWidth，由当前提议选择。 |
| `GiftSheetView` | 示例使用错误：仅在放置时切换紧凑尺寸；父级测量自然高度时仍使用旧字号、间距和网格高度。 | 测量和放置都按当前宽度及实际水平安全区更新尺寸参数；不重建 ViewModel 或清空选择。 |
| `AnimatedKeyboardResponsiveView` | 示例使用错误：直接使用键盘相交高度，悬浮／分离键盘也会抬升整块底部内容。 | 使用 Kit 的 `.followsDockedKeyboard()` 协调器，结合 UIKit keyboardLayoutGuide 判定；保留原有底部留白和诊断信息。容器变化时重新解析键盘几何。 |
| `ViewThatFitsDemoViewController` | 示例使用错误：允许指定 320 点实验画布，在 320 点窗口扣除页面边距后会越界。 | 增加稳定的横向画布滚动宿主，视口受当前提议限制，画布保留用户指定尺寸和实验选择语义。 |
| `SwiftUILocalizationBridgeDemoViewController` | 示例能力缺口：正文和弹窗没有滚动回退；宽屏没有阅读宽度限制，NavigationView 未声明单列呈现。 | SwiftUI ScrollView + 可收缩的 720 点最大阅读宽度；弹窗使用 stack 导航样式。UIKit 传递完整父容器，SwiftUI 负责安全区。 |
| `QuickLayoutKeyboardAvoider` / `QuickLayoutScrollView` | 框架缺陷：避让器仅在键盘事件到来时更新 inset；无新通知的容器缩放或安全区变化会留下旧避让量。 | 新增 `refreshGeometry()`，使用最近键盘上下文重新转换到当前容器。Kit 滚动宿主在布局完成后自动刷新；普通 UIScrollView 的宿主可显式调用。保持原有相交与安全区策略。 |
| `ContentMargins` / `QuickLayoutKeyboardAvoider` | 框架缺陷：避让器用当前滚动轴的指示器增量处理两个轴；垂直表单会给水平指示器误加同样的 margin。 | 分别读取、扣除和恢复 vertical / horizontal 已应用增量，不改变内容 margin 或键盘策略。 |
| `QuickLayoutView` / `QuickLayoutScrollView` | 框架失效传播缺口：子宿主放置后更新物理安全区会改变自然尺寸，但外层自然高度滚动视口可能继续使用旧测量值。 | 子宿主安全区变化和滚动内容尺寸变化向父级发布测量失效。使用多层自然高度回归验证传播，不在面板补偿固定高度。 |
| `MainViewController` | 示例导航呈现错误：iPad 展开目录侧栏的大标题与右侧工具按钮重叠，实际截图可见标题遮挡。 | 按真实 UISplitViewController 折叠状态切换原生行内／大标题；展开侧栏行内显示，单列恢复大标题。不参与内容宽度计算。 |
| `SeatView` | 示例尺寸约束错误：分数徽章宽度固定等于头像，扣掉 padding 后会不必要地缩小本可放下的积分文字。 | 头像宽度改为徽章的 minWidth，继续允许容器约束文字宽度，并保留已有字号缩放下限。 |

SwiftUI 桥接页继续使用 SwiftUI 与原生 UIHostingController 约束，因为页面本身用于验证 SwiftUI 本地化环境。原生 Tab / Split / Navigation、系统照片选择器、列表和 Popover 保留 UIKit 的容器／呈现职责，不增加 QuickLayoutKit 包装。

## 安全区与失效责任

- 普通 Kit 页面使用 QuickLayoutHostingController / QuickLayoutView；可滚动正文优先由 contentMargins 和滚动宿主管理视口边距。
- `ContentFittingScroll` 保留 `.never` 自动 inset 策略。调用方决定外层安全区；礼物面板背景延伸到底边，内部操作区消费底部安全区。
- 键盘示例由内部 QuickLayoutView 的停靠协调器发布键盘高度；底部布局只应用一次该遮挡，外部控制器不再做键盘位移。
- 滚动键盘避让由 `QuickLayoutKeyboardAvoider` 维护内容和指示器 inset 增量。尺寸变化不需要伪造键盘通知；单纯滚动且避让量不变时不会重新将输入框拉回可见区域。
- 聊天维持列表全容器 frame，通过 viewportInsets 避让输入栏和系统区域，并在尺寸变化时按消息身份恢复阅读位置。
- 集合／瀑布流布局使用 layout environment 的有效尺寸；阅读宽度使用 maxWidth，保留窄容器收缩能力。
- 控制器与视图负责布局，ViewModel 保留内容与选择状态职责。

## API 最小复现与建议

自然高度滚动辅助布局的复现条件：外层宿主宽 1000，滚动视口 maxWidth 620，内容为多行文本并使用 `containerRelativeFrame(.horizontal)`，滚动视图还有左右 16、上下 10/20 的 contentInset。若直接测量 content，其宽度上下文来自外层，且高度未包含滚动边距；真正放入 ScrollView 后文本重新换行，视口自然高度不一致。

回归入口：`AppNavigationTests/fittingScrollMeasuresInsideItsOwnContainerContext()`。它检查同一实例在 1000 → 320 → 600 → 1000 点变化时，文本宽度和自然视口高度与滚动内容一致。

这属于 Demo 对 Kit API 的使用错误，并未证实库的 ScrollView 测量算法有缺陷。当前公开 ScrollView 在滚动轴上接受有限视口提议，这是已有语义；“自然高度与可用高度取较小值”仍由 Demo 辅助布局提供。若要提升公开 API，可增加明确的 fit-content 视口策略，同时覆盖 inset、安全区、容器相对尺寸、无界提议与动态缩放，避免改变现有默认语义。

键盘避让器的框架缺陷最小复现：给 320×480 的滚动视图设置 bottom inset 10，应用 `(x: 0, y: 360, width: 320, height: 120)` 的键盘上下文，bottom inset 为 130。保持键盘上下文不变，仅把容器高度改成 300，旧实现仍保留 130；正确结果为 10。随后改成 430 / 480 时应得到 80 / 130。回归入口：`DemoTests/keyboardAvoiderRecalculatesInsetsWhenContainerResizesWithoutNotification()`，同时覆盖 Kit 自动刷新和 UIKit 显式刷新。

```swift
let avoider = QuickLayoutKeyboardAvoider(scrollView: scrollView)
// 持有 avoider。QuickLayoutScrollView 自动刷新；普通 UIScrollView 的宿主：
override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    avoider.refreshGeometry()
}
```

该修复在框架层处理几何失效，没有在页面重复补偿 inset。默认避让器原有的相交策略保持兼容；示例中需要“仅停靠键盘抬升内容”时使用现有 `.followsDockedKeyboard()` API。

自然尺寸失效传播最小复现：外层 `QuickLayoutView` → `ContentFittingScroll` → 内层 `QuickLayoutView`，内层为 40 点高的内容并消费 bottom safe area。仅把内层安全区从 0 改为 34 / 58 / 0，不改变外层 frame，不手动标记外层布局，视口应更新为 74 / 98 / 40。对应 `AppNavigationTests/nestedSafeAreaChangeInvalidatesNaturalScrollViewport()`。UIKit 在放置后解析物理安全区，回归需消费这些向外传播的后续布局失效。

回归中的旧假设也作了修正：语音房短窗口已有独立舞台滚动视口，不能用 UIScrollView 数量断言布局；公屏应衔接舞台视口而非完整舞台内容底边。礼物面板受 620 点阅读宽度限制，分类横向滚动属于设计行为，改为验证末项可达。没有放宽几何误差容限。聊天顶部 inset 测试保留同一消息屏幕位置的 0.5 点断言，移除“绝对 contentOffset 永不变化”的重复假设：estimated 行物化时 UIKit 会同步修正行位置和滚动偏移；首轮失败时同一消息屏幕位置断言已通过，聊天生产代码无需补偿。Profile 的滚动测试改为检查按实际内容范围钳制后的底部偏移；iPad 高视口能容纳全部内容时，滚动到底仍停在起点是正确行为。

## 本轮验证记录

当前环境：Xcode 的 iOS 27.2 SDK / Simulator。首轮构建被已存在的 SwiftProtobufPlugin 指纹变更提示阻塞；用户明确授权信任并启用后继续通过 Xcode MCP 构建。未关闭插件验证。

历史 iOS 26.5 结果不算作本轮证据。

- Xcode MCP `BuildProject(buildForTesting: true)`：应用及 DemoTests 测试包阶段性构建成功，0 编译错误，272.777 秒。首轮完整依赖编译后发现新增测试的 `.infinity` 类型推断歧义，修正为 `CGFloat.infinity` 后取得本次成功结果。此结果早于后续键盘避让器框架修复，也未包含 DemoUITests，不能代替最终构建。
- iPad mini (A17 Pro) 原生 Xcode MCP 首轮：测试停在 Launching DemoTests，无用例标准输出，诊断日志记录运行器启动失败；在 Xcode 停止遗留测试动作后，原始 `Test-Demo-2026.11.02_11-02-04-+0800.xcresult` 摘要为 total 0 / passed 0 / failed 0 / result unknown。这是环境／测试启动问题，不算布局断言结果。
- XcodeBuildMCP 通道重试：显式关闭并行测试，工具在 300 秒超时；实际仍处于 build-for-testing，没有运行用例。核对命令属于本轮任务后停止该遗留构建。其编译设置与原生 Xcode 不同，后续切回原生通道触发依赖重新编译。
- 原生 Xcode MCP 在 iPhone 17 上重新构建成功（含键盘框架修改，0 编译错误）。导航／动态布局套件：**16 通过，1 跳过，0 失败**。跳过项为要求 iPad 的分栏展开／折叠测试。MCP 初次读取结果包时提示尚未写完；稍后直接用 `xcresulttool` 核对得到 `Passed`、total 17 / passed 16 / skipped 1 / failed 0。
  - 结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-Demo-2026.11.02_11-18-26-+0800.xcresult`
  - 构建日志：`/var/folders/_b/4kvsp2_s0ss21dbxf2_s7bnh0000gn/T/ActionArtifacts/default/GetBuildLog/1E722C52-668F-4550-93C8-D89DE45CD080.txt`
- 最终 iPhone 17 导航与动态布局组：**17 通过、1 跳过、0 失败**（18 项；包含新增自然尺寸失效传播最小回归）。
  - 结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-Demo-2026.11.02_11-50-42-+0800.xcresult`
- 最终 iPhone 17 相关布局组：**116 通过、0 失败、0 跳过**（原始 xcresult 的方法级统计；MCP 参数结果展示为 117 个通过项）。覆盖键盘、宿主环境、滚动尺寸与边距、容器相对尺寸、代表控制器、RTL、Profile、Dashboard、Frame Lab、语音房礼物／充值／麦位等；滚动测量测试包含 1152 次 SwiftUI 对照。
  - 结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-Demo-2026.11.02_11-52-53-+0800.xcresult`
  - 首轮曾记录 7 个失败结果，分别触发指示器轴向修复、自然尺寸失效修复、徽章尺寸修复和旧视口断言更新；保留首轮证据，不计作最终通过结果。
- 集合／瀑布流组：**12 通过、0 失败**，包括大字体、阿拉伯语与不对称安全区；检查了测试产生的横向瀑布流大字体和阿拉伯语截图。
  - 结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-Demo-2026.11.02_11-55-01-+0800.xcresult`
- 聊天视口重跑：**6 通过、0 失败**（原始 xcresult 方法级统计；MCP 参数结果展示为 8 个通过项）；附件分页：**4 通过、0 失败**。统计以原始 xcresult 的摘要为准，MCP 参数展开结果不重复累加。
  - 视口结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-Demo-2026.11.02_11-58-58-+0800.xcresult`
  - 分页结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-Demo-2026.11.02_12-00-28-+0800.xcresult`
- 最终 Xcode MCP `BuildProject(buildForTesting: true)`，`AdaptiveNavigationRegression` / iPhone 17：**构建成功，0 错误，31.918 秒**。日志确认包含 `DemoUITests` 和新增 `AdaptiveNavigationUITests.swift` 编译。
  - 构建日志：`/var/folders/_b/4kvsp2_s0ss21dbxf2_s7bnh0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261102-120950.txt`
- iPad mini 第二轮导航尝试在应用安装后停留于测试启动阶段，控制台无用例输出，结果包未写完；停止本工程遗留动作并关闭该模拟器，保留数据。后续改用预构建 xctestrun 的 XcodeBuildMCP 通道重试，不再触发依赖编译。
- iPhone 17 UI 回归：**6 通过、0 失败**。实际执行横竖屏、详情边界、键盘提交、推入／返回／重新进入、Tab 对齐、聊天草稿保留、SwiftUI 弹窗和 Geometry 演示。
  - 原始结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-AdaptiveNavigationRegression-2026.11.02_12-10-09-+0800.xcresult`
  - 导出截图：`/tmp/quicklayout-adaptive-audit-20261102/iphone-ui/manifest.json`。已查看横屏键盘页、横屏 SwiftUI 单列弹窗、竖屏语音房；语音房舞台在有限视口内独立滚动。
- iPad 预构建导航尝试：应用启动成功，但 Swift Testing 筛选未执行任何用例；工具显示成功退出，原始结果却是 total 0 / result unknown，因此不计为通过。原始结果：`/tmp/quicklayout-adaptive-audit-20261102/ipad-navigation.xcresult`。重启后回到原生 Xcode 单元测试通道。
- iPad mini (A17 Pro) 导航／动态布局最终重试：**18 通过、0 失败、0 跳过**。包括原生分栏展开／折叠、返回目录再进入、实例和选择保留，以及目录页面宽窄尺寸往返。
  - 结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-Demo-2026.11.02_12-22-24-+0800.xcresult`
- iPad mini (A17 Pro) 相关布局组：**116 通过、0 失败、0 跳过**（原始 xcresult 方法级统计；参数展开为 117 个通过项）。首轮仅 Profile 的旧测试要求底部偏移必须离开起点，修正其高视口假设后串行重跑整个布局组通过。
  - 结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-Demo-2026.11.02_12-25-46-+0800.xcresult`
- iPad UI 首轮：4 通过、2 失败。原生顶部 Tab 的 AX 视觉边界高度为 36 点，不能据此认定系统命中区域不足 44 点；改为验证真实点击选中、同高、可见边界。目录多次搜索在清空后失去输入焦点，测试增加清空后重新点击文本区域；该现象尚不足以认定为 Kit 布局缺陷。另从导航截图发现侧栏大标题被工具按钮遮挡，已修复原生标题呈现并增加折叠／展开回归。
  - 首轮结果：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-AdaptiveNavigationRegression-2026.11.02_12-27-24-+0800.xcresult`
- 侧栏标题修复后，iPad 导航组再次 **18 通过、0 失败、0 跳过**，新增展开行内标题／折叠恢复大标题断言。
  - 结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-Demo-2026.11.02_12-35-09-+0800.xcresult`
- 标题修复后 iPad UI：**6 通过、0 失败、0 跳过**。已查看最终竖屏目录／详情截图，目录标题完整且不再被工具按钮遮挡；横屏键盘页的输入与提交按钮均位于详情列内。
  - 结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-AdaptiveNavigationRegression-2026.11.02_12-36-40-+0800.xcresult`
  - 截图索引：`/tmp/quicklayout-adaptive-audit-20261102/ipad-ui/manifest.json`。
- 侧栏标题修复及 Profile 断言调整后，iPhone 导航／Profile 补跑：**23 通过、1 跳过、0 失败**（24 个方法；MCP 参数展开为 25 项）。跳过项仍为 iPad 分栏展开／折叠专属用例。
  - 结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-Demo-2026.11.02_12-43-58-+0800.xcresult`
- 侧栏标题及 UI 断言调整后，iPhone 受影响的 UI 补跑：**3 通过、0 失败**（详情列边界／键盘提交、导航旋转及推入返回、Tab 选中与对齐）。此前完整相关 UI 组 6 项通过；本次仅重跑受影响项。已核对最终 iPhone 目录截图，大标题与底部原生 Tab 保持原有呈现。截图索引：`/tmp/quicklayout-adaptive-audit-20261102/iphone-ui-final/manifest.json`。
  - 结果包：`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/Test-AdaptiveNavigationRegression-2026.11.02_12-45-38-+0800.xcresult`
- 所有代码修改完成后的最终 Xcode MCP `BuildProject(buildForTesting: true)`：**成功，0 编译错误，4.691 秒**，scheme `AdaptiveNavigationRegression`，destination `iPhone 17`。
  - 构建日志：`/var/folders/_b/4kvsp2_s0ss21dbxf2_s7bnh0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261102-125009.txt`
- `git diff --check` 通过；22 个修改／新增文件全部保留在工作区，未提交 Git。

## 后续验证更新

搜索焦点与真实系统窗口的后续修复／验证见 [SearchFocusAndWindowValidation-2026-11-02.md](SearchFocusAndWindowValidation-2026-11-02.md)。已移除清空后再次点击搜索框的测试绕行，修复独立清空动作；完成真实自由窗口连续拖动和状态保留回归。下方记录保留初轮验收时的边界，最新状态以补充报告为准。

## 初轮覆盖边界与未完成项

已执行的尺寸验证包括：26 个目录入口使用同一控制器在 1024 → 768 → 600 → 375 → 320 → 1366 → 1024 点之间往返变化；自然高度滚动、礼物面板、Frame Lab、Dashboard、键盘场景另有宽高和安全区变化断言。导航组验证原生分栏展开／折叠和状态保留。UI 组验证模拟器实际横竖屏、Tab 切换和导航。

这些测试没有完成以下系统／硬件验收，不能据此宣称整个设备矩阵全部通过：

- iPad 系统分屏多任务、自由窗口拖动的连续中间帧、不同应用并排及系统窗口按钮操作。
- 真机鼠标／触控板指针、硬件键盘、系统悬浮／分离键盘拖动；当前键盘几何策略有自动化回归，实际 UI 使用模拟器停靠键盘。
- 全目录每种 Popover、照片选择器和工具栏的完整交互矩阵；本轮覆盖源码与相关现有回归，不等于全部呈现路径的手动验收。
- 原生搜索栏清空后曾出现焦点丢失，当前 UI 回归通过重新点击文本区域继续输入；没有证明该现象仅由自动化造成，真实触摸／硬件键盘的无额外点击输入仍待复核。
- 全目录 RTL／最大辅助字体、VoiceOver，以及旧 iOS 运行时和真机。RTL／大字体已覆盖相关几何、集合和瀑布流回归。

本轮运行的是与修改相关的测试组，不是仓库全部测试。各组串行执行；未执行的场景不计作通过。未新增屏幕／机型推算内容宽度，未改动业务状态所有权。

## 修改文件

- `Demo/Demo/Features/Keyboard/AnimatedKeyboardResponsiveView.swift`
- `Demo/Demo/Features/Layout/ViewThatFitsDemoViewController.swift`
- `Demo/Demo/Features/Main/MainViewController.swift`
- `Demo/Demo/Features/Localization/SwiftUILocalizationBridgeDemoViewController.swift`
- `Demo/Demo/Features/VoiceRoom/Views/Gift/GiftSheetView.swift`
- `Demo/Demo/Features/VoiceRoom/Views/Header/RoomHeaderView.swift`
- `Demo/Demo/Features/VoiceRoom/Views/Seats/SeatView.swift`
- `Demo/Demo/Support/ContentFittingScroll.swift`
- `Demo/DemoTests/AppNavigationTests+DynamicLayout.swift`
- `Demo/DemoTests/AppNavigationTests.swift`
- `Demo/DemoTests/ChatFullscreenLayoutTests.swift`
- `Demo/DemoTests/DemoTests+Keyboard.swift`
- `Demo/DemoTests/DemoTests+Profile.swift`
- `Demo/DemoTests/DemoTests+VoiceRoomGift.swift`
- `Demo/DemoTests/DemoTests+VoiceRoomSeatLayout.swift`
- `Demo/DemoUITests/AdaptiveNavigationUITests.swift`
- `README.md`
- `Sources/QuickLayoutKit/QuickLayoutKitUIKit/ContentMargins.swift`
- `Sources/QuickLayoutKit/QuickLayoutKitUIKit/QuickLayoutKeyboard.swift`
- `Sources/QuickLayoutKit/QuickLayoutKitUIKit/QuickLayoutScrollView.swift`
- `Sources/QuickLayoutKit/QuickLayoutKitUIKit/QuickLayoutView.swift`
- `Docs/AdaptiveLayoutAudit-2026-11-02.md`
