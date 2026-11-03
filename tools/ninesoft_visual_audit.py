#!/usr/bin/env python3
"""Compare original visual references against real application captures.

Produces Expected, Actual, Overlay, Diff, metrics.json and REPORT.md.
Never generates, overwrites or infers a reference from a capture.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageChops, ImageEnhance


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def compare(expected: Path, actual: Path, output: Path, threshold: int) -> dict:
    if not expected.is_file():
        return {"status": "BLOCKED_MISSING_EXPECTED", "expected": str(expected)}
    if not actual.is_file():
        return {"status": "BLOCKED_MISSING_ACTUAL", "actual": str(actual)}

    with Image.open(expected) as original:
        baseline = original.convert("RGB")
    with Image.open(actual) as capture:
        screenshot = capture.convert("RGB")
    if baseline.size != screenshot.size:
        return {
            "status": "BLOCKED_DIMENSION_MISMATCH",
            "expected_size": list(baseline.size),
            "actual_size": list(screenshot.size),
        }

    output.mkdir(parents=True, exist_ok=True)
    baseline.save(output / "Expected.png")
    screenshot.save(output / "Actual.png")
    Image.blend(baseline, screenshot, 0.5).save(output / "Overlay.png")
    ImageEnhance.Contrast(
        ImageChops.difference(baseline, screenshot)
    ).enhance(5).save(output / "Diff.png")

    delta = np.abs(
        np.asarray(baseline, dtype=np.int16)
        - np.asarray(screenshot, dtype=np.int16)
    ).astype(np.float64)
    mae = float(np.mean(delta))
    rmse = math.sqrt(float(np.mean(np.square(delta))))
    pixels = np.max(delta, axis=2)
    mismatch_count = int(np.count_nonzero(pixels > threshold))
    mismatch_percent = 100.0 * mismatch_count / float(pixels.size)

    result = {
        "status": (
            "PIXEL_IDENTICAL_PENDING_FUNCTIONAL"
            if rmse == 0 else "DIFFERENCES_REMAIN"
        ),
        "width": baseline.size[0],
        "height": baseline.size[1],
        "mae_0_to_255": round(mae, 6),
        "rmse_0_to_255": round(rmse, 6),
        "threshold_0_to_255": threshold,
        "mismatching_pixels": mismatch_count,
        "pixel_mismatch_percent": round(mismatch_percent, 6),
        "expected_sha256": sha256(expected),
        "actual_sha256": sha256(actual),
    }
    (output / "metrics.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--expected-dir", type=Path, required=True)
    parser.add_argument("--actual-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--threshold", type=int, default=0)
    args = parser.parse_args()

    if not 0 <= args.threshold <= 255:
        parser.error("Threshold must be within 0..255")
    screens = json.loads(args.manifest.read_text(encoding="utf-8"))["screens"]
    if len(screens) != 20 or len({screen["id"] for screen in screens}) != 20:
        parser.error("Manifest must contain exactly 20 unique screen ids")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    report = [
        "# NineSoft visual acceptance",
        "",
        "Source images are immutable original user references, not app goldens.",
        "",
        "| Screen | Status | Expected | Actual | Overlay | Diff | MAE | RMSE | Mismatch % |",
        "|---|---|---|---|---|---|---:|---:|---:|",
    ]
    totals: dict[str, int] = {}
    results = []
    for screen in screens:
        screen_id = screen["id"]
        expected = args.expected_dir / (screen_id + ".png")
        actual = args.actual_dir / (screen_id + ".png")
        folder = args.output_dir / screen_id
        metrics = compare(expected, actual, folder, args.threshold)
        metrics.update(screen_id=screen_id, title=screen["title"])
        results.append(metrics)
        status = metrics["status"]
        totals[status] = totals.get(status, 0) + 1
        links = (
            [f"[{name}]({screen_id}/{name}.png)" for name in (
                "Expected", "Actual", "Overlay", "Diff"
            )]
            if (folder / "Expected.png").exists() and
               (folder / "Actual.png").exists()
            else ["-"] * 4
        )
        mae = metrics.get("mae_0_to_255", "-")
        rmse = metrics.get("rmse_0_to_255", "-")
        mismatch = metrics.get("pixel_mismatch_percent", "-")
        report.append(
            f"| {screen['title']} | {status} | "
            + " | ".join(links)
            + f" | {mae} | {rmse} | {mismatch} |"
        )

    report.extend(["", "## Totals", ""])
    report.extend(f"- {status}: {count}" for status, count in sorted(totals.items()))
    report.extend([
        "",
        "A pixel match alone does not prove accounting, API, or functional parity.",
        "No source reference or production state is modified by this report.",
        "",
    ])
    (args.output_dir / "REPORT.md").write_text(
        "\n".join(report), encoding="utf-8"
    )
    (args.output_dir / "results.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(totals, sort_keys=True))
    return 0 if totals == {"PIXEL_IDENTICAL_PENDING_FUNCTIONAL": 20} else 2


if __name__ == "__main__":
    sys.exit(main())
