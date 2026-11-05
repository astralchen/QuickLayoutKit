// QuickLayoutKit 的统一导入入口，同时导出基础布局、布局扩展与 UIKit 宿主 API。
@_exported import QuickLayout
@_exported import QuickLayoutKitCore
@_exported import QuickLayoutKitUIKit
// 显式导出本库栈入口，避免与上游同名构建函数产生歧义。
@_exported import func QuickLayoutKitCore.HStack
@_exported import func QuickLayoutKitCore.VStack
