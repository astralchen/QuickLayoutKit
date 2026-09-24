# Frame 实验室视觉与交互验收

final result: passed

最新的方案 1／方案 3 切换与用户补充参考图验收见文末「双方案切换最终验收」；此前章节保留为初版与闪烁修复记录。

本次将选定的方案 1 实现为现有 Demo 内的 UIKit / QuickLayoutKit 页面。验收结论覆盖下列原生适配与验证范围，不表示对概念图逐像素复刻或完成真机验证。

## 对照材料与尺度

- 设计源：`/Users/sondra/.codex/generated_images/01a0cde1-0441-7323-8e36-10193d17e705/exec-3c873500-a618-410d-9368-a265d64ee0f1.png`，853 × 1844 px，设计逻辑画布约 390 × 844 pt，不含系统状态栏。
- 实现截图目录：`/Users/sondra/.codex/visualizations/2026/09/23/01a0cde1-0441-7323-8e36-10193d17e705/frame-lab/`。
- 实现设备：iPhone 17 Pro / iOS 26.5，402 × 874 pt、3× 密度，截图 1206 × 2622 px。CSS 尺寸不适用。
- 对照状态：简体中文、浅色、固定尺寸、双轴、容器宽度 100%、高度 200 pt、内容拉伸关闭。
- 整页证据：设计源与 `frame-lab-default.png` 已在同一次图像检查中一起查看。密度按源图约 2.187 px/pt、实现 3 px/pt 换算解释；未把截图像素直接当成布局点数。
- 代码区证据：设计源与 `frame-lab-code.png` 已在同一次图像检查中一起查看，重点阅读等宽字体、高亮、换行与解释文字。实现截图为滚动后的状态，仅对照对应的代码区域。
- 附加状态：`frame-lab-dark.png`、`frame-lab-arabic-alignment.png`，以及六个场景与拉伸状态截图。

## 检查结果

| 检查面 | 结论 |
| --- | --- |
| 字体与文字层级 | 系统中文字体配合等宽代码，保留品牌小标题、主标题、次要说明和代码层级；代码完整显示并允许换行。 |
| 间距与布局 | 保留介绍、场景选择、预览、参数、拉伸开关、代码的顺序；16 pt 页面边距和分组圆角。系统导航、安全区域、真实 200 pt 预览使页面比概念图更长，代码区通过纵向滚动完整到达。 |
| 颜色 | 页面局部明确使用 systemBlue，消除 Demo 默认紫色影响；灰色虚线、蓝色外框和橙色内容分别配文字图例。深色模式已实际检查。 |
| 图形与清晰度 | 边界是布局中的真实 UIView / CAShapeLayer，属于被演示内容，没有用静态图代替交互。按钮采用 SF Symbols，文字和边线清晰。 |
| 文案与数据 | 保留设计稿标题和介绍；测量值来自真实视图。Hello 自然宽度依字体为约 55 pt，不照搬概念图 64 pt；frame 固定尺寸实测为 120 × 64 pt。 |

原生适配：保留工程语言菜单与 iOS 26 原生导航控件；测量值放在预览下方，避免在撑满和小尺寸场景中覆盖被测内容。代码区保留独立复制按钮和成功反馈。未发现剩余阻塞使用或误导 API 语义的 P0 / P1 / P2 问题。

## 发现与修复记录

1. 实际截图中滑块、场景箭头与复制图标继承了紫色，偏离方案 1（P2）。已在页面设置蓝色 tint，并单独设置重置和语言按钮颜色；最终默认截图确认修正，UI 测试再次通过。
2. 大字号测试发现滑块外框为 44 pt、滑块本体仍为 34 pt（P2）。已改为滑块自身双轴 resizable，再设置高度；复跑六项测试全部通过。
3. 代码区首屏未完全出现，需要确认可达性。新增 UI 断言验证滚动后代码可命中且整体 frame 位于窗口内；保存 `frame-lab-code.png`，确认代码与说明完整可读。

## 验证结果与限制

- Demo 模拟器构建：通过。
- 聚焦单元／布局／入口测试：6 通过，0 失败，0 跳过。覆盖 frame 与内容独立尺寸、min/max、ideal、撑满、链式顺序、九种 LTR/RTL 对齐、72 组页面场景/语言/尺寸组合、大字号控件及首页路由。
- UI 测试：中文六场景操作、滑块、选项、拉伸、复制成功反馈、重置及阿拉伯语对齐，共 2 项通过。补充代码可见性后，中文操作用例再次通过。
- 界面目视检查：浅色、深色、RTL、默认预览、理想尺寸、链式组合和代码区域已查看。
- 静态检查：`git diff --check` 通过；新增 47 个本地化键均含英文、简体中文和阿拉伯语。
- 单元测试结果包：`/private/tmp/FrameLabUnitFinal.xcresult`。
- UI 结果包：`/private/tmp/FrameLabUIFinal.xcresult`；代码可见性补充：`/private/tmp/FrameLabCodeVisibility.xcresult`。
- UI 构建原先被已有 `ChatMessageMenuUITests.swift:208` 的编译器类型检查超时阻塞。本次 UI 验证命令使用 `EXCLUDED_SOURCE_FILE_NAMES=ChatMessageMenuUITests.swift`；该聊天测试文件未修改，不能将结果描述为整个 UI 测试目标无条件通过。
- 真机、独立 iPad UI 操作、VoiceOver 朗读：未执行。窄屏、横屏和大字号覆盖来自布局测试，不等同于这些环境的手动视觉验证。

## 后续细节

- P3：链式组合的四组尺寸在较窄空间会换行，后续可进一步优化成分组读数；当前所有数值可读，没有裁切。

## 宽度调节闪烁修复（2026-09-24）

- 原因：滑块每次 valueChanged 都执行完整刷新，清空并重新插入分段选项，反复重建选中背景。
- 修复：容器尺寸调节仅刷新尺寸控件、预览和布局；完整刷新也仅在选项文字变化时重建分段。切换选项时保留分段视图。
- 修复前新增回归在连续调节时捕获分段视图替换和菜单重建，产生 11 条失败断言；该测试进程在收尾阶段停滞，记录日志后终止。
- 修复后 Frame Lab 六项单元／布局回归通过，0 失败、0 跳过，包含控件身份稳定性、选择状态、预览尺寸与场景／语言文字刷新。结果：`/private/tmp/FrameLabFlickerAfter.xcresult`。
- iPhone 17 Pro / iOS 26.5 模拟器连续往返拖动宽度 UI 测试 1 项通过。结果：`/private/tmp/FrameLabFlickerUI.xcresult`。沿用上文聊天测试文件编译排除项。
- 拖动后的截图已检查；控件不重建由运行时回归断言验证，未进行逐帧录屏或真机验证。

## 双方案切换最终验收（2026-09-24）

final result: passed

### 视觉基准与原生适配

- 以用户最新附图为方案 3 的视觉基准：`/var/folders/_b/4kvsp2_s0ss21dbxf2_s7bnh0000gn/T/codex-clipboard-8c652e6f-f733-40d4-a80c-97fb84f8f540.png`。
- 基准副本及最终截图目录：`/Users/sondra/.codex/visualizations/2026/09/23/01a0cde1-0441-7323-8e36-10193d17e705/frame-lab/presentations/`。
- 基准 `reference.png` 为 853 × 1844 px，约 390 × 844 pt 的概念画布；原生截图为 iPhone 17 Pro / iOS 26.5、402 × 874 pt、3×、1206 × 2622 px。CSS 不适用，按逻辑点数比较内容结构，未宣称逐像素一致。
- 原生系统状态栏、iOS 26 导航按钮和用户要求新增的固定方案切换区占用顶部空间。实验区独立滚动，代码不要求首屏完整出现，已通过窗口包含和可点击断言验证可达性。
- 默认打开方案 1；方案 3 首次打开／重置展示参考图中的对齐实验，选择顶部前缘，容器宽度 100%、高度 180 pt。内容尺寸仍来自测量，中文当前约 55 × 28 pt，未写死稿中的 72 × 32 pt。

### 对照证据与检查结果

最终 `option3-light.png`、`option3-controls-code-light.png` 和用户参考图已在同一图像检查输入中一起查看，分别核对整页组织及九宫格、参数、代码细节；`option1-dark.png`、`option3-dark.png`、`option3-controls-code-dark.png`、`option3-arabic-dark.png` 已实际打开检查。

| 检查面 | 结果 |
| --- | --- |
| 字体与层级 | 保留场景标题、灰色观察提示、ALIGNMENT 标签、操作标题、蓝色 API 名称及加粗对齐说明；代码等宽换行完整可读。对齐名称沿用工程的前缘／后缘语义以适配 RTL。 |
| 间距与结构 | 场景菜单与前后按钮独立成行；预览、操作区、带范围的高度滑块和更多参数置于同一大卡片，用细线分隔；代码另置卡片。九宫格采用 48 pt 点击区域，窄屏和大字号改为上下排列。 |
| 颜色与状态 | 系统灰底、浅／深色卡片、蓝色选中态、橙色内容、灰色图例；高亮、禁用和选中状态可辨认。 |
| 图形与清晰度 | 三层尺寸来自真实布局视图，九宫格为可操作按钮，图标为 SF Symbols，无截图替代实际界面。撑满时 frame 与容器重合，边界也会重合。 |
| 文案与内容 | 保留参考图的观察标题、九宫格说明、140／280 范围与更多参数副标题；尺寸读数使用真实值。RTL 数字加入方向隔离，保持宽 × 高顺序。全部 72 个 Frame Lab 本地化键包含中英阿三种语言。 |

### 本轮发现与修复

1. 第一版仅复用了方案 1 的分组风格，未充分还原用户指定的方案 3。已改为独立导航、大卡片分区、九宫格旁的说明层级、滑块范围及独立代码卡片，并以用户最新附图重新对照。
2. 布局测试发现分段控件和九宫格按钮只设置了外框尺寸，实际控件仍按自然尺寸显示。改为控件双轴 resizable 后，44／48 pt 实际尺寸断言通过。
3. 更多参数副标题居中、箭头紧随标题，偏离参考行结构。改为 leading 标题对齐与 fill 水平布局，最终浅／深色截图确认标题、副标题沿前缘排列，箭头位于后缘。
4. 阿拉伯语观察提示中的宽高可能被双向文本重排。已隔离数字片段，最终 RTL 截图确认观察提示与实测读数均显示宽 × 高。
5. 首轮 UI 测试两项失败来自测试操作：RTL 按钮索引镜像后选择了错误方案，以及在 Home 手势区拖动部分可见滑块而切换应用。改为本地化标题定位及先将滑块滚离系统手势区域，复跑两项均通过。

### 验证结果与边界

- 模拟器构建通过；`git diff --check` 通过。
- 8 项单元／布局测试通过：独立状态、独立滚动恢复、当前方案重置、九宫格及 RTL、六场景几何、两套 UI 的 144 组语言／尺寸／场景／宽度组合、大字号、分段／九宫格视图身份稳定性和本地化。结果：`/private/tmp/FrameLabPresentationsUnit2.xcresult`。
- 6 个 UI 用例均取得通过结果：已有三项见 `/private/tmp/FrameLabPresentationsUI.xcresult`；修正后的两项见 `/private/tmp/FrameLabPresentationsUI2.xcresult`；外观用例覆盖浅／深色。首轮结果包包含已修正的两个测试操作失败，不作为全绿结果包。
- 最后按钮排版与数字方向调整后的验证：`/private/tmp/FrameLabPresentationsDarkFinal.xcresult` 为外观及 RTL 两项通过；`/private/tmp/FrameLabPresentationsLightFinal.xcresult` 为浅色外观一项通过。最终截图均来自这两个结果包。
- UI 构建继续使用 `EXCLUDED_SOURCE_FILE_NAMES=ChatMessageMenuUITests.swift`，避开既有聊天测试类型检查超时；未改动该文件，不代表完整 UI 测试目标无条件通过。
- 真机、独立 iPad UI、VoiceOver 朗读未执行；窄屏、横屏、大字号来自布局测试。未以静态截图替代逐帧闪烁验证，控件连续调节期间不重建由回归断言验证。
- 当前无剩余 P0／P1／P2 视觉问题。保留系统导航外观、真实尺寸、固定方案切换区及由此产生的纵向滚动，属于本次原生适配范围。

## 实验模式命名优化（2026-09-24）

- 当前对外名称：原「方案 1」为「自由实验」，原「方案 3」为「引导实验」。上文方案编号属于历史设计与验收记录，保留以便追溯。
- 英文为 Freeform / Guided；阿拉伯语为 تجربة حرة / تجربة موجّهة。切换控件的可访问名称为「实验模式」/ Experiment mode / نمط التجربة。
- 本地化键改为 `frame.presentation.freeform` 与 `frame.presentation.guided`，旧 `.one` / `.three` 键和代码调用已移除；Xcode 预览使用新名称。保留 `frame.presentation` 标识、内部枚举和现有状态／布局／局部刷新行为。
- Demo 编译通过，8 项已有单元／布局回归全部通过，0 失败、0 跳过；包括独立状态与滚动位置、当前模式重置、控件身份稳定性、320 pt 窄屏、横屏、大字号与三语布局。结果：`/private/tmp/FrameLabNamingUnit.xcresult`。
- iPhone 17 Pro / iOS 26.5 上 4 项 UI 用例全部通过，0 失败、0 跳过：三语模式名称与可访问名称、默认选中和往返切换、独立状态恢复与重置、引导实验 RTL 对齐、连续宽度拖动。结果：`/private/tmp/FrameLabNamingUI.xcresult`。
- iPhone SE（第 3 代，375 pt 宽）/ iOS 26.5 上三语外观与切换用例通过，0 失败、0 跳过。结果：`/private/tmp/FrameLabNamingNarrowUI.xcresult`。
- 两台模拟器的中英阿浅色截图已目视检查：顶部名称完整，无省略或裁切；选中态可辨，阿拉伯语左右顺序正确。原始截图：`/Users/sondra/.codex/visualizations/2026/09/23/01a0cde1-0441-7323-8e36-10193d17e705/frame-lab/naming/`。
- UI 构建沿用 `EXCLUDED_SOURCE_FILE_NAMES=ChatMessageMenuUITests.swift`，该既有聊天测试文件未修改；以上结果仅代表 Frame Lab 定向验证。`git diff --check` 通过。
- 本轮未复测深色外观、真机、iPad 或 VoiceOver 实际朗读；320 pt 窄屏、横屏和大字号证据来自布局测试。未做逐帧视频检查，连续刷新稳定性由已有视图身份断言和拖动操作回归验证。

## FrameLabView 功能组件拆分（2026-09-24）

- 将页面拆为 `FrameLabViewController.swift`、`FrameLabView.swift` 和 `FrameLabComponents.swift`。控制器、展示枚举、默认状态与预览入口原样保留；`FrameLabView` 类从约 519 行缩减到 235 行。
- 页面组合六个组件：介绍、场景导航、预览、选项、参数、代码卡片。组件封装稳定控件、布局片段、样式、本地化及局部更新；不新增 UIView 容器层级。页面负责实验状态、展开状态、滚动恢复、卡片分组与弱引用事件连接。
- 保留 `previewView`、`codeLabel`、`metricsLabel` 的计算属性检查入口；底层控件由组件持有。所有原有可访问性标识保持一致。九宫格布局继续根据页面宽度及辅助功能字号选择排列。
- 尺寸变化仅更新参数、预览及实测文案；分段与九宫格继续复用，菜单和代码不随滑块重新生成。测量回调仅在读数或引导提示变化时请求页面布局。
- 首次编译发现两个滑块布局片段缺少 `@LayoutBuilder`，已补充；最终 Demo 编译和八项现有单元／布局测试全部通过，0 失败、0 跳过。结果：`/private/tmp/FrameLabComponentsUnit2.xcresult`。首次构建失败保留在 `/private/tmp/FrameLabComponentsUnit.xcresult`，不作为通过证据。
- iPhone 17 Pro / iOS 26.5 六项现有 FrameLab UI 用例全部通过，0 失败、0 跳过，覆盖六场景、复制、重置、更多参数、独立状态／滚动恢复、九宫格与 RTL、三语外观及连续拖动。结果：`/private/tmp/FrameLabComponentsUI.xcresult`。
- iPhone SE（第 3 代，375 pt 宽）三语外观／切换复跑 1 项通过：`/private/tmp/FrameLabComponentsNarrowUI.xcresult`。iPhone 17 Pro 深色三语外观／切换复跑 1 项通过：`/private/tmp/FrameLabComponentsDarkUI.xcresult`。
- 已对照重构前后中文浅色的自由实验首屏与引导实验操作／代码区截图，卡片、间距、尺寸与布局保持一致；深色截图与之前 `presentations/` 基准对照，保留此前已完成的模式命名变化。补充查看了 SE 的中英阿页面与深色英文／阿拉伯语界面，未发现本次拆分导致的裁切或 RTL 排列变化。
- 当前原始截图目录：`/Users/sondra/.codex/visualizations/2026/09/23/01a0cde1-0441-7323-8e36-10193d17e705/frame-lab/components/`。浅色基准为相邻 `naming/` 目录，深色历史基准为 `presentations/` 目录。
- 320 pt 窄屏、横屏与大字号覆盖来自现有布局测试；本轮未做这些配置的额外截图检查，未执行真机、独立 iPad 或 VoiceOver 朗读验证。未做逐帧录像；防闪烁证据为控件身份断言和连续拖动回归。
- 未新增重复测试或修改现有测试断言。UI 构建继续使用既有 `EXCLUDED_SOURCE_FILE_NAMES=ChatMessageMenuUITests.swift`；结果仅代表 FrameLab 定向验证。`git diff --check` 通过，新文件末尾空白检查通过。
- 保留现有未提交改动，不提交或推送。验证后恢复 iPhone 17 Pro 浅色外观，并关闭本轮启动的 SE 模拟器。

## Xcode 组件预览补充（2026-09-24）

- 在 `FrameLabView.swift` 增加自由实验、引导实验展开参数两项页面预览；在 `FrameLabPreviewView.swift` 增加固定尺寸和 RTL 前缘对齐两项真实布局预览。
- 在 `FrameLabComponents.swift` 增加介绍、场景导航、真实预览与读数、九宫格、分段／大字号菜单、参数、代码卡片七项组件预览。预览宿主传入实际画布宽度与字号环境，组件回调支持导航、选择、滑块、展开及复制操作。
- 新增 11 项预览，保留原有 4 项控制器预览，共 15 项。新增代码均位于 `#if DEBUG`，预览宏标记 iOS 17 可用性，不修改正式页面逻辑。
- Swift 语法检查、Debug 模拟器构建、`git diff --check` 通过。构建日志为 `/private/tmp/FrameLabPreviewsBuild.log`；日志出现一条未导致构建失败的 `DecodingError.dataCorrupted` 内部工具诊断，最终退出码为 0，结果为 `BUILD SUCCEEDED`。
- 本轮未在 Xcode Canvas 中逐一启动预览，也未重复执行模拟器 UI 回归；编译通过不等同于 Canvas 交互已验证。
