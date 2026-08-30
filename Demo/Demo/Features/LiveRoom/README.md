# LiveRoom 架构

`LiveRoom` 按功能内聚的 MVVM 组织，依赖方向固定为：

`Controllers / Views -> ViewModels -> Models`

- `Models`：后台舞台快照、稳定业务 ID、零基麦位位置、客户端布局目录、礼物与充值目录，不依赖 UIKit 或具体页面生命周期。
- `ViewModels`：直播间状态、送礼选择与交易校验、充值选择与入账；不执行导航和 UIKit 动画。
- `Views`：只负责布局、渲染、用户输入和无障碍反馈，按聊天、麦位、送礼、充值等子域拆分。
- `Controllers`：绑定 ViewModel，协调导航、键盘、子控制器 containment 和跨视图动画。
- `Animations`：可独立生命周期的送礼特效与麦位场景转场协调。
- `Support`：跨子域共享的主题、预览数据与轻量辅助能力。

## 约束

1. 余额、选择状态、业务校验只能在 ViewModel 中提交，View 不维护第二份业务真相。
2. ViewModel 不引用具体 View 或 ViewController，也不直接弹窗、导航或播放动画。
3. Controller 不重新实现 ViewModel 已有的金额、麦位或选择校验。
4. 新增大组件时优先放入对应子域；单文件接近 500 行时按职责拆成视图、交互、渲染或动画文件。
5. 跨层回调使用业务请求或结果模型，避免多个无语义的基础类型参数。
6. 每个独立 UIView 与 UIViewController 都在自身源文件末尾声明 `#Preview`，不创建 `+Preview` 文件或 `Previews` 目录；预览数据只能来自 `DEBUG` 下的 `LiveRoomPreviewData`。
7. 麦位用户、音频状态、分数、房间模式和业务能力只由 `LiveRoomStageSnapshot` 驱动；View、Cell 与 Layout 不得本地补造生产用户。
8. `LiveRoomSeatPosition` 是后台协议中的零基位置：第一个麦位为 `0`。数组顺序不具备业务语义，Resolver 必须按 `position` 映射 Slot。
9. `seatID` 标识服务端音频实体，`slotID` 标识布局语义位置，`userID` 标识用户；送礼选择和跨布局动画必须使用 `userID`，不能混用三种身份。
10. 业务命令不乐观写入布局。客户端等待后台返回更高 `revision` 的合法快照后，才提交新的舞台 Presentation。
11. 头像业务数据只保存 `LiveRoomAvatarImageID`，不把 `UIImage` 放入 Sendable 快照；Support 层统一解析 Asset Catalog，资源缺失或空麦时回退 SF Symbol。

## 舞台解析

- `party` 解析为 `party.nine`，容量为 9，合法位置为 `0...8`。
- `individual + disabled` 解析为 `individual.audience / collapsed`，只显示位置 `0` 的放大主播麦。
- `individual + enabled` 解析为 `individual.audience / expanded`，显示位置 `0...4`。
- 未注册的 PK 或未知业务模式不会进入 View 层；已有页面保留最后一个有效舞台，首次进入则使用受控的派对房回退。
- 服务端快照只携带业务语义和稳定 ID；具体尺寸、间距、宽屏与紧凑高度适配由客户端 `UICollectionViewLayout` 和 Metrics 负责。

## 麦位 Collection 架构

- `LiveRoomSeatStageView` 持有不可滚动的 `UICollectionView`，舞台高度由外层 QuickLayout 管理，麦位内部不形成第二个滚动区域。
- Diffable Item 身份固定为“有用户用 `userID`、空麦用 `slotID`”；`seatID` 只标识音频实体，不参与视图移动身份。
- `LiveRoomSeatCollectionGeometry` 根据已校验的 Presentation、客户端布局家族、Metrics 与 RTL 方向生成绝对 Frame，自定义 Layout 不读取 ViewModel。
- 房型切换、上下麦和换麦直接动画真实 Cell 的 Frame、透明度与内容；不创建截图、镜像麦位或专用转场 Overlay。
- 快速连续切换时，从当前 presentation layer 冻结的可见位置继续到最新合法快照；仅分数、音频状态等数据变化时只刷新 Cell，不重启场景动画。
