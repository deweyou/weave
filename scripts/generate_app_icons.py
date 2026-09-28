#!/usr/bin/env python3
"""Sync the editable SVG and export native icon renditions with Xcode's ictool."""

import argparse
import html
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "design/AppIcon"
MASTER = DESIGN / "yours-mark.svg"
ICON = DESIGN / "AppIcon.icon"
LAYER = ICON / "Assets/yours-mark.svg"
OUTPUT = ROOT / ".build/app-icons"
RENDITIONS = ("Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark")


def run(*arguments):
    subprocess.run([str(argument) for argument in arguments], check=True)


def sync_layer(check):
    artwork = ET.parse(MASTER).getroot()
    namespace = {"svg": "http://www.w3.org/2000/svg"}
    if artwork.get("viewBox") != "0 0 1024 1024":
        raise ValueError("The master must use the shared 1024 × 1024 canvas.")
    paths = artwork.findall(".//svg:path", namespace)
    if {path.get("id") for path in paths} != {"wave", "droplet"}:
        raise ValueError("Keep the wave and droplet as separately named paths.")
    if artwork.findall(".//svg:image", namespace):
        raise ValueError("The master must contain vector artwork, not embedded bitmaps.")
    if check:
        if not LAYER.exists() or LAYER.read_bytes() != MASTER.read_bytes():
            raise ValueError("Icon Composer artwork is stale. Run scripts/generate_app_icons.py.")
    else:
        LAYER.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(MASTER, LAYER)


def export_image(tool, path, platform, rendition, size):
    run(tool, ICON, "--export-image", "--output-file", path,
        "--platform", platform, "--rendition", rendition,
        "--width", size, "--height", size, "--scale", 1)


def export_preview():
    cards = []
    for rendition in RENDITIONS:
        filename = f"ios-{rendition}.png"
        cards.append(
            f'<figure><img src="{filename}" alt="{html.escape(rendition)}">'
            f'<figcaption>{html.escape(rendition)}</figcaption>'
            '<div class="sizes">'
            + ''.join(f'<img src="{filename}" width="{size}" height="{size}" '
                      f'alt="{size}px">' for size in (16, 32, 64))
            + '</div></figure>'
        )
    (OUTPUT / "preview.html").write_text(
        '<!doctype html><html lang="zh-CN"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Yours App Icon</title><style>'
        'body{font:15px system-ui;margin:40px;background:#e8eaed;color:#202124}'
        'main{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:24px}'
        'figure{margin:0;text-align:center}figure>img{width:100%;max-width:280px}'
        'figcaption{margin:16px}.sizes{display:flex;align-items:center;justify-content:center;gap:24px}'
        '</style><h1>Yours</h1><p>Apple Icon Composer 原生导出；透明外观会随系统壁纸变化。</p>'
        '<main>' + ''.join(cards) + '</main></html>\n', encoding="utf-8")
    # This full-tile SVG is for design review only; the app uses the unmasked layer.
    source = MASTER.read_text(encoding="utf-8")
    source = source.replace('<g id="yours-mark"',
                            '<rect id="preview-background" width="1024" height="1024" '
                            'rx="224" fill="#ffffff"/>\n  <g id="yours-mark"')
    (OUTPUT / "yours-icon-preview.svg").write_text(source, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check master/layer consistency without writing.")
    parser.add_argument("--sync-only", action="store_true", help="Sync SVG without rendering exports.")
    arguments = parser.parse_args()
    sync_layer(arguments.check)
    if arguments.check or arguments.sync_only:
        return
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    tool = developer.parent / "Applications/Icon Composer.app/Contents/Executables/ictool"
    if not tool.is_file():
        raise FileNotFoundError("Select an Xcode installation that includes Icon Composer and ictool.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for platform, prefix in (("iOS", "ios"), ("macOS", "macos")):
        for rendition in RENDITIONS:
            export_image(tool, OUTPUT / f"{prefix}-{rendition}.png", platform, rendition, 1024)
    iconset = OUTPUT / "Yours.iconset"
    iconset.mkdir(exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "@2x" if scale == 2 else ""
            export_image(tool, iconset / f"icon_{size}x{size}{suffix}.png", "macOS", "Default", size * scale)
    run("iconutil", "-c", "icns", iconset, "-o", OUTPUT / "Yours.icns")
    export_preview()


if __name__ == "__main__":
    main()
