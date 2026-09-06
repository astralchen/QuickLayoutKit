# iOS 26 iMessage 风格聊天页

`IMessageChat` 是 Demo 内独立的一对一聊天页面，用来演示 QuickLayout、ListKit、AppLocalization、iOS 26 UIKit Liquid Glass、文本、音频、照片/视频消息与语音输入的组合使用。页面不复用或修改已有的 `UICollectionView` / `UITableView` 消息示例，也不为 QuickLayoutKit 增加公共 API。

该模块仅用于本地界面和交互演示，不接入网络、上传、持久化或真实消息服务。每次进入页面都会创建新的 `IMessageChatViewModel`、页面附件存储与音频控制器，恢复与联系人 Alex 的固定示例会话；录制及从回复文本合成的音频只在本次页面生命周期内有效。

当前 Demo deployment target 为 iOS 26.2，页面使用 iOS 26 原生玻璃 API。媒体层保留 iOS 17–25 的语音识别后端，但这只是未来降低整个 Demo deployment target 时可复用的兼容实现，不表示当前页面已在旧系统运行或验收通过。

## 文件职责

- `IMessageChatModel.swift`：内部文本/附件消息模型、音频与有序媒体组元数据、收发方向、送达状态、稳定时间线 ID、集中刷新身份与渲染模型。
- `IMessageChatViewModel.swift`：初始会话、文本与统一附件发送、媒体组加可选文字的原子发送、类型专属验证、时间分隔、输入中状态、模拟回复、已读状态和本地化物化。
- `IMessageChatAttachmentStore.swift`：页面独立临时目录、外部文件导入、附件草稿、事务式提交、取消删除和页面销毁清理。
- `IMessageChatAudioController.swift`：录音、文本转音频回复、波形采样、预览、单实例播放、语音转写、权限、音频会话与中断处理。
- `IMessageChatPhotoPickerController.swift`：UIKit `PHPickerViewController`、有序增量选择、图片/视频文件导入、缩略图、草稿代次、选择同步与 Sheet detent。
- `IMessageChatBottomObstructionCoordinator.swift`：逐帧采样公开的键盘 layout guide 与照片 Sheet presentation layer，并统一计算输入栏底部遮挡。
- `IMessageChatMediaViews.swift`：媒体草稿预览条、单媒体尾巴气泡、多媒体层叠卡片、展示索引状态与全屏图片/视频预览。
- `IMessageConversationView.swift`：使用 `UICollectionView` 与 `CollectionListAdapter` 渲染时间线，并管理列表更新、音频播放刷新、层叠封面状态、滚底和运行时方向刷新。
- `IMessageChatCells.swift`：文本发送/接收气泡、时间标记、送达状态和输入中动画。
- `IMessageChatAudioViews.swift`：音频气泡、播放/暂停按钮、波形进度、时长与可复用音频 Cell。
- `IMessageChatComposerView.swift`：Liquid Glass 输入栏、1–5 行文本输入、统一用户动作、“照片/音频”附件菜单、媒体横向预览、语音转文字、录音面板和停止后的音频预览。
- `IMessageContactTitleView.swift`：导航栏中的联系人头像、名称和 iMessage 副标题。
- `IMessageChatViewController.swift`：组合会话列表与输入栏，绑定 ViewModel，并协调媒体状态、键盘、本地化、RTL 和错误反馈。
- `IMessageChatPreviewData.swift`：仅在 `DEBUG` 下提供文本、录音、预览、播放以及 incoming/outgoing 音频气泡的确定性预览数据。

依赖方向保持为：

```text
ViewController / Views -> ViewModel -> Models
              |
             +-> Attachment Store
              |
              +-> Audio Controller -> AVFAudio / Speech
              |
              +-> Photo Picker -> PhotosUI / ImageIO / AVFoundation
              |
              +-> Bottom Obstruction -> UIKeyboardLayoutGuide / CADisplayLink
```

ViewModel 不持有播放器、录音器或 UIKit 对象。输入栏通过单一
`IMessageChatComposerAction` 上报用户事件，时间线通过单一
`IMessageChatMessageAction` 上报消息操作；两者只渲染页面协调器发布的状态，
不维护第二份录音、转写或播放业务状态。

## 消息模型与回复流程

单条消息的内容为以下三种之一：

- `.localized(key:)`：固定示例或模拟回复，运行时切换语言后重新解析。
- `.userText`：用户输入或语音转写形成的原始文本，切换语言时不改写。
- `.attachment(.audio)`：统一附件边界中的音频载荷，包含稳定附件 ID、本地可回放文件 URL、精确时长与归一化波形采样。用户录音为 AAC `.m4a`，模拟语音回复为 `.caf`。
- `.attachment(.mediaGroup)`：一次有序选择形成的 1–20 项媒体，保存稳定组/项目 ID、资源标识、页面拥有的原文件与缩略图 URL、像素尺寸以及图片/视频类型；视频类型额外保存有效时长。

音频 Model 不包含 `AVAudioPlayer`、`AVAudioRecorder` 或 UIView。ListKit 的消息 ID 继续作为稳定身份；刷新身份同时包含附件元数据、消息方向和送达文案。播放进度属于页面级瞬时状态，由音频控制器直接更新可见 Cell；滚出屏幕后重新出现的 Cell 会在配置时读取同一份播放状态。

文本与附件共用 delivered → typing → reply → read 生命周期，并根据发出消息的类型生成对应回复。媒体草稿附带非空文字时，先追加一条媒体组，再追加一条独立文字消息，整次操作只安排一次模拟回复；送达状态显示在文字消息下，没有文字时才显示在媒体组下。

1. 追加稳定 ID 的 outgoing 消息，最新一条 outgoing 显示“已送达”。
2. 时间线显示输入中气泡。
3. 发出文本时，ViewModel 通过可注入的 `Sleeper` 等待约 900 毫秒，再追加现有本地化文本回复。
4. 发出音频时，约 900 毫秒的最短输入中时间与本地文本转音频并行执行；两者都完成后追加 incoming 音频附件。
5. 音频合成失败、系统没有对应语言声线或生成文件无效时，回退为同一资源键的文本回复，不留下输入中状态。
6. 回复进入时间线时，最新 outgoing 变为“已读”并移除输入中气泡。
7. 页面销毁、显式取消或发送新消息时，待处理延时和音频合成一并取消。

音频模拟回复使用 `AVSpeechSynthesizer.write(_:toBufferCallback:)` 获取 PCM buffer，并写入页面临时目录中的 `.caf` 文件。该流程只生成附件，不调用 `speak`，不会自动从扬声器朗读，也不需要麦克风或 Speech Recognition 权限。简体中文、英语和阿拉伯语分别使用 `zh-CN`、`en-US` 与 `ar-SA` 的系统默认可用声线；不要求下载增强声线或固定 voice identifier。

合成器根据音频帧数和采样率计算精确时长，并从 PCM 振幅压缩出 36 个归一化波形槽位。生成的 incoming 音频继续使用现有单实例播放器，只有用户点击消息气泡后才开始播放。已经生成的语音附件不会在运行时切换语言后重新合成；后续回复使用新的应用语言。

只有最新一条 outgoing 消息显示“已送达/已读”。时间线第一条消息必定带时间标记；后续消息与上一条间隔达到 5 分钟时插入新的时间标记。

## 照片/视频选择与媒体消息

“+ → 照片”使用 UIKit `PHPickerViewController`，同时选择图片和视频，最多 20 项。
配置采用 `.continuousAndOrdered` 与 `.current` 表示模式，保留系统的照片、精选集、
搜索和完成操作，并关闭 staging area 与敏感内容干预界面。页面不请求完整照片库权限，
也不遍历或修改系统选择器私有视图层级。重新打开时使用资源标识恢复预选；选择数组、
全屏预览页序和发送模型始终保持用户勾选顺序。

资源通过 `NSItemProvider.loadFileRepresentation` 读取后立即复制到页面附件目录，不能
长期引用系统临时 URL。图片保留原文件，并通过 ImageIO 生成最长边不超过 1280px 的
JPEG 缩略图；视频验证视频轨道与正时长，通过 `AVAssetImageGenerator` 生成同样上限的
封面。模型只保存值类型和文件 URL，不保存 `UIImage`、`PHPickerResult`、
`NSItemProvider`、`PHAsset`、`AVAsset`、播放器或手势对象。

媒体草稿存在时，输入栏上层显示 80 × 120pt、4pt 间距的横向预览条，下层继续使用
1–5 行文字输入。所有项目完成导入后才启用发送；视频预览显示图标和 `m:ss` 时长，
删除按钮同步取消系统勾选并清理该项文件。媒体草稿与音频录制互斥，但关闭照片 Sheet
不会丢弃已经导入的媒体或文字。

已发送媒体按以下规则显示：

- 1 项不显示数量标题，媒体自身使用约 22pt 圆角和收发方向对应的消息尾巴；视频中央显示播放按钮。
- 2–20 项显示蓝色四宫格与“`N 个项目`”，主卡片为 216 × 300pt，并按附件实际数量显示最多五层卡片。已浏览项目逐层露在返回方向，未浏览项目逐层露在前进方向；每层水平偏移 8pt、垂直偏移 6pt，多项不绘制尾巴。
- 媒体原始顺序始终保持 `[0, 1, …, N-1]`。左滑进入下一项，右滑回到上一项，首尾阻尼回弹且不循环；可见卡片从原始顺序中截取包含当前封面的连续窗口，展示索引只存于当前页面的 `[MessageID: Int]` 状态，不修改附件数组。
- Cell 按媒体组实际数量绑定最多五张连续索引的卡片，并通过明确的 `layer.zPosition` 保证主卡片最高。超过五项时可见窗口跟随当前封面移动。第 1 项时后置层只向前进侧展开；中间项同时在两侧显示已浏览和未浏览层；末项时后置层只向返回侧展开。cell 自适应高度包含标题、300pt 主卡片和全部层叠偏移，滑动不会改变列表 content size 或送达状态位置。
- 点击主卡片或可明确命中的后置卡片，从对应原始索引进入全屏预览。图片页支持捏合和双击缩放；视频页使用 `AVPlayerViewController` 播放本地文件，离页时停止并释放播放器。

发送顺序固定为“读取完整草稿 → ViewModel 原子验证并追加 → 提交草稿”。任何项目
缺文件、缩略图、有效像素尺寸、视频轨道或正时长时都不产生部分消息，媒体和文字草稿
保持不变。单项导入失败只删除失败项；页面退出时取消未完成任务并清理未发送草稿。

## 文本输入与语音转文字

普通输入状态由左侧独立 44 点“+”玻璃按钮和右侧输入胶囊组成。“+”使用 `UIMenu` 与 `showsMenuAsPrimaryAction`，展示“照片”和“音频”：照片同时承载图片/视频选择；存在媒体草稿时禁用音频，避免静默覆盖草稿。当前范围不包含相机拍摄或媒体编辑。

`UITextView` 的基础高度为 44 点，随内容扩展到最多 5 行，超过后在输入框内部滚动。空输入显示麦克风；裁剪后存在非空文本时显示原有发送箭头。存在媒体草稿时始终隐藏听写麦克风，并在全部导入完成后显示蓝色发送箭头。发送文本会删除首尾空白和换行，保留正文内部换行；纯空白不会发送。

文本态和录音态使用独立的玻璃布局度量。文本态的 `inputGlassView` 使用 4 点
语义起始内边距、6 点语义结束内边距和 4 点内容间距；尾部操作区域固定宽
44 点，麦克风高 40 点。文本发送与音频预览发送按钮统一使用 38 × 28 点
视觉 frame、胶囊圆角和至少 44 × 44 点命中区域，因此发送按钮呈横向胶囊而不是
正圆。文本发送按钮与 `inputGlassView` 底边另保留 6 点间距；
麦克风按钮保留 2 点底部间距，使两种尾部操作占据相同的 42 点布局高度。
录音态不复用这些值。录音和预览玻璃统一使用 64 点高度与 14 点四边基础
内边距；实时录音波形在该内容边界内额外保留 14 点语义起始留白。

点击尾部麦克风时才请求麦克风和 Speech 权限：

1. 授权和识别资产准备期间显示准备状态，不提前修改草稿。
2. 转写期间尾部按钮变为红色停止按钮，最新 partial result 替换当前活动转写片段，不重复追加同一句。
3. 点击停止、中断或识别结束后保留最后文本为普通草稿，不自动发送。
4. 用户开始手动编辑时，输入栏先通知媒体协调器停止转写，再接受编辑，已取消代次返回的异步结果不会覆盖草稿。
5. 没有识别结果时恢复空输入；权限或识别失败不发送任何消息。

系统后端由媒体服务选择，ViewController 不判断系统版本：

- iOS 26+ 优先使用 `SpeechAnalyzer`、`SpeechTranscriber` 和 `AssetInventory`。识别前通过等价 locale 解析支持语言，并在需要时安装本地语音资产；如果 Analyzer 在当前设备、模拟器、语言或资产状态下无法启动，则清理未完成状态并回退到 `SFSpeechRecognizer`。只有两个后端都无法启动时才显示“语音识别不可用”；部分 Simulator Runtime 不提供任一后端，降级不能伪造识别结果。
- iOS 17–25 兼容实现使用 `SFSpeechRecognizer` 与 `AVAudioEngine`。支持设备端识别时设置 `requiresOnDeviceRecognition`；不支持时允许系统在线识别。
- App 的英语、简体中文和阿拉伯语分别映射为 `en-US`、`zh-CN` 和 `ar-SA` 识别 locale。

## 音频录制、预览与发送

选择“+ → 音频”后保留当前文本草稿和键盘状态，输入栏临时切换为整行录音面板。录音态使用 16 点页面水平边距、64 点胶囊高度和 8 点上下边距。录音和预览玻璃中的内容统一使用 14 点四边基础内边距，实时录音波形在共享内容边界内额外保留 14 点语义起始留白，因此波形距玻璃起始边为 28 点；36 点停止按钮以及预览态的播放、发送控件均从同一条 14 点内容边界定位。两种媒体内容栈都显式声明垂直内边距，不依赖父视图的隐式居中。录音和预览波形在 30 点布局槽内垂直居中绘制为 2–12 点高的紧凑柱形，消息气泡波形不受此限制。停止按钮的视觉尺寸遵循设计图，同时把实际命中区域对称扩展到 44 点。固定的媒体态度量不会改变普通文本输入栏的 44 点基础高度：

1. 首次使用时请求麦克风权限。
2. 使用 AAC `.m4a`、44.1 kHz、单声道、96 kbps 语音配置录音，并启用 metering。
3. 每约 50 毫秒采样一次音量；录音 UI 从第一帧起固定使用 60 个波形槽位，以 2 点柱宽和 2 点间距匹配 iPhone 16 Pro 设计图，并将语义起始侧 28% 的旧采样绘制为浅红色。采样不足时用最低振幅补齐，超过上限后滚动保留最新采样，因此录音过程中柱宽和胶囊内边距都不会变化。`#Preview` 使用相同的固定槽位转换，避免 Canvas 与真实录音状态出现不同柱宽。最终附件另行压缩为固定数量的归一化波形采样，避免数据随时长无限增长。
4. 录音态显示红色实时波形、`m:ss` 时长和红色停止按钮；达到 120 秒时自动停止。
   同一次录音中的计量、波形和时长更新只刷新现有内容，不重新计算 Composer
   或父视图布局，因此 16 点页面边距、14 点四边基础内边距和停止按钮位置在
   整段录音期间保持不变。
5. 少于 1 秒的录音立即删除并显示“录音时间太短”，随后恢复原文本草稿。
6. 有效录音进入预览：左侧为独立的 44 点玻璃取消按钮；胶囊内依次为 36 点次级填充播放/暂停按钮、静态波形、带次级填充背景的总时长和统一的 38 × 28 点胶囊发送按钮。紧凑视觉控件均保留至少 44 点的实际命中区域。
7. 取消会停止预览并删除文件；发送会把附件交给 ViewModel。两种操作都会恢复原文本草稿，音频操作不会顺带发送或清空草稿。

预览和时间线共用一个 `AVAudioPlayer`，同一时间最多播放一个附件。再次点击当前附件会暂停并保留进度，再次点击从该进度继续；点击另一条音频会停止上一条并切换目标。播放状态保存在媒体协调器中，因此 Cell 滚出屏幕不会停止播放，Cell 复用或重新出现时会从页面级状态恢复按钮与波形进度。时间线中的文本和音频气泡共用 12 点页面水平边距；音频气泡在最大宽度框内显式按消息方向贴语义边缘，发出音频、发出文本及其送达状态必须落在同一条尾边，RTL 时对应镜像到语义起始侧。

## 临时文件与页面生命周期

每个 `IMessageChatPageAttachmentStore` 创建独立临时目录：

- 有效录音先注册为草稿；取消、过短或编码失败的录音立即删除。
- 照片/视频原文件与缩略图使用同一个媒体组草稿 ID；删除单项时只清理该项，取消草稿时整体清理，已发送后整体提交。
- 发送时先由 ViewModel 验证附件，成功追加消息后才把草稿转为已提交附件；发送
  失败不会清空预览。
- 合成失败、取消、空 buffer 或零时长产生的部分 `.caf` 文件立即删除。
- 已发送录音和成功生成的回复音频仍位于页面目录中，供时间线回放。
- 页面离开时停止录音、转写和播放并释放音频会话。
- 页面及音频控制器销毁时取消异步任务、移除通知观察、停止媒体对象，并由附件
  存储删除整个临时目录。

因此，音频和照片/视频消息都不会跨页面恢复，也不会上传、写入业务缓存或进入真实消息存储。

## 音频会话、中断与失败处理

录音、语音转写和音频播放由同一个音频控制器互斥管理。开始录音或转写会暂停当前播放；录音与转写不能同时占用麦克风。

音频会话使用 `playAndRecord`、`spokenAudio`、默认扬声器和蓝牙免提路由；空闲时通过 `notifyOthersOnDeactivation` 释放会话。

来电、其他音频会话中断或 App 进入后台时：

- 录音达到 1 秒则停止并保留为预览，否则删除并恢复文本态。
- 播放立即暂停，不在中断结束后自动恢复。
- 语音转写停止并保留最后草稿，不自动重启麦克风。
- 耳机等旧输出路由移除时立即暂停播放。

权限只在首次触发对应功能时请求。音频消息只需要麦克风权限；语音转文字同时需要麦克风和 Speech 权限。拒绝或受限制时显示英语、简体中文或阿拉伯语说明；可恢复的拒绝状态提供“打开设置”。录音、播放、转写、语音资产或文件失效也通过本地化错误反馈处理，不自动发送消息。

权限声明位于 `InfoPlist.xcstrings`：

- `NSMicrophoneUsageDescription`：录制音频消息及语音输入。
- `NSSpeechRecognitionUsageDescription`：把讲话转写为消息草稿。

## 列表布局、滚动与键盘/照片 Sheet

- 文本和音频气泡都以可用行宽约 75% 为上限；单媒体最大宽度 252pt，多媒体层叠完整外框为 232pt。
- incoming 位于语义 `leading`，outgoing 位于语义 `trailing`；RTL 下位置、尾角、送达状态与控件顺序按语义镜像。
- outgoing 音频沿用蓝色消息色，incoming 音频使用系统次级填充色。
- 送达状态与 outgoing 气泡的语义尾端对齐，不能使用屏幕边缘独立定位。
- 首次加载和主动发送后滚到底部；收到回复、本地化刷新、输入栏高度或模式变化时，只有用户原本接近底部才跟随滚动。
- 用户浏览历史时，本地化刷新保存并恢复可见锚点，录音/预览状态变化不会强制把列表拉到底部。
- 列表使用 `.interactive` 键盘收起模式。

本页面在 `super.viewDidLoad()` 前关闭框架自动键盘安全区处理：

```swift
quickLayoutKeyboardSafeAreaBehavior = .disabled
```

`IMessageChatBottomObstructionCoordinator` 独占输入栏底部位移，避免框架键盘 inset 与页面 Sheet inset 重复抬升。系统键盘正常显示或交互下拉时，通过 `CADisplayLink` 读取 `UIKeyboardLayoutGuide.layoutFrame.minY`；照片 Sheet 展示时则读取呈现层的实时位置，让输入栏跟随上下移动，并以打开面板时最近一次完整系统键盘内容高度为上限。遮挡高度按“容器底部 − 遮挡顶部 − 容器底部安全区”计算，避免重复加入底部安全区。

照片 Sheet 提供键盘等高的小档（首次 300pt，最小 220pt）和 `.large()`。输入栏上限与 custom detent 均以不含底部安全区的键盘内容高度为依据，输入栏自身保留 8pt 页面内边距，Sheet 的悬浮边缘由系统负责。小档允许背景交互，大档使用系统遮罩。Sheet 超过键盘高度上限后继续覆盖下层内容，输入栏停在上限；向下收回时，输入栏恢复跟随。

键盘 → 照片时，输入栏在整个面板入场动画期间保持稳定键盘高度，不随面板从屏幕外升起而先下落再上移。系统入场完成后，以面板实际位置校准后续拖动的几何差值，消除悬浮边缘和缩放造成的小幅高度跳变；面板向下退出屏幕时，校准量也会归零。没有可见停靠键盘时直接打开照片，仍正常从底部跟随升起。从创建 Sheet 到明确切回键盘前，键盘通知不修改输入栏高度上限，也不触发 `invalidateDetents()`。附件菜单关闭时 UIKit 可能发出移除候选栏后的临时键盘高度；若用它覆盖上限，照片面板仍保持打开时的高度，就会遮挡输入栏。照片 → 键盘时先保留交接起点，收到键盘通知后按系统曲线切换到最终高度；Sheet 完全关闭且 keyboard layout guide 到达目标后才恢复逐帧键盘采样。交接期间不会在正在 dismiss 的 Sheet 上调用 `invalidateDetents()`。外接或浮动键盘没有底部软件键盘遮挡时，Sheet 消失后回到底部。

文本、录音、音频预览和媒体预览高度变化都通过同一“变化前记录 `isNearBottom`，布局后按原状态决定是否滚底”的规则处理。

## Liquid Glass 与导航标题

输入栏继承 `QuickLayoutView`，使用 `QuickLayoutVisualEffectView` 承载玻璃内容。框架通过 `bodyContainerView` 把 QuickLayout body 安装到玻璃 API 要求的 `contentView`，控件布局由 `HStack`、`ZStack` 和 `onGeometryChange` 驱动。玻璃效果只用于输入控制层，不覆盖消息内容区域。“+”按钮的玻璃宿主通过 `UICornerConfiguration.capsule()` 固定交互形状，按钮配置同时使用 `.capsule`，因此普通态、按下态和菜单高亮态都保持 44 × 44 点正圆，不依赖系统临时推导圆角。

`IMessageContactTitleView` 使用 QuickLayout 的 `HStack` 与 `VStack`，并通过明确的 `intrinsicContentSize` / `sizeThatFits(_:)` 桥接 `UINavigationBar` 测量。标题最大宽度为 220 点、高度不超过 44 点，包含 30 × 30 点系统头像、联系人名称 Alex 和本地化副标题。配置副标题后必须调用 `sizeToFit()`。

## 本地化、RTL 与辅助功能

- 文案位于 `Localizable.xcstrings`，权限说明位于 `InfoPlist.xcstrings`，均覆盖英语、简体中文和阿拉伯语。
- 文本统一使用自然对齐；收发位置只使用 semantic leading/trailing，不使用固定 left/right。
- 文本气泡、音频气泡、媒体组、播放、暂停、录音停止、删除、取消、发送、时长、播放进度、时间、送达状态、输入中状态和输入框均提供辅助功能标签或值。
- 多媒体组是 adjustable 元素：VoiceOver 递增查看下一项、递减查看上一项，播报“第 X 项，共 N 项，图片/视频”；到达首尾时播报边界且不循环。后置卡片不重复暴露为独立元素，双击从当前封面打开预览。
- Dynamic Type 会更新正文、时长与送达文本；系统语义色适配浅色、深色和高对比度。
- 输入中动画在 Reduce Motion 开启时停止；媒体操作不依赖装饰动画完成。

运行时切换语言会重建本地化固定文案与辅助功能文本，但不会修改音频附件、用户文本或语音转写后的草稿。运行时切换 LTR/RTL 会重建列表布局并刷新已物化 Cell，保证可见 Cell 与后续复用 Cell 使用同一方向。

## 路由与 Xcode Preview

页面通过 Demo 内部路由进入：

```swift
DemoRoute.imessageChat
```

每个独立 `UIView`、`UICollectionViewCell` 与 `UIViewController` 都在自身源文件末尾声明 `#Preview`，统一放在 `#if DEBUG` 内。方向敏感组件包含 RTL 变体；录音、预览、播放和 incoming/outgoing 音频气泡使用 `IMessageChatPreviewData` 的确定性数据。

预览数据只能来自 `IMessageChatPreviewData`。不要创建 `+Preview.swift` 文件或 `Previews` 目录，也不要在组件文件中临时构造会随时间变化的业务数据。

## 测试重点

相关测试位于 `Demo/DemoTests/DemoTests.swift` 与 `Demo/DemoTests/IMessageChatMediaTests.swift`。测试必须使用协议注入的假服务、固定 Clock、受控 Sleeper 与确定性附件，不能读取真实麦克风、依赖在线识别、调用真实系统声线或用真实休眠等待结果。

当前回归重点包括：

- 文本发送只生成文本回复；音频发送在最短输入中时间和合成完成后生成音频回复，失败时回退文本。
- 回复合成的语言映射、取消、部分文件清理、时长和固定波形槽位保持确定。
- 音频 ID、时长、波形归一化和本地化刷新保持不变。
- 0.99 秒拒绝、1 秒允许和 120 秒自动停止边界。
- 录音、转写和播放互斥；切换条目、暂停续播、路由移除、无效文件与页面释放回到确定状态。
- iOS 26/旧版后端能力选择，以及英语、简体中文和阿拉伯语 locale 映射。
- partial result 替换、停止、错误、无结果和手动编辑不重复或覆盖原草稿。
- 空文本显示麦克风，非空文本显示发送；附件菜单包含“照片”和“音频”，媒体草稿存在时音频入口禁用。
- 1、2、5、20 项媒体发送边界，无效媒体原子拒绝，以及“媒体组 + 文字”只安排一次回复。
- 选择顺序、草稿导入完成门槛、文件整体提交/清理，以及层叠状态跨 cell 重用保留。
- 5 项媒体的全部旋转顺序、物理左右滑方向、距离/速度阈值、首尾不循环和模型数组不变。
- iPhone 16 Pro 402pt 行宽下，三项媒体的 232 × 344pt 外框以及五项以上媒体的 248 × 356pt 外框完整参与 cell 首次自适应测量，不退化为 10 × 10pt 占位尺寸或与下一行重叠。
- 键盘与照片 Sheet 遮挡计算扣除底部安全区，避免输入栏顶部再出现一份重复安全区间距。
- 取消或发送音频后恢复原草稿，音频发送不清空文本草稿。
- 文本 1–5 行、录音/预览 64 点固定胶囊高度、16 点页面水平边距、键盘停靠与最后一条消息遮挡。
- Dynamic Type 变化会重新测量文本输入高度；固定 64 点媒体面板中的时长字体最多缩放到 24 点，保证辅助功能字号下时长完整且波形仍有可用宽度。
- 文本和音频 Cell 在 LTR/RTL 下贴正确语义边缘，并覆盖 Dynamic Type、VoiceOver、Reduce Motion、深色和高对比度状态。

编译、单元测试、Simulator UI、真实麦克风、真机 Speech、蓝牙/耳机和系统中断属于不同证据，验收时必须分别记录为“通过 / 失败 / 未执行 / 被环境阻塞 / 不适用”，不能用通用构建代替真机媒体结果。

## 维护约束

1. 模块保持 Demo 内部可见，不为 QuickLayoutKit 新增公开 API。
2. 不与现有 `MessageModel`、`MessageListViewModel` 或两种消息列表 Demo 合并。
3. 消息只存在于当前页面生命周期，不添加网络、上传或持久化抽象。
4. 新增时间线内容必须提供稳定 ID，并补齐 ListKit 刷新身份。
5. 录音、音频播放、转写和 `AVAudioSession` 必须继续由音频控制器单点拥有；附件文件由页面附件存储单点拥有，Cell 与输入栏不得直接创建媒体对象。
6. 修改气泡布局时必须同时验证短文本、长文本、音频、单媒体、多媒体层叠、LTR、RTL 和 Dynamic Type。
7. 修改输入栏时必须验证键盘展开、照片 Sheet 小/大档与交互拖动、两种遮挡源交接、1–5 行、录音态、媒体预览态、原草稿恢复和最后一条消息遮挡。
8. iOS 26 原生玻璃 API 只用于导航或输入控制层，消息内容层保持系统纯色背景。
9. Composer 预览项固定为 120 点高，按附件像素比例计算 80～160 点宽度；多帧图片和 Live Photo 显示动态图片标志。当前范围不包含相机拍摄、图片编辑、视频剪辑、GIF 动画播放、Live Photo 播放、其他附件、上传、持久化、Tapback、内联回复或真实已读回执；GIF 与 Live Photo 仍按静态缩略图发送和预览。
10. iOS 17–25 只属于语音识别服务的兼容预留；旧系统页面运行需要未来降低整个 Demo deployment target 并提供非 iOS 26 UI。
11. 新增独立 View 或 ViewController 时，必须在同一源文件补充基于 `IMessageChatPreviewData` 的 `#Preview`。
12. 新增内部类型、状态、回调和用户动作方法使用 UIKit SDK 风格的 `///` 文档注释：先给出简洁摘要，再按需要补充讨论、参数和返回值；不要用逐行翻译代码的噪声注释。

## 参考资料

- [SpeechAnalyzer](https://developer.apple.com/documentation/Speech/SpeechAnalyzer)
- [Speech framework](https://developer.apple.com/documentation/speech/)
- [Apple Messages 使用说明](https://support.apple.com/en-gb/guide/iphone/iph82fb73ba3/26/ios/26)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [UIKit appearance customization](https://developer.apple.com/documentation/uikit/appearance-customization)

### 键盘与照片菜单 UI 回归

`IMessageChatRegression` Scheme 仅运行 `IMessageChatKeyboardUITests`，通过真实点击“输入框 → ＋ → 照片”验证切换前后输入栏底边保持一致且未被面板遮挡，并保留截图。高度缓存与交接状态的确定性回归仍位于 `IMessageChatMediaTests`。
