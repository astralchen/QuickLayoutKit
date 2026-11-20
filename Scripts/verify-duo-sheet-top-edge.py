#!/usr/bin/env python3
"""用活动外屏的无损截图核对双层 Sheet 顶边。需 Pillow 和 build-for-testing 生成的 xctestrun。
先在 Device Hub 切到要检查的闭合横向，使用 simctl io <device> enumerate 获取外屏 UUID。
"""
import argparse
import os
from pathlib import Path
import subprocess
from concurrent.futures import ThreadPoolExecutor
from threading import Event

from PIL import Image, ImageChops


def capture(device, display, folder, stop):
    index = 0
    while not stop.is_set():
        filename = folder / f"{index:03}.png"
        subprocess.run(["xcrun", "simctl", "io", device, "screenshot", f"--display={display}",
                        str(filename)], check=True, capture_output=True, timeout=15)
        index += 1


def read_halfway(folder, width, target):
    samples = []
    for path in sorted(folder.glob("*.png")):
        with Image.open(path) as image:
            scale = image.width / width
            if image.width <= image.height:
                raise ValueError(f"{path} 不是横屏")
            # 测试页面的上层是白色，下层是靛色。用两列定位前页顶边，独立核对实际行程。
            xs = [int(image.width * fraction) for fraction in (0.43, 0.47)]
            top = next((y for y in range(image.height)
                        if all(min(image.getpixel((x, y))[:3]) > 249 for x in xs)), None)
            if top is None:
                continue
            if samples and top / scale < target - 6:
                break  # 只比较首次向上穿过半程的画面，排除松手后的回弹。
            if abs(top / scale - target) > 6:
                continue
            # 覆盖最顶一行、原来发生偏差的像素和向内 4 pt 的对照区域。
            strip = image.crop((int(image.width * 0.30), 0, int(image.width * 0.70), round(4 * scale) + 1))
            samples.append((path.name, top / scale, strip.convert("RGB")))
    offsets = [row[1] - target for row in samples]
    if not offsets or min(offsets) >= 0 or max(offsets) <= 0 or min(map(abs, offsets)) > 1:
        raise ValueError(f"{folder}: 缺少跨过 {target:.2f} pt 的半程原始像素，偏移 {offsets}")
    return samples


def verify(args):
    args.output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, TEST_RUNNER_DUO_GESTURE_POSES="closedLandscape",
               TEST_RUNNER_DUO_DIM_THRESHOLD="upper", TEST_RUNNER_DUO_TOP_EDGE="1")
    cmd = ["xcodebuild", "test-without-building", "-xctestrun", str(args.xctestrun),
           "-destination", f"platform=iOS Simulator,id={args.device}", "-parallel-testing-enabled", "NO",
           "-only-testing:DemoUITests/DuoSheetGestureTests/testStackedDetentDragsInDevicePoses",
           "-resultBundlePath", str(args.output / "gestures.xcresult")]
    positions = {}
    stop = Event()
    with ThreadPoolExecutor(max_workers=1) as worker, (args.output / "gestures.log").open("w") as log:
        with subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as test:
            task = None
            try:
                for line in test.stdout:
                    log.write(line)
                    if line.startswith("DUO_EDGE_BEGIN "):
                        _, engine, width, target = line.split()
                        positions[engine] = float(width), float(target)
                        folder = args.output / engine
                        folder.mkdir()
                        stop.clear()
                        task = worker.submit(capture, args.device, args.display, folder, stop)
                    elif line.startswith("DUO_EDGE_END "):
                        stop.set()
                        task.result()
                    elif line.startswith("SHEET_ADJUST "):
                        raise RuntimeError("请将已点亮的 Duo 外屏切到闭合横向再运行")
            except BaseException:
                test.terminate()
                raise
            finally:
                stop.set()
            if test.wait() != 0:
                raise RuntimeError(f"手势测试失败，见 {log.name}")
    if set(positions) != {"UIKit", "Sheet", "Panel"}:
        raise ValueError("缺少三套控制器的半程实拖记录")
    reference = None
    for engine in ("UIKit", "Sheet", "Panel"):
        samples = read_halfway(args.output / engine, *positions[engine])
        if reference is None:
            reference = samples[0][2]
        for name, top, strip in samples:
            if strip.size != reference.size:
                raise ValueError(f"{engine}/{name} 的活动显示器尺寸与 UIKit 不同")
            error = max(high for _, high in ImageChops.difference(strip, reference).getextrema())
            print(f"{engine}/{name}: 顶边 {top:.2f} pt，RGB 最大通道差 {error}")
            if error:
                raise ValueError(f"{engine}/{name} 的顶边像素与 UIKit 不一致")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--display", required=True)
    parser.add_argument("--xctestrun", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="本次截图与测试结果的新目录")
    verify(parser.parse_args())
