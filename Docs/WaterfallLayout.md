# UICollectionViewWaterfallLayout

本实现提供混合交叉轴尺寸、UIKit 自适应测量和最短列排列。旧的 `Section.laneCount` 已移除；配置、布局与测量回调均在主 actor 上运行，没有后台布局任务。

布局源码位于 `Sources/QuickLayoutKit/QuickLayoutKitUIKit/UICollectionViewWaterfallLayout.swift`，由 `QuickLayoutKit` 统一导出，支持 iOS 15 及以上。Demo 直接使用框架公开类型；引擎诊断与缓存统计保留 internal，由测试通过 `@testable import QuickLayoutKitUIKit` 访问。

## 配置与迁移

```swift
extension UICollectionViewWaterfallLayout {
    nonisolated public enum LaneSize: Equatable, Sendable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }
}

import QuickLayoutKit

var section = UICollectionViewWaterfallLayout.Section()
section.lanes = [.flexible(), .flexible()] // 旧 laneCount = 2
section.lanes = [.adaptive(minimum: 160)] // 容器决定列数
section.lanes = [.fixed(120), .flexible(), .adaptive(minimum: 80)]
let layout = UICollectionViewWaterfallLayout(section: section)
let count: Int? = layout.resolvedLaneCount(in: 0)
```

`fixed` 和 `flexible` 各占一条列／行；`adaptive` 在分配给自己的空间内展开。先扣除固定尺寸及描述之间的统一 `interLaneSpacing`，剩余空间均分给非固定描述。flexible 应用上下限；adaptive 按最小尺寸决定数量，再按每条的上下限分配尺寸。达到最大尺寸后，空白留在逻辑交叉轴末端，不重新分配给其他描述。

例如可用宽度 320、间距 10，`[.fixed(70), .flexible(minimum: 20, maximum: 150), .adaptive(minimum: 35, maximum: 80)]` 得到 `[70, 115, 52.5, 52.5]`。这参考 `GridItem.Size` 的描述方式，分配规则由本布局明确定义，不依赖 SwiftUI 的布局实现。

空间不足时保留固定／最小尺寸，超出容器的部分由 collection view 裁剪。正有限容器才能解析；零或不可用的交叉轴返回 `nil`。空数组、非正或非有限尺寸、上下限颠倒、数量／坐标溢出回退到默认两条 flexible，DEBUG 输出诊断。最大展开数量限制为 1,000,000，避免异常配置导致不受控分配；极端间距导致默认坐标也溢出时同时回退到默认间距 10。

`lanes.count` 是描述数量；`resolvedLaneCount(in:)` 才是实际列／行数。Demo 用 UIFontMetrics 缩放最小尺寸并设置 `.adaptive(minimum:)`，不再维护第二份自动列数公式。原来固定数量的调用改为 `Array(repeating: .flexible(), count: count)`。

## 命名与日志

类型和文件统一命名为 `UICollectionViewWaterfallLayout`，采用与 `UICollectionViewFlowLayout` 相同的命名结构。这是 QuickLayoutKit 提供的自定义布局，通过 `import QuickLayoutKit` 使用。原 `ContentConfigurationWaterfallLayout` 调用已直接迁移，不保留旧别名。

框架使用系统 `Logger`，subsystem 为 `QuickLayoutKit`，category 为 `WaterfallLayout`，不再直接 `print`。仅 DEBUG 构建记录日志：常规失效使用 debug 级别，默认关闭，可通过 `QuickLayoutDiagnostics.isEnabled = true` 开启；非法 lanes 或不支持的边界配置使用 warning 级别。动态失效原因采用默认隐私遮蔽，开发者提供的 boundary kind 明确公开，固定事件描述始终可见。

日志参数延迟求值，关闭诊断时不拼接常规失效消息；Release 构建不求值诊断参数，也不输出上述日志。`QuickLayoutDiagnostics` 同时控制框架已有的布局记录，调试完成后可关闭并调用 `reset()` 清理记录。

## 继承

`UICollectionViewWaterfallLayout` 是 `open` 类。外部模块可继承，并覆写 `prepare()`、`collectionViewContentSize`、布局属性查询、bounds／preferred attributes 失效回调及 `invalidateLayout(with:)`，在需要保留默认布局行为时调用 `super`。

`layoutAttributesClass` 和 `invalidationContextClass` 保持不可在外部模块覆写，确保内部测量身份与候选几何上下文一致。Section、provider 与尺寸查询继续使用共享几何状态；公开访问不等于开放任意内部缓存覆写。

```swift
class CustomWaterfallLayout: UICollectionViewWaterfallLayout {
    override func prepare() {
        super.prepare()
        // 在这里追加自定义布局处理。
    }
}
```

## 几何与测量

- 每条 lane 缓存逻辑交叉轴起点和长度，每个条目记录实际 lane；frame、测量 key 和 `sizingForItem(at:)` 使用同一份已提交几何。等宽两列保留直接比较的快速路径，同高优先逻辑起始列。
- 容器／配置未准备好时 `sizingForItem(at:)` 返回零约束，不在查询中调用 `prepare()`。准备完成或换列改变宽度后，合并到下一主循环调用 `sizingInvalidationHandler`。
- 调用方在后续布局周期只更新尺寸策略变化的可见 cell，离屏条目在配置时取最新尺寸。Demo 的容器、方向和 Dynamic Type 刷新不应用数据 snapshot；模型内容变化才更新 snapshot。
- 测量按稳定 ID、内容版本、实际交叉轴尺寸、主轴策略、方向、字号类别、显示比例和配置 generation 匹配。移动保持 ID；不匹配的旧属性／候选被拒绝。
- 每项最多四个宽度变体，保留当前使用的结果，其余按 LRU 淘汰；完整数据／环境更新时清理删除 ID、旧版本和不再可用的宽度。候选不复制整个测量字典。
- `LaneSize`、`ResolvedLane`、`ItemSizing` 和诊断值遵循 `Sendable`。Section、provider、布局、UIKit 属性及带 `AnyHashable` 的测量缓存保持主 actor 所有权。
- 属性的 `NSObject.isEqual(_:)` 非隔离入口只比较不可变的测量标识，再调用父类比较；不使用 `MainActor.assumeIsolated` 或 `nonisolated(unsafe)` 读取测量 key。完整 key 在主 actor 比较，相同 key 重用标识，属性复制保留标识。为兼容 iOS 15，标识存储使用 `NSLock`；仅此小型容器采用 `@unchecked Sendable`，所有读写加锁，且不包含 UIKit 状态或 `AnyHashable`。这不改变 UIKit 属性本身的主 actor 修改边界。

## 更新与索引

section 使用相对坐标，每 128 项保存一个不可变几何块及前后列末端检查点。拟合从条目所在块开始，前缀直接共享；下一个检查点完全相同或所有列仅相差同一平移量时，共享后缀块并更新轻量位移。否则继续按最短列重排，头部最坏情况仍为 O(N × L)。后续 section 只更新起点，不逐项移动 UIKit 属性。

候选记录数据／测量版本及环境状态，失效提交立即发布有效候选；交错回调重新基于最新已接受测量计算。之后的 `prepare()` 不重复重建。bounds 候选在目标环境生效时复用。锚点偏移只提交尚未应用的增量。

区域查询二分 section 范围，再二分各 lane 的稀疏块索引和块内有序区间；仅相交元素生成属性。长卡片和极稀疏列也能命中。横向 RTL 将查询转换到逻辑主轴；纵向 RTL 镜像交叉轴。固定 header/footer 按 section 范围筛选；背景有独立区间索引，支持负 inset 延伸。

稳定 ID → IndexPath 和缓存数据源顺序用于恢复可见锚点。全部可见项删除时沿旧顺序线性回退，不再嵌套遍历新旧数据。Demo 的元数据和模型配置使用预建 ID 字典。

几何内只保存轻量记录；UIKit 属性按查询创建。候选共享未修改块；仅保留当前几何、一个待提交 bounds 候选和待恢复锚点。每次拟合会复制小的块／section 索引数组，复杂度并非严格常数；没有每次拟合全量复制条目数组或测量字典。

## 复现验证

`WaterfallLayoutEngineTests.swift` 包含解析／Sendable、固定数据参考算法对照、混合宽度重测、交错与过期回调、稀疏列查询、缓存上限、删除回退、bounds、背景溢出，以及非主 actor 属性相等性和复制的测试。`WaterfallLayoutTests.swift` 与 `ContentConfigurationWaterfallTests.swift` 覆盖原有布局、真实卡片、动态字号、方向、补充视图、背景和 snapshot 分离。

性能测试默认禁用，通过 `WATERFALL_BENCHMARK=1` 启用。原始 `WaterfallLayoutPerformanceTests.swift` 保持基准场景用于前后对照；新增矩阵为 3 轮 × 1,000／10,000 条 × 纵向／横向／横向 RTL × 两条 flexible／单 adaptive／fixed+flexible × 1／10 section。

矩阵记录 P50/P95、每次耗时、实际 lane 数、完整重建、重排项数、区域候选、锚点查找、候选复用、元数据查询、缓存数量和进程常驻内存。缓存 prepare、稳定滚动及拟合后 prepare 断言零重建／元数据查询；查询 P95 ≤ 2 ms，尾部 64 项内更新 P95 ≤ 8 ms，且只重排至多 192 项／次。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash Scripts/run-waterfall-benchmark.sh SIMULATOR_UDID /private/tmp/waterfall-benchmark
```

可设置 `WATERFALL_PACKAGE_CACHE` 复用 SourcePackages，或设置 `WATERFALL_PREBUILT_PRODUCTS=/path/to/Debug-iphonesimulator` 使用精简宿主。生成器直接编译框架目录中的 Layout、PerformanceTests 和 EngineTests（精简宿主以 `WATERFALL_STANDALONE_HOST` 选择测试模块导入），链接已有 QuickLayout、QuickLayoutCore、QuickLayoutBridge、FastResultBuilder 对象。布局及测试为 Release `-O`，预编译依赖须匹配工具链和架构；本次依赖来自 Debug 缓存。

脚本先编译再非并行执行测试，输出 `results.json`、`scalability.json` 和 xcresult，记录 run ID、源码 SHA-256、Git HEAD 和配置，并拒绝复制陈旧结果。计时不包含真实文本拟合；真实 cell 收敛由独立 Demo 功能测试验证。常驻内存是包含 UIKit／测试宿主的采样值，不是 Allocations 峰值。模拟器计时不用于推断 FPS；真机首屏、hitch 和内存仍需在指定设备记录。
## 修复前基线（2026-09-12）

本次测试日期：2026-09-12。Xcode 26.5（17F42），iOS 26.5 / iPhone 17 Pro 模拟器，x86_64 模拟器运行架构。原始布局以 Release `-O` 编译，QuickLayout 依赖复用 Debug 产物。

源码基线：`b526648ed311584511b13fa259e43343abaf46de`；布局 SHA-256：`bdaf15914136fdb8f3149208cb5044e60f10a5500c820378853989a954635b30`。

两轮使用自动释放池的基准均通过，覆盖纵向、横向和横向 RTL。以下为纵向两轮结果范围，单位均为毫秒。主机负载波动明显，因此保留两轮原始数据，不把本次计时当作稳定硬件性能评级。首次、批量和删除场景每轮仅一个样本。

| 场景 / 统计口径 | 1,000 条 | 10,000 条 |
| --- | ---: | ---: |
| 首次布局（单次） | 29.605–92.988 | 291.809–770.080 |
| 缓存 prepare（20 次中位数） | 0.003–0.004 | 0.003–0.004 |
| 区域查询（120 次中位数） | 0.158–0.179 | 3.173–3.259 |
| 区域查询（120 次 P95） | 0.231–0.778 | 5.358–17.275 |
| 拟合回调及失效（5 次中位数） | 25.277–87.745 | 284.745–754.495 |
| 拟合后 prepare（5 次中位数） | 14.480–16.620 | 151.579–368.489 |
| 8 次拟合 + 1 次 prepare（单次） | 239.891–278.417 | 2287.468–5819.019 |
| 删除 90% 并恢复锚点（单次） | 55.740–124.938 | 5581.885–15320.057 |

单条拟合完整链路的平均耗时，以两段总耗时之和除以 5 计算：
- 1,000 条：42.760–93.842 ms。
- 10,000 条：450.078–1073.143 ms。

### 不受计时抖动影响的工作量证据

| 10,000 条场景 | 元数据调用次数 | 结论 |
| --- | ---: | --- |
| 首次 prepare | 10,000 | 全量构造测量 key |
| 20 次缓存 prepare | 0 | 现有缓存命中路径有效 |
| 120 次区域查询 | 0 | 耗时来自属性扫描等工作，不是重新测量 |
| 每次拟合回调及失效 | 10,002 | 1 次全量候选布局 + 2 次 key 校验 |
| 每次拟合后 prepare | 10,000 | 相同测量再次全量重建 |
| 8 次拟合 + 1 次 prepare | 90,016 | 合并 prepare 没有合并回调中的全量重建 |

区域查询零次元数据调用不能证明查询为 O(1)；源码仍对所有 cell 做相交判断。删除场景在删除全部可见锚点及前 90% 数据后，旧锚点列表逐个扫描新的 10% 属性集合，存在约 0.9N × 0.1N 的查找规模。

### 元数据查找独立对照

最终一轮做了 5 组相同查询顺序的对照，仅计完整查询循环，不计预建字典：

| 每轮查询数 | 数组 first 查找中位数 | 字典查找中位数 |
| --- | ---: | ---: |
| 1,000 | 0.375 ms | 0.039 ms |
| 10,000 | 134.120 ms | 1.135 ms |

这个对照验证替换查找的收益；它不包含 Diffable Data Source 查询，也不代表完整 Demo 的加速倍数。独立冷启动场景的波动较大，不用它推算元数据成本。


原始数据：[修复前运行 1](Benchmarks/waterfall-10000-baseline-run1.json)、[修复前运行 2](Benchmarks/waterfall-10000-baseline-run2.json)。这些原始文件保持不变；旧版本没有新增的重排项数等计数器，因此不反推未采集的计数。

Swift 6 检查可独立运行（不改变整个工程的语言模式）：

```bash
bash Scripts/check-waterfall-concurrency.sh /path/to/Debug-iphonesimulator x86_64
```

脚本以默认 MainActor 和默认非隔离两种设置实际生成 Swift 6 严格并发模块，验证 `[LaneSize]`、解析结果和 `ItemSizing` 可跨 actor 传递，并验证主 actor 外创建 Section 被编译器拒绝。以 iOS 15 为最低版本编译不使用 `@testable` 的外部客户端，检查公开 API、跨模块继承及非隔离属性比较调用。UIKit 属性与 provider 不声明跨 actor 传递能力。

## 修复后验收（2026-09-13）

本节原始性能记录采集于移入框架前；迁移保留布局算法，调整模块归属、公开访问级别、调用方引用，以及属性相等性比较的 Swift 6 隔离边界。历史 JSON 的源码校验值保持不变。

最终版本的精简宿主 9 项测试全部通过，包含 108 组配置、972 条场景记录的三轮矩阵。此前执行的一份三轮矩阵也保留在原始结果中。下表使用最终运行 `waterfall-scalability-run2.json`，列出所有 10,000 条配置中的范围；首次、八次拟合、头部和删除每组每轮只有一个样本，不能将它们的 `p95_ms` 字段解释为稳定尾延迟。

| 场景 | 最终运行结果 | 工作量与验收 |
| --- | --- | --- |
| 缓存 prepare / 稳定滚动 | 全部通过 | 重建 0、重排 0、元数据 0 |
| 区域查询 P95 | 0.027–0.120 ms | 小于 2 ms；候选随相交元素增长 |
| 尾部 64 项内单条更新 P95 | 0.627–2.123 ms | 小于 8 ms；5 次共重排至多 520 项，无无关前缀重排 |
| 拟合后 prepare | 全部复用 | 重建 0、元数据 0 |
| 8 次连续拟合 | 4.658–57.677 ms | 完整重建 0，元数据 16；最多重排 35,312 项，保留最短列语义 |
| 头部更新 | 0.452–15.990 ms | 最坏重排 10,000 项，明确保留 O(N) 路径 |
| 删除 90% | 3.836–10.420 ms | 只读取剩余 1,000 项元数据；锚点回退保持线性 |

以下前后对照采用同机、同方向、同样两条 flexible、390×844 容器、估算长度 120、相同操作序列。旧源码从原提交读取到临时宿主，不修改工作区；两次测试之间没有并行编译。单位 ms。改进比例只代表这些布局微基准，不是完整页面或 FPS 改进。

| 10,000 条纵向场景 | 修复前（补测） | 修复后 | 耗时减少 |
| --- | ---: | ---: | ---: |
| 首次布局 | 274.116 | 26.587 | 90.30% |
| 区域查询 P95 | 3.982 | 0.039 | 99.03% |
| 8 次拟合 + prepare | 2137.319 | 25.798 | 98.79% |
| 删除 90% + 锚点恢复 | 5041.993 | 8.065 | 99.84% |
| 头部更新（3 轮中位数） | 272.447 | 5.916 | 97.83% |

头部对照采用独立的全新 fixture，三轮范围从 266.000–308.975 ms 降至 5.200–7.276 ms，每次元数据查询由 20,002 降至 2。该 fixture 的等长估算与矩阵中的变长估算不同，两者分别报告。8 次拟合合并一次 prepare 的元数据查询从 90,016 降至 16，消除了重复完整构建。

常驻内存采样包含测试框架、UIKit 和累计结果数组；最终三轮最大值分别为 147.72、149.79、151.37 MiB。没有将这组数据宣称为 Allocations 峰值或独立布局内存。缓存断言验证每项最多四个测量变体；几何通过不可变块共享，没有维护历史快照列表。数据／环境改变仍需要重新读取元数据并完整构建，拟合更新使用检查点增量路径。

最终 Demo 功能回归覆盖真实卡片收敛、动态字号和方向、稳定 ID 与删除、固定补充视图、背景、混合宽度及尺寸刷新不应用 snapshot。Swift 6 严格检查验证尺寸值跨 actor 传递成功、主 actor 外创建 Section 被拒绝。环境和测量版本失效时同时丢弃旧候选的锚点偏移，避免旧回调改变新的滚动位置。

未连接真机（`devicectl list devices` 返回空），因此真机首屏、滚动 hitch、FPS 和 Allocations 峰值未测；这些不由模拟器计时代替。

原始结果：

- [最终三轮矩阵](Benchmarks/waterfall-scalability-run2.json)、[首次三轮矩阵](Benchmarks/waterfall-scalability-run1.json)
- [最终原场景对照](Benchmarks/waterfall-10000-after-run2.json)、[首次原场景对照](Benchmarks/waterfall-10000-after-run1.json)
- [旧源码补测](Benchmarks/waterfall-10000-baseline-run3.json)
- [头部更新修复前](Benchmarks/waterfall-head-before.json)、[头部更新修复后](Benchmarks/waterfall-head-after.json)

复现旧源码补测时，在精简宿主模式同时设置 `WATERFALL_BASELINE_REV=b526648ed311584511b13fa259e43343abaf46de`。生成器只把旧版本布局和对应 API 的测试副本放在输出目录，不运行依赖新 API 的 EngineTests；同一组头部测试同时用于前后版本。脚本记录实际被测源码的 SHA-256，所有产物校验本次 run ID。


## 属性相等性隔离修复复验（2026-09-13）

`isEqual(_:)` 不再使用 `MainActor.assumeIsolated`。完整测量 key 的比较与标识复用在主 actor 完成；非隔离入口仅读取锁保护的不可变标识，再执行 UIKit 原有比较。增量重排直接读取旧块标识，仅交叉轴约束改变时创建新标识；数据重建时才按稳定 ID 查找并比较完整 key。复制、未改变输入的重建、内容版本更新和混合宽度换列均有相等性回归，并实际从 detached task 调用比较。

两种默认隔离设置下的 Swift 6 严格并发模块生成及 iOS 15 外部 API 检查通过。完整 Demo 回归 29 项通过，1 项矩阵默认跳过；最终 Release 精简宿主 11 项全部通过，矩阵为 108 组配置、972 条记录。完整 Demo 回归完成后，对标识复用增加了旧块直接读取优化，并由最终精简宿主重新验证。

本次最终源码 SHA-256：`02627f290149b2080855a411f80467ea05eb85aa238be36838b369623d61a610`。以下为三轮所有 10,000 条配置范围，单位毫秒：

| 场景 | 本次结果 | 工作量 |
| --- | --- | --- |
| 区域查询 P95 | 0.031–0.133 | 元数据 0，完整重建 0 |
| 尾部更新 P95 | 0.568–2.384 | 5 次至多重排 520 项，完整重建 0 |
| 缓存 prepare／稳定滚动／拟合后 prepare | 全部通过 | 元数据 0，重排 0，完整重建 0 |
| 首次布局 | 24.336–46.080 | 重排 10,000 项 |
| 8 次连续拟合 | 5.635–62.448 | 元数据 16，完整重建 0，至多重排 35,312 项 |
| 头部更新 | 0.452–14.395 | 最坏重排 10,000 项 |
| 删除 90% | 5.888–13.060 | 元数据 1,000，锚点查找通过线性上界断言 |

首次布局、8 次拟合、头部和删除仍是每配置每轮一个样本，不解释为稳定 P95。常驻内存三轮最大采样为 156.98、157.67、159.35 MiB，包含宿主、UIKit 和累计测试结果；此结果不等同于布局分配峰值，也不能据此单独归因标识存储的内存成本。每项测量缓存四个变体上限断言通过。

原始数据：[本次三轮矩阵](Benchmarks/waterfall-equality-scalability.json)、[原场景](Benchmarks/waterfall-equality-results.json)、[头部独立场景](Benchmarks/waterfall-equality-head.json)。先前基线及其源码校验值保持不变。
