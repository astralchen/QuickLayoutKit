# VoiceRoom 架构

`VoiceRoom` 表示以麦位和语音互动为核心的房间演示，按功能内聚的 MVVM 组织，依赖方向固定为：

`Controllers / Views -> ViewModels -> Models`

- `Models`：后台舞台快照、稳定业务 ID、零基麦位位置、客户端布局目录、礼物与充值目录，不依赖 UIKit 或具体页面生命周期。
- `ViewModels`：直播间状态、送礼选择与交易校验、充值选择与入账；不执行导航和 UIKit 动画。
- `Views`：只负责布局、渲染、用户输入和无障碍反馈，按聊天、麦位、送礼、充值等子域拆分。
- `Controllers`：绑定 ViewModel，协调导航、键盘、子控制器 containment 和跨视图动画。
- `Animations`：可独立生命周期的送礼特效，以及麦位几何变化的判定。
- `Support`：跨子域共享的主题、预览数据与轻量辅助能力。

## 约束

1. 余额、选择状态、业务校验只能在 ViewModel 中提交，View 不维护第二份业务真相。
2. ViewModel 不引用具体 View 或 ViewController，也不直接弹窗、导航或播放动画。
3. Controller 不重新实现 ViewModel 已有的金额、麦位或选择校验。
4. 新增大组件时优先放入对应子域；单文件接近 500 行时按职责拆成视图、交互、渲染或动画文件。
5. 跨层回调使用业务请求或结果模型，避免多个无语义的基础类型参数。
6. 每个独立 UIView 与 UIViewController 都在自身源文件末尾声明 `#Preview`，不创建 `+Preview` 文件或 `Previews` 目录；预览数据只能来自 `DEBUG` 下的 `VoiceRoomPreviewData`。
7. 麦位用户、音频状态、分数、房间模式和业务能力只由 `RoomStageSnapshot` 驱动；View、Cell 与 Layout 不得本地补造生产用户。
8. `SeatPosition` 是后台协议中的零基位置：第一个麦位为 `0`。数组顺序不具备业务语义，Resolver 必须按 `(roomSide, position)` 映射 Slot。
9. `seatID` 标识服务端音频实体，`slotID` 标识布局语义位置，`userID` 标识用户；送礼选择和跨布局动画必须使用 `userID`，不能混用三种身份。
10. 业务命令不乐观写入布局。客户端等待后台返回更高 `revision` 的合法快照后，才提交新的舞台 Presentation。
11. 头像业务数据只保存 `AvatarImageID`，不把 `UIImage` 放入 Sendable 快照；Support 层统一解析 Asset Catalog，资源缺失或空麦时回退 SF Symbol。
12. 用户昵称 key 只属于 `SeatOccupant`；角色统一由 `SeatRole.roomSeat(at:)` 映射，空麦内容统一由 `SeatDisplayContent` 按角色生成。禁止复用用户昵称 key、解析 `slotID` 字符串，或在各房型 View 内重复判断 8 号麦。
13. Demo 的派对房与个播房使用两套确定性阵容；只有主播共享 `userID`，玩法切换不得裁剪并复用同一用户数组。
14. 观众身份与麦上用户统一使用 `RoomUserID`；观众的在麦状态从最新快照中本房的 assignment 派生，使用零基 `SeatAddress`，展示时才转换为一基编号。已打开的观众列表和资料页随快照同步。
15. 业务命令的等待状态由请求自身持有，普通快照不能清除。成功响应经过版本与结构校验后，即使已被推送提交或被更新的推送覆盖，也视为已确认，且不回退舞台。
16. 送礼提交边界必须校验收礼人 `userID` 唯一；重复收礼人请求整体拒绝，不扣款。

## 舞台解析

- `party` 解析为 `party.nine`，容量为 9，合法位置为 `0...8`。
- `individual + disabled` 解析为 `individual.audience / collapsed`，只显示位置 `0` 的放大主播麦。
- `individual + enabled` 解析为 `individual.audience / expanded`，显示位置 `0...4`。
- `pk(styleID: "room.nine")` 解析为 `pk.room.nine`：左侧本房、右侧对方，各有 `0...8`，缺失 assignment 保留空位；物理左右不随 RTL 交换。
- 未注册的 PK 或未知业务模式不会进入 View 层；已有页面保留最后一个有效舞台，首次进入则使用受控的派对房回退。
- 空麦必须使用 `.unavailable` 且积分为 `0`；空用户 ID、空昵称 key 和非法空麦状态会在 Resolver 层拒绝。
- 服务端快照只携带业务语义和稳定 ID；具体尺寸、间距、宽屏与紧凑高度适配由客户端 `UICollectionViewLayout` 和 Metrics 负责。

## 麦位 Collection 架构

- `SeatStageView` 持有不可滚动的 `UICollectionView`，舞台高度由外层 QuickLayout 管理，麦位内部不形成第二个滚动区域。
- Diffable Item 身份固定为“有用户用 `userID`、空麦用 `slotID`”；`seatID` 只标识音频实体，不参与视图移动身份。
- `SeatCollectionGeometry` 根据已校验的 Presentation、客户端布局家族、Metrics 与 RTL 方向生成绝对 Frame，自定义 Layout 不读取 ViewModel。
- 房型切换、上下麦和换麦由 `SeatCollectionLayout` 的 UIKit 更新回调动画真实 Cell 的位置、尺寸与透明度；新增／删除使用 0.96 倍缩放淡入淡出。Cell 始终只保留一个真实 `SeatView`，内容直接更新。
- `SeatStageView.apply(presentation:animated:)` 是统一提交入口；身份不变的几何变化使用独立 batch update，纯内容变化只刷新 Cell。舞台高度、公屏位置与 PK 装饰直接更新，不再依赖场景转场协调器。
- 快速连续切换仅保留最新目标，等待当前 UIKit 更新完成后无动画提交；分数、音频状态等内容更新不会打断几何动画。更新期间临时关闭麦位交互并允许退出 Cell 超出容器，完成后恢复交互、裁剪与辅助功能顺序。
- 首次展示、不可见、禁用动画及减少动态效果时直接提交；环境变化和退出页面会停止可见动画，串行收敛最新状态。送礼锚点始终从真实头像的 presentation layer 查询。

## 麦位显示规则

派对房、个播房和厅 PK 共用以下内容来源；厅 PK 的本房和对方使用相同规则。

| 职责 | 唯一入口 | 规则 |
| --- | --- | --- |
| 房内角色 | `SeatRole.roomSeat(at:)` | 位置 0 为 `.host`，8 为 `.exclusive`，其余为 `.guest(index:)`；仅对当前布局包含的位置生效 |
| 空麦图标 | `SeatRole.emptySeatSymbolName` | 专属座使用 `sofa.fill`，其他角色使用 `person.crop.circle` |
| 空麦名称 | `SeatRole.localizedSeatName` | 主持麦使用 `liveRoom.userCard.hostSeat`，专属座使用 `liveRoom.seat.eight`（中文“专属座”），普通客麦使用 `liveRoom.userCard.guestSeat` 和位置编号 |
| 用户及空麦内容 | `SeatDisplayContent(presentation:)` | 统一解析昵称、头像和分数/状态文案；有用户读取 assignment，无用户读取 Slot 角色 |
| 视图配置 | `SeatView.configure(presentation:)` | 只接收一份 Presentation，从其中读取 assignment，避免两份参数不一致；正式 Cell 和 Preview 共用此入口 |

- `role` 表示业务身份，`styleID` 表示视觉尺寸。PK 的 8 号麦为 `.exclusive` 角色，但仍使用 `.pkGuest` 的尺寸；不能用 `.pkGuest` 推断它是普通麦位。
- 缺失 assignment 与 `occupant == nil` 的空麦记录必须显示相同的图标和名称，且不可打开用户卡片。`SeatAssignment` 的空麦 Symbol 回退也复用角色规则，不解析稳定 ID。
- 有人时，头像和昵称来自 `SeatOccupant`，分数来自 assignment；0 分仍按有人显示。用户下麦、Cell 复用和房型切换后必须恢复对应角色的空麦内容。
- 普通房型在分数区域显示积分或“待上麦”，名称另占一行；PK 在分数区域显示紧凑积分或共用的空麦名称，客麦不另占昵称行。PK 空置主持麦也复用主持麦名称，8 号麦显示“专属座”。
- PK 分数缩写集中在 `SeatDisplayContent`；几何、头像大小、间距和可见行仍由 `SeatVisualStyleID`、`SeatView` 与 Metrics 管理。
- 新增房型应复用上述入口；新增特殊麦位时集中修改角色映射、角色图标/名称与回归用例，不在 View、fixture 或 Preview 中添加另一套编号判断。

相关回归：`RoomPKTests.vacantSeatContentIsSharedAcrossRoomLayoutsAndMissingAssignments` 覆盖三种房型的显式空麦与缺失记录；`exclusiveSeatsPreservePartyVacancyAndRefreshAfterOccupancy` 覆盖两侧专属座上下麦及复用；`RoomPKUITests.testExclusiveSeatVacancyMatchesPartyRoom` 验证 PK 与派对房实际显示。

## 命名

- 功能目录与导航入口使用 `VoiceRoom` / `voiceRoom`。只有整页控制器 `VoiceRoomViewController`、整页状态 `VoiceRoomViewModel`、主题 `VoiceRoomTheme` 和预览数据 `VoiceRoomPreviewData` 保留完整前缀。
- 子功能按职责命名：送礼使用 `Gift…`，充值使用 `Recharge…`，观众使用 `Audience…`，麦位使用 `Seat…`；房间资料、舞台快照与业务命令使用 `RoomInformation…`、`RoomStage…` 和 `RoomCommand…`。观众列表面板对应 `AudienceSheetViewModel`。
- 麦位业务模型统一使用 `SeatAssignment`，不提供含义重复的 `Seat` 别名；`SeatID`、`SeatSlotID`、`RoomUserID` 继续分别表示音频实体、布局位置和用户身份。
- `SeatSizeClass` 表示麦位尺寸等级；`SeatSlotPresentation` 与 `SeatStagePresentation` 表示解析后的展示数据。
- 通用视图按实际职责命名：`MinimumHitTargetButton` 扩展最小命中区域，`TranslucentCardView` 提供半透明卡片样式，`StarfieldBackgroundView` 绘制星点背景，`SpeakingIndicatorView` 显示说话状态动画。`RoomPublicChatView` 表示房间公屏，`SeatUserCardView` 表示麦位用户卡片。
- `AvatarImages.swift` 提供模型到 UIKit 头像的扩展。
- 源文件、扩展与预览辅助函数跟随职责名称；组件测试使用组件名，房间集成测试保留 `voiceRoom…` 场景前缀。
- 本地化 key 与无障碍标识继续使用已有的 `liveRoom.*`；头像资源名称、资源标识值、复用标识与日志分类保持原值。

## 厅 PK

- 原有“更多”菜单选择“厅 PK”，仍经业务命令与递增 revision 快照确认；可切回九麦、五麦，或“结束 PK”恢复进入前阵容与观众席状态。
- 本房继续沿用原 seatID / userID / slotID，进入 PK 时使用本房专属头像，退出后恢复原头像；双方占麦用户使用互不重复的头像资源，对方 fixture 使用独立身份；两侧分别以 0 为主持麦、1–4 和 5–8 为两排观众麦。
- 双方用户均可查看资料卡。收礼列表、全选、发送校验和动画执行只消费本房占麦用户；对方请求必须在扣款前拒绝。
- `RoomPKGeometry` 与 `RoomPKSeatMetrics` 共享容器宽度测量，`RoomPKDecorationView` 仅负责房间标识和 PK 字样。舞台仍使用现有 CollectionView 和真实 Cell 转场。
- `RoomPK` scheme 同时构建单元测试与 UI 测试，筛选厅 PK、麦位转场和原有直播间回归，并通过实际菜单执行交互验收。模拟数据不包含邀请、真实 RTC 或胜负结算。
