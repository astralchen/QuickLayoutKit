# 默认安全区行为验证

验证日期：2026-11-10。开发分支：`codex/default-safe-area`；起点：`77aa2ac45cc88db661b334f6a0892ea506094195`。以下结果来自 iPhone 18 Pro / iOS 27.2 模拟器，不能替代 iPad、Duo 或真机验证。

## 实现约束

- QuickLayout 检出目录保持干净，版本仍为 `62310c0a7f4ec43f3ea6ff89f3824ef6b23b2bb3`，包清单和依赖锁定文件没有修改。
- 默认消费容器安全区与停靠键盘区域；`ignoresSafeArea` 按区域、边缘恢复可用空间。
- `safeAreaPadding` 默认额外间距仍为 `0`；显式额外间距与 `contentMargins` 保持独立。
- 普通宿主、声明式滚动、原生列表和嵌套宿主分别验证安全区只消费一次。
- 新增实现注释、迁移说明与验证记录使用中文。迁移规则见 [默认安全区域迁移](DefaultSafeArea.md)。

## 自动化结果

各行是不同运行范围，包含交叉覆盖，不应将数量相加当作独立测试总数。

| 范围 | 结果 | 说明 |
| --- | --- | --- |
| QuickLayoutKit 包测试 | 194 通过，0 失败 | 包含新增的 4 项宿主投影、原生滚动和作用域隔离回归 |
| Demo 集成测试 | 115 通过，0 失败，3 跳过 | 导航、动态布局、Arrangement、内容配置、附件分页、GeometryReader、containerRelativeFrame、默认安全区 SwiftUI 对照、聊天全屏及键盘动画 |
| 最终 ApplicationTests 回归 | 227 通过，0 失败 | 明确排除下述已复现的既有座位断言问题 |
| SafeAreaPadding UI | 3 通过，0 失败 | 中文 LTR、阿拉伯语 RTL、旋转；每项遍历 10 种组合并检查末行可达性 |
| 最后一次 UI 复核 | 5 通过，0 失败 | SafeAreaInset 的 4 项交互测试，以及重新采集整屏截图的旋转测试 |

`DefaultSafeAreaParityTests` 保留原生 SwiftUI 容器安全区；Kit 一侧不添加补偿 padding。100 组几何配置覆盖默认布局及修饰符、固定尺寸与嵌套忽略、滚动外框与内容区域，组合 LTR/RTL、两种容器宽度和不对称安全区。另用实际系统软件键盘比较 6 种模式：默认、忽略容器、忽略键盘、忽略全部、嵌套默认、嵌套忽略键盘。比较的是实际视图几何，而非仅比较内部计算值。

UI 测试实际点击页面控件、切换语言、旋转设备、滚动至末行、在末行处展开插入栏、点击软件键盘输入并拖动收起。输入栏位置、动态高度、滚动边界和收起后的恢复状态均有断言。动画回归等待真实呈现层中间帧，仍要求位置严格处于起点与终点之间，瞬移不能通过。

## 截图复核

以下为最终 UI 运行直接导出的原始附件，没有裁剪或重绘。已逐张查看：横屏内容与安全区诊断边界相符；键盘出现时输入栏位于键盘上方；收起后输入栏恢复到页面底部系统栏之上。横屏滚动内容可以经过系统栏后方，内容 inset 负责保证滚动末端可见。

- [横屏默认布局](Validation/DefaultSafeArea/landscape-default.png)
- [软件键盘与输入栏](Validation/DefaultSafeArea/keyboard-visible.png)
- [拖动收起键盘后](Validation/DefaultSafeArea/keyboard-dismissed.png)

## 已知基线问题和未覆盖范围

`ApplicationTests/voiceRoomSeatLayoutsExpandOnIPadWidth()` 在 iPhone 上模拟 1200 × 1024 布局时，原有测试期待座位 104、宿主 192，实际得到 74、142。使用本分支起点编译的测试产品复跑，同样的 3 条断言失败，确认是既有基线问题。最终 ApplicationTests 回归明确排除此项，不将其计为通过，也没有为此改变 VoiceRoom 座位规则。

集成运行的 3 个跳过用例需要实际 iPad：`splitSafeAreaScenariosPreserveModifierContrast`、`splitDetailRespectsAsymmetricSafeAreaAcrossColumnWidths`、`splitCollapseAndExpansionPreserveSelectedController`。本次没有执行 iPad/Duo 设备姿态、真机、旧版 iOS、浮动或分离键盘的交互验证。

空滚动视图的交叉轴零理想尺寸继续遵循 Kit 既有契约；`safeAreaPadding` 的默认额外间距及 `safeAreaInset` 默认 spacing 继续为零。这些差异不纳入“与 SwiftUI 全部行为一致”的声明。

## 本地证据索引

结果包位于本机 `~/Library/Developer/XcodeBuildMCP/workspaces/QuickLayoutKit-dfd3cdcfdbe6/result-bundles/`，对应日志位于同级 `logs/`。时间戳为 UTC。

| 证据 | xcresult 文件名 |
| --- | --- |
| 包测试 194 项 | `test_sim_2026-11-10T05-46-20-716Z_pid42007_335afbe5.xcresult` |
| 集成 115 通过、3 跳过 | `test_sim_2026-11-10T05-46-52-478Z_pid42007_c1836955.xcresult` |
| SafeAreaPadding UI 3 项 | `test_sim_2026-11-10T05-50-50-583Z_pid42007_c094a53f.xcresult` |
| 最终 UI 5 项及上述截图 | `test_sim_2026-11-10T06-00-04-805Z_pid42007_c8fc1601.xcresult` |
| 最终 ApplicationTests 227 项 | `test_sim_2026-11-10T06-05-39-416Z_pid42007_ff1a4cb2.xcresult` |
| 起点测试产品复现座位断言 | `test_sim_2026-11-10T04-50-57-378Z_pid42007_67c2be83.xcresult` |

SafeAreaPadding 的 3 项 UI 结果所在运行还包含 ApplicationTests；该次应用测试的一个固定延时动画断言失败，不能将整个结果包标为通过。随后该断言改用现有呈现层等待工具，保留动画中间态和完成态检查，单独复核及最终 227 项应用回归均通过。


## 原生列表补充验证（2026-11-10）

首页截图暴露了上一轮 Demo 迁移的遗漏：直接作为 UIView 叶子放置的原生集合视图被限制在安全区内。新增 `List(collectionView)` 与 `List(tableView)` 入口，保留现有 ListKit 数据源和复用，默认填满父布局提供的有限空间，并复用滚动视口与内容 inset 的安全区规则。首页与瀑布流已迁移；普通内容配置 Table/Collection 页面本身使用 UIKit 全尺寸容器，不经过 Kit 默认安全区包装。

新增 `NativeListSafeAreaTests` 直接比较原生 SwiftUI.List 与 UITableView 的视口，检查 LTR/RTL、不对称安全区、首尾边距、重复重排、嵌套宿主、`.never`、额外间距及声明移除。另检查首页完整视口、补充视图在滚动中的稳定自然高度、忽略安全区后项目内部不重新避让。

系统键盘对照由 6 种扩展到 8 种，增加原生列表 `.never` 和 `.always` 两种 inset 策略。新增首页 UI 测试实际执行中文/阿拉伯语滚动、末行可达、旋转、搜索输入与清空。初次截图还暴露了分组标题重复计入窗口安全区的问题；已通过原生列表内容边界隔离修复，不通过修改标题固定高度掩盖。

最终结果和截图以本节补充记录为准；前面的结果包保留为上一阶段证据。


- 最终 List 集成回归：**56 通过、0 失败、3 跳过**。范围为 `NativeListSafeAreaTests`、`DefaultSafeAreaParityTests`、`AppNavigationTests`、`ContentConfigurationCollectionTests`。结果包：`test_sim_2026-11-10T06-34-32-576Z_pid42007_2ea4355b.xcresult`。
- 7 项新增 List 测试同时覆盖显式列表与业务自行管理的原生滚动视图，两者的安全区所有权不会互相覆盖。分组标题不再随滚动位置改变自然高度，瀑布流复用尺寸回归通过。

- 最终应用与首页交互回归：**229 通过、0 失败**，其中 ApplicationTests 227 项、NativeListSafeAreaUITests 2 项。继续明确排除上文已复现的既有座位断言问题。结果包：`test_sim_2026-11-10T06-37-32-536Z_pid42007_44aab9b3.xcresult`。
- 最终包测试：**194 通过、0 失败**。结果包：`test_sim_2026-11-10T06-40-49-175Z_pid42007_b0d878be.xcresult`。
- 最终截图已逐张复核：[滚动时经过系统栏后方](Validation/DefaultSafeArea/list-scrolling.png)、[最后一行完整可见](Validation/DefaultSafeArea/list-last-row.png)、[阿拉伯语横屏](Validation/DefaultSafeArea/list-landscape-rtl.png)。分组标题附近的异常大空白已消除。
- 验证结束后重新构建并启动 Demo 中文首页。QuickLayout 源码与锁定版本保持不变，`git diff --check` 通过。iPad/Duo、真机与旧版 iOS 仍未补跑。


## 照片面板与输入栏间距补充验证（2026-11-10）

通过实际“键盘 → 附件菜单 → 照片”路径复现大空白。原因是聊天页缓存的键盘内容高度已扣除页面底部安全区，而系统 Sheet 的自定义档位只排除窗口底部安全区。本机页面为 83 点、窗口为 34 点，直接复用缓存高度会让面板少 49 点；随后几何校准保留该差值，使输入栏与面板分离。

`PhotoPickerController` 在系统解析档位时读取当前页面与窗口的安全区，按 `内容高度 + max(0, 页面底部安全区 - 窗口底部安全区)` 换算，再应用原有最小高度和系统最大高度。没有写死标签栏高度，没有添加负间距；原有遮挡协调器保持不变。定位期间观测到的照片面板校准偏差由约 52 点降至约 5 点，剩余差值来自系统面板呈现几何。

最终针对性运行：**15 通过、0 失败、0 跳过**，范围为完整 `ChatFullscreenLayoutTests`、7 项照片面板/键盘遮挡测试及新增附件菜单 UI 测试。参数化宿主测试包含直接打开与键盘后打开两种路径；UI 测试实际点击附件菜单、打开系统照片面板、向下拖动关闭、点击输入框切回软件键盘。切回键盘后，输入框底边与切换前相差不超过 1 点。结果包：`test_sim_2026-11-10T07-01-24-311Z_pid42007_c336e689.xcresult`。

最终运行的四张整屏原始附件已逐张复核：[直接打开照片](Validation/DefaultSafeArea/photo-picker-direct.png)、[从键盘打开照片](Validation/DefaultSafeArea/photo-picker-from-keyboard.png)、[拖动关闭](Validation/DefaultSafeArea/photo-picker-dismissed.png)、[切回键盘](Validation/DefaultSafeArea/photo-picker-return-keyboard.png)。照片截图采集时系统图库仍显示加载状态，本次验证的是面板及输入栏的布局和交接，不将其作为照片加载、选择或发送通过的证据。验证设备仍限于 iPhone 18 Pro / iOS 27.2 模拟器。


## Frame 实验室左上角残留滑块头（2026-11-10）

截图中的白色块来自引导实验收起更多参数后，未选中宽屏候选中的宽度滑块行。`ViewThatFits` 将该行收为零尺寸，UIKit 内部的滑块仍有 44 点高度，行默认不裁剪子视图，因此滑块头越界绘制到滚动内容左上角。修复只为 Demo 的 `FrameLabSliderRow` 开启边界裁剪，保留控件实例与展开后的正常布局，不修改 QuickLayout 或通用布局 API。

新增回归先在修复前失败，记录到行 frame `(0, 12, 0, 0)`、滑块 frame `(8, -22, 0, 44)`。修复后最终运行 **11 通过、0 失败、0 跳过**：9 项 Frame 实验室应用测试，以及中文收起／展开／拖动／再次收起／恢复值、阿拉伯语顶部前缘对齐的 2 项实际 UI 测试。现有应用测试覆盖两种模式、三语、窄宽尺寸、九种对齐、辅助功能字号及控件复用。设备为 iPhone 18 Pro / iOS 27.2 模拟器；宽尺寸为程序化窗口测试，未运行实际 iPad。

结果包：`test_sim_2026-11-10T07-52-27-653Z_pid42007_6b123e11.xcresult`。已逐张查看原始附件：[默认收起](Validation/DefaultSafeArea/frame-top-leading-collapsed.png)、[展开并拖动](Validation/DefaultSafeArea/frame-top-leading-expanded.png)、[再次收起](Validation/DefaultSafeArea/frame-top-leading-recollapsed.png)、[阿拉伯语前缘](Validation/DefaultSafeArea/frame-top-leading-rtl.png)。左上角白色块已消失，展开时完整滑块正常可见。


## ViewThatFits 统一管理候选可见性（2026-11-10）

本节替代上一节的 Demo 局部裁剪方案。已撤回 `FrameLabSliderRow.clipsToBounds`，由 Kit 的 `ViewThatFits` 在实际应用节点时隐藏未选中分支独占的视图，并继续将其折叠为零尺寸。选中分支在放置前恢复原有隐藏值，内层候选随后独立提交，因此外层不会强行显示内层未选中的内容。布局测量、候选试探和视图提取都不提交隐藏状态；缓存节点携带各自的提交信息。

Kit 的普通宿主、按钮、效果视图、列表宿主及内容视图通过共同放置入口管理恢复，滚动宿主在实际 applyFrame 时接入同一作用域。记录弱引用视图与宿主，按记录身份检查所有权，处理声明移除、跨宿主转移和宿主释放；业务原本隐藏的视图保留原状态。

已检查现有使用点：

| 使用位置 | 需要保护的行为 |
| --- | --- |
| Frame 实验室页面与对齐选项区 | 未选中宽屏候选的滑块行完全隐藏；展开后恢复，嵌套九宫格正常 |
| 计数器操作区与自适应按钮 | 横纵布局共享按钮；图标／文字备用项正确切换 |
| Dashboard、资料页统计与操作区 | 同一组视图在横纵布局中复用，不能被另一候选误隐藏 |
| 每日记录统计 | 横纵候选共享文字，不增加重复实例 |
| 语音房头部 | 外层横纵候选与内部操作区候选嵌套，保留各层选择 |
| 内容配置瀑布流 | 纵向适配中多次测量共享标题与正文，测量不改变当前显示 |
| ViewThatFits 示例 | 三个独立候选中只有最终选中项可见 |

包级最终运行 **202 通过、0 失败、0 跳过**，其中新增 8 项可见性回归覆盖越界控件／命中、原始隐藏值、纯测量与提取、缓存节点、嵌套及共享视图、宿主声明移除、跨宿主所有权、宿主释放、空回退及滚动宿主。结果包：`test_sim_2026-11-10T08-12-37-993Z_pid42007_e6f1fdbc.xcresult`。

应用与 UI 最终运行 **261 通过、0 失败、0 跳过**，其中 259 项应用／对照测试及 2 项实际 UI 测试；继续排除前文已复现的 `voiceRoomSeatLayoutsExpandOnIPadWidth()` 基线失败项，不将其计入通过。范围包括 `ApplicationTests`、`ViewThatFitsGuideTests`、`AlignmentGuidePropagationTests`、`ContentConfigurationCollectionTests`、`DailyRecordMonthTests`。SwiftUI 参考线对照同时断言 Kit 候选的实际隐藏状态。工具等待在 300 秒处超时，但底层运行正常完成；已读取最终 xcresult summary，结果为 Passed、261 passed、0 failed。结果包：`test_sim_2026-11-10T08-13-22-275Z_pid42007_2665468c.xcresult`。

已逐张核对本次统一修复后的原始截图：[默认收起](Validation/DefaultSafeArea/view-that-fits-collapsed.png)、[展开拖动](Validation/DefaultSafeArea/view-that-fits-expanded.png)、[再次收起](Validation/DefaultSafeArea/view-that-fits-recollapsed.png)、[阿拉伯语前缘](Validation/DefaultSafeArea/view-that-fits-rtl.png)。这些截图来自撤回 Demo 裁剪后的代码。设备仍为 iPhone 18 Pro / iOS 27.2 模拟器；未补跑真机、iPad/Duo 或旧版 iOS。

QuickLayout 检出目录仍干净，版本仍为 `62310c0a7f4ec43f3ea6ff89f3824ef6b23b2bb3`；包清单与依赖锁定文件未修改，`git diff --check` 通过。


## 原生列表横屏交叉轴重复安全区（2026-11-10）

首页横屏出现横向滚动与内容偏移，根因是组合布局已经通过 `contentInsetsReference` 在交叉轴内部避让安全区，但该消费量不一定体现在 `adjustedContentInset` 中。Kit 将其误判为尚未处理，再向 `contentInset` 添加相同边距。复现测试记录到 `contentSize.width == bounds.width`，却额外加入左右各 62 或 124 点，产生 124／248 点的横向范围；这些是测试环境读数，修复没有硬编码相应尺寸。

修复位于 `ContentMargins.swift`：原生组合布局使用 automatic、safeArea、layoutMargins 或 readableContent 参考时，将其交叉轴安全区与 UIKit 自动 inset 取逐边最大值，作为已经消费的区域。`.none` 继续使用原有补足规则。处理按布局实际滚动轴区分，不修改调用方布局、不关闭滚动、不隐藏指示器，也不覆盖 contentSize。

验证结果：

- 原生列表单元／集成 **9 项通过**。新增首页窗口与安全区往返验证，严格检查横向范围和偏移；另比较横纵两轴、四种边界参考、三种自动 inset 策略，共 24 个配置，与未包装的原生组合布局比较交叉轴范围及首项位置，并确认主轴仍可滚动。结果包 `test_sim_2026-11-10T08-30-26-613Z_pid42007_99ff7a54.xcresult` 的应用测试部分通过；该次 UI 拖动误触单元格进入详情而失败，不能将整个包标为通过。
- 调整手势起点到非交互分组标题后，首页 **3 项 UI 全部通过**。中文／阿拉伯语各执行左右横屏、转回竖屏，以及每个方向的双向实际拖动；同时回归系统栏后方滚动、末行可达、搜索键盘和清空。结果包：`test_sim_2026-11-10T08-32-42-567Z_pid42007_54b49ee2.xcresult`。
- 最终包级 **202 项通过、0 失败、0 跳过**。结果包：`test_sim_2026-11-10T08-35-30-561Z_pid42007_f68b818d.xcresult`。

已复核原始附件中的列表左右边界：[中文左横屏](Validation/DefaultSafeArea/catalog-landscape-left.png)、[中文右横屏](Validation/DefaultSafeArea/catalog-landscape-right.png)、[阿拉伯语左横屏](Validation/DefaultSafeArea/catalog-landscape-rtl-left.png)、[阿拉伯语右横屏](Validation/DefaultSafeArea/catalog-landscape-rtl-right.png)。验证设备为 iPhone 18 Pro / iOS 27.2 模拟器，未补跑实际 iPad/Duo、真机或旧版 iOS。QuickLayout 源码、依赖版本及锁定文件保持不变，`git diff --check` 通过。

## ViewThatFits 先测量、再同步层级（2026-11-10）

本节替代前面的“隐藏并折叠”实现。`ViewThatFits` 将不可变选择信息保存在本轮最终测量节点中，Kit 宿主据此解析需要挂载的视图，并将视图列表与同一份布局节点一起交给 QuickLayout。理想尺寸试探、其他建议尺寸的测量和旧缓存节点互不覆盖；未选中分支独占的 UIView 从层级移除，重新选中时复用实例，不改写 `isHidden`，也不强行清空被移除视图的旧 frame。

普通宿主、滚动宿主共用桥接层；`GeometryReader` 独立管理的动态内容也在测量后解析候选。共享视图按对象身份去重，内层候选只贡献最终选中的视图。纯 `sizeThatFits` 绕过上游的层级更新，避免测量时挂载、移除或重排视图。滚动宿主保留原有内容矩形、方向和对齐坐标。

原始 `views()` 仍用于枚举声明中的全部视图，原始 QuickLayout `applyFrame` 仍只负责几何提交；自动挂载语义由 Kit 宿主提供。移除沿用上游的出现／消失协调：存在 UIView 动画时，旧视图可保留到消失动画结束。视图退出层级不等于释放实例、取消订阅或复刻 SwiftUI 的所有生命周期事件。

Demo 的候选状态读取改为实际挂载关系。Frame 实验室回归检查收起后控件不存在于宿主层级，展开后仍是原控件；不再把零尺寸或 `isHidden` 作为选择依据。

验证结果：

- 包级最终 **206 项通过、0 失败、0 跳过**，其中 12 项挂载回归覆盖首次测量隔离、缓存选择独立、共享与嵌套候选、共享控件无移除回调、禁用宿主、声明移除与跨宿主转移、空回退、零尺寸选中视图、滚动宿主、Reader 动态内容及嵌套宿主。结果包：`test_sim_2026-11-10T09-03-46-008Z_pid42007_13e19b70.xcresult`。
- 应用／对照测试 **291 项通过**，覆盖 `ApplicationTests`、`ViewThatFitsGuideTests`、`GeometryReaderTests`、`AlignmentGuidePropagationTests`、`ContentConfigurationCollectionTests`、`DailyRecordMonthTests` 和 `NativeListSafeAreaTests`。继续明确排除前文已复现的 `voiceRoomSeatLayoutsExpandOnIPadWidth()` 基线失败项，不将其计入通过。加上同次运行的 2 项 UI 测试，结果包共 **293 通过、0 失败、0 跳过**：`test_sim_2026-11-10T08-58-43-380Z_pid42007_a6ab2f91.xcresult`。
- SwiftUI 对照包括 LTR／RTL、宽窄建议及自定义参考线的 8 组比较，以及同一个宿主按 100 → 300 → 100 → 300 点往返切换的 8 次挂载／尺寸比较。挂载测试对 SwiftUI 的运行循环提交进行有界等待，超时仍报错；不据此承诺所有系统版本的内部实现一致。

中间验证曾发现对照测试使用了不同坐标范围，以及 SwiftUI 更新前读取探针的问题；修正测试坐标与等待条件后上述应用回归全部通过。应用级 `app.screenshot()` 的横屏附件出现裁切；等待窗口及控件稳定后仍复现，改用 `XCUIScreen.main.screenshot()` 后整屏画面正常。最终证据采用稳定后的整屏截图，不使用中间异常附件。


最终实际 UI **2 项通过、0 失败、0 跳过**：中文顶部前缘对齐 → 展开参数 → 拖动宽度 → 收起 → 左右横屏及转回竖屏 → 再次展开并确认数值保留；另验证阿拉伯语顶部前缘对齐。收起后直接断言滑块不存在于可访问层级。最终结果包：`test_sim_2026-11-10T09-09-02-668Z_pid42007_50f5dc87.xcresult`。

已逐张核对最终原始附件：[默认收起](Validation/DefaultSafeArea/view-that-fits-mounted-collapsed.png)、[展开并拖动](Validation/DefaultSafeArea/view-that-fits-mounted-expanded.png)、[再次收起](Validation/DefaultSafeArea/view-that-fits-mounted-recollapsed.png)、[设备左横屏](Validation/DefaultSafeArea/view-that-fits-mounted-landscape-left.png)、[设备右横屏](Validation/DefaultSafeArea/view-that-fits-mounted-landscape-right.png)、[阿拉伯语前缘](Validation/DefaultSafeArea/view-that-fits-mounted-rtl.png)。左上角没有未选中滑块残留，横屏视图完整，转回竖屏后预览和参数值保持一致。

本轮设备为 iPhone 18 Pro / iOS 27.2 模拟器；未补跑真机、实际 iPad/Duo 或旧版 iOS。QuickLayout 源码检出干净，仍为 `62310c0a7f4ec43f3ea6ff89f3824ef6b23b2bb3`，包清单和依赖锁定文件均未修改；`git diff --check` 通过。工作保留在 `codex/default-safe-area`，未提交或推送。

## 瀑布流旋转后滚动的局部安全区反馈（2026-11-10）

用户补充复现顺序为进入瀑布流、旋转、再滚动。检查发现 `List` 内容边界仍用单元格当前的 UIKit 局部 `safeAreaInsets` 减去列表 `adjustedContentInset`。旋转和滚动过程中，局部值可能包含视图移出视口的遮挡，远大于列表边距；剩余部分被默认安全区包装加入自然尺寸，并可能进入自适应测量缓存。

新增受控回归在修复前失败：自然尺寸 100 × 40 的内容分别被测成 184 × 356 和 100 × 1126。结果包：`test_sim_2026-11-10T09-26-58-208Z_pid42007_b080ed5a.xcresult`。修复在 `QuickLayoutSafeAreaHostContext` 的原生 `List` 内容边界建立独立内容坐标，不将视口遮挡传入单元格自然尺寸；内部已有的显式 Kit 作用域仍优先处理。保留瀑布流列数算法和测量缓存匹配策略，没有固定卡片高度或通过 reloadData 掩盖问题；QuickLayout 源码和依赖保持不变。

新增测试同时改变容器宽高并滚动，真实 UI 用例从首页进入页面，执行左右横屏、旋转后上下拖动、回到首项、返回竖屏及点击卡片。初版 UI 回滚手势落入固定工具区，未真正回到首项，已调整为在工具区与底部栏之间的内容区域拖动；这次失败不作为布局问题的复现证据。单纯旋转的初版 UI 用例未复现用户截图中的整块空白，因此根因回归采用上述可控局部遮挡输入，并以最终旋转加滚动交互检查实际效果。

包级修复后 **207 项通过、0 失败、0 跳过**：`test_sim_2026-11-10T09-28-06-093Z_pid42007_77a9b46f.xcresult`。

继续核对截图时发现另一个可由实际旋转加滚动稳定触发的问题：转回竖屏后，单元格宽度恢复为 183 点，内容配置却仍保留横屏的 172.5 点，卡片高度由初始 311.333 点变为 301 点。新增往返尺寸断言后 UI 测试失败（`test_sim_2026-11-10T09-36-27-729Z_pid42007_7086c814.xcresult`）；临时诊断确认 `sizingForItem` 一直返回零，单元格和内容视图均保留旧配置。

原因是 `UICollectionViewWaterfallLayout.refreshEnvironment` 可在公开尺寸查询或拟合校验中发现晚到的安全区、布局边距和特征变化；此前只把内部几何标成过期，没有安排 UIKit 再次调用 `prepare`。修复在查询栈之外合并安排布局失效，保留有效测量缓存；若正常 `prepare` 已提交新几何，延后任务直接跳过。新增 `lateSafeAreaChangeRecoversSizingWithoutAnotherBoundsChange` 验证晚到的安全区变化不需要再旋转一次才能恢复尺寸。

修复该失效链后，加强的真实 UI 测试通过（`test_sim_2026-11-10T09-43-21-423Z_pid42007_2816d94d.xcresult`）。临时诊断代码已删除；最终回归另行运行，包含两个横屏方向的滚动和回顶、两次返回竖屏的宽高恢复、标题位置与点击响应。

最终应用与交互回归 **46 项通过、0 失败、1 跳过**：`test_sim_2026-11-10T09-45-33-630Z_pid42007_a849dce0.xcresult`。包含内容配置、瀑布流几何及增量测量、原生 List 安全区、SwiftUI 默认安全区／系统键盘对照，以及真实旋转滚动 UI 用例。跳过的是要求 `WATERFALL_BENCHMARK=1` 才运行的 `scalabilityMatrix` 大规模性能基准，不计为通过。

已核对最终整屏附件：[左横屏滚动后回到首项](Validation/DefaultSafeArea/waterfall-rotation-landscape-left.png)、[右横屏滚动后回到首项](Validation/DefaultSafeArea/waterfall-rotation-landscape-right.png)、[再次返回竖屏](Validation/DefaultSafeArea/waterfall-rotation-returned-portrait.png)。返回竖屏的首卡宽高与初始值误差不超过 1 点，标题在窗口内，点击仍可响应；这些结果不等同于在修复前完整复现了用户截图的整屏空白。

最终源码状态下再次运行包级测试：**207 项通过、0 失败、0 跳过**，结果包 `test_sim_2026-11-10T09-48-58-214Z_pid42007_f4193ad8.xcresult`。`git diff --check` 通过；QuickLayout 检出仍干净，版本和所有依赖锁定文件未变。本轮实际交互限于 iPhone 18 Pro / iOS 27.2 模拟器，未补跑真机、iPad/Duo 或旧版 iOS。

## Horizontal 模式的紧凑行高（2026-11-10）

用户截图中的白色卡片超出紫色背景，源于 Demo 横向模式声明了随动态字体缩放的 200 点最小行高，而背景仍按实际可用高度绘制。本轮调整 Demo 的 section provider：横向最小行高取原最小值与 `environment.container.effectiveContentSize.height - section.contentInsets.top - section.contentInsets.bottom` 的较小值。原生环境已扣除安全区和工具区，避免再次扣减；宽裕空间仍使用多行，紧凑空间由现有 `ViewThatFits` 增加文本宽度。通用 `.adaptive(minimum:)` 契约和 QuickLayout 源码、依赖均未更改。

新增 `waterfallHorizontalCardsStayInsideBackgroundAtCompactHeights`，组合 390 → 320 → 390 点容器高度、普通／较大字体和上下安全区，检查可见卡片不超出背景及安全内容高度，并检查正文完整。修复前失败，记录卡片底部 212 点、可用高度约 146 点，以及大字体下底部约 275.667 点的越界：`test_sim_2026-11-10T09-56-46-286Z_pid42007_2970a298.xcresult`。

新增实际 UI 用例明确点击 Horizontal，再执行左横屏 → 竖屏 → 右横屏及左右拖动，检查首卡在底部栏上方、标题仍在卡片内，并保存整屏截图。原有 Vertical 模式旋转滚动用例继续保留。

修复后 **26 项通过、0 失败、0 跳过**，包括 24 项内容配置测试和 2 项实际 UI 测试。结果包：`test_sim_2026-11-10T09-58-49-179Z_pid42007_5955bfd3.xcresult`。已逐张核对 [Horizontal 左横屏](Validation/DefaultSafeArea/waterfall-horizontal-fit-left.png)、[Horizontal 返回竖屏](Validation/DefaultSafeArea/waterfall-horizontal-fit-portrait.png)、[Horizontal 右横屏](Validation/DefaultSafeArea/waterfall-horizontal-fit-right.png)：卡片垂直范围在紫色背景内部，横屏为一行，竖屏恢复多行；横向延伸的内容仍可滚动查看。验证设备为 iPhone 18 Pro / iOS 27.2 模拟器；本轮未改框架源码，未重复包级测试。

## 横屏滚动指示器的独立安全区补偿（2026-11-10）

资料页横屏指示器过度内缩的问题由真实 UI 回归复现：874 点宽视口中，垂直指示器的可访问区域中心在 x=732，落入卡片内容。修复前结果包：`test_sim_2026-11-10T10-12-28-978Z_pid42007_9fbf1fc9.xcresult`。

`ContentMargins` 原先将内容的自动 inset 调整量也用于指示器补偿；内容没有滚动范围的交叉轴可能没有自动调整，但 UIKit 指示器仍有独立自动调整。因此分开计算两者已承担的安全区域，保留 `automaticallyAdjustsScrollIndicatorInsets` 的调用方选择。自动调整开启时让 UIKit 决定轨道实际位置，Kit 只加入业务基线、显式边距及尚未承担的插入栏预留；关闭时由 Kit 补齐所需安全区。组合布局消费的内容安全区不再误当成指示器已消费区域。参考 [Apple 的自动指示器调整文档](https://developer.apple.com/documentation/uikit/uiscrollview/automaticallyadjustsscrollindicatorinsets)。

修复后真实 UI 首轮通过，两个横屏方向的可访问指示器中心分别为 x=856 和 x=805.333，返回竖屏为 x=384；左右方向不同由系统避让屏幕边缘决定。这些数值是可访问轨道区域，不当作可见灰色滑块的精确中心。首轮截图时指示器已淡出，后续将截图提前至手势结束后，最终证据另行记录。

包级 **210 项通过、0 失败、0 跳过**：`test_sim_2026-11-10T10-16-09-112Z_pid42007_9af5e75a.xcresult`。新增 3 项用例覆盖内容／指示器自动调整组合、LTR/RTL、水平轴、业务基线、开关切换、原生 List 忽略安全区及声明移除。

应用与实际 UI 回归共 84 项：首轮 82 项通过，2 项旧断言仍要求手动叠加系统已承担的安全区而失败（`test_sim_2026-11-10T10-18-32-967Z_pid42007_c96bc437.xcresult`）。更新这两项断言并补充自动开关切换检查后，定向复测 2 项均通过（`test_sim_2026-11-10T10-22-04-203Z_pid42007_db658ed0.xcresult`）。框架实现未在这两次运行之间改变，只有说明注释补充；不将首轮结果包描述为整批全绿。覆盖键盘避让、插入栏、内容边距、聊天列表、原生 List 和 SwiftUI 安全区对照。

最终实际旋转滚动 UI 用例通过，已核对指示器可见时的 [左横屏](Validation/DefaultSafeArea/profile-indicator-landscape-left.png)、[右横屏](Validation/DefaultSafeArea/profile-indicator-landscape-right.png)、[返回竖屏](Validation/DefaultSafeArea/profile-indicator-returned-portrait.png)。指示器在卡片右侧，屏幕方向改变时保留系统边缘避让。本轮实际 UI 为英文资料页，LTR/RTL 的显式边距映射另由包级测试覆盖；未补跑 RTL 实际手势、真机或旧版系统。

QuickLayout 检出保持干净，源码、版本和依赖锁定文件未修改；`git diff --check` 通过。工作仍保留在 `codex/default-safe-area`，未提交或推送。

## 其他滚动页面的扩展审查（2026-11-10）

按滚动宿主和边距来源检查 Demo：普通 Kit 纵向滚动页、嵌套横向轮播／Geometry、原生 Collection/Table 内容配置页、原生 List 瀑布流、聊天消息、语音房内嵌列表及弹层。指示器共用上一节的独立补偿；聊天列表显式关闭系统自动指示器调整，由输入栏提供边距，保留其单一所有者。隐藏指示器的内嵌列表不要求显示轨道。

发现未经过 `List` 声明的原生复用内容仍会将主轴视口遮挡反馈为自然尺寸。受控回归在修改前将 100 × 40 测成 100 × 356：`test_sim_2026-11-10T10-33-38-776Z_pid42007_230a7e34.xcresult`。Kit 层为 UITableView 的单元格／页眉页脚，以及方向明确的 Collection Flow、Compositional、Waterfall 复用内容建立坐标边界，排除滚动主轴的视口遮挡；交叉轴保留局部安全区并扣除已有 inset，内部显式 Kit 作用域继续优先。未知自定义布局不推测方向，普通 UIView 包装不误判为复用内容。

实际截图审查还发现内容边距页的嵌套预览向上覆盖说明文字。固定 360 点的内层视口高于外层横屏可用高度，被错误识别为填满外层视口，再恢复了一次顶部和底部安全区。新增回归在修复前报告高度额外增加 142 点、预览起点 94 点而前一内容结束于 160 点：`test_sim_2026-11-10T10-48-41-191Z_pid42007_f64edbdf.xcresult`。安全区上下文现在记录当前滚动内容的主轴，内层局部视口不再沿该轴恢复外层区域，交叉轴继续沿用原有规则。

上述框架修复后的包级测试 **214 项通过、0 失败、0 跳过**：`test_sim_2026-11-10T10-49-27-238Z_pid42007_d481130e.xcresult`。新增回归覆盖自然尺寸稳定、纵向／横向交叉轴约束、内部显式作用域，以及横竖屏往返时固定预览不侵入相邻内容。

语音房另有操作栏坐标问题：列位置取自根视图坐标，作为安全内容区域中的 padding 后又叠加了一次侧边安全区；实际对齐回归记录相差 62 点。现在改为相对 `safeAreaLayoutGuide.layoutFrame` 计算。双紧凑尺寸类别下标准 split 收起辅助公屏属于已有语义；排查期间的临时双列样式未保留。实际 UI 检查覆盖横屏收起与返回竖屏恢复；支持双列的环境用应用回归显式提供尺寸类别和侧边安全区，检查公屏与操作栏两端一致。

首轮扩展实际 UI 共 9 项，7 项通过、2 项失败：`test_sim_2026-11-10T10-36-28-658Z_pid42007_e38d6679.xcresult`。通过的六个页面为原生 Collection、Table、动态滚动、表单、内容边距和 Geometry 的左右横屏／返回竖屏／上下滑动，另有聊天软件键盘输入、发送及交互收起。该轮通用断言没有检查嵌套预览和说明文字是否重叠，不能把它记为整页布局无异常。语音房失败后的方向状态影响了下一项插入栏键盘测试；为键盘用例显式指定竖屏后通过，结果见 `test_sim_2026-11-10T10-42-34-583Z_pid42007_10646cc3.xcresult`（该结果包另有语音房和轮播失败，不是整批通过）。轮播用例继续要求末项完整可见，并增加有界拖动次数，避免五次短拖动不足以到达末项。

嵌套预览修复后，应用位置回归、内容边距实际旋转滚动、横向轮播实际左右拖动与返回竖屏尺寸恢复三项通过：`test_sim_2026-11-10T10-55-17-920Z_pid42007_5a0af113.xcresult`。该中间结果包另有两项语音房失败，不记为整批通过。最终保留标准 split 并修复列坐标后，语音房应用回归和实际 UI 两项均通过：`test_sim_2026-11-10T11-04-23-961Z_pid42007_35e0553a.xcresult`。实际 UI 断言竖屏公屏可见、可滚动，左右横屏遵循标准收起规则，返回竖屏恢复公屏与操作栏对齐；不将收起状态计为横屏公屏滚动覆盖。

已核对并保存 [嵌套预览返回竖屏](Validation/DefaultSafeArea/scroll-audit-nested-preview-portrait.png)、[嵌套预览横屏滚动](Validation/DefaultSafeArea/scroll-audit-nested-preview-landscape.png)、[轮播末项返回竖屏](Validation/DefaultSafeArea/scroll-audit-carousel-returned-portrait.png)、[语音房恢复竖屏](Validation/DefaultSafeArea/scroll-audit-room-returned-portrait.png)。

扩展应用回归覆盖 113 个测试方法，包括目录页面在七种宽度下的滚动范围、边距和键盘组合、原生 List、内容配置、语音房导航及 SwiftUI 对照。首轮应用 112 项通过、1 项失败，另外 7 项实际 UI 全部通过；结果包共 119 通过、1 失败：`test_sim_2026-11-10T11-07-02-326Z_pid42007_35ee62e1.xcresult`。这轮再次验证原生 Collection、Table、动态滚动、表单和 Geometry 的三种方向，以及聊天软件键盘和插入栏键盘交互。已核对最终 [Collection 横屏指示器](Validation/DefaultSafeArea/scroll-audit-native-collection-landscape.png) 和 [Table 横屏指示器](Validation/DefaultSafeArea/scroll-audit-native-table-landscape.png)。

唯一失败是瀑布流紧凑高度加大字体时，正文高度约 15.67 点、所需高度约 25.33 点。仅增加纵排文本宽度仍无法满足标题和正文两行的最小高度。Demo 的 `ViewThatFits` 最后增加同排文本候选，用横向滚动容纳宽度，保留正文完整高度；没有改变通用布局算法或固定缩小字体。

修复后重跑内容配置全部 24 项回归和瀑布流两项实际旋转／滚动用例，**26 项通过、0 失败、0 跳过**：`test_sim_2026-11-10T11-13-27-280Z_pid42007_689afa51.xcresult`。该次验证包含横向与纵向模式、左右横屏、返回竖屏以及滚动后的卡片尺寸与点击响应。未把前面的失败结果包改写为整批通过。

本轮最终实际 UI 共 12 个用例分批通过。审查过的弹层、隐藏指示器列表及其他目录页，不等同于逐页执行了全部实际手势；它们分别由源码检查、目录几何回归或已有专项测试覆盖。本轮实际交互设备为 iPhone 18 Pro / iOS 27.2 模拟器，未补跑真机、iPad/Duo、旧版 iOS 或所有语言的实际手势。QuickLayout 检出仍干净，版本为 `62310c0a7f4ec43f3ea6ff89f3824ef6b23b2bb3`，所有依赖清单与锁定文件未修改；`git diff --check` 通过。工作保留在 `codex/default-safe-area`，未提交或推送。

## 动态滚动页与 SwiftUI 指示器对照（2026-11-11）

在 iPhone 18 Pro / iOS 27.2 模拟器上从同一菜单进入动态滚动页及 Debug 专用 SwiftUI 对照页。两者使用相同的行数、行高和边距声明。水平 16 pt 只作用于滚动内容，指示器顶部预留按钮高度加 8 pt，底部预留 8 pt。

从竖屏进入，依次切到左横屏、右横屏并返回竖屏，每次都实际拖动并验证首项位置改变。两种横屏下两页的视口宽度均为 874 pt，卡片右边缘为 796 pt，可见灰条中心约为 807.5 pt。竖屏宽度为 402 pt，两页卡片右边缘均为 386 pt，灰条中心约为 397.5 pt。灰条取自手势后的全屏截图；交互测试另行比较辅助功能轨道中心和上下端，容差为 1 pt。[QuickLayoutKit 横屏截图](Validation/DefaultSafeArea/dynamic-indicator-kit-landscape.png) · [SwiftUI 横屏截图](Validation/DefaultSafeArea/dynamic-indicator-swiftui-landscape.png)

初次比较轨道横坐标通过。扩大断言后一次读到横屏互换时的动画中间帧；测试改为等待滚动视口与窗口重合再取样。最终定向 UI 测试通过，结果包为 `qlk-dynamic-swiftui-settled.xcresult`。本轮验证覆盖英文、从左至右布局和上述模拟器。

### 动态滚动页的阿拉伯语 RTL 对照（2026-11-11）

在同一台 iPhone 18 Pro 模拟器上用阿拉伯语启动应用，从目录进入动态滚动页和 SwiftUI 对照页。顶部 trailing 操作在两页均位于左侧。每次旋转后先等滚动视口与窗口重合，再读取首张卡片的完整边界，执行向上拖动并检查首项位移。两页在三种姿态下的卡片边距、垂直指示器辅助功能轨道横坐标和上下端均在 1 pt 容差内。

| 设备姿态 | 视口宽度 | 卡片距左、右边缘 | 可见灰条中心距左边缘 | 手势截图 |
| --- | ---: | ---: | ---: | --- |
| 左横屏 | 874 pt | 各 78 pt | 66.5 pt | [QuickLayoutKit](Validation/DefaultSafeArea/dynamic-rtl-kit-landscape-left.png) · [SwiftUI](Validation/DefaultSafeArea/dynamic-rtl-swiftui-landscape-left.png) |
| 右横屏 | 874 pt | 各 78 pt | 66.5 pt | [QuickLayoutKit](Validation/DefaultSafeArea/dynamic-rtl-kit-landscape-right.png) · [SwiftUI](Validation/DefaultSafeArea/dynamic-rtl-swiftui-landscape-right.png) |
| 返回竖屏 | 402 pt | 各 16 pt | 4.5 pt | [QuickLayoutKit](Validation/DefaultSafeArea/dynamic-rtl-kit-returned-portrait.png) · [SwiftUI](Validation/DefaultSafeArea/dynamic-rtl-swiftui-returned-portrait.png) |

截图来自通过的 RTL 定向测试 `qlk-dynamic-rtl-first.xcresult`。按屏幕方向读取 3× 原图，横屏可见灰条占第 195 至 203 像素列，竖屏占第 9 至 17 列（从零计数）。两套实现逐方向一致。辅助功能轨道比可见灰条宽，测试分别记录轨道与截图。

英文 LTR 和阿拉伯语 RTL 启动回归共 2 项通过（`qlk-dynamic-bidirectional.xcresult`）。另用英文系统语言启动，在应用菜单点选阿拉伯语后进入页面，重复相同的旋转与拖动流程，1 项通过（`qlk-dynamic-rtl-menu.xcresult`）。两条 RTL 路径的卡片水平边距和可见灰条横坐标均与上表一致；各自的轨道上下端也与同一语言环境下的 SwiftUI 对照相符。

## FixedSize Lab 在 Duo 内屏旋转后回到顶部（2026-11-11）

在 iPhone Duo / iOS 27.2 模拟器的展开内屏上，用 Device Hub 实际旋转。先进入页面，转为横屏并拖动纵向内容，再返回竖屏并向下拖回顶部。SwiftUI 对照页使用相同的分栏、导航栏和标签栏容器，竖向 ScrollView 内嵌横向 ScrollView，回顶时两页的实测内容高度均为 951 pt。

修复前，内容到顶时两页的归一化纵向偏移均为 0。FixedSize Lab 多包了一层布局宿主，纵向滚动视图收到的系统顶部安全区为 0 pt，显式指示器顶部边距为 82 pt。SwiftUI 的对应数值分别为 82 pt 和 0 pt。竖屏辅助功能轨道的上端因此相差 27 pt（82 pt 与 55 pt）。本次复现了轨道偏差，未稳定复现反馈截图中灰条长时间停在屏幕中段的幅度。

将 FixedSizeView 直接用作控制器根视图后，两页横屏轨道均为 (918, 55, 30, 559) pt。返回竖屏后，两页第一次回滑的归一化偏移均为 0，实际顶部、底部安全区分别为 82 pt、83 pt，显式纵向指示器边距为零。竖屏轨道均为 (636, 55, 30, 813) pt。将首次回顶的 3× 内屏截图转正，在可见灰条中心列取样，两页灰条均从第 245 像素延伸至第 2235 像素。辅助功能轨道与可见灰条的上端分别记录。

[FixedSize Lab 首次回顶](Validation/DefaultSafeArea/fixed-size-duo-kit-returned-top.png) · [SwiftUI 首次回顶](Validation/DefaultSafeArea/fixed-size-duo-swiftui-returned-top.png)

实际手势对照结果包为 `qlk-duo-fixed-hub-after.xcresult`。移除临时诊断代码后，FixedSize 定向回归 9 项全部通过（`qlk-duo-fixed-clean-tests.xcresult`），包含系统栏换边时的安全区、指示器设置、RTL 轮播位置和 SwiftUI 布局对照。

## Duo 横屏的几何画布和嵌套横向视口（2026-11-11）

在 iPhone Duo / iOS 27.2 模拟器的展开内屏上，使用同一个双列导航和右侧标签栏。窗口实测为 951 × 669 pt。XCUITest 在真实滑块上把边距调到接近上限，再把宽度拉到最大。表中横坐标均以窗口左边缘为原点，单位为 pt。

| 布局声明 | 实现 | 灰色画布左右边缘 | 横向滚动视口左右边缘 |
| --- | --- | --- | --- |
| 原页面，外层滚动内容边距 16 | SwiftUI | 282.33 ～ 851.00 | 16.00 ～ 935.00 |
| 原页面，外层滚动内容边距 16 | QuickLayoutKit 修复前 | 282.33 ～ 851.00 | 0.00 ～ 951.00 |
| 调整后，页面布局内边距 16 | SwiftUI | 282.33 ～ 851.00 | 282.33 ～ 851.00 |
| 调整后，页面布局内边距 16 | QuickLayoutKit | 282.33 ～ 851.00 | 282.33 ～ 851.00 |

原生 SwiftUI 允许触及安全区边缘的嵌套视口扩展，并在窗口两侧保留外层的显式内容边距。旧的 Kit 实现将显式边距也发布为子视口可恢复的安全区，向两侧各多扩展了 16 pt。框架现分别处理相对尺寸所依赖的完整内容边距和子视口可恢复的系统区域。真实窗口回归还覆盖附加安全区从右侧切到左侧时，默认满宽嵌套视口的左右边界。

几何示例单独使用页面 padding 留出 16 pt，在这块局部空间内按比例分配画布宽度。两页均保留 260 pt 高的画布与垂直居中的 200 pt 高滚动视口。QuickLayoutKit 实际页面满宽时的画布 frame 为 (282.33, 399, 568.67, 260)，滚动视口为 (282.33, 429, 568.67, 200)。SwiftUI 对照页仅保留两个滑块和画布，画布纵向位置随上方控件数量而变化。

实际从画布内横向拖至末端，再反向拖回起点。QuickLayoutKit 样本宽约 909.87 pt，SwiftUI 约 910 pt。两者在起点和末端均保留滑块指定的约 44 pt 边距。初始失败对照和首次修复验证分别记录于 `geometry-duo-wide-before.xcresult`、`geometry-duo-fix1.xcresult`。

[QuickLayoutKit 满宽回拖后的内屏截图](Validation/DefaultSafeArea/duo-canvas-kit-full-width.png) · [SwiftUI 满宽回拖后的内屏截图](Validation/DefaultSafeArea/duo-canvas-swiftui-full-width.png)

iPhone 18 Pro Max 的方向网格、几何场景与内容边距嵌套预览通过实际交互。首轮横向轮播已到末项，反向手势却从可见的目录侧栏开始，未能回到首项（`geometry-other-scrolls.xcresult`）。手势起点改为依据详情列宽度选择后，左右横屏、返回竖屏的轮播往返通过（`geometry-duo-other-recheck.xcresult`）。

同窗对照还复现了 Duo 键盘避让的两个独立差异。上游依次设置子视图的 bounds 与 center，子宿主在中间位置投影键盘区域时多扣了 115 pt。位置确定后需要重新布局；层级提交期间也必须沿用布局修饰符已消费的安全区，否则内层显式忽略键盘时无法恢复空间。修复后默认避让、忽略键盘、保留容器安全区及原生列表均通过同窗软件键盘对照（`geometry-duo-verified.xcresult`）。框架的宿主、指示器及候选挂载专项共 24 项通过（`geometry-framework.xcresult`）。

最终构建在 Duo 上通过 23 项 Demo 回归及 1 项与 SwiftUI 对照的画布拖动 UI 测试。iPhone 18 Pro Max 另通过 24 项内容配置集合与瀑布流测试，以及 1 项横向轮播旋转往返 UI 测试（`geometry-other-final.xcresult`）。

## Duo 几何画布满宽后的 RTL 旋转与拖动（2026-11-11）

在展开的 Duo 内屏使用阿拉伯语运行同一详情列。宽度滑块从默认值 0.8 实际向左拖至最大值，内容左右 padding 保持默认 16 pt。通过样本宽度等于画布宽度的 1.6 倍校验滑块确实到达终点。每次旋转均核对窗口宽高和内屏截图的旋转信息，两种同宽横屏可分别识别。若 XCTest 仅更新设备报告的朝向，应在 Device Hub 旋转内屏，直到界面完成旋转。

修复前左横屏的画布和内层视口水平范围均为 16 ～ 584.67 pt。SwiftUI 样本的右边缘在 568.67 pt，QuickLayoutKit 却将样本左边缘放在 32 pt，初始显示了另一端（`geometry-rtl-duo-2.xcresult`）。RTL 前缘对应最大水平偏移，改变视口或内容宽度都会移动这个起点。滚动宿主现按上一次布局的前缘判断是否需要跟随尺寸变化，同时让实际手势和中途位置继续由 UIKit 管理。几何页的局部方向开关也同步内层横向宿主。

下表是修复后的窗口坐标，单位为 pt。SwiftUI 对照页只保留滑块与画布，画布 y 为 184、视口 y 为 214；两套实现相对于画布的视口 frame 相同。

| 设备姿态 | 窗口尺寸 | QuickLayoutKit 画布 (x, y, w, h) | QuickLayoutKit 横向视口 (x, y, w, h) | 两页到达两端后的边距 |
| --- | --- | --- | --- | --- |
| 左横屏 | 951 × 669 | (16, 388, 568.67, 260) | (16, 418, 568.67, 200) | 左右均约 16 |
| 右横屏 | 951 × 669 | (16, 388, 568.67, 260) | (16, 418, 568.67, 200) | 左右均约 16 |
| 返回竖屏 | 669 × 951 | (16, 388, 637, 260) | (16, 418, 637, 200) | 左右均约 16 |

两个横屏上样本左缘从 −341.33 拖到 32，再回到 −341.33；返回竖屏后从 −382.33 拖到 32，再回到 −382.33。Kit 和 SwiftUI 回到起点后的差异在 1 pt 容差内。Kit 竖屏页面内切换 RTL → LTR → RTL 也分别停靠在正确的逻辑前缘。Duo 实际交互通过（`geometry-rtl-duo-5.xcresult`），框架回归 142 项通过（`geometry-rtl-framework-3.xcresult`）。其中尺寸变化回归还检查中途物理偏移恰好等于过渡布局的最大偏移时，仍能保留用户位置。

[左横屏](Validation/DefaultSafeArea/duo-rtl-canvas-landscape-left.png) · [右横屏](Validation/DefaultSafeArea/duo-rtl-canvas-landscape-right.png) · [返回竖屏](Validation/DefaultSafeArea/duo-rtl-canvas-portrait.png)

## Duo RTL 满宽画布从中途松手后连续旋转

在竖屏将宽度拉满，沿横向缓慢拖动，按住 0.5 秒再松手。两次采样确认停止后，保持手指离开画布，用 Device Hub 依次转左横屏、右横屏、竖屏。下表记录样本距 RTL 右端起点的距离与该姿态的总行程，单位 pt。距离等于总行程时，画布显示物理左端。

| 姿态 | QuickLayoutKit 距离 / 行程 | SwiftUI 距离 / 行程 |
| --- | --- | --- |
| 竖屏松手 | 197.20 / 414.20 | 197.33 / 414.33 |
| 左横屏 | 373.20 / 373.20 | 373.33 / 373.33 |
| 右横屏 | 373.20 / 373.20 | 373.33 / 373.33 |
| 返回竖屏 | 414.20 / 414.20 | 414.33 / 414.33 |

本次同一真实分栏内，两页均在首次转横屏时移至左端并保持到最后。上节的中途物理偏移断言覆盖单次受控尺寸变化，这里的分栏旋转走完整的系统转场。实测结果包为 `geometry-middle-2.xcresult`，包含两页共八组截图。

## Duo RTL 展开目录的横移与竖向指示器

在同一个分栏导航控制器中分别打开阿拉伯语 Demo 目录和 SwiftUI 分组 List。Duo 横屏时目录位于右侧，窗口坐标 x 为 600.67 pt，列宽 350.33 pt。先在目录中水平往返拖动，再向上拖动目录并截取亮屏画面。

| 实测项目 | QuickLayoutKit 修复前 | QuickLayoutKit 修复后 | SwiftUI |
| --- | --- | --- | --- |
| 水平拖动后首行左缘 x | 620.67 → 704.67 pt | 620.67 pt，往返均不变 | 620.67 pt，往返均不变 |
| 向上拖动 | — | 目录纵向滚动 | 目录纵向滚动 |
| 竖向灰条距目录物理左缘 | — | 3 pt | 3 pt |

亮屏原图为 2853 × 2007 px（3×）。目录左缘在 x = 1802 px，两张图在 y = 600 px 的灰条都覆盖 x = 1811…1819 px，宽 3 pt。目录使用的搜索栏和列表行高不同，本次比较横向几何与滚动方向。

原因是 Duo 工具栏的 84 pt 避让在宿主的物理右侧，在镜像列表的局部坐标中位于左侧。统一坐标后，列表已处理的安全区不会再写入内容或指示器边距。独立窗口回归另加了 84 pt 单边安全区，修复前横向行程达到 168 pt，修复后两套实现均为 0 pt。复现和修复后的结果分别保存在 `catalog-rtl-side1.xcresult`、`catalog-rtl-side2.xcresult`。

[QuickLayoutKit 目录滚动原图](Validation/DefaultSafeArea/duo-rtl-catalog-kit.png) · [SwiftUI 对照原图](Validation/DefaultSafeArea/duo-rtl-catalog-swiftui.png)

## Duo 目录在运行时切换语言和方向

同一次启动依次使用英文、通过地球菜单切到阿拉伯语、再切回英文。在展开内屏的左横屏、右横屏和返回竖屏分别重复。竖屏显示详情时先点系统侧栏按钮展开目录。正式目录使用 ListKit 数据源，SwiftUI 对照目录使用相同的分组和标题。每种状态下水平往返拖动首行上方的分组标题，再纵向拖动列表并拖回顶部。

| 内屏姿态 | 英文首行边距（左 / 右） | 切阿拉伯语后 | 切回英文后 |
| --- | --- | --- | --- |
| 左横屏 | 20 / 20 pt | 20 / 104 pt | 20 / 20 pt |
| 右横屏 | 20 / 20 pt | 20 / 104 pt | 20 / 20 pt |
| 返回竖屏并展开侧栏 | 20 / 20 pt | 20 / 20 pt | 20 / 20 pt |

边距以目录的物理边缘为基准。横屏英文列宽 266.33 pt；阿拉伯语列靠右，宽 350.33 pt，其中 84 pt 由工具栏占用。竖屏覆盖式侧栏宽 260 pt。水平拖动的断言分别检查首行两端，容差 1 pt。滚动灰条与系统可拖动热区分别测量，灰条的外缘在英文时距列右缘 3 pt，在阿拉伯语时距列左缘 3 pt。

运行时切回英文后，原 SwiftUI 对照页的标题和首行可访问性文案已经更新，分组标题和行内文字却被整体水平翻转。来自同一列的截图中，修复前必须水平翻转后才能识别出 “Content Margins” 和 “Frame Lab”。对照页现在通过 AppLocalization 的 `appLocalizationEnvironment(_:resetContentOnLayoutDirectionChange:)` 为列表注入语言和方向。仅对列表子树启用方向变化时重置，外层分栏、导航和宿主保持身份。重置可能丢弃 SwiftUI 列表的局部状态，本项在首行切换语言；目录中段的验证见下节。正式目录继续使用已有的 UIKit 方向刷新、列表重建及可见条目恢复流程。

[切回英文时镜像的原图局部](Validation/DefaultSafeArea/duo-catalog-english-before.png) · [修复后的同一列](Validation/DefaultSafeArea/duo-catalog-english-after.png)

最终回归 `testRuntimeDirectionAndRotationMatchSwiftUI` 通过（`catalog-live-6.xcresult`，1 个 UI 测试，18 组实测）。两套目录中同一条目实际纵向移动的距离均为横屏 150.67 pt、竖屏 218.33 pt。18 张纵拖亮屏原图都测得灰条距相应列边缘 3 pt，12 次英文首行截图识别均读到 “Safe Area Padding”。其中早一轮竖屏使用 80 pt 的短拖，未观测到首行移动（`catalog-live-5.xcresult`）；最终使用窗口坐标拖动视口高度的 24%，直接测量持续可见条目的位移，并检查反向拖动回顶。

## Duo 目录中段切换语言的阅读位置

在 iOS 27.2 展开内屏上，每个目录分别走左横屏、右横屏、返回竖屏。每个姿态都先通过真实拖动停在目录中段，等首行位置连续两次采样稳定，再用语言菜单从英文切到阿拉伯语并切回英文。每次以稳定条目标识、行高及有符号偏移记录。偏移等于行顶减去该列导航栏和搜索框下方的可读视口顶边，负值表示行顶已滚出视口。正式目录有搜索框，SwiftUI 分组列表对照页只有导航栏。两套目录各自以松手时的实际首行为基准。对照页显式启用了布局方向变化时重建 List，这里的回顶结论仅适用于该配置。

修复前，SwiftUI 对照页在左横屏从“横向滚动” −16 pt 跳到目录第一项 +40.33 pt。方向变化会更换整个 List 的身份，宿主现在在语言写入前读取旧列表，等新列表进入窗口后再恢复。正式目录的“几何观察”从英文 70.33 pt 缩为阿拉伯语 58 pt 时，沿用 −66 pt 偏移会让下一行成为首行。两套目录现在都优先保留原偏移；原偏移会遮住整行时保留先前露出的行尾。用户仍停在该处时切回长行，恢复原来的精确偏移。

QuickLayout 依赖使用 `main`，本轮解析到 `b633586`。下表中同一行的三次测量具有相同的目录条目标识，数值单位为 pt。

| 目录 | 展开内屏姿态 | 首个可见条目 | 英文 | 阿拉伯语 | 切回英文 |
| --- | --- | --- | ---: | ---: | ---: |
| 正式目录 | 左横屏 | 几何观察 | −67.33 | −55.00 | −67.33 |
| 正式目录 | 右横屏 | HGrid & VGrid | −6.67 | −6.67 | −6.67 |
| 正式目录 | 返回竖屏 | ArrangementView | −20.67 | −20.67 | −20.67 |
| SwiftUI.List 对照 | 左横屏 | HGrid & VGrid | −23.67 | −23.67 | −23.67 |
| SwiftUI.List 对照 | 右横屏 | 几何观察 | −17.67 | −17.67 | −17.67 |
| SwiftUI.List 对照 | 返回竖屏 | HGrid & VGrid | −23.67 | −23.67 | −23.67 |

正式目录左横屏的“几何观察”在三次采样中各露出 3 pt 行尾。真实窗口回归另外覆盖了译文令整个目录变短的情况。新内容已经滚到底部时，保存原先请求的位置和实际停住的位置；用户仍在该处时切回原语言，恢复原偏移。用户在第二种语言下继续滚动，则以新的阅读位置为准。

本轮定向回归通过，结果包为 `catalog-reading-13.xcresult`。其中包含两项真实手势 UI 测试和三项窗口或位置计算测试，UI 测试共保留 18 张内屏截图。
