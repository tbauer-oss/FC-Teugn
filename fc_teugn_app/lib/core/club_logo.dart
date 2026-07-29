import 'package:flutter/material.dart';

class ClubLogo extends StatelessWidget {
  const ClubLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Wappen des FC Teugn',
      image: true,
      child: Image.asset(
        'assets/branding/fc_teugn_logo_hires.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
