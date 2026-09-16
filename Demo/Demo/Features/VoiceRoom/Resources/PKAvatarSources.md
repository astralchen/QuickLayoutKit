# PK 用户头像

使用内置 `image_gen` 生成的 16 位虚构成年用户头像（2026-09-16）。

- 第一组 7 张用于 `RoomPKFixtures.opponentAssignments` 的位置 0、1、2、3、4、6、7；位置 5、8 保持空麦。
- 追加 9 张由 `AvatarImageID.pkCurrentFixtures` 提供，按本房零基麦位位置使用；只为占麦用户分配，退出 PK 后恢复原头像。
- 每个 imageset 包含 @2x（256×256）和 @3x（384×384）PNG。运行时继续由 `AvatarImages.swift` 解析，并由现有视图裁成圆形。
- 资源目录：`Demo/Demo/Assets.xcassets/<资源名称>.imageset/`。

## 资源预览与提示词

每次调用的完整提示词为下面的公共提示词，接上该资源的 `Subject: … . Background: … .`。

```text
Use case: photorealistic-natural. Asset type: a square profile avatar for a voice chat room iOS demo. Generate exactly ONE fictional adult person, no collage. Professional natural studio head-and-shoulders portrait, facing camera, centered face, visible hair top with small margin, shoulders to bottom edge. The face must be clearly recognizable when the square is clipped to a small circular avatar. Premium realistic photography, natural skin texture, soft flattering light, tasteful casual clothing, clean subtly graded background. Square 1024x1024 composition. No text, no border, no logos, no watermarks, no accessories obscuring the face, no hands. Maintain credible human proportions.
```

### VoiceRoomPKAvatarHost

![VoiceRoomPKAvatarHost](../../../Assets.xcassets/VoiceRoomPKAvatarHost.imageset/VoiceRoomPKAvatarHost@2x.png)

- Subject: a fictional East Asian woman aged 28, elegant chin-length dark brown bob, warm confident smile, ivory blouse.
- Background: deep rose and violet studio gradient.

### VoiceRoomPKAvatarOne

![VoiceRoomPKAvatarOne](../../../Assets.xcassets/VoiceRoomPKAvatarOne.imageset/VoiceRoomPKAvatarOne@2x.png)

- Subject: a fictional East Asian man aged 27, short textured black hair swept slightly upward, relaxed friendly smile, dark teal crewneck.
- Background: rich teal studio gradient.

### VoiceRoomPKAvatarTwo

![VoiceRoomPKAvatarTwo](../../../Assets.xcassets/VoiceRoomPKAvatarTwo.imageset/VoiceRoomPKAvatarTwo@2x.png)

- Subject: a fictional East Asian woman aged 25, shoulder-length chestnut wavy hair, gentle open smile, light peach knit sweater.
- Background: soft coral and peach studio gradient.

### VoiceRoomPKAvatarThree

![VoiceRoomPKAvatarThree](../../../Assets.xcassets/VoiceRoomPKAvatarThree.imageset/VoiceRoomPKAvatarThree@2x.png)

- Subject: a fictional East Asian man aged 30, tidy short black hair with a side part, subtle round dark eyeglasses, friendly understated smile, navy shirt.
- Background: blue and indigo studio gradient.

### VoiceRoomPKAvatarFour

![VoiceRoomPKAvatarFour](../../../Assets.xcassets/VoiceRoomPKAvatarFour.imageset/VoiceRoomPKAvatarFour@2x.png)

- Subject: a fictional East Asian woman aged 26, long dark hair tied into a loose ponytail with soft bangs, cheerful natural smile, pale blue blouse.
- Background: mint and turquoise studio gradient.

### VoiceRoomPKAvatarSix

![VoiceRoomPKAvatarSix](../../../Assets.xcassets/VoiceRoomPKAvatarSix.imageset/VoiceRoomPKAvatarSix@2x.png)

- Subject: a fictional East Asian man aged 26, medium-length loosely wavy dark brown hair, soft friendly smile, cream casual sweater.
- Background: warm amber and ochre studio gradient.

### VoiceRoomPKAvatarSeven

![VoiceRoomPKAvatarSeven](../../../Assets.xcassets/VoiceRoomPKAvatarSeven.imageset/VoiceRoomPKAvatarSeven@2x.png)

- Subject: a fictional East Asian woman aged 29, straight dark brown shoulder-length hair tucked behind one ear, calm welcoming smile, lavender knit top.
- Background: lavender and lilac studio gradient.

### VoiceRoomPKAvatarExtra01

![VoiceRoomPKAvatarExtra01](../../../Assets.xcassets/VoiceRoomPKAvatarExtra01.imageset/VoiceRoomPKAvatarExtra01@2x.png)

- Subject: a fictional East Asian woman aged 24, very short black pixie haircut, oval face, lively broad smile, ivory casual shirt.
- Background: sky blue studio gradient.

### VoiceRoomPKAvatarExtra02

![VoiceRoomPKAvatarExtra02](../../../Assets.xcassets/VoiceRoomPKAvatarExtra02.imageset/VoiceRoomPKAvatarExtra02@2x.png)

- Subject: a fictional East Asian man aged 32, close cropped dark hair, broad face and strong eyebrows, slight smile, beige linen shirt.
- Background: muted olive green studio gradient.

### VoiceRoomPKAvatarExtra03

![VoiceRoomPKAvatarExtra03](../../../Assets.xcassets/VoiceRoomPKAvatarExtra03.imageset/VoiceRoomPKAvatarExtra03@2x.png)

- Subject: a fictional East Asian woman aged 27, auburn shoulder-length hair with blunt bangs, round face, joyful natural smile, navy knit top.
- Background: warm apricot studio gradient.

### VoiceRoomPKAvatarExtra04

![VoiceRoomPKAvatarExtra04](../../../Assets.xcassets/VoiceRoomPKAvatarExtra04.imageset/VoiceRoomPKAvatarExtra04@2x.png)

- Subject: a fictional East Asian man aged 25, longish straight black hair parted in the middle, narrow face, gentle smile, light grey crewneck.
- Background: dusty lavender studio gradient.

### VoiceRoomPKAvatarExtra05

![VoiceRoomPKAvatarExtra05](../../../Assets.xcassets/VoiceRoomPKAvatarExtra05.imageset/VoiceRoomPKAvatarExtra05@2x.png)

- Subject: a fictional East Asian woman aged 31, long softly curled black hair, defined cheekbones, small warm smile, muted rose blouse.
- Background: dark emerald studio gradient.

### VoiceRoomPKAvatarExtra06

![VoiceRoomPKAvatarExtra06](../../../Assets.xcassets/VoiceRoomPKAvatarExtra06.imageset/VoiceRoomPKAvatarExtra06@2x.png)

- Subject: a fictional East Asian man aged 29, tidy wavy chestnut hair, thin silver eyeglasses, oval face, relaxed smile, white oxford shirt.
- Background: soft cyan studio gradient.

### VoiceRoomPKAvatarExtra07

![VoiceRoomPKAvatarExtra07](../../../Assets.xcassets/VoiceRoomPKAvatarExtra07.imageset/VoiceRoomPKAvatarExtra07@2x.png)

- Subject: a fictional East Asian woman aged 26, dark brown hair in a neat high bun, friendly round cheeks, bright smile, cream knit top.
- Background: berry and rose studio gradient.

### VoiceRoomPKAvatarExtra08

![VoiceRoomPKAvatarExtra08](../../../Assets.xcassets/VoiceRoomPKAvatarExtra08.imageset/VoiceRoomPKAvatarExtra08@2x.png)

- Subject: a fictional East Asian man aged 34, short black textured hair, subtle neatly trimmed stubble, welcoming smile, charcoal casual shirt.
- Background: warm terracotta studio gradient.

### VoiceRoomPKAvatarExtra09

![VoiceRoomPKAvatarExtra09](../../../Assets.xcassets/VoiceRoomPKAvatarExtra09.imageset/VoiceRoomPKAvatarExtra09@2x.png)

- Subject: a fictional East Asian woman aged 28, sleek shoulder-length black hair, delicate thin round eyeglasses, calm friendly smile, powder blue knit sweater.
- Background: soft periwinkle studio gradient.
