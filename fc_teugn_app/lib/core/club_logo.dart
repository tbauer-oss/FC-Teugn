import 'dart:async';

import 'package:flutter/material.dart';

// Diese bereinigte 800px-Datei besitzt klare, harte Kanten und eignet sich für
// die kompakte Darstellung im App-Chrome besser als der sehr große
// Originalexport mit eingebetteten Vorschaudaten.
const _clubLogoAsset = 'assets/branding/fc_teugn_logo.png';

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

Future<void> preloadBrandingAssets({String? launchAsset}) async {
  await Future.wait([
    _preloadAsset(_clubLogoAsset),
    if (launchAsset != null) _preloadAsset(launchAsset),
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
