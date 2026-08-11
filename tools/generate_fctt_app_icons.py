from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "fc_teugn_app"
SOURCE = APP / "assets" / "branding" / "fc_teugn_talents_icon.png"
CLUB_LOGO = APP / "assets" / "branding" / "fc_teugn_logo_hires.png"
SHARE_BACKGROUND = (
    APP / "assets" / "branding" / "app_icon_background_v2.png"
)
BACKGROUND = (8, 9, 8, 255)
CANVAS_SIZE = 1024


def flatten(source: Image.Image, size: int = CANVAS_SIZE) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), BACKGROUND)
    artwork = source.resize((size, size), Image.Resampling.LANCZOS)
    canvas.alpha_composite(artwork)
    return canvas.convert("RGB")


def padded(source: Image.Image, artwork_size: int) -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), BACKGROUND)
    artwork = source.resize(
        (artwork_size, artwork_size),
        Image.Resampling.LANCZOS,
    )
    offset = (CANVAS_SIZE - artwork_size) // 2
    canvas.alpha_composite(artwork, (offset, offset))
    return canvas.convert("RGB")


def save_png(value: Image.Image, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    value.save(target, format="PNG", optimize=True, compress_level=6)


def save_scaled(
    source: Image.Image,
    targets: dict[str, int],
) -> None:
    for relative_path, size in targets.items():
        scaled = source.resize((size, size), Image.Resampling.LANCZOS)
        save_png(scaled, APP / relative_path)


def compose_share_image(
    source: Image.Image,
    club_logo: Image.Image,
    background: Image.Image,
) -> Image.Image:
    canvas = background.resize((1200, 630), Image.Resampling.LANCZOS).convert(
        "RGBA"
    )
    app_icon = source.resize((540, 540), Image.Resampling.LANCZOS)
    canvas.alpha_composite(app_icon, (55, 45))

    crest = club_logo.copy()
    crest.thumbnail((310, 470), Image.Resampling.LANCZOS)
    canvas.alpha_composite(
        crest,
        (780 + (310 - crest.width) // 2, (630 - crest.height) // 2),
    )
    return canvas.convert("RGB")


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    club_logo = Image.open(CLUB_LOGO).convert("RGBA")
    share_background = Image.open(SHARE_BACKGROUND).convert("RGBA")

    standard = flatten(source)
    launcher = padded(source, 1000)
    maskable = padded(source, 960)

    save_png(standard, APP / "assets/branding/app_icon_master.png")
    save_png(maskable, APP / "assets/branding/app_icon_maskable_master.png")

    save_scaled(
        launcher,
        {
            "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
            "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
            "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
            "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
            "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
            "android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png": 48,
            "android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png": 72,
            "android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png": 96,
            "android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png": 144,
            "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png": 192,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png": 20,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png": 40,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png": 60,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png": 29,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png": 58,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png": 87,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png": 40,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png": 80,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png": 120,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png": 120,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png": 180,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png": 76,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png": 152,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png": 167,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": 1024,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": 16,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png": 32,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png": 64,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png": 128,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png": 256,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png": 512,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png": 1024,
        },
    )

    save_scaled(
        standard,
        {
            "web/favicon.png": 64,
            "web/favicon-16.png": 16,
            "web/favicon-32.png": 32,
            "web/favicon-48.png": 48,
            "web/apple-touch-icon.png": 180,
            "web/icons/Icon-192.png": 192,
            "web/icons/Icon-512.png": 512,
            "web/icons/Icon-1024.png": 1024,
        },
    )
    save_scaled(
        maskable,
        {
            "web/icons/Icon-maskable-192.png": 192,
            "web/icons/Icon-maskable-512.png": 512,
            "web/icons/Icon-maskable-1024.png": 1024,
        },
    )
    save_png(
        compose_share_image(source, club_logo, share_background),
        APP / "web/og.png",
    )


if __name__ == "__main__":
    main()
