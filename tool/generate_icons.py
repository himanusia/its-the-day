"""Generate every raster launcher/web icon from the product SVG master.

Run: uv run --with pillow==12.3.0 python tool/generate_icons.py
Master: assets/branding/its_the_day_mark.svg

The native asset catalogs deliberately keep Flutter's generated filenames and
Contents.json identifiers. Only the pixels are replaced here, so Xcode and
Gradle keep consuming the established technical resources.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
MASTER_VIEWBOX = 256
RENDER_SIZE = 4096
BACKGROUND = '#0D1117'


def _box(values: Iterable[float], canvas: int) -> tuple[int, ...]:
    return tuple(round(value * canvas / MASTER_VIEWBOX) for value in values)


def _render_master() -> Image.Image:
    """Rasterize the simple SVG master at a fixed supersampled resolution.

    The master intentionally uses only rect/circle/path primitives. Keeping the
    same geometry here avoids a dependency on a platform SVG renderer while
    preserving deterministic antialiasing for every platform's PNGs.
    """
    canvas = RENDER_SIZE
    image = Image.new('RGBA', (canvas, canvas), BACKGROUND)
    draw = ImageDraw.Draw(image)

    # <rect width="256" height="256" rx="72" ... />
    draw.rounded_rectangle(
        _box((0, 0, 256, 256), canvas),
        radius=round(72 * canvas / MASTER_VIEWBOX),
        fill=BACKGROUND,
    )
    # <circle cx="128" cy="128" r="83" ... />
    draw.ellipse(_box((45, 45, 211, 211), canvas), fill='#57D5A0')
    # <circle cx="128" cy="128" r="64" ... />
    draw.ellipse(_box((64, 64, 192, 192), canvas), fill=BACKGROUND)
    # <path d="M120 71h16v54l37 22-9 15-44-27z" ... />
    draw.polygon(
        [_box(point, canvas) for point in (
            (120, 71),
            (136, 71),
            (136, 125),
            (173, 147),
            (164, 162),
            (120, 135),
        )],
        fill='#A9F4D0',
    )
    draw.ellipse(_box((119, 119, 137, 137), canvas), fill='#FFD28A')
    # <path d="M190 54l5 12 12 5-12 5-5 12-5-12-12-5 12-5z" ... />
    draw.polygon(
        [_box(point, canvas) for point in (
            (190, 54),
            (195, 66),
            (207, 71),
            (195, 76),
            (190, 88),
            (185, 76),
            (173, 71),
            (185, 66),
        )],
        fill='#FFD28A',
    )
    return image


def icon(size: int, *, maskable: bool = False) -> Image.Image:
    """Return an opaque RGB PNG image at the requested pixel size."""
    image = _render_master()
    if maskable:
        safe_size = round(RENDER_SIZE * 0.84)
        safe = image.resize((safe_size, safe_size), Image.Resampling.LANCZOS)
        image = Image.new('RGBA', (RENDER_SIZE, RENDER_SIZE), BACKGROUND)
        margin = (RENDER_SIZE - safe_size) // 2
        image.alpha_composite(safe, (margin, margin))
    return image.resize((size, size), Image.Resampling.LANCZOS).convert('RGB')


def _catalog_outputs(relative_catalog: str) -> dict[Path, int]:
    catalog = ROOT / relative_catalog
    contents_path = catalog / 'Contents.json'
    contents = json.loads(contents_path.read_text())
    outputs: dict[str, int] = {}
    for entry in contents.get('images', []):
        filename = entry.get('filename')
        size = entry.get('size')
        scale = entry.get('scale')
        if not isinstance(filename, str) or not isinstance(size, str):
            raise ValueError(f'{contents_path}: every image needs a filename and size')
        if not isinstance(scale, str) or not scale.endswith('x'):
            raise ValueError(f'{contents_path}: invalid scale for {filename!r}')
        base = float(size.split('x', 1)[0])
        pixels = round(base * float(scale[:-1]))
        previous = outputs.get(filename)
        if previous is not None and previous != pixels:
            raise ValueError(f'{contents_path}: conflicting size for {filename!r}')
        outputs[filename] = pixels
    return {catalog / name: pixels for name, pixels in outputs.items()}


def _write_outputs(outputs: dict[Path, int], *, maskable: set[Path] | None = None) -> None:
    maskable = maskable or set()
    for path, size in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        icon(size, maskable=path in maskable).save(path, format='PNG', optimize=False)
        print(f'{path.relative_to(ROOT)}: {size}x{size}')


def main() -> None:
    outputs = {
        ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png': size
        for density, size in (
            ('mdpi', 48),
            ('hdpi', 72),
            ('xhdpi', 96),
            ('xxhdpi', 144),
            ('xxxhdpi', 192),
        )
    }
    outputs.update({
        ROOT / 'web/favicon.png': 32,
        ROOT / 'web/icons/Icon-192.png': 192,
        ROOT / 'web/icons/Icon-512.png': 512,
        ROOT / 'web/icons/Icon-maskable-192.png': 192,
        ROOT / 'web/icons/Icon-maskable-512.png': 512,
    })
    outputs.update(_catalog_outputs('ios/Runner/Assets.xcassets/AppIcon.appiconset'))
    outputs.update(_catalog_outputs('macos/Runner/Assets.xcassets/AppIcon.appiconset'))
    maskable = {
        path for path in outputs
        if path.name.startswith('Icon-maskable-')
    }
    _write_outputs(outputs, maskable=maskable)


if __name__ == '__main__':
    main()
