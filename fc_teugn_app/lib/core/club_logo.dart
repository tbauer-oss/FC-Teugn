import 'dart:async';

import 'package:flutter/material.dart';

import 'app_identity.dart';

const _clubLogoAsset = 'assets/branding/fc_teugn_logo_hires.png';

Future<void> _preloadAsset(String asset) async {
  final completer = Completer<void>();
  final stream = AssetImage(asset).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, synchronousCall) {
      if (!completer.isCompleted) completer.complete();
      stream.removeListener(listener);
    },
    onError: (error, stackTrace) {
      if (!completer.isCompleted) completer.complete();
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  await completer.future.timeout(
    const Duration(seconds: 2),
    onTimeout: () => stream.removeListener(listener),
  );
}

Future<void> preloadBrandingAssets() async {
  await Future.wait([
    _preloadAsset(_clubLogoAsset),
    _preloadAsset(AppIdentity.splashAsset),
    _preloadAsset(AppIdentity.webSplashAsset),
  ]);
}

class ClubLogo extends StatelessWidget {
  const ClubLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Wappen des FC Teugn',
      image: true,
      child: Image.asset(
        _clubLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
