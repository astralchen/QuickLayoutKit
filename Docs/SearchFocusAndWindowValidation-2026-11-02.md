# 搜索焦点与系统窗口验证（2026-11-02，后续审查）

本轮保留此前动态布局修改，不提交 Git。优先移除 UI 测试中清空后的再次点击，复现并修复真实输入行为，再验证系统窗口操作。本报告补充并更新 `AdaptiveLayoutAudit-2026-11-02.md` 的未完成项。

## 搜索焦点：复现、归因与修复

基线操作：在 iPad mini（A17 Pro）/ iOS 27.2 Simulator 搜索 UIKit → 打开详情 → 再次编辑搜索 → 点击搜索框内的清空按钮 → 直接输入 Directional。没有再次点击输入框。两次基线均失败，实际键盘收起，XCTest 报告输入框没有键盘焦点。

临时诊断记录确认，清空前 UISearchController.active 和 UITextField.isFirstResponder 均为 true。清空时 UIKit 自身执行以下链路，先取消搜索呈现，再结束编辑：

```text
UITextField _clearButtonClicked:
UISearchTextField _delegateShouldClear
UISearchBar _searchBarTextFieldShouldClear
UISearchBar _performCancelAction
UISearchController _searchBarCancelButtonClicked:
UISearchController _dismissPresentation:
UISearchBar resignFirstResponder
UITextFieldTextDidEndEditingNotification
```

现场调用栈：`/tmp/quicklayout-search-window-audit-20261102/search-focus-before.log`。诊断代码已从应用移除，不使用私有 API 修复。尝试公开的 `automaticallyShowsCancelButton = false` 后同样失败，该配置已撤销。

这不是 QuickLayoutKit 测量或环境失效造成的焦点丢失。观察到的原生行为也与 Chromium 自身的 iPad 搜索测试说明一致：新系统中清空会同时关闭搜索。该外部材料仅作佐证，根因依据本工程实测调用栈。[Chromium 原始测试代码](https://chromium.googlesource.com/chromium/src/+/195cd5eca9542e3f0c81fe394ffe817838f3b142/ios/chrome/test/earl_grey/chrome_earl_grey_ui.mm)。Apple 的 `automaticallyShowsCancelButton` 只控制取消按钮的自动显示，不提供“清空后保留搜索呈现”的策略。[Apple API 说明](https://developer.apple.com/documentation/uikit/uisearchcontroller/automaticallyshowscancelbutton)。

目录需要清空后继续输入。实现使用 UISearchTextField 公开的 `rightView` 提供独立清空按钮，同时关闭它的内置 clearButton。动作仅更新搜索文本和筛选状态；不调用 isActive、becomeFirstResponder、延迟重聚焦或内部 delegate。仍保留原生 UISearchController、输入框、导航层级及系统取消搜索。按钮有 44×44 的交互区域，英文／简体中文／阿拉伯文可访问性名称；空查询时隐藏。没有按设备型号切换实现。

修改文件：

- `Demo/Demo/Features/Main/MainViewController.swift`
- `Demo/Demo/Localizable.xcstrings`
- `Demo/DemoTests/AppNavigationTests.swift`
- `Demo/DemoUITests/AdaptiveNavigationUITests.swift`

## 最小复现与 API 建议

本工程的最小操作路径就是上述 5 步，不需要旋转、调整尺寸、切换语言或重建列表。原生问题的关键配置为：

```swift
let search = UISearchController(searchResultsController: nil)
search.obscuresBackgroundDuringPresentation = false
navigationItem.searchController = search
navigationItem.hidesSearchBarWhenScrolling = false
navigationItem.preferredSearchBarPlacement = .stacked
// 在 iPad 的 split primary 导航中激活搜索、输入文本，点击内置 Clear。
// 观察 isActive / textDidEndEditing；不加入任何结束编辑逻辑。
```

上述代码摘录表达需提交给 UIKit 的复现配置；本轮运行证据来自真实目录控制器与记录的 UIKit 调用栈，尚未另建独立 Xcode 样例工程。可以向 UIKit 提出独立的 clear-action 策略，使清空文本与取消呈现能分别配置。QuickLayoutKit 不应接管 UISearchController 的编辑生命周期。

## 串行回归

运行时原始结果包位于（Xcode 会按保留策略清理旧包）：
`/Users/sondra/Library/Developer/Xcode/DerivedData/QuickLayoutKit-gvhlwctdffgjmscwtleqxnrbfrno/Logs/Test/`

| 批次 | 结果 | 原始结果包 |
| --- | --- | --- |
| 移除再次点击后的基线 | 1 失败 | `Test-AdaptiveNavigationRegression-2026.11.02_14-23-20-+0800.xcresult` |
| 加调用栈诊断的基线 | 1 失败 | `Test-AdaptiveNavigationRegression-2026.11.02_14-27-11-+0800.xcresult` |
| 关闭自动取消按钮显示的对照 | 1 失败，未保留此方案 | `Test-AdaptiveNavigationRegression-2026.11.02_14-30-31-+0800.xcresult` |
| 独立清空动作，多页面导航流程 | 1 通过 | `Test-AdaptiveNavigationRegression-2026.11.02_14-34-09-+0800.xcresult` |
| iPad 导航及语言／RTL 单元回归 | 29 个测试方法通过 | `Test-Demo-2026.11.02_14-39-20-+0800.xcresult` |
| 连续清空输入，竖→横→竖，不再次点击 | 1 通过 | `Test-AdaptiveNavigationRegression-2026.11.02_14-36-50-+0800.xcresult` |

补充证据目录：`/tmp/quicklayout-search-window-audit-20261102/results/`。已另存本轮控制台日志；最终分屏与侧栏批次原始包也已复制到该目录。较早原始包被 Xcode 清理后，以运行时返回结果、当时核对记录及另存日志为证，不声称旧包仍在 DerivedData。

最终 UI 批次：

| 设备／场景 | 结果 | 原始结果包 |
| --- | --- | --- |
| iPad 真实自由窗口持续拖动与往返恢复 | 1 通过 | `Test-AdaptiveNavigationRegression-2026.11.02_15-08-26-+0800.xcresult` |
| iPad 真实双应用分屏、分隔线、清空输入、旋转、侧栏按钮 | 1 通过 | `Test-AdaptiveNavigationRegression-2026.11.02_15-20-52-+0800.xcresult` |
| iPhone 17 搜索清空、推入／返回、旋转、多页面键盘 | 3 通过、0 失败 | `Test-AdaptiveNavigationRegression-2026.11.02_15-23-43-+0800.xcresult` |
| iPhone 17 导航／动态布局／语言与 RTL 单元组 | 28 方法通过、1 跳过、0 失败 | `Test-Demo-2026.11.02_15-36-57-+0800.xcresult` |

新增单元回归验证清空后第一响应者、搜索呈现、选中路由和详情实例保留；循环内不重新请求焦点。新增 UI 回归直接输入下一条查询，经过三次方向状态与六次清空，末尾再输入 Geometry。

## 系统分屏与自由窗口

本轮通过 XCUITest 对 SpringBoard 的窗口边框执行持续触摸拖动，未修改应用 UIWindow / UIView 的 frame。iPad mini（A17 Pro）/ iOS 27.2 的真实窗口尺寸依次为：

`1133×744 → 375×486 → 635×621 → 375×486 → 935×621 → 1133×744`

每步保留同一个 Counter 详情和已增加至 4 的计数，短窗口通过真实 swipe 将按钮完整滚到浮动 Tab 栏上方，检查水平边界；恢复全屏后目录和详情同时可用。最终回归通过：`Test-AdaptiveNavigationRegression-2026.11.02_15-08-26-+0800.xcresult`。截图位于 `/tmp/quicklayout-search-window-audit-20261102/resize-final/`，录像为同级 `system-resize-final.mp4`。

首轮 `15-00-11` 在四次拖动和状态检查后失败：末步已被系统吸附为全屏，测试仍尝试点击仅自由窗口存在的控件。保留该失败；后续根据实际窗口状态决定恢复操作，并将终点移离吸附边缘。未为此改动应用布局。

系统“左右排列”通过原生窗口菜单执行，并从系统选择器选择“设置”，形成两个真实应用窗口。正式回归 `15-17-45` 通过：Demo 宽度 `561.5 → 458 → 661.5` 点，高度 621 点；搜索 Frame → 清空 → 不再次点击直接输入 Counter → 打开详情 → 加至 4 → 拖动系统分隔线 → 竖屏 → 横屏 → 恢复全屏，状态保留。截图位于 `/tmp/quicklayout-search-window-audit-20261102/tile-final/`。竖屏时系统按最小窗口宽度重新排列窗口，右侧“设置”可位于后方；不将系统的重叠排列当作 Demo 内容越界。

窗口控件探查不计入正式通过数量。“设置”界面不保证存在 UITableView，正式测试使用其系统窗口卡片和真实边界验证双应用，不断言其他应用的内部视图类型。`15-16-07` 保留了该错误假设造成的失败；后续截图可见“设置”实际内容已加载。

探查期间保留了定位失败：全屏没有自由窗口按钮、读取激活动画中的非最终窗口边界、XCTest 不支持 hittable 查询谓词，以及未归一化跨启动保留的窗口大小。均修正测试环境操作，不修改页面或放宽应用布局断言。

录像使用 AVAssetImageGenerator 的精确时间（前后容差均为零）抽帧核对，避免默认关键帧容差重复返回同一画面。`video-final-contact.png` 保留 3 秒采样图；可见拖动中间尺寸的重排、单栏／双栏转换及滚动到达。该证据不是逐帧性能分析，不涵盖硬件指针或旧版 Split View 系统。

最终侧栏增强批次 `Test-AdaptiveNavigationRegression-2026.11.02_15-20-52-+0800.xcresult`：**1 通过、0 失败**，原始结果包汇总已核对。额外执行 Hide Sidebar → Show Sidebar，确认 Counter 搜索词、选中路由和计数保留。结束后恢复全屏与竖屏，并终止本轮打开的“设置”。两个系统窗口用例仅在 iPadOS 26+ 执行；并排系统选择器当前支持中文／英文“设置”图标，需设备已启用系统窗口模式。未改变系统多任务设置。

## 本轮仍未执行的边界

- 真机触控板／鼠标指针和硬件键盘；模拟器的坐标鼠标操作未可靠转发为触摸，因此不计入通过，实际窗口回归由 XCUITest 的触摸事件完成。
- iOS 26 之前的传统 Split View / Slide Over、旧版运行时；本轮实际系统分屏运行于 iOS 27.2 窗口模式。
- 全目录每个 Popover、照片选择器、最大辅助字体／VoiceOver 的完整交互矩阵；此前的相关几何和 RTL 回归继续保留。
- 原生搜索行为尚未另建独立 UIKit 工程，最小操作路径、关键配置、实际调用栈和失败日志已给出。

这些边界不以构建成功、控制器 frame 测试或截图代替验收。本轮没有修改 QuickLayoutKit 框架实现；保留此前布局修复，未提交 Git。

## 最终构建与检查

- Xcode MCP `BuildProject(buildForTesting: true)`，Demo / iPhone 17：成功，0 编译错误，19.119 秒。日志：`BuildProject-Log-20261102-154407.txt`（ActionArtifacts/default/BuildProject）。
- iPhone 单元组原始 `.xcresult` 顶层汇总为 **28 通过、1 跳过、0 失败，总计 29 方法**；参数展开后的设备计数为 29 通过、1 跳过，二者不混用。跳过项为 `splitCollapseAndExpansionPreserveSelectedController()`，iPhone 原生紧凑导航不运行该 iPad 展开场景；该项已在 iPad 通过。
- `Localizable.xcstrings` JSON 解析和 `git diff --check` 通过。
- 本轮直接修改 6 个文件：MainViewController、Localizable.xcstrings、AppNavigationTests、AdaptiveNavigationUITests，以及本报告与初轮审查报告。此前框架／页面／测试的其他修改保留；没有 Git 提交。

收尾检查发现工作区在 15:25 出现并行的 `.docked` → `.followsDockedKeyboard` 命名调整（包括 VoiceRoomViewController 和包测试等文件）。这些内容未由本轮搜索修复引入，按现状保留，未覆盖或归入本轮新增修复。最终 Demo 构建发生于该调整之后；本轮没有额外运行整套包测试。
