#!/usr/bin/env python3
"""Build the deterministic unpacked-extension ZIP without third-party packages."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

EXTENSION_VERSION = "1.0.0"
PACKAGE_NAME = f"its-the-day-chrome-companion-v{EXTENSION_VERSION}.zip"
PACKAGE_FILES = (
    "manifest.json",
    "popup.html",
    "popup.css",
    "popup.js",
    "navigation.js",
    "assets/its_the_day_mark.svg",
    "icons/icon-16.png",
    "icons/icon-32.png",
    "icons/icon-48.png",
    "icons/icon-128.png",
    "icons/icon-192.png",
    "icons/icon-512.png",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default=f"dist/{PACKAGE_NAME}",
        help="ZIP path relative to extension/ (default: %(default)s)",
    )
    return parser.parse_args()


def resolve_inside(root: Path, value: str) -> Path:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = root / candidate
    candidate = candidate.resolve()
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise SystemExit("Refusing to write a package outside extension/.") from error
    return candidate


def validate_manifest(root: Path) -> None:
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("manifest_version") != 3:
        raise SystemExit("manifest.json must declare manifest_version 3")
    if manifest.get("version") != EXTENSION_VERSION:
        raise SystemExit("manifest.json and package version must match")


def write_package(root: Path, output: Path) -> None:
    validate_manifest(root)
    files = []
    for relative_name in PACKAGE_FILES:
        source = root / relative_name
        if not source.is_file():
            raise SystemExit(f"Missing runtime file: {relative_name}")
        files.append((relative_name, source.read_bytes()))

    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for relative_name, contents in files:
            info = ZipInfo(relative_name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o644 << 16
            archive.writestr(info, contents)

    print(f"Packaged {len(files)} files -> {output}")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    args = parse_args()
    output = resolve_inside(root, args.output)
    write_package(root, output)


if __name__ == "__main__":
    main()
