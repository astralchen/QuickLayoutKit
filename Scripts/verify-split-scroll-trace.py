#!/usr/bin/env python3
"""核对真实手势采样；几何操作成功但没有与减速重叠时，以非零状态退出。

用法：python3 Scripts/verify-split-scroll-trace.py SplitScrollGestureTrace.json
用于复核 2026-11-03 手势验收保存的 JSON；临时 App 采样器和录制用例已清理。
只分析记录，不驱动 UI；不能替代录像检查，也不能证明未采到的帧没有跳动。
"""

import json
import sys
from pathlib import Path


def verify(path):
    trace = json.loads(Path(path).read_text())
    rows = [dict(zip(trace["columns"], values)) for values in trace["rows"]]
    if len(rows) < 2:
        raise ValueError("采样不足")
    keys = ("windowWidth", "windowHeight", "primaryWidth")
    changes = []
    for index in range(1, len(rows)):
        before, current = rows[index - 1], rows[index]
        # 用例结束时恢复竖屏；不把这次方向变化算作窗口拖动。
        if any(r["windowWidth"] <= r["windowHeight"] for r in (before, current)):
            continue
        if any(abs(current[k] - before[k]) > 0.1 for k in keys):
            changes.append(index)
    groups = []
    for index in changes:
        if not groups or rows[index]["t"] - rows[groups[-1][-1]]["t"] > 1:
            groups.append([])
        groups[-1].append(index)

    results = []
    for group in groups:
        first, last = group[0], group[-1]
        before, after = rows[first - 1], rows[last]
        window_change = abs(after["windowWidth"] - before["windowWidth"]) > 1
        axis = "windowWidth" if window_change else "primaryWidth"
        kind = ("window" if window_change else "column") + (
            "-expand" if after[axis] > before[axis] else "-shrink"
        )
        overlap = [i for i in group if rows[i]["decelerating"]]
        result = {
            "case": kind,
            "geometry_before": {k: before[k] for k in keys},
            "geometry_after": {k: after[k] for k in keys},
            "overlap_samples": len(overlap),
            "covered": False,
        }
        if overlap:
            start = overlap[0]
            end = start
            while end + 1 < len(rows) and rows[end + 1]["decelerating"]:
                end += 1
            segment = rows[start:end + 1]
            movement = segment[-1]["offsetY"] - segment[0]["offsetY"]
            direction = 1 if movement >= 0 else -1
            reversals = sum(
                (b["offsetY"] - a["offsetY"]) * direction < -0.5
                for a, b in zip(segment, segment[1:])
            )
            result.update({
                "first_overlap_time": rows[start]["t"],
                "remaining_deceleration_seconds": round(rows[end]["t"] - rows[start]["t"], 4),
                "movement_after_overlap_pt": round(movement, 4),
                "reverse_steps": reversals,
                "largest_sample_gap_seconds": round(max(
                    (b["t"] - a["t"] for a, b in zip(segment, segment[1:])), default=0
                ), 4),
                "covered": abs(movement) > 1 and reversals == 0,
            })
        results.append(result)
    cross_error = max(abs(r["offsetX"] + r["insetLeft"]) for r in rows)
    width_error = max(abs(r["contentWidth"] - max(
        0, r["width"] - r["insetLeft"] - r["insetRight"]
    )) for r in rows)
    required = {"column-expand", "column-shrink", "window-shrink", "window-expand"}
    covered = {r["case"] for r in results if r["covered"]}
    passed = required <= covered and cross_error <= 0.5 and width_error <= 0.5
    return {
        "input": str(Path(path).resolve()),
        "samples": len(rows),
        "cross_axis_error_max_pt": cross_error,
        "content_width_error_max_pt": width_error,
        "largest_deceleration_sample_gap_seconds": round(max(
            (b["t"] - a["t"] for a, b in zip(rows, rows[1:])
             if a["decelerating"] and b["decelerating"]), default=0
        ), 4),
        "cases": results,
        "missing_coverage": sorted(required - covered),
        "coverage_and_alignment_passed": passed,
        "limits": "需结合录像及原始采样检查突跳；此检查不代表逐帧速度或所有安全区域场景通过。",
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    report = verify(sys.argv[1])
    print(json.dumps(report, ensure_ascii=False, indent=2))
    sys.exit(0 if report["coverage_and_alignment_passed"] else 1)
