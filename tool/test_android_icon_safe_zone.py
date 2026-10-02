"""Deterministic Android icon safe-zone regression.

This is a static raster/XML check only. It does not place a widget, launch an
APK, or prove launcher rendering on a device; the parent agent owns that runtime
QA gate.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))

import generate_icons  # noqa: E402

# Android's adaptive-icon central safe circle is 66 of the 108-unit viewport.
SAFE_RADIUS_RATIO = 33 / 108
BACKGROUND = (13, 17, 23)
ANDROID_OUTPUTS = (
    "android/app/src/main/res/mipmap-mdpi/ic_launcher.png",
    "android/app/src/main/res/mipmap-hdpi/ic_launcher.png",
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png",
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png",
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png",
)


def _is_mark(pixel: tuple[int, int, int]) -> bool:
    return sum((channel - base) ** 2 for channel, base in zip(pixel, BACKGROUND)) > 36


def _assert_circle_safe(image: Image.Image, label: str) -> None:
    image = image.convert("RGB")
    width, height = image.size
    assert width == height, f"{label}: expected a square raster"
    center = (width - 1) / 2
    safe_radius = width * SAFE_RADIUS_RATIO + 2.0
    outside = []
    for y in range(height):
        for x in range(width):
            pixel = image.getpixel((x, y))
            if not isinstance(pixel, tuple) or len(pixel) < 3:
                continue
            if not _is_mark((int(pixel[0]), int(pixel[1]), int(pixel[2]))):
                continue
            distance = ((x - center) ** 2 + (y - center) ** 2) ** 0.5
            if distance > safe_radius:
                outside.append((x, y, distance))
    assert not outside, f"{label}: mark pixels escape the adaptive safe circle: {outside[:3]}"


def _check_vector(path: Path) -> None:
    source = path.read_text()
    match = re.search(r'android:scaleX="([0-9.]+)"', source)
    assert match, f"{path}: missing constrained mark scale"
    assert float(match.group(1)) <= 0.80, f"{path}: mark scale is too large"
    assert "M80,23" in source, f"{path}: original spark is missing"
    assert "M14,14" not in source, f"{path}: legacy oversized square remains"


def main() -> None:
    _check_vector(ROOT / "android/app/src/main/res/drawable/itstheday_icon_foreground.xml")
    _check_vector(ROOT / "android/app/src/main/res/drawable/itstheday_splash_mark.xml")

    generated = generate_icons.icon(
        1024,
        mark_scale=generate_icons.ANDROID_MARK_SCALE,
    )
    _assert_circle_safe(generated, "supersampled Android generator output")

    for relative in ANDROID_OUTPUTS:
        path = ROOT / relative
        assert path.is_file(), f"missing generated Android icon: {path}"
        with Image.open(path) as image:
            _assert_circle_safe(image, relative)

    print(
        "PASS: Android clock/spark mark fits the deterministic circle safe zone "
        "(static only; not placed-widget or launcher runtime QA)."
    )


if __name__ == "__main__":
    main()
