from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "fc_teugn_app"
SOURCE = APP / "assets" / "branding" / "fc_teugn_logo_hires.png"
BACKGROUND = (23, 25, 24, 255)


def render_icon(size: int, padding_ratio: float = 0.13) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), BACKGROUND)
    logo = Image.open(SOURCE).convert("RGBA")
    available = round(size * (1 - 2 * padding_ratio))
    logo.thumbnail((available, available), Image.Resampling.LANCZOS)
    offset = ((size - logo.width) // 2, (size - logo.height) // 2)
    canvas.alpha_composite(logo, offset)
    return canvas.convert("RGB")


def replace_existing_pngs(directory: Path, padding_ratio: float = 0.13) -> None:
    for target in directory.glob("*.png"):
        with Image.open(target) as existing:
            size = max(existing.size)
        render_icon(size, padding_ratio).save(target, optimize=True)


def main() -> None:
    web_icons = APP / "web" / "icons"
    for target in web_icons.glob("*.png"):
        with Image.open(target) as existing:
            size = max(existing.size)
        padding = 0.2 if "maskable" in target.name.lower() else 0.13
        render_icon(size, padding).save(target, optimize=True)

    render_icon(64, 0.1).save(APP / "web" / "favicon.png", optimize=True)

    for mipmap in (APP / "android" / "app" / "src" / "main" / "res").glob(
        "mipmap-*"
    ):
        replace_existing_pngs(mipmap)

    replace_existing_pngs(
        APP / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    )
    replace_existing_pngs(
        APP / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    )


if __name__ == "__main__":
    main()
