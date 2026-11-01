# UIKit SDK 编译兼容

`UIView.ReservedRegion`、`UIView.reservedRegions(kind:options:)` 和 `UIHingeInteraction` 使用两层保护：

```swift
#if compiler(>=6.4)
if #available(iOS 27.1, *) {
    // UIKit 原生 API
}
#endif
```

按项目约定使用 Xcode 自带编译器与配套 SDK，以 Swift 6.4 作为新 API 的编译门槛。当前 Xcode 26.5 工具链不编译此分支；运行时 availability 继续保护旧系统。相应原生 API 测试使用同一条件。

旧工具链保留公共几何查询类型及其 availability；系统保留区域快照为空，不安装铰链交互。坐标转换、锚点、内容边距、窗口变化观察及已有显示链接继续工作。

当前环境不能验证新 SDK 分支。升级配套 Xcode 后，应运行 `nativeReservedRegionsMatchUIKitAndKeepIdentifiers`；当前工具链运行 `olderSDKKeepsGeometryWithoutNativeReservedRegions` 验证降级路径。不需要额外设置自定义编译标志。
