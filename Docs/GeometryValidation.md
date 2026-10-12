# 二维 GeometryProxy 验证记录

日期：2026-10-12。工具链：Xcode 27.1（27A9275），iOS 27.1 SDK。
框架最低部署版本保持 iOS 15。接口对照本机 SwiftUICore / UIKit 公开声明，参考
[Apple GeometryProxy 文档](https://developer.apple.com/documentation/swiftui/geometryproxy)。

## 实现范围

- 坐标空间、反向 bounds 查询、纯布局作用域、二维 Anchor 解析。
- 显式容器元数据、内容边距、方向性角内缩及原生同心圆角。
- UIKit 保留区域采样、稳定 ID、活动状态、选项及方向镜像。
- 宿主布局结束后的成批快照、回调重入合并、窗口监测与卸载清理。
- 独立 Demo 的四组场景、英/中/阿拉伯语、Dynamic Type 和无障碍标识。

生产实现不导入 SwiftUI；仅测试中的数值对照夹具使用 SwiftUI。圆角的原生计算约定和
SwiftUI 系统容器差异见 README。QuickLayout 依赖检出目录没有修改。

## 自动化结果

| 检查 | 状态 | 证据 |
|---|---|---|
| 原有及新增几何定向回归 | 通过 | 23 项、2 个 suite，正常 `TEST EXECUTE SUCCEEDED`；`qlk-geometry-regression.log` |
| Duo 27.1 宿主几何测试 | 通过 | 15 项，`qlk-geometry-final-duo-unit.log` |
| SwiftUI 尺寸对照 | 通过 | `swiftUIReferenceReportsSameLocalSize`，真实 UIWindow / UIHostingController |
| Duo 系统区域对照 | 通过 | 2 个活动 occlusion、0 个 division；frame、活动状态和重复 ID 对照通过 |
| 框架全套测试 | 失败（已有基线问题） | 187 项：185 通过、2 失败；原有几何及新增 15 项全部通过，`qlk-geometry-final-package-3.log` |
| Duo 27.1 Demo UI | 通过 | 四场景、RTL、尺寸和方向切换；`qlk-geometry-final-duo-ui.log` |
| iPhone 18 Pro Max 27.0 Demo UI | 通过 | 同一测试构建；`qlk-geometry-final-iphone-ui.log` |
| iPad Pro 11-inch (M5) 26.5 Demo UI | 通过 | 同一测试构建；`qlk-geometry-final-ipad-ui.log` |
| 最低版本与并发编译 | 通过 | iOS 15 target、Swift 6 complete concurrency、同文件导入 SwiftUI；未加 availability 防护的新查询按预期编译失败 |
| 静态收尾 | 通过 | `git diff --check`、工程 plist、scheme XML，18 个新增文案键的三语言覆盖 |

新增测试覆盖：同名遮蔽、跨 UIKit 宿主作用域、纯布局 Anchor、窗口隔离、冻结快照、卸载失效、
缩放旋转、非零 bounds origin、嵌套滚动轴、非对称边距和 RTL、边缘过滤、缺失空间、圆角计算、
区域活动筛选与镜像、frame 已含 margins、祖先移动、测量静默、尺寸不变时边距变化、重建身份、
卸载清理、action 重入以及兄弟观察者快照一致性。

区域筛选和镜像测试中的人工矩形只验证纯值逻辑；真实系统区域来自
`nativeReservedRegionsMatchUIKitAndKeepIdentifiers`，两类证据不混用。

## 已有失败与环境边界

在未修改的 `6fda8fb` 基线上独立复现以下两个测试的相同失败，日志为
`/private/tmp/qlk-geometry-baseline-tests.log`：

- `cellFittingUsesSubclassMeasurementWithoutMeasuringBodyAgain`：期望高度 47 / 测量次数 1，实际 37 / 0。
- `gradientViewUsesGradientAsItsRootLayerAndUpdatesConfiguration`：期望 2 个颜色，实际 0。

Duo 的展开、折叠、部分展开切换尚无运行证据。当前安装的 Xcode 27.1 工具链没有
`Contents/Developer/Applications/Simulator.app`，现有旧版 Simulator 菜单和 simctl 未提供可用的
Duo 姿态控制入口。横竖屏交互不能替代折叠姿态验证，也没有把人工区域当作系统返回值。

完整框架运行已完成 187 项断言；随后 xcodebuild 在结果收尾阶段长时间停滞，已终止该进程，
因此不能将这次运行记为正常退出的 CI 成功。另一次启动曾遇到 launchd `Operation canceled`，
重启并串行运行后恢复。以上与两个既有断言失败分别记录。

iOS 15 实机/模拟器运行、VoiceOver 实际朗读及各 Dynamic Type 档位的完整视觉矩阵未执行。
测试包含挂载、卸载与重建，但没有宣称覆盖所有列表适配器的实际滚动复用场景。

## 复查方式

几何用例同时参与 Swift Package 测试及 `DemoTests` app 宿主测试。Duo 的无宿主 `xctest`
曾在首次 UIView 初始化时阻塞于 UIKit / BoardServices，因此 Duo 使用 app 宿主执行。

```sh
# 普通 iPhone：完整框架测试
xcodebuild -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme QuickLayoutKit -destination 'platform=iOS Simulator,id=<iPhone ID>' \
  -clonedSourcePackagesDirPath .build -skipPackageUpdates \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO test

# Duo：几何用例（显式选择 Swift Testing suite）
xcodebuild -project Demo/Demo.xcodeproj -scheme Demo \
  -destination 'platform=iOS Simulator,id=<Duo ID>' \
  -clonedSourcePackagesDirPath .build -skipPackageUpdates \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -only-testing:DemoTests/GeometryProxyTests test

# 三类设备分别运行四场景 UI 回归
xcodebuild -project Demo/Demo.xcodeproj -scheme GeometryRegression \
  -destination 'platform=iOS Simulator,id=<device ID>' \
  -clonedSourcePackagesDirPath .build -skipPackageUpdates \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO test
```

`GeometryRegression` 仅选择 `GeometryDemoUITests`；几何 Swift Testing suite 使用上述独立命令。
本次 `.xcresult` 与控制台日志位于 `/private/tmp/qlk-geometry-*`，属于本机临时验证产物。

## 验证源码标识

12 个几何源文件、Demo 和测试文件按相对路径排序，以 `path + NUL + bytes + NUL` 串联计算 SHA-256：

`459409c6c749d8dfc3f7e44bb7369c107ed24a5ad5dadc71e4c2aa5124225f3a`

范围：Core 的 `Geometry*.swift` 与 `ReservedRegion.swift`、`QuickLayoutScrollView.swift`、
`GeometryDemoViewController.swift`、`GeometryProxyTests.swift` 和 `GeometryDemoUITests.swift`。
