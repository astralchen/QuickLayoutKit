# Tab 布局方向调查（2026-11-02）

## 当前结论

三个硬约束继续满足：不重建 UITabBarController；容器 trait/semantic 随选择语言变化；保留 UIKit 系统浮动栏。

Demo 已切到 `/Users/sondra/Documents/GitHub/AppLocalization` 本地依赖。Xcode 解析日志确认 `AppLocalization @ local`，项目和 workspace 的 Package.resolved 仅移除了原远程 AppLocalization pin，其他依赖版本不变。

AppLocalization 原先只同步 UINavigationController 的方向 trait，对 UITabBarController 仅设置 view/tabBar semantic。工程内原型证实：没有 Demo 补丁的原生 Tab 容器在阿拉伯语下仍可能向子页面报告 LTR。现已将同样的 trait 同步放进 AppLocalization 的 `applyContainerDirection`，在子页面刷新前执行。Demo 删除了运行时重复设置，仍保留首次建视图前的初始 trait 设置。没有新增公开 API。

这修复了库的 Tab 容器 trait 同步遗漏，**未修复 iPad 原生浮动栏 RTL→LTR 的镜像残留**。

## 独立于 AppLocalization 的复现

`Experiments/TabDirectionIsolation` 是无包依赖的 UIKit App。它不加载 AppLocalization 或 QuickLayoutKit，不调用应用语言更新、appearance proxy 或重建根控制器。始终使用同一个 UITabBarController、UINavigationController 和子页面。

直接设置公开 trait 和 semantic 属性，执行 LTR→RTL→LTR→RTL→LTR，在每轮 immediate/layout/settled（等待 600ms）采样。

iPad / iOS 27.2 的稳定状态如下。轴翻转来自只读诊断 getter，并用 UIView.convert 和 CALayer.convert 独立核对。

| 状态 | Tab 容器 trait | 浮动 collection 轴翻转 | item cell 轴翻转 | 标签局部 +10x 转换到窗口 | 导航 Action 标签 |
| --- | --- | --- | --- | --- | --- |
| 首次 LTR | LTR | false | false | +10 | +10 |
| RTL | RTL | true | true | +10 | +10 |
| 返回 LTR | LTR | **true** | false | **-10** | +10 |
| 再次 RTL | RTL | true | true | +10 | +10 |
| 再次 LTR | LTR | **true** | false | **-10** | +10 |

残留位于以下层级的 collection 自身坐标边界：

```text
UILayoutContainerView
  _UITabContainerView
    _UIFloatingTabBar
      UIVisualEffectView
        _UIVisualEffectContentView
          UIView / UIView
            _UIFloatingTabBarCollectionView  ← 返回 LTR 仍保留轴翻转
              _UIFloatingTabBarItemCell      ← 已清除补偿翻转
                _UIFloatingTabBarItemView
                  UILabel
```

该 collection 的 UIView.transform、UIView.transform3D、layer.transform、layer.sublayerTransform 及 presentation transform 均为 identity；isGeometryFlipped 为 false。公开 collection layout 的 flipsHorizontallyInOppositeLayoutDirection 始终为 false，developmentLayoutDirection 始终为 LTR。不能据此把残留归因于公开 transform 矩阵未恢复。

只读内部 getter `_flipsHorizontalAxis` / CALayer `flipsHorizontalAxis` 与上述坐标变化一致。私有读取仅存在于诊断 target；正式 Demo 和 AppLocalization 没有私有 setter 或内部视图遍历修复。

## 公开刷新实验

独立 App 加 `--refresh` 后，对公开窗口/控制器/view/tabBar/navigationBar 边界执行：

- setNeedsUpdateProperties / updatePropertiesIfNeeded（iOS 26+）。
- setNeedsUpdateConstraints / updateConstraintsIfNeeded。
- setNeedsLayout / layoutIfNeeded。

上述刷新仍留下相同 collection 轴翻转，因此没有加入正式代码。Apple 将属性刷新定义为更新内容和样式、并与布局更新分开；它不是内部方向缓存清除 API：
https://developer.apple.com/documentation/uikit/uiview/updatepropertiesifneeded()

## 本轮验证

| 检查 | 结果 |
| --- | --- |
| 本地依赖基线：Demo iPad AppNavigationTests | 21 个测试，20 通过；仅 Tab 标签镜像参数化测试失败 |
| Demo 原型：不补 / 补 Tab trait | 不补时 4 个方向断言失败；补齐后该参数用例无失败 |
| 最终 Demo iPad：AppNavigationTests + NativeTabLocalizationTests | 22 个测试，21 通过；仍仅 Tab 标签镜像参数化测试失败（18 个断言，初始中文/阿拉伯文两组） |
| 最终 Demo iPhone：容器同步、标签往返、草稿焦点 | 3 个测试全部通过；标签测试含中文/阿拉伯文两个初始参数 |
| AppLocalization UIKit 容器基础测试 + 新 Tab 测试 | 12/12 通过，iPhone / iOS 27.2 |
| AppLocalization generic iOS build | 通过 |
| AppLocalization swift test（macOS） | 26/27 通过；String Catalog 编译资源测试失败 |
| 改动前 HEAD 临时副本运行相同资源测试 | 同样在 LocalizedStringResolverTests.swift:21 失败，确认不是本轮引入 |
| 仓库内独立 UIKit 复现工程 build | 通过 |

草稿测试覆盖中文→阿拉伯文→中文→英文→阿拉伯文→中文，检查相同根控制器、导航控制器、聊天页面、view model、选中 Tab、草稿文本及 isFirstResponder。每轮不重新获取焦点，直接插入“续”并核对文本；再次 synchronize 后也检查焦点。上述是模拟器宿主测试，未声称完成真机或完整 UI 点击回归。

测试日志与原始采样（本机临时产物）：

- `/tmp/QuickLayoutKit-tabs-local-suite.log` / `.xcresult`
- `/tmp/QuickLayoutKit-tabs-trait-prototype.log` / `.xcresult`
- `/tmp/QuickLayoutKit-tabs-local-final-ipad.log` / `.xcresult`
- `/tmp/QuickLayoutKit-tabs-local-final-iphone.log` / `.xcresult`
- `/tmp/AppLocalization-tab-traits-tests.log` / `.xcresult`
- `/tmp/AppLocalization-tab-traits-ios-build.log`
- `/tmp/AppLocalization-tab-traits-swift-test.log`
- `/tmp/AppLocalization-tab-baseline-resource-test.log`
- `/tmp/quicklayout-tab-layers-standalone-ipad.json`
- `/tmp/quicklayout-tab-refresh-standalone-ipad.json`
- `/tmp/quicklayout-tab-public-refresh-ipad.png`

尚未解决的范围很明确：在三个硬约束下，找到能让 UIKit 浮动 collection 清除内部水平轴翻转的受支持刷新路径。现有证据定位了残留层，不能当作已找到公开 API 修复。

## 后续：setter 调用链与缓存写回（同日）

本轮仅扩展独立工程与诊断记录，没有继续改动 Demo 或 AppLocalization 的正式实现。

### 谁设置了翻转

在 arm64 iPad / iOS 27.2 上，使用 LLDB 条件断点，限定对象为系统浮动栏 collection/layout。App 自己完成 LTR→RTL→LTR→RTL→LTR，调试器只读取状态并记录调用栈，不发起私有 setter 调用。

首次进入 RTL：

1. `UICollectionView._layoutDirectionTraitDidChange` 运行。
2. `UICollectionViewCompositionalLayout._fullResolve` 调用 `setLayoutRTL(true)`。
3. `_fullResolve` 经 `UIScrollView._setFlipsHorizontalAxis` 调用 `UIView._setFlipsHorizontalAxis(true)`。

返回 LTR 时的实际顺序（两次均相同）：

```text
UICollectionView._layoutDirectionTraitDidChange
  → UIScrollView._setFlipsHorizontalAxis(false)
    → UIView._setFlipsHorizontalAxis(false)

_UIFloatingTabBar.layoutSubviews
  → _updateSelectionViewFrameAnimated:completion:
    → UICollectionView.layoutAttributesForItemAtIndexPath:
      → UICollectionViewData._prepareToLoadData
        → UICollectionViewCompositionalLayout._prepareLayout
          → _performDeferredResolveIfNecessary
            → _fullResolve
              → UIScrollView._setFlipsHorizontalAxis(true)
                → UIView._setFlipsHorizontalAxis(true)
```

所以“最终仍为 true”不是 trait 回调没执行，也不是完全没有清除，而是**清除后又被布局解析写回 true**。第二次 setter 的入口采样明确记录：effectiveDirection=LTR、traitDirection=LTR、layoutRTLBefore=true、axisFlipBefore=false、setterArgument=1。

### 为什么会写回

反汇编观察到当前 UIKit 实现的 `_fullResolve` 开头：已有 `layoutRTL=true` 时跳过方向重判；否则读取 collection 的 effective direction，只有 RTL 分支会调用 `setLayoutRTL(true)`。该分支未执行对称的 LTR 复位。随后 `_fullResolve` 把缓存的 layoutRTL 交给布局求解过程，并在 RTL 镜像分支再次设置 collection 轴翻转。

自主往返追踪共捕获 13 个事件：只有一次 `setLayoutRTL(true)`，没有 `setLayoutRTL(false)`。返回 LTR 后，同一个 `_UIFloatingTabBarCollectionViewLayout` 的缓存仍为 true。以上是当前模拟器运行时的实测行为，不是 Apple 提供的公开实现契约；不外推到所有 OS 版本。

可复查证据：

- `Experiments/TabDirectionIsolation/Evidence/autonomous-setter-events.jsonl`：原始自主切换调用栈与 setter 入参。
- `Experiments/TabDirectionIsolation/Tools/trace_flips.py`：可重跑的 LLDB 只读断点脚本。
- `/tmp/TabDirectionSetterTrace/disassembly.txt`：当前会话反汇编和符号查找原始输出。
- `/tmp/TabDirectionSetterTrace/autonomous-layers.json`：同一次追踪的稳定视图状态。

### 公开容器恢复路径实验

每种策略在单独进程中运行，两次返回 LTR 后分别尝试恢复，再更新 badge/执行布局，检查是否复发。整个往返保持原 UITabBarController 和页面实例；恢复操作没有写内部翻转标记，没有引入替代 Tab 栏。

| 策略 | 内部 collection/layout 是否更换 | 最终镜像 |
| --- | --- | --- |
| idiom 临时 phone 后恢复 | 否 | 保留 |
| phone + compact 后恢复 | 否 | 保留 |
| tabSidebar/sidebar 显隐后返回 tabBar | 否 | 保留 |
| setTabBarHidden 隐藏再显示 | 否 | 保留 |
| 添加临时 Tab 再移除 | 否 | 保留 |
| 修改 standardAppearance 后恢复 | 否 | 保留 |
| performBatchUpdates 更新 badge | 否 | 保留 |
| 改变 minimizeBehavior | 否 | 保留 |
| 改变 preferredContentSizeCategory 后恢复 | 否 | 保留 |

所有策略的 layoutRTL 仍为 true。sidebar 用例另有正确朝向的 sidebar 标签留在层级中，不能把它当作浮动栏已恢复。原始精简记录保存在 `Experiments/TabDirectionIsolation/Evidence/public-recovery-results.json`。

这些操作均未找到有效恢复路径；这不是对所有公开 API 都无解的穷尽证明。

### 应用自有 collection 的正负对照

独立 App 的选中页面增加一个应用自有 compositional collection，每次方向变化都使布局失效。它也能复现相同缓存/镜像现象。容器和系统浮动栏始终保留，下面操作只作用于应用自有 collection。

| 自有 collection 操作 | 即时结果 | 再次 invalidate + layout 后 |
| --- | --- | --- |
| invalidateLayout | 镜像 | 镜像 |
| 修改 configuration | 镜像 | 镜像 |
| 切到 FlowLayout，再挂回原 compositional layout | 暂时正常，layoutRTL 仍为 true | **镜像复发** |
| setCollectionViewLayout 安装新 compositional layout | 正常，layoutRTL=false | **继续正常** |

两轮往返结果一致，文字坐标方向与 axis/cache getter 互相吻合。见 `Evidence/owned-collection-results.json`。

这说明清除旧布局状态对本例有效，而“旧布局重挂后文字暂时正常”是不能采用的假恢复。应用自有 collection 有公开 layout factory，可以替换自己的布局；当前尚未找到让系统浮动栏通过公开 UITabBarController API 生成新 native layout 的入口。没有通过私有子视图遍历替换系统布局，也没有把此对照作为浮动栏的正式修复。

### 网上资料核对

Apple 的 [UITraitEnvironment 文档](https://developer.apple.com/documentation/uikit/uitraitenvironment) 说明 trait override 会向后代传播；当前采样也确认 collection 已读到新的 LTR，故问题落在后续布局缓存，而非方向传播失败。

找到一个作者在 2020 年直接报告的 [compositional layout 运行时切换方向后内容镜像案例](https://stackoverflow.com/questions/63605883/ios-swift-uicollectionviewcompositionallayout-mirrored-ui-on-switching-ui-layout)。该案例使用 AppleLanguages、appearance 和 root 重建，环境与本工程不同，不能据此断定根因相同；作者的固定 LTR 加手动 transform 做法也不适用于本任务约束。本次调用链结论来自本地追踪。未检索到 Apple 对当前浮动栏问题公布的受支持恢复入口。

独立工程最终构建成功；所有本轮运行时证据来自 iPad / iOS 27.2 模拟器。没有将本轮实验声称为正式应用修复、真机验证或新的聊天焦点回归。

## 2026-11-03：直接验证 UITab / tabs / setTabs / selectedTab

针对用户提供的 iOS 18 新 API，补做从初始化即使用 UITab 的独立对照。此前九种容器实验使用传统 viewControllers 初始化，不能代替本组验证。

本组流程：创建一次 UITabBarController 和三个页面；创建一次对应的三个 UITab，provider 返回既有页面；首次就赋值 tabs 并通过 selectedTab 选中。此后不调用 UITabBarController.viewControllers 相关读写；后续内容更新也使用 UITab.badgeValue。

| 策略 | 两次返回 LTR 后及后续 badge 更新 |
| --- | --- |
| tabs = 原数组 | 镜像仍在 |
| setTabs(原数组, animated: false) | 镜像仍在 |
| setTabs(原数组, animated: true) | 镜像仍在 |
| setTabs([])，布局并等待 200ms，再恢复原数组 | 镜像仍在 |
| setTabs(反序数组)，布局并等待 200ms，再恢复原顺序 | 镜像仍在 |
| 仅保留选中 UITab，布局并等待 200ms，再恢复所有 UITab | 镜像仍在 |
| selectedTab 切到另一项，布局并等待 200ms，再恢复 | 镜像仍在 |

每种策略独立启动一个进程，均运行 LTR→RTL→LTR→RTL→LTR。各稳定采样点确认：原控制器、UITab 模型、最终 selectedTab、被选中控制器和页面身份一致；内部 collection/layout 仍是原对象。恢复完成时容器 trait 已为 LTR，但 layoutRTL=true、axisFlip=true，Alpha 标签的局部 +10x 转换到窗口仍为 -10。

清空、重排、移除未选中项用于避免“同一数组被当作无变化”的干扰。它们同样没有更换或重置内部 layout，所以本组结果不能归结为仅重赋同一数组而没产生内容差异。

结果限于 iPad mini (A20 Pro) / iOS 27.2 模拟器，不声称所有系统版本行为相同。没有测试新建 UITab 后复用仍绑定旧 UITab 的控制器，也没有把保持模型/页面身份等同于焦点连续性；本轮没有重新验证聊天焦点。

独立工程构建成功。七组结果及身份断言全部与上述失败现象一致；不是镜像修复测试通过。精简证据为 `Experiments/TabDirectionIsolation/Evidence/modern-tabs-recovery-results.json`，完整采样为 `/tmp/tab-modern-api-results/recovery-tabs-*.json`，构建日志为 `/tmp/tab-modern-api-build.log`。本轮仅更新独立工程与记录，没有修改正式 Demo 或 AppLocalization。

## 2026-11-03：私有 layoutRTL 缓存同步时机实验

用户授权在独立工程试验缓存同步。本轮没有修改正式 Demo 或 AppLocalization。仅 opt-in 的 `--cache=before/after/late` 会调用原生 layout 的私有 `setLayoutRTL:`；默认路径、`--cache=none`、公开恢复路径均不调用该 setter。调用前检查精确类名及 ObjC 参数/返回类型，不 swizzle，不写 axis flip，不修改 transform，不替换 collection/layout/controller。

环境：iPad mini (A20 Pro) / iOS 27.2 模拟器，独立工程构建成功。每组 9 个交替方向阶段（4 轮往返），每阶段采集 settled、更新标题/badge 并 invalidateLayout 后、临时减小 window.bounds.width 80 点后、恢复尺寸并追加输入后，共 36 个稳定采样点。

| 时机与初始化 | 组数 | 结果 |
| --- | --- | --- |
| 不同步；传统 viewControllers，LTR 起始 | 1 | 四次返回 LTR 全部镜像 |
| 更新方向前同步；传统 API / UITab，LTR / RTL 起始 | 4 | 全部正常，后续布局未复发 |
| 更新方向后、显式布局前同步；传统 API 的 LTR / RTL 起始、UITab 的 LTR 起始 | 3 | 全部正常，后续布局未复发 |
| 布局稳定后再同步；传统 API，LTR 起始 | 1 | 四次返回 LTR 仍镜像 |

有效的七组共 252 个稳定采样点，逐个断言：三个 Tab 标签的局部 +10x 在窗口仍是 +10x；按 Tab 身份比较位置顺序，LTR 为正序、RTL 为逆序；容器与 collection 的 trait/effective direction 跟随目标方向；layoutRTL 和 collection axis flip 同步为目标方向。按 Tab 身份判断，不能把内部 subviews 枚举顺序当成屏幕顺序，UITab 更新后其视图树顺序可以不同。

所有九组均保持同一 root、navigation、系统 tabBar、内部 collection、layout、输入框实例；UITab 组也保持原模型、选中项、控制器和页面身份。

输入探针只在启动时调用一次 becomeFirstResponder，各稳定采样点始终 firstResponder=true。每阶段不重新获取焦点而追加一个“续”，每次最终文本均精确等于原草稿加对应数量的字符。这是独立 UITextView 的焦点/草稿证据，不等于正式聊天页面回归，也没有验证软键盘显示、真实键盘事件或用户点击 Tab。截图 `/tmp/tab-cache-success.png` 确认四轮往返后“示例 / Beta / Gamma”文字、顺序和选中背景正常。

关键负对照：`late` 在 LTR 稳定后确实把 layoutRTL 改为 false，但 axis flip 仍为 true，后续 invalidate 与尺寸变化也未清除，标签 +10x 仍变成 -10x。清缓存可防止后续 `_fullResolve` 再次打开镜像，但不自动清除已经遗留的轴翻转。切换前同步能让 UIKit 自身的方向回调清除轴翻转，并避免后续被旧缓存覆盖。

这为之前 LLDB 调用链提供因果对照，**不是找到受支持的公开 API 修复**。私有 setter 的兼容性未获保证，本实验不进入正式代码或复用包。结果也未覆盖真机、其他 iOS 版本、系统分屏/旋转或正式聊天页面；窗口变化仅为直接修改 UIWindow.bounds 的合成压力。

证据：`Experiments/TabDirectionIsolation/Evidence/cache-results.json`；完整采样 `/tmp/tab-cache-results/cache-*.json`；构建日志 `/tmp/tab-cache-probe-build.log`；可复跑脚本 `Tools/run_cache_probes.py`。

### 用户提供文章：清空旧 tabBarItem 对照

阅读 [How iOS 18 Changed UITabBarController and Fixes for Localization Issues](https://medium.com/@sanabriabrasil/how-ios-18-changed-uitabbarcontroller-and-fixes-for-localization-issues-8114cf58625f)（2024-12-12）。作者报告的是 storyboard 创建的 Tab 标题更新问题，使用 UITab 并在 provider 里把原控制器的 tabBarItem 置 nil。文章对内部缓存的解释属于作者判断，不能直接作为本次轴翻转根因的证据。

补测两组：从一开始使用 UITab 的基线，以及同样初始化但 provider 内 `controller.tabBarItem = nil`。两组均不调用私有 setter，各做 9 阶段/4 轮往返。第一项标题都能在“示例”和“الأمثلة”之间正确更新，但每次回到 LTR 仍是 layoutRTL=true、axisFlip=true、标签局部 +10x 转到窗口 -10x。清空旧 item 未修复本例。两组 first responder/草稿采样也正常。

这只说明文章的该做法不能消除本模拟器上的方向镜像，不否定作者原先的 storyboard 标题问题。没有在本轮搭建 storyboard 重现作者的独立问题。精简证据 `Evidence/article-item-results.json`；完整采样 `/tmp/tab-article-results/`；最新构建日志 `/tmp/tab-cache-medium-build.log`。

## 2026-11-03：截图建议的 unspecified 语义对照

针对用户截图中的 `semanticContentAttribute = .unspecified`，补测两组纯公开 API 方向设置路径，均从 UITab 初始化、使用 `--cache=none`，不调用私有 setter：

1. `--semantics=inherited`：只让 UIWindow 的 semantic 跟随语言；容器 view、tabBar、navigationBar、页面均为 unspecified；容器 trait 继续跟随语言。
2. `--semantics=traits`：连 UIWindow 也保持 unspecified，仅更新 tab/navigation 容器的 layoutDirection trait overrides。

iPad mini / iOS 27.2 模拟器，两组构建运行成功；每组 9 阶段、4 轮往返、36 个稳定采样点。两组均成功传播实际方向：RTL 时原生 collection effective/trait 为 RTL，LTR 时均为 LTR，collection semantic 始终 unspecified。但每次 RTL→LTR 后 layoutRTL 与轴翻转仍为 true，三个 Tab 标签局部 +10x 在窗口中均为 -10x；后续标题/badge、布局失效、合成窗口尺寸变化后仍镜像。

因此本次问题不是给每个 app-owned view 显式写 forceLeftToRight/forceRightToLeft 才产生；去掉这些显式 semantic 写入后仍复现。`.unspecified` 是语义默认值，不是内部布局缓存的 reset API。两个实验均保留原容器和系统浮动栏；输入探针各采样点保有 first responder，最终文本按预期追加，无重新获取焦点。正式 Demo 和 AppLocalization 本轮未修改。

截图的“硬编码 Leading/Trailing 约束”标题与其正文不一致：正文实际描述的是固定 left/right；leading/trailing 通常才是适应阅读方向的选项。另外，正确 RTL 的项目排列反转与字形水平镜像需要分开判断；本例异常发生在返回 LTR 后，不能由正常 RTL 自动排列反转解释。关于内部浮动栏所有动画/手势都会反转的说法，本轮没有验证。

Apple 参考：[UISemanticContentAttribute](https://developer.apple.com/documentation/uikit/uisemanticcontentattribute)、[semanticContentAttribute](https://developer.apple.com/documentation/uikit/uiview/semanticcontentattribute)。上述故障结论来自本地采样，不是 Apple 文档对私有浮动栏行为的保证。

精简证据：`Experiments/TabDirectionIsolation/Evidence/unspecified-results.json`。完整采样：`/tmp/tab-unspecified-results/`。构建日志：`/tmp/tab-unspecified-build.log`。复跑：`Tools/run_cache_probes.py --semantics-only`，其余 simulator/app/output 参数同 README。

## 2026-11-03：实施头脑风暴候选——上游传播、时序与切换前适配

用户要求开始实施后，在独立工程新增可复跑的公开 API 候选矩阵。本轮正式 Demo 和 AppLocalization 未修改；尚无通过筛选的公开 API 候选可供接入。

环境仍为 iPad mini (A20 Pro) / iOS 27.2 模拟器，原生 UITab 初始化。所有视图保持 unspecified；`--cache=none`，私有 setter 调用数为 0。候选操作仅作用于公开的 app-owned container/window/scene API。读私有状态和后续针对原生 layout 的 invalidateLayout 是诊断与压力步骤，不作为发布方案。

| 类别 | 实际组合 | 组数 | 结果 |
| --- | --- | --- | --- |
| 方向来源 | controller 基线、UIWindow、UIWindowScene；后两者移除子控制器方向 override | 3 | 均镜像 |
| 标题更新时序 | 先标题后方向、方向后显式布局再标题、异步入主队列再标题、同一同步段方向后标题；分别使用 controller/scene 方向来源 | 8 | 均镜像 |
| 切换前展示适配 | 在旧方向下先隐藏栏、进入 sidebar、或 override horizontalSizeClass=compact；在替代状态更新方向并完成布局，再恢复浮动栏；分别使用 controller/scene 来源 | 6 | 均镜像 |

17 组每组 9 个方向阶段/4 轮往返；共 612 个稳定采样点，272 个返回 LTR 后的采样点仍镜像。每个失败样本均为相同的四项：layoutRTL 残留、axis flip 残留、标签字形镜像、Tab 顺序错误；没有把缺失 collection 或方向传播失败误当成本缺陷。新一轮构建成功，Python runner 语法与 git diff --check 通过。

上游传播的对照确认实际发生：RTL 时 controller 来源的 scene/window/tab traits 为 0/0/1；window 来源为 0/1/1；scene 来源为 1/1/1。所有组 collection 的 effective/trait 都正确跟随方向；返回 LTR 后也全部为 LTR，但 layoutRTL=true、axisFlip=true。故这几个传播入口均未触发缓存重置。

隐藏栏和 compact 的中间采样中，浮动 collection 不在当前视图树；恢复后仍是原 collection/layout。每组稳定采样始终只有一个 layout 身份，说明离开当前视图树并不等于内部布局被销毁。sidebar 路径也没有换掉布局。

17 组均保留 root、navigation、tabBar、UITab 模型及选中控制器/页面身份。输入框身份、原草稿与追加字符正确，所有采样点（包括临时展示状态）firstResponder=true，每阶段追加后选区停在文本末端。未模拟真实输入法 marked text；仅记录 hasMarkedText，不声称 IME 连续性已验证。主队列异步变体也不等同于保证下一渲染帧；同步变体没有抑制 UIKit 自身可能发生的同步布局。

原始采样 `/tmp/tab-public-matrix-results/`，精简证据 `Experiments/TabDirectionIsolation/Evidence/public-matrix-results.json`。复跑脚本 `Tools/run_public_matrix.py`。构建日志 `/tmp/tab-public-matrix-build.log`。结果是 17 个候选均未修复，不能将矩阵执行完成表述为修复测试通过。

### 后备：新 UITab 模型身份

增加相同 identifier 的新模型，以及新 identifier 的新模型两条路径。先用公开 API 清空 selectedTab 和 tabs，再完成布局并等待 200ms；旧关联未释放时继续最多等待 10 次 200ms。通过公开 UIViewController.tab 检查旧关联，不调用私有清理方法。

两次尝试都在第一次准备切换方向时触发守卫：tabs 和 selectedTab 已为空，但额外等待 2000ms 后，三个页面仍各自关联原 UITab。因此没有创建/绑定新模型，记录 replacementBlocked=true 后终止该组。每组只完成初始 LTR 的 4 个稳定采样点，**不能把它统计为完成了语言往返或证明新模型方案无效**。这只说明当前清空/等待流程没有满足实验要求的旧关联释放条件，不是对所有公开关联管理方式都无解的证明。

证据 `Evidence/fresh-model-results.json`，完整采样 `/tmp/tab-fresh-model-results/`。当前可复跑命令为同一 runner 加 `--fresh-tabs-only`。最新构建日志 `/tmp/tab-fresh-model-build.log`。

### 新矩阵的正对照

用最新独立工程复跑 `--direction-source=scene --semantics=traits --timing=atomic --modern-tabs --cache=before`。唯一额外干预是此前用户授权的私有缓存同步，共 9 次 setter 调用。4 轮往返、36 个稳定采样点全部正常，root/page/model/input 与原 layout 身份保留，草稿和采样焦点正常。结果 `Evidence/public-matrix-positive-control.json`，完整采样 `/tmp/tab-public-positive-control/`。

这验证检查能区分实际恢复与上述公开路径的失败；不是把私有方案升级为正式实现。本轮没有满足接入条件的公开候选，所以没有修改 AppLocalization 或正式 Demo，也没有运行或声称通过正式聊天 UI/输入法回归。

## 2026-11-03：经用户授权接入 Demo 私有兼容处理

用户要求“先加入进去，写上注释”后，新增 `Demo/Demo/App/FloatingTabBarDirectionWorkaround.swift`，并由 `AppTabBarController.prepareForLocalization(_:)` 调用。本地 AppLocalization 的准备阶段在更新 window 语义方向及容器 trait 之前执行；仅在此阶段同步原 layout 的 `layoutRTL` 缓存，后续方向与文案仍走正常本地化流程。

实现限定 `_UIFloatingTabBarCollectionView` / `_UIFloatingTabBarCollectionViewLayout`，检查 getter/setter 存在、参数数量与 BOOL/void 编码，仅在缓存与目标方向不一致时调用 `setLayoutRTL:`。不加载未加载页面、不替换控制器或布局、不修改 transform，也不安装 swizzle。注释明确私有 API、已验证环境、调用时序、兼容边界及移除条件。私有处理保留在 Demo，未加入 AppLocalization 默认实现。

正式 Demo 的 iPad mini (A20 Pro) / iOS 27.2 回归：`AppNavigationTests` + `NativeTabLocalizationTests` 共 22 项全部通过。包含从中文和阿拉伯文启动的多轮方向切换、后续 badge/窗口宽度变化的文字几何方向检查，以及原聊天页面/模型/选中 Tab 身份、草稿、选区和 firstResponder 保留；每次切换后向原输入框追加字符。结果包：`/tmp/QuickLayoutKit-private-tab-integration-ipad.xcresult`。这是宿主测试证据，真实界面菜单与键盘流程另行记录。

iPad 的 `TabLocalizationUITests` 两项均通过：通过语言菜单完成中文→阿拉伯文→中文往返，验证原生 Tab 的标题、顺序、选中态及点击；聊天流程在两次切换后均未重新点击输入框，通过 `app.typeText` 继续输入，草稿最终为 `Language draft continued continued`。人工检查导出的阿拉伯文、最终中文和聊天截图，浮动栏字形方向正常，聊天光标停在末端。结果包：`/tmp/QuickLayoutKit-private-tab-ui-ipad.xcresult`；8 张截图及 manifest：`/tmp/QuickLayoutKit-private-tab-ui-ipad-attachments/`。该模拟器使用键盘事件输入，未覆盖真实设备、软键盘展示或中文输入法 marked text。

iPhone 18 Pro / iOS 27.2 UI 回归保留失败：聊天草稿/焦点测试通过；Tab 往返测试在第一次切换阿拉伯文后，标题/位置联合等待条件超时（`TabLocalizationUITests.swift` 当时第 75 行），没有完成后续往返。失败截图中底部 Tab 的阿拉伯文及视觉顺序正常，尚未确定是 accessibility 查询还是其他状态不一致，不能据此宣布 iPhone 完整验证通过。期间菜单动画等待也出现 60 秒超时；MCP 外层调用 300 秒超时后，读取底层已完成的 xcodebuild 结果确认 1 通过、1 失败。结果包：`/tmp/QuickLayoutKit-private-tab-ui-iphone.xcresult`，失败截图与查询附件：`/tmp/QuickLayoutKit-private-tab-ui-iphone-attachments/`。

用户随后要求缩短聊天标题。将 `ChatViewController.localizedTitleKey` 从 `demo.imessage.title` 改为现有 `app.tab.chat`，避免页面加载/本地化时将长标题传播到系统 Tab 栏；在既有聊天 UI 测试增加首次进入及两次语言切换后的简短 Tab 标题断言。

修改短标题后，iPad 聊天 UI 测试复跑通过：首次进入为“聊天”，切换后分别为“الدردشة”和“聊天”，原草稿和无需重新点击输入框的连续输入仍通过。结果包：`/tmp/QuickLayoutKit-short-chat-title-ipad.xcresult`。

## 2026-11-03：定位 iPhone Tab 往返等待超时

在原 UI 测试保留标题、位置、选中态与点击断言的基础上，每个阶段新增三个 Tab 的 identifier/label/frame/selected 及完整 accessibility tree 附件。首次运行遇到 Runner 准备阶段崩溃（`XCTWaiter(StallHandling)`），不计为布局结论；复用构建产物关闭测试并行后重现原超时。

在阿拉伯文阶段，截图的 Tab 文案已是阿拉伯文，位置也正确从右向左排列，但可访问性树仍返回中文：

| identifier | 实际 accessibility label | frame.origin.x | 选中 |
| --- | --- | --- | --- |
| app.tab.examples | 示例 | 242.33 | true |
| app.tab.chat | 聊天 | 152.00 | false |
| app.tab.voiceRoom | 语音房 | 61.67 | false |

因此超时触发于标签匹配条件，而非该样本的 RTL 位置条件。它是可见标题与辅助功能名称不同步，不能通过放宽断言或延长等待掩盖。失败证据：`/tmp/QuickLayoutKit-tab-iphone-diagnostic-retry.xcresult`；导出目录 `...-attachments/` 中 `5AAF27D9-769F-41CA-A955-22F7FC1182EA.txt` 保存完整树，`74AE66BE-B5B8-4CB7-819D-D5681209125A.png` 为同阶段截图。准备阶段失败保留在 `/tmp/QuickLayoutKit-tab-iphone-diagnostic.xcresult`。

首先尝试在 `AppTabBarController.render(_:)` 同步公开属性 `UITabBarItem.accessibilityLabel`，但 iPhone 聊天 UI 测试仍读到旧中文 label；该路径没有刷新既有按钮的名称。失败日志/结果保留在 `/tmp/QuickLayoutKit-tab-iphone-accessibility-fixed.xcresult`，后续测试在已确认失败后手动停止。

接着在本地化标题变化时重新提供 `UITabBarItem`，保留 badge、enabled、tag、图标等本 Demo 使用的状态。该路径使按钮名称正确变成阿拉伯文，但复制旧 item 的 accessibilityIdentifier 后，新按钮标识缺失，导致定位失败。`/tmp/QuickLayoutKit-tab-iphone-item-refresh.xcresult` 的 UI hierarchy 证实三项 label 均已更新；不能将此中间结果计为完整通过。后续改为根据稳定 AppTab 身份重新赋予 identifier，并在设置 controller.tabBarItem 后再次同步。

这些候选仅使用公开的 item API；没有新增私有调用、控制器重建或改变方向语义。原来的标题和位置等待断言继续保留；诊断增加缺失元素守卫，使缺失 identifier 时也能保存完整状态，而不是在读取 label 时提前退出。

再次设置页面 item 的 identifier 也没有使新系统按钮暴露该标识（`/tmp/QuickLayoutKit-tab-iphone-item-identity.xcresult`）。最终保留刷新 item 以更新实际辅助功能名称的实现；测试优先使用稳定 identifier，在系统未暴露 identifier 时按当前本地化名称定位。仍逐项断言名称相等、方向顺序、选中态、可点击性，并实际依次点击三个 Tab。若旧 identifier 仍存在但 label 错误，或者不存在预期语言的按钮，测试仍会失败。这是定位方式适配，不是删除标题检查。系统未暴露 identifier 的现象作为已知测试边界保留。

最终 iPhone 18 Pro / iOS 27.2 两项 UI 测试全部通过：`/tmp/QuickLayoutKit-tab-iphone-final.xcresult`。覆盖两轮中→阿→中及三个 Tab 的实际点击；聊天在语言切换后短标题、选中态、草稿及无需重新聚焦的追加输入均通过。导出目录 `/tmp/QuickLayoutKit-tab-iphone-final-attachments/` 含 8 张截图及 6 个阶段的完整 accessibility tree；已目视检查阿拉伯文与最终中文截图，字形与顺序正常。菜单动画等待仍有系统 60 秒警告，但没有放宽功能断言，最终测试成功。

最终 iPad mini (A20 Pro) / iOS 27.2 宿主回归 22/22 通过：`/tmp/QuickLayoutKit-tab-ipad-final-unit.xcresult`。在既有多语言往返测试新增系统 UITabBar 与 `_UIFloatingTabBarCollectionView` 实例身份断言，以及切换前 badge 在切换后保留的检查；两个启动语言的参数化测试均通过。聊天页面、模型、草稿、选区与 firstResponder 检查也通过。因此重新提供 item 没有重建 Tab 容器、系统浮动 collection 或原页面。

最终 iPad 两项 UI 测试也全部通过：`/tmp/QuickLayoutKit-tab-ipad-final-ui.xcresult`，复用与 iPhone 最终 UI 测试相同的构建产物。覆盖实际菜单的两轮中→阿→中、三个系统 Tab 点击，以及聊天短标题/草稿/焦点。附件导出在 `/tmp/QuickLayoutKit-tab-ipad-final-ui-attachments/`。本轮最终结果为 iPhone UI 2/2、iPad UI 2/2、iPad 宿主回归 22/22；最初的失败证据继续保留。验证范围为 iOS 27.2 模拟器，没有扩展为真机、其他系统版本或中文输入法 marked text 的保证。

提交前按用户要求恢复 AppLocalization 远程引用：`https://github.com/astralchen/AppLocalization`，分支 `main`，两个 Package.resolved 均锁定 `2fe1d665fd4ff6983ea858adf6c75b888577e221`。工作区和 Demo 工程分别完成依赖解析；远程检出包含 `UIKitLocalizationPreparing` 以及方向变化前的 prepare 调用，提交与本地干净副本一致。本次切换依赖来源未重新运行 UI 测试；此前本地源码验证结果与远程解析验证分别记录。


## 2026-11-03：修复英文与中文切换时浮动栏可见标题残留

用户截图中的中文页面与英文 Tab 混用已在 iPad mini (A20 Pro) / iOS 27.2 重现。仅替换 `UITabBarItem` 时，辅助功能名称已切为中文，浮动栏可见文字仍为 `Examples / Chat / Voice room`。英文与中文的 LTR → LTR 切换没有方向变化，原有只检查辅助功能名称的 UI 断言因此通过；原宿主方向测试从整个控制器查找任意匹配标题，也没有逐项验证浮动栏文字。

复现证据：`/tmp/QuickLayoutKit-tab-english-chinese-baseline.xcresult`，附件目录 `/tmp/QuickLayoutKit-tab-english-chinese-baseline-attachments/`。新增浮动 collection 可见 cell 标题断言后，修复前测试失败：`/tmp/QuickLayoutKit-tab-visible-labels-before.xcresult`。这些结果保留，不能把前一项 UI 测试通过视为可见文字正确。

修复在 `AppTabBarController.render(_:)` 替换 item 前，先更新原 item 的 `title` 和 `accessibilityLabel`；继续保留原替换流程，使可见标题和辅助功能名称都刷新。本次仅使用公开 item 属性，不新增私有调用，也不替换页面或 Tab 容器。

回归增加英文启动及连续中英切换，逐项验证浮动栏实际可见 UILabel 标题，并保留原方向、badge、容器/页面身份、草稿和焦点检查。iPad `AppNavigationTests` 21 项及新增中英菜单 UI 测试 1 项全部通过：`/tmp/QuickLayoutKit-tab-visible-labels-fixed.xcresult`。附件目录 `/tmp/QuickLayoutKit-tab-visible-labels-fixed-attachments/`，两次中文阶段截图均已目视确认顶部为“示例 / 聊天 / 语音房”。本轮范围为 iOS 27.2 模拟器，未覆盖真机及其他系统版本。

iPhone 18 Pro / iOS 27.2 复用同一构建产物执行新增中英菜单 UI 回归，1/1 通过：`/tmp/QuickLayoutKit-tab-visible-labels-iphone.xcresult`。验证连续英文→中文→英文→中文后，三个系统 Tab 的辅助功能名称均与当前语言一致。
