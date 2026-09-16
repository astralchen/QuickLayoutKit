# 远程礼物示例配置

仅 JSON 配置随 Demo 打包，MP4/SVGA 动画始终通过远程 URL 播放，由播放器管理运行时缓存。

- `gift_effects_mp4.json`：https://github.com/astralchen/VAPView/blob/1.0.0/Demo/VAPDemoApp/gift_effects_mp4.json
- `gift_effects_svga.json`：https://github.com/astralchen/SVGAView/blob/1.0.0/Examples/Examples/gift_effects_svga.json
- 配置版本：两个仓库的 `1.0.0` 标签。
- Demo 按配置顺序加入全部有效条目：VAP 145 项、SVGA 105 项，加上原有 18 项及 1 项组合示例，共 269 项。
- 同名重复配置会跳过并记录诊断；不同名称共用同一个 URL 时保留各自礼物。稳定 ID 使用格式和名称，原有 flowerJourney / flowerBouquet 的 ID 保持不变。
- “花下与君游”和“萌萌花束”保留现有翻译；其他礼物缺少翻译时显示配置原名。
- 播放不访问 GitHub，而是使用 JSON 中的素材 URL，进入栏目不会预下载素材。
- 价格 520 为 Demo 演示值。

## 配置校验（SHA-256）

- `gift_effects_mp4.json`：`6b4423866c527d33246bdf0f71d5c69a28e3febf0359b25695872ae52b30e4d7`
- `gift_effects_svga.json`：`d375b81aa77fa800756deb95a89c7c0aecf42862f7cd90f8cd5b7eb9864c1275`

## 多特效示例

- “花漾三重奏”（flowerDuet）：原生爆发 → 花下与君游（VAP）→ 萌萌花束（SVGA），单价 520 星币。
- `Gift.effects` 保存准确的组合顺序；原生通常放前面，也可出现在中间或最后，不做类型排序。
- 多特效栏目按 `effects.count > 1` 筛选；包含 VAP 或 SVGA 的组合也会出现在相应格式栏目。
- 一份赠送作为异步任务整体占用队列，所有效果各执行一遍；失败继续下一效果，60 秒总超时或取消停止整组。
