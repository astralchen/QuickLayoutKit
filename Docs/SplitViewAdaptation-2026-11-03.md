# Demo UISplitViewController 适配与验证（2026-11-03）

参考：[WWDC25 — 让你的 UIKit App 更加灵活](https://developer.apple.com/cn/videos/play/wwdc2025/282/)。

## 实现

- 保留原生双列、现有列宽约束和详情控制器所有权。
- `MainViewController` 统一以所属 Split 的实际 `isCollapsed` 判断侧栏状态，兼容 iOS 15，不依赖 iOS 26 trait 或设备类型。
- 展开时隐藏 disclosure、保留选中项；折叠时显示 disclosure、清除侧栏选中态；独立 Navigation 中保留箭头。
- Split 完成折叠／展开、菜单重新出现和布局时更新已有 cell；配置和 `onDisplay` 时覆盖复用／预取 cell。状态未变化时不遍历重配整个列表，不重建数据源或详情。
- 验证中发现 `QuickLayoutScrollView` 在左右非对称 inset 交换后，内容尺寸更新但非滚动轴偏移保留旧值。最终实现通过 `bounds.origin` 对齐非滚动轴，并在对齐之后执行延迟滚动请求，避免无动画 `setContentOffset` 覆盖主轴动画。布局持续维持交叉轴对齐，以处理动画后续帧携带旧偏移的情况；横向滚动容器同样处理上下 inset。
- 安全区域示例保留 UIKit 默认的 `.automatic`，让各 Scenario 对比未消费、逐边消费和额外间距。首次适配曾统一设置 `.always`；重新核对演示目的后撤回，因为额外的自动避让会影响内容对比。此页面的基线不要求内容始终处于全部安全区内。

## 真实 UI 验证

设备：iPad mini (A20 Pro)，iOS 27.2 Simulator。通过 XCUITest 操作系统窗口边框和 App 内 Split 分隔线，未用修改 UIWindow.frame 或注入 trait 冒充系统拖动。

| 场景 | 实际结果 |
| --- | --- |
| Split 内列宽拖动 | 324 → 360 → 295 → 318 pt；窗口尺寸不变；搜索、选中项、计数 4 保持；按钮位于详情列内。通过。 |
| 系统自由窗口连续缩放 | 1158×756 → 375×486 → 635×601 → 375×486 → 935×601 → 1158×756。通过。 |
| 折叠后返回目录、再进入详情 | 无侧栏选中高亮，有 disclosure；搜索 Counter 和详情计数 4 保留。通过。 |
| 再次展开 | 选中高亮恢复，disclosure 隐藏。通过，已查看实际截图。 |
| 详情内容、输入和键盘 | 本地化示例与键盘页内容保持在详情列内；软件键盘上方可提交，横屏仍可操作。复测通过。 |

首轮详情／键盘测试失败：等待软件键盘超时。失败 AX 记录证明 `keyboard.input` 已 `Keyboard Focused`，但系统仅提供 68 pt 高的附件栏。切换 Simulator 的硬件键盘连接后，以原断言、原点击步骤重跑通过；没有添加第二次点击绕过。首轮失败保留。

截图和完整结果存于 `/tmp/quicklayout-split-evidence/`：

- `ipad-window-column.xcresult`：系统窗口和列宽通过、首轮键盘失败的结果。
- `ipad-detail-keyboard-final.xcresult`：原键盘测试复测通过。
- `system-window-collapsed-menu-0.png`：375 pt 真实窗口的无选中高亮／有箭头目录。
- `split-column-drag-2.png`：展开后的无箭头选中项及计数 4。
- `system-window-restored.png`：恢复全宽窗口。
- `manifest.json`、`detail-final/manifest.json`：原始附件索引。

## 自动化与对照

- 首轮聚焦测试 4 项中 2 项失败：英文搜索词与模拟器当前中文语言不一致；非滚动轴旧偏移导致内容越过右侧安全区。
- 搜索断言改为使用实际本地化标题；修复滚动偏移后，同一组 4 项全部通过。
- 新增真实 Split 容器内的非对称安全区／列宽几何回归，以及安全区域示例基线文本边界回归。这些属于容器几何测试，与上述真实系统手势证据分开统计。
- iPad 上菜单、搜索、本地化、折叠展开、动态布局与安全区回归 25/25 通过，结果保留为 `/tmp/quicklayout-split-evidence/ipad-regression-25.xcresult`。
- iPhone 17 / iOS 27.2 上同组回归 22 通过、0 失败，3 项仅适用于 iPad 展开分栏的测试按条件跳过。结果保留为 `/tmp/quicklayout-split-evidence/iphone-regression-22.xcresult`。
- 上述 25/22 项结果属于撤回 `.always` 之前的快照。原基线文本边界测试已改为 `splitSafeAreaScenariosPreserveModifierContrast()`，在三个列宽下验证 baseline → zeroAll → baseline 的页面范围与默认 inset 策略；撤回后的验证单独记录。
- 撤回后的验证（17:15，iPad）：`splitSafeAreaScenariosPreserveModifierContrast()`、`safeAreaPaddingDemoCoversQuickLayoutCombinations()`、`safeAreaPaddingDemoFollowsLandscapeSafeAreaChanges()` 三项均通过，测试执行共 2.691 秒。MCP 首次读取报告 xcresult 未写完；随后直接读取 Xcode 实际日志目录的结果包，确认 3/3 通过，已归档到 `/tmp/quicklayout-split-evidence/scenario-automatic-final.xcresult`。
- 库测试使用仓库 `Package.swift`、`Sources`、`Tests` 的临时副本，在 iPhone 17 / iOS 27.2 上运行：190 个测试方法，188 通过，2 失败。新双轴 inset／主轴位置回归的两个参数分支均通过。
- 两个库失败为 `cellFittingUsesSubclassMeasurementWithoutMeasuringBodyAgain()` 和 `gradientViewUsesGradientAsItsRootLayerAndUpdatesConfiguration()`。用 Git HEAD 的原始 `QuickLayoutScrollView.swift` 对照后，两项同样失败；新增 inset 回归在旧实现的两个轴上均失败，证明新用例能够捕获修复的问题。未修改这两项无关行为。
- 库完整结果：`/tmp/quicklayout-split-library-test.xcresult`；修改前对照：`/tmp/quicklayout-split-library-baseline-final.xcresult`。日志已复制到证据目录。

## 构建与环境记录

### 非滚动轴对齐与主轴动画修复

- 审查发现，原先在 `applyPendingScrollIfPossible()` 之后调用无动画 `setContentOffset`，会在需要校正旧交叉轴偏移时覆盖主轴滚动动画。
- 修复改为只更新 `bounds.origin` 的交叉轴，并先完成对齐、再处理延迟滚动。每轮布局维持单轴对齐，避免动画后续帧重新带回旧交叉轴位置。
- 新增 Demo 宿主测试，使用真实 `UIScrollView` 滚动动画和完成代理回调。测试子类明确保留内容尺寸变化前的交叉轴偏移，以重现本修复针对的状态；不是将此注入状态当作系统窗口手势证据。
- 最初只改变 inset 的测试在新旧实现中都通过，说明 UIKit 自动对齐会漏测修正分支。补全旧偏移条件后，修复前两个参数化测试的横／竖四个分支全部失败：运行中动画不再前进，延迟动画无法正常完成。
- 修复后，同一组动画用例及分栏非对称安全区、Scenario 对比、滚动边距回归共 5 个测试、7 个执行分支全部通过（iPad mini / iOS 27.2）。测试检查主轴继续前进、最终到达目标、完成回调，以及交叉轴正确对齐。
- 对照失败包：`/tmp/quicklayout-split-evidence/scroll-animation-baseline-failed.xcresult`；最终通过包：`/tmp/quicklayout-split-evidence/scroll-animation-final.xcresult`。MCP 曾提前报告结果包未完成；随后直接读取实际包确认最终状态并归档。
- 本次未重跑完整库测试，也未将程序滚动动画用例视为真实手势减速验证。修复未使用 iOS 15 之后的新 API；仍无 iOS 15 运行时实测。

### 构建工具

- 实际 workspace `QuickLayoutKit.xcworkspace` 构建成功，0 编译错误，Demo 保持 iOS 15.0 deployment target。
- 初始独立项目构建遇到 SwiftProtobuf 插件问题：Demo 项目锁定 1.38.1，实际 workspace 锁定 1.39.0。后续使用 workspace，没有修改依赖锁定版本。
- `AdaptiveNavigationRegression` scheme 在 Xcode 的测试发现中将 Swift Testing 用例标记为禁用，因此 Demo 单元测试使用 `Demo` scheme 精确选择；UI 测试使用原适配 scheme。
- workspace 的自动生成库 scheme 没有可执行测试 bundle，库回归改用隔离的临时 Swift package。首次基线对照还遇到测试进程建连前终止，后续单独重跑完成；该环境失败不计入应用测试通过数。

## 减速与尺寸变化的手势验收

以下是 **2026-11-03 的历史验收方法与结果**。用于采集该证据的临时 App 代码和专用录制用例已于 2026-11-04 清理；下文的类名、启动参数及内部驱动接口用于说明证据如何取得，不代表当前代码仍提供这些入口。离线 JSON 核验脚本与原始证据保留。

- `testRecordGestureScrollingDuringGeometryChanges()` 用 XCTest 原生触摸先甩动列表，再拖动 Split 分隔线／SpringBoard 窗口角。分别覆盖列宽增大、减小，以及窗口缩小、放大；不设置窗口 frame、列宽属性或 contentOffset。
- `-quicklayoutkit.traceSplitScroll` 仅在 Debug 下启用只读 CADisplayLink 记录器和 120 项测试列表。正常启动仍使用原列表；不改变 decelerationRate，不替换滚动代理。记录实际窗口、列宽、adjustedContentInset、contentOffset 及减速状态，输出 App Documents 中的 `SplitScrollGestureTrace.json`。
- XCTest 默认的事件前后空闲等待会错过减速阶段。这个专用用例在测试进程内临时替换 `XCUIApplicationProcess` 的两个空闲等待查询，结束时恢复；触摸仍使用 XCTest API。该辅助逻辑依赖当前 Xcode 内部接口，接口不可用时明确跳过，不进入 Demo 或库目标，也不作为 iOS 15 产品 API 使用。
- UI 测试的通过只证明四种实际尺寸变化发生。必须另外运行 `python3 Scripts/verify-split-scroll-trace.py <trace.json>`，核对四种变化均与 `isDecelerating` 重叠、重叠后继续移动、无超过 0.5 pt 的反向步进，以及交叉轴对齐。覆盖缺失返回非零退出码；最终还须结合录像和原始采样检查突跳。
- 前两轮手势确实改变尺寸，但减速先结束，不能算作减速重叠通过。第二轮完整记录有 318 个采样，四种重叠均为零，横向对齐误差为 0 pt。原始文件为 `/tmp/quicklayout-split-evidence/gesture-xctest-round2.json`，录像为同目录 `gesture-overlap-round2.mp4`；核验脚本对该记录返回失败，保留作为覆盖缺失的对照。
- 第三轮初次尝试遇到 Xcode MCP 连接关闭，未进入手势阶段；容器中的采样仍是第二轮旧文件，不能计为新结果。随后通过独立构建／测试入口重跑，不把工具连接状态当作用例状态。

### 最终手势结果（19:03–19:06）

独立入口完成构建和测试，xcresult 为 1 通过、0 失败、0 跳过。测试工具曾因等待超过 300 秒返回超时，底层构建仍继续；最终直接读取完整 xcresult 确认通过。未改依赖版本或锁文件。

第三轮重跑使用 8000 pt/s 的 XCTest 甩动速度（基准甩动仍为 1400），实际减速由 UIScrollView 默认参数产生。四项均采到尺寸变化与 `isDecelerating == true` 重叠；从首次重叠到减速最后一个采样，主轴继续同向移动：

| 实际操作 | 实际几何变化（pt） | 重叠后继续减速 | 重叠后主轴位移 |
| --- | --- | --- | --- |
| 列宽增大 | 265 → 293；窗口 1158×756 不变 | 1.950 秒 | +286 pt |
| 列宽减小 | 293 → 260；窗口 1158×756 不变 | 1.922 秒 | −261.5 pt |
| 窗口缩小 | 1158×756 → 839×665.5 | 1.128 秒 | +212 pt |
| 窗口放大 | 839×665.5 → 1110×756 | 0.420 秒 | −23 pt |

- 完整记录 563 个采样，四项重叠后均无反向步进；自然结束减速后未观察到位置重置。采样中的最大横向误差 `abs(offsetX + adjustedInsetLeft)` 为 **0 pt**。
- 左侧 adjusted inset 随列宽变化为 281 → 286 → 309 → 276 pt，并非固定 inset 的空验证。`contentWidth` 与 `bounds.width - adjustedInsetLeft - adjustedInsetRight` 的最大误差为 **0 pt**；底部 inset 实际经历 28 / 18 pt。
- 已核对测试截图及录屏抽帧，窗口和内容确实发生变化。结论为：本轮四项操作未取消惯性减速，未观察到交叉轴漂移或主轴位置重置。
- **证据边界：**真实系统缩放期间，连续减速采样的最大时间间隔为 **0.789 秒**，录像为 10 fps。这不能证明未采到的每一帧都连续，也不能作为零掉帧／零卡顿的性能验收。没有通过修改滚动物理参数掩盖该限制。
- 这一轮只增加／完善本任务的 Debug 手势采样、测试夹具、UI 测试、核验脚本和验证记录，没有新增聊天业务逻辑，也未进一步修改库的滚动实现。

证据位于 `/tmp/quicklayout-split-evidence/`：

- `gesture-round3-retry.xcresult`、`gesture-round3-result.json`：最终测试结果。
- `gesture-round3-retry.json`：原始采样；`gesture-round3-verification.json`：四项覆盖、对齐和宽度核验。
- `gesture-round3-retry-actions.mp4`：原始录屏；`gesture-final-22s.mp4`：原片 182–204 秒的无重编码节选；`gesture-round3-attachments/manifest.json`：六张测试截图及时间戳。
- `gesture-round3-build-test.log`：构建、原生触摸、实际几何变化和测试通过日志。
- `gesture-round2-verification.json`：同一核验脚本对无重叠记录返回失败的对照。

## 临时验证代码清理（2026-11-04）

- 移除 `SplitScrollTraceRecorder`、SceneDelegate 的记录器持有与启动参数分支，以及 Dynamic Scroll 的 120 项测试列表分支；两个业务文件恢复到本任务修改前的内容。
- 移除仅用于录制减速重叠的 `testRecordGestureScrollingDuringGeometryChanges()`、XCTest 内部空闲查询替换、对应的 ObjectiveC 导入，以及只服务该用例的额外启动参数传递。
- 保留运行中滚动动画、延迟滚动动画的横／竖参数化回归，非对称安全区／列宽回归，SafeArea Scenario 对比，以及真实系统窗口和 Split 列宽拖动的 UI 回归。
- 保留 `Scripts/verify-split-scroll-trace.py` 作为已有 JSON 的离线复核工具；它不再依赖当前 Demo 中的采样入口。原始 JSON、录像、截图、通过结果及未命中重叠的对照记录保持不变。
- 清理仅涉及本任务临时代码，分栏适配和 `QuickLayoutScrollView` 修复保留；未触及聊天业务或 Git 暂存区。
- 清理后使用实际 workspace／Demo scheme 在 iPad mini / iOS 27.2 重新构建并执行上述两项参数化动画回归、非对称安全区回归和 Scenario 对比回归：**4 个测试方法通过，0 失败、0 跳过**。结果为 `/tmp/quicklayout-split-evidence/cleanup-regression-20261104.xcresult`。本轮没有重跑真实系统窗口／列宽 UI 手势，历史验证结果仍保留。
- 离线脚本复核最终采样返回 0，复核无重叠对照返回 1；`git diff --check` 通过，Demo 源码中已无临时采样器或专用启动参数引用。

## 提交前审查（2026-11-04）

- 核对实现、重命名引用、回归测试和验证记录，未发现需要阻止提交的代码问题；未包含新增聊天业务或临时采样代码。
- SafeArea 页面原有用户暂存的 `.always` 与工作区 `.automatic` 不一致。说明它与 Scenario 回归的冲突后，用户最终确认保留工作区 `.automatic` 和原 Scenario 对比；同步暂存区后，该文件相对 HEAD 无净改动。
- 将两份原始采样原样归档到本目录下的 `Validation/SplitView-2026-11-03/`，避免离线核验依赖本机临时目录。完整录像、截图和 xcresult 仍按上文记录保留在本机证据目录。
- 审查沿用清理后已通过的 4 个测试方法（含横／竖参数化，共 6 个分支）；此后仅补充证据与文档，没有修改已验证的 Swift 实现。

在仓库根目录复核已归档证据：

```sh
python3 Scripts/verify-split-scroll-trace.py Docs/Validation/SplitView-2026-11-03/final-trace.json
# 预期退出码 0：四项减速重叠及对齐均满足检查。
python3 Scripts/verify-split-scroll-trace.py Docs/Validation/SplitView-2026-11-03/no-overlap-trace.json
# 预期退出码 1：真实尺寸变化发生，但没有减速重叠，不能算通过。
```

## 覆盖边界

- 已验证运行时为 iOS 27.2 模拟器；没有 iOS 15 模拟器，也未运行 iOS 15 真机。iOS 15 兼容结论限于 deployment target 编译与此次变更的 API 可用性。
- 本轮未覆盖物理 iPad、鼠标／触控板、VoiceOver、所有页面／弹窗的完整组合，也未重复两 App 并排系统场景。
- 键盘验证完成后已恢复 Simulator 原先的硬件键盘连接设置。
