import 'dart:io';

import 'package:image/image.dart' as image;

const _canvasSize = 1024;
const _launcherArtworkSize = 1000;
const _maskableArtworkSize = 960;

void main() {
  final source = _readPng('assets/branding/fc_teugn_talents_icon.png');
  final clubLogo = _readPng('assets/branding/fc_teugn_logo_hires.png');
  final shareBackground =
      _readPng('assets/branding/app_icon_background_v2.png');

  final standard = _flattenAndResize(source, _canvasSize);
  final launcher = _composePaddedIcon(source, _launcherArtworkSize);
  final maskable = _composePaddedIcon(source, _maskableArtworkSize);

  _writePng('assets/branding/app_icon_master.png', standard);
  _writePng('assets/branding/app_icon_maskable_master.png', maskable);

  _writeScaledIcons(launcher, {
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
    'android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png': 192,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png': 20,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png': 40,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png': 60,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png': 29,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png': 58,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png': 87,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png': 40,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png': 80,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png': 120,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png': 120,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png': 180,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png': 76,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png': 152,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png':
        167,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png':
        1024,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png': 16,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png': 32,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png': 64,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png': 128,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png': 256,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png': 512,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png': 1024,
  });

  _writeScaledIcons(standard, {
    'web/favicon.png': 64,
    'web/favicon-16.png': 16,
    'web/favicon-32.png': 32,
    'web/favicon-48.png': 48,
    'web/apple-touch-icon.png': 180,
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
    'web/icons/Icon-1024.png': 1024,
  });

  _writeScaledIcons(maskable, {
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,
    'web/icons/Icon-maskable-1024.png': 1024,
  });

  _writePng(
    'web/og.png',
    _composeShareImage(
      icon: source,
      clubLogo: clubLogo,
      background: shareBackground,
    ),
  );
}

image.Image _flattenAndResize(image.Image source, int size) {
  final canvas = image.Image(width: size, height: size)
    ..clear(image.ColorRgba8(8, 9, 8, 255));
  final resized = image.copyResize(
    source,
    width: size,
    height: size,
    interpolation: image.Interpolation.cubic,
  );
  image.compositeImage(canvas, resized);
  return canvas;
}

image.Image _composePaddedIcon(image.Image source, int artworkSize) {
  final canvas = image.Image(width: _canvasSize, height: _canvasSize)
    ..clear(image.ColorRgba8(8, 9, 8, 255));
  final safeIcon = image.copyResize(
    source,
    width: artworkSize,
    height: artworkSize,
    interpolation: image.Interpolation.cubic,
  );
  image.compositeImage(canvas, safeIcon, center: true);
  return canvas;
}

image.Image _composeShareImage({
  required image.Image icon,
  required image.Image clubLogo,
  required image.Image background,
}) {
  final canvas = image.copyResize(
    background,
    width: 1200,
    height: 630,
    interpolation: image.Interpolation.cubic,
  );
  final appIcon = image.copyResize(
    icon,
    width: 540,
    height: 540,
    interpolation: image.Interpolation.cubic,
  );
  final crest = image.copyResize(
    clubLogo,
    width: 310,
    maintainAspect: true,
    interpolation: image.Interpolation.cubic,
  );

  image.compositeImage(canvas, appIcon, dstX: 55, dstY: 45);
  image.compositeImage(
    canvas,
    crest,
    dstX: 780,
    dstY: (630 - crest.height) ~/ 2,
  );
  return canvas;
}

image.Image _readPng(String path) {
  final decoded = image.decodePng(File(path).readAsBytesSync());
  if (decoded == null) {
    throw StateError('PNG konnte nicht gelesen werden: $path');
  }
  return decoded;
}

void _writeScaledIcons(image.Image source, Map<String, int> targets) {
  for (final entry in targets.entries) {
    final scaled = image.copyResize(
      source,
      width: entry.value,
      height: entry.value,
      interpolation: image.Interpolation.cubic,
    );
    _writePng(entry.key, scaled);
  }
}

void _writePng(String path, image.Image value) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(image.encodePng(value, level: 6));
}
