# AdaptivePanelController

`AdaptivePanelController` 在 UIKit 父控制器的视图区域中承载一个非模态面板。公开配置参考 `UISheetPresentationController`，内容可使用普通 UIKit、QuickLayoutKit 或其他视图控制器。

## 使用

```swift
import QuickLayoutKit

let panel = AdaptivePanelController(contentViewController: contentController)
panel.detents = [
    .custom(identifier: "compact") { context in
        context.maximumDetentValue / 3
    },
    .medium(),
    .large(),
]
panel.selectedDetentIdentifier = "compact"
panel.show(in: self)

// 调用方持有面板，后续可切档或关闭。
panel.selectDetent(.large)
panel.dismiss()
```

传入 `containerView` 可以将面板限制在宿主的某个子区域。该视图必须属于父控制器的视图层级。普通视图通过 `init(contentView:)` 承载。

面板默认启用 `prefersPageSizing`，从宿主的可读正文宽度、正文边距和可用区域计算页面宽度。手机在 regular/regular 环境下还受容器短边约束，不预设 540、653 或 720 点宽度。关闭页面模式后，调用方声明的 `preferredContentSize` 才参与浮动尺寸选择。所有尺寸都会限制在当前容器中；横屏贴边时可单独开启 `widthFollowsPreferredContentSizeWhenEdgeAttached`。

`safeAreaSource` 默认 `.container`，尊重宿主的导航栏等安全区。需要覆盖容器栏位时可选择 `.window`；窗口安全区仍会与宿主 bounds 相交。`context.safeAreaInsets` 记录宿主或窗口提供的安全区，页面外框策略作用后的实际区域见 `availableRegion`。

面板通过父子控制器关系管理内容。内容内部和把手区域使用 QuickLayout 排版，控制器根据档位和交互求解面板的外部边界。Demo 的内容与配置页面均使用 QuickLayoutKit。

## 与系统 Sheet 的配置对应

| 系统能力 | 组件接口及约定 |
| --- | --- |
| `detents` | 支持 medium、large 和带稳定标识的自定义解析器；返回 nil 停用当前档位。medium 在紧凑高度下停用。 |
| `selectedDetentIdentifier` | 无效标识回退到当前最小有效档位，公开属性更新为实际使用的标识。空配置或全部停用时回退到 large。 |
| `invalidateDetents()` | 外部测量依赖变化后请求重算。上下文提供可用区域、最大高度、尺寸类别、分隔带和可选折叠角度。 |
| `animateChanges` | 合并配置变化，并从当前动画状态过渡。 |
| `largestUndimmedDetentIdentifier` | 默认 nil 表示所有档位允许操作背景。指定标识后，高于该档位时显示遮罩并拦截背景交互。系统 Sheet 的 nil 默认值会遮罩所有档位。 |
| `prefersScrollingExpandsWhenScrolledToEdge` | 控制在内容区上滑是否先展开面板。把手独立支持切档。可通过 `trackingScrollView` 指定滚动视图。 |
| 把手、圆角 | `prefersGrabberVisible`、`preferredCornerRadius`。把手支持辅助功能增减高度。 |
| 紧凑高度贴边 | `prefersEdgeAttachedInCompactHeight`，默认 true。 |
| 内容宽度 | `prefersPageSizing`、`widthFollowsPreferredContentSizeWhenEdgeAttached` 和内容控制器的 `preferredContentSize`。 |
| 位置 | `preferredPlacement` 支持 automatic、leading、center、trailing；`sourceView` 优先。逻辑边缘遵循 RTL。 |
| 用户关闭 | `allowsInteractiveDismissal`、`shouldDismiss`、`onDismissAttempt` 和 `onDismiss`。代码调用 `dismiss` 直接关闭。 |
| 档位变化通知 | `onSelectedDetentChange` 同时报告用户、程序和环境引起的有效档位变化。 |

档位数值表示内容高度，贴底时额外包含底部安全区。浮动面板以最大档位的底边为锚点。解析器应只计算高度，避免在计算期间修改面板配置。

## 折叠环境

组件从宿主区域的尺寸、安全区和系统 `.division` 保留区域计算可用空间。系统 frame 包含交互建议边距，横向位置分区使用去除 margins 后的实际分隔范围；零宽或零高的分隔线同样有效。竖向分隔的 automatic 优先选择更宽一侧，`sourceView` 所在区域优先，其余结合位置偏好和布局方向选择。

桌面姿态的横向折叠采用档位策略：页面模式下 large 和自定义档位继续按完整容器计算，medium 限制在分隔带下方的可用高度（包含系统建议的交互边距）。关闭页面模式后，所有档位使用下方单独区域。这一区别来自实际 UISheetPresentationController 对照，不以角度阈值或设备型号决定。

展开纵屏的系统 medium 仍参考未激活的物理分隔带，因此档位上下文包含 `.includeInactive` 的分隔信息；面板位置仅按活动分隔进行分区。闭合外屏的窗口页面采用浮动外框，可横向覆盖系统侧栏；内容内部仍应遵守横向安全区，避免按钮落入摄像头或系统区域。`.container` 安全区来源继续尊重局部宿主。以上均从公开姿态、分隔区域和容器几何求解，不读取设备名称。

在支持的 SDK 与 iOS 27.1 及以上系统中，通过 `UIHingeInteraction` 更新 `context.hingeState` 和 `context.hingeAngle`。角度单位为弧度，无铰链信息时为 nil。默认几何由实际可用区域决定，自定义档位可以读取角度表达业务策略。

窗口缩放与折叠过程中复用内容实例。停靠的键盘覆盖所选区域时，面板默认缩小可用高度。在 Duo 内屏的 regular/regular 页面中，若输入焦点位于面板内，外框临时展开至容器允许的最大高度，列表继续延伸至页面底部，键盘覆盖其下方的内容；需要固定在键盘上方的底部输入控件可使用内容视图的 `keyboardLayoutGuide`。切换姿态时按当前分区重新计算宽度，保留所选档位，收起键盘后按该档位布局。`avoidsKeyboard` 可关闭键盘适配。

## 对照页面与验证

Demo 的「基础布局 → 自适应非模态面板」提供 QuickLayoutKit / UIKit 切换。两种实现使用相同的列表、输入框、关闭按钮和档位配置。页面顶部与面板内部显示实际尺寸、位置、容器尺寸、安全区、横竖屏、horizontalSizeClass、verticalSizeClass、档位、最大内容高度、设备姿态与折叠角度。组件额外显示所选可用区域；系统内部可用区域不推测，标记为「UIKit 管理」。小档位内部空间不足时，前两行优先显示姿态、角度以及面板和容器尺寸；完整诊断信息同步保留在页面配置区域，可滚动查看。

两个实现默认都使用页面尺寸，不设置内容首选宽度；自定义档位为各自 `maximumDetentValue` 的三分之一。对照页使用窗口根控制器和 `.window` 安全区来源，避免导航栏、标签栏额外压缩组件。通用组件仍允许显式传入局部宿主。对照时先核对容器、安全区与尺寸类别，再比较面板尺寸，不能仅凭设备型号判断应该相等。

对照按行为进行。系统 Sheet 的内部尺寸阈值、动画曲线和滚动手势仲裁由 UIKit 管理，当前组件使用自己的规则。源视图定位、浮动宽度和极小窗口下的结果需要结合目标应用验证。

验证覆盖以下独立层次。

- 确定性测试检查档位解析、分隔区域、背景命中、控制器挂载与移除、重复展示及尺寸变化。
- UI 测试通过实际把手拖动和背景点击检查组件，并打开系统 Sheet 对照。
- Device poses 验收需要在面板持续展示期间完成折叠角度变化、旋转、内外屏往返，观察内容状态与几何连续性。

Apple 参考资料为 [UISheetPresentationController](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller) 和 [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)。

## 初版实际观察（iOS 27.2，尺寸修正前）

以下是 Demo 页面在 Device Hub 上观察到的读数，用于说明容器适配和定位差异，不是组件中的尺寸常量。

| 实现 | 姿态 | 容器 | 三分之一档位面板 |
| --- | --- | --- | --- |
| UIKit | 展开横屏，180° | 951×669 | 653×243 |
| UIKit | 书本姿态，128.6° | 951×669 | 459×243 |
| UIKit | 桌面姿态，128.6° | 669×951 | 653×312 |
| QuickLayoutKit | 展开纵屏，180° | 669×951 | 629×248 |
| QuickLayoutKit | 桌面姿态，128.6° | 669×951 | 629×110 |
| QuickLayoutKit | 闭合外屏横屏，0° | 678×466 | 594×150 |
| QuickLayoutKit | 展开横屏，180° | 951×669 | 580×184 |

单位均为 pt；角度来自 `UIHingeInteraction`。组件的同一内容实例经过桌面姿态、展开、闭合外屏、重新展开和旋转后，测试文本保留。上述观察包含真实显示画面与辅助功能树核对。

iPhone 18 Pro 和 Duo 0° 闭合外屏均已验证屏幕键盘输入。若输入框已经获得焦点而键盘仍位于窗口下方，可在 Device Hub 的 Device → Keyboard 中检查 Simulate Hardware Keyboard。复测逐键输入 Panel，旋转后输入框仍处于可见键盘上方。Duo 的 XCTest 方向请求可能无法旋转实际外屏，需在测试等待期间使用 Device Hub 的旋转按钮。失败与复测的窗口坐标见[设备验证记录](AdaptivePanelValidation.md)。

## 2026-11-13 尺寸差异复查

用户截图中，Duo 展开横屏、180°、medium 的系统面板为 653×385，初版组件为 847×276。运行时确认两个尺寸类别均为 regular。修正对照页的宿主层级和安全区来源，并区分手机展开页面、填满容器宽度的页面卡片、宽容器浮层及紧凑高度贴边布局。

iOS 27 的 medium 采用实测的最大内容高度 56% 策略，旧系统继续采用约一半的策略。这是组件策略，不是 Apple 保证不变的公式。测试在真实系统 Sheet 的 custom resolver 回调中读取系统 medium 作为独立基准。曾尝试传入仅实现公开协议的上下文，但 iOS 27.2 访问内部选择子并抛异常；该实现已撤回，组件不使用私有选择子或隐藏 Sheet 测量。

页面卡片在小档位保留边缘留白，最大档位展开到容器宽度。档位仍按逻辑内容高度解析，`panelFrame` 报告最终显示尺寸。列表和内容背景透明，由组件统一绘制面板背景与圆角。

浮层边缘的 8 点留白是组件外观常量，类似圆角与把手尺寸；面板本身的宽高、位置、最大档位均由当前容器计算。不能用临时 `UIView().layoutMargins` 充当这一留白：Duo 实测会返回 0，与普通手机和平板不同。

iPadOS 27.2 模拟器的窗口级页面在保持呈现后旋转时，系统最大档位比同方向首次打开少 44 pt。组件在 iPad 的普通尺寸类别、面板宿主覆盖窗口时按此实测值保留顶距，扣除宿主安全区已有的部分，再按可用容器高度解析各档位。这个留白属于实测适配值。重新打开会重置旋转状态，单独拖动窗口边角不会触发该策略。

各设备的最终通过项、失败项和残余尺寸差异见 [设备验证记录](AdaptivePanelValidation.md)。

诊断显示完整的 `horizontalSizeClass` / `verticalSizeClass` 字段及 compact、regular、unspecified 值。系统侧读取 presentation container 的 traits，组件侧读取实际宿主 traits。

`containerMatrixPreservesBoundsAndContent` 覆盖 2 种 idiom × 8 组容器 × 3 个档位；这是确定性容器测试，不能替代真实多窗口验收。`testAllDetentsInCurrentPose` 保留 Device Hub 当前姿态，采集两个实现的三档截图与诊断文本。旋转取证要求诊断值连续稳定至少一秒，避免保存转场中间帧。
