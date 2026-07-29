import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ClubLogo extends StatelessWidget {
  const ClubLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Wappen des FC Teugn',
      image: true,
      child: SvgPicture.asset(
        'assets/branding/fc_teugn_logo.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
