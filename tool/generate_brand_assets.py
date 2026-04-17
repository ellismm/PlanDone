from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "logo" / "plandone_log.png"
ASSET_DIR = ROOT / "assets" / "branding"
BACKGROUND = (244, 244, 244, 255)
THRESHOLD = 18


def _ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def _is_background(pixel: tuple[int, int, int, int], background: tuple[int, int, int, int]) -> bool:
    r, g, b, a = pixel
    if a == 0:
        return True
    return max(abs(r - background[0]), abs(g - background[1]), abs(b - background[2])) <= THRESHOLD


def _make_transparent(image: Image.Image, *, limit_to_top_ratio: float | None = None) -> tuple[Image.Image, tuple[int, int, int, int]]:
    image = image.convert("RGBA")
    background = image.getpixel((0, 0))
    analysis_height = image.height if limit_to_top_ratio is None else int(image.height * limit_to_top_ratio)

    transparent = image.copy()
    pixels = transparent.load()
    bbox: tuple[int, int, int, int] | None = None

    for y in range(transparent.height):
        for x in range(transparent.width):
            pixel = pixels[x, y]
            in_scope = y < analysis_height
            if in_scope and not _is_background(pixel, background):
                if bbox is None:
                    bbox = (x, y, x + 1, y + 1)
                else:
                    bbox = (
                        min(bbox[0], x),
                        min(bbox[1], y),
                        max(bbox[2], x + 1),
                        max(bbox[3], y + 1),
                    )
            elif _is_background(pixel, background):
                pixels[x, y] = (255, 255, 255, 0)

    if bbox is None:
        raise RuntimeError("Unable to detect non-background logo content.")

    return transparent, bbox


def _pad_bbox(bbox: tuple[int, int, int, int], *, padding: int, width: int, height: int) -> tuple[int, int, int, int]:
    left, top, right, bottom = bbox
    return (
        max(0, left - padding),
        max(0, top - padding),
        min(width, right + padding),
        min(height, bottom + padding),
    )


def _resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.resize(size, Image.Resampling.LANCZOS)


def _save_png(image: Image.Image, path: Path, size: tuple[int, int] | None = None) -> None:
    if size is not None:
        image = _resize(image, size)
    _ensure_parent(path)
    image.save(path, format="PNG")


def _build_square_icon(mark: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (1024, 1024), BACKGROUND)
    inner = mark.copy()
    inner.thumbnail((720, 720), Image.Resampling.LANCZOS)
    offset = ((canvas.width - inner.width) // 2, (canvas.height - inner.height) // 2)
    canvas.alpha_composite(inner, dest=offset)
    return canvas


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")

    full_logo_transparent, full_logo_bbox = _make_transparent(source)
    full_logo_crop = full_logo_transparent.crop(
        _pad_bbox(full_logo_bbox, padding=24, width=source.width, height=source.height),
    )

    mark_transparent, mark_bbox = _make_transparent(source, limit_to_top_ratio=0.62)
    mark_crop = mark_transparent.crop(
        _pad_bbox(mark_bbox, padding=20, width=source.width, height=source.height),
    )

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    _save_png(full_logo_crop, ASSET_DIR / "plandone_logo.png")
    _save_png(mark_crop, ASSET_DIR / "plandone_mark.png")

    square_icon = _build_square_icon(mark_crop)
    _save_png(square_icon, ASSET_DIR / "plandone_app_icon.png")

    android_icons = {
        "mipmap-mdpi/ic_launcher.png": 48,
        "mipmap-hdpi/ic_launcher.png": 72,
        "mipmap-xhdpi/ic_launcher.png": 96,
        "mipmap-xxhdpi/ic_launcher.png": 144,
        "mipmap-xxxhdpi/ic_launcher.png": 192,
    }
    for relative_path, size in android_icons.items():
        _save_png(square_icon, ROOT / "android" / "app" / "src" / "main" / "res" / relative_path, (size, size))

    ios_icons = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    ios_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for filename, size in ios_icons.items():
        _save_png(square_icon, ios_dir / filename, (size, size))

    macos_icons = {
        "app_icon_16.png": 16,
        "app_icon_32.png": 32,
        "app_icon_64.png": 64,
        "app_icon_128.png": 128,
        "app_icon_256.png": 256,
        "app_icon_512.png": 512,
        "app_icon_1024.png": 1024,
    }
    macos_dir = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for filename, size in macos_icons.items():
        _save_png(square_icon, macos_dir / filename, (size, size))

    web_icons = {
        "favicon.png": 32,
        "icons/Icon-192.png": 192,
        "icons/Icon-512.png": 512,
        "icons/Icon-maskable-192.png": 192,
        "icons/Icon-maskable-512.png": 512,
    }
    for relative_path, size in web_icons.items():
        _save_png(square_icon, ROOT / "web" / relative_path, (size, size))

    windows_icon_path = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    _ensure_parent(windows_icon_path)
    square_icon.save(
        windows_icon_path,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    print("Generated brand assets and platform icons.")


if __name__ == "__main__":
    main()
