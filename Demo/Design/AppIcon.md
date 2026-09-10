# QuickLayoutKit Demo 应用图标

图标以不同布局关系表达 QuickLayout 的组合能力：

- 左侧紫蓝容器内嵌两个不同高度的模块，表现嵌套、纵向堆叠与内边距。
- 右侧顶部橙黄横向模块，下方薄荷色与绿色不等宽双栏，表现横向组合与比例分配。
- 左右底部对齐，内嵌模块以轻微悬浮感表现层次。
- 无独立外框、圆形或横跨底部的长条；浅紫、桃色、冰蓝和薄荷色渐变背景铺满画布。

资源：`../Demo/Assets.xcassets/AppIcon.appiconset/AppIcon.png`

三个外观均为 1024 × 1024 PNG，应用外轮廓由系统裁切：

- `AppIcon.png`：默认彩色外观，带不透明渐变背景。
- `AppIcon-Dark.png`：深色外观，透明背景，由系统提供底色。
- `AppIcon-Tinted.png`：着色外观，黑底灰度图，使用 Gray Gamma 2.2 色彩配置，由系统着色。

三个文件均已绑定至 AppIcon.appiconset 对应槽位。
参考：[Apple 资源目录图标规范](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)。
使用内置 imagegen 编辑，以 sips 缩放至所需尺寸。
当前为静态玻璃风格图像，未配置 Icon Composer 分层资源或系统动态光效。

## 最终编辑提示词

```text
Use case: precise-object-edit
Edit the supplied QuickLayout icon. Remove COMPLETELY the long blue-cyan rounded rectangle spanning across the entire bottom foreground. Remove its outline, reflections and shadow. Restore the clean pastel gradient background where it was. Do not replace it with any new foreground bar, base, platform, circle or badge.
Refine the remaining composition into a balanced aligned layout:
Preserve the left violet-blue parent panel and its two inset pale lavender modules, the upper-right orange-yellow horizontal block, and the lower-right two unequal-width mint/green vertical columns.
Finish and reveal the previously obscured rounded bottoms of the mint and green columns cleanly. Set the bottom edge of the left violet parent panel to exactly the same horizontal baseline as the bottoms of these two columns. Adjust the left panel's lower internal module only as necessary to keep comfortable consistent inner bottom padding.
Keep the tops aligned as before, all horizontal widths and relative column proportions, and the existing precise gaps. Do not stretch the green columns down to the old bar's bottom. Instead trim the excess height of the violet panel to align with the existing green column bottoms, then move the complete group slightly downward as one unit if needed to keep it optically centered within the square.
The final foreground consists of exactly SIX pieces: one violet parent container, its two inset lavender children, one orange header, one narrow mint column, one wider green column. The left nested children should have soft subtle separation from the parent, retaining an elegant sense of layering without extra objects.
Preserve the Apple-like colorful translucent glass styling, tasteful luminous edges, soft shadows and lavender/peach/ice-blue/mint gradient background. No extra shapes, no enclosing frame, no bottom bar, no text or watermark. Make this a polished harmonious app icon with clean legible layout relationships.
Output one opaque 1024x1024 square image with background to every edge.
```

## 深色外观提示词

```text
Use case: background-extraction
Create the Dark appearance asset of the attached QuickLayout iOS app icon. Preserve EXACTLY the current foreground composition, all six shapes, placement, scale, rounded corners, relative proportions and nested structure. Remove the entire pastel background and all broad background glow to real transparent alpha, including every empty gutter and surrounding margin. Do not simulate transparency with black, white, checkerboard or any solid background.
Refine ONLY foreground colors for legibility over a system near-black background: luminous saturated violet-blue parent at left, two pale lavender inset shapes, coral-orange-gold upper-right bar, bright mint narrow column and green wider column lower right. Maintain tasteful Liquid Glass edge lighting and smooth tinted faces, moderate highlights, no aggressive bloom. The foreground should look polished on dark gray. Keep its outer silhouette and all positions identical to the reference. No extra shapes or text. Single square PNG with REAL transparent background, ideally 1024x1024.
```

## 着色外观提示词

```text
Use case: style-transfer
Create the Tinted appearance grayscale source asset of the attached QuickLayout iOS app icon. Preserve EXACTLY the foreground composition, all six shapes, positions, proportions, corner radii and nested structure. Replace the pastel background with a solid opaque BLACK #000000 background filling every edge and all empty gutters.
Convert the foreground to strictly neutral grayscale, no colored tint whatsoever: a medium silver-gray left parent panel, two much lighter almost-white inset modules, light silver upper-right bar, medium-light silver narrow lower column and brighter silver wide lower-right panel. Preserve clear tonal differentiation of parent and children. Keep refined monochrome glass highlights, subtle gradients, crisp rounded silhouettes. Main foreground luminances medium to bright for recoloring by iOS, background black. Match original geometry exactly, no changed scale, added shapes, borders, labels or text. No transparency: fully opaque square grayscale icon, ideally 1024x1024.
```

两种外观使用内置 imagegen 编辑；使用 sips 调整输出尺寸，并将着色版本编码为灰度 PNG。
