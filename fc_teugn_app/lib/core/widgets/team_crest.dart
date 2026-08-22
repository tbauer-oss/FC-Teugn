import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../club_logo.dart';

/// Renders both club crests inside an identical visual frame, so differently
/// cropped source images do not make one team look more important than the
/// other.
class TeamCrest extends StatelessWidget {
  const TeamCrest.club({
    required this.size,
    this.darkSurface = false,
    super.key,
  })  : isClub = true,
        logoUrl = null;

  const TeamCrest.opponent({
    required this.size,
    required this.logoUrl,
    this.darkSurface = false,
    super.key,
  }) : isClub = false;

  const TeamCrest.ownTeam({
    required this.size,
    required bool isPlayingCommunity,
    required this.logoUrl,
    this.darkSurface = false,
    super.key,
  }) : isClub = !isPlayingCommunity;

  final bool isClub;
  final String? logoUrl;
  final double size;
  final bool darkSurface;

  @override
  Widget build(BuildContext context) {
    final background = darkSurface ? Colors.white : AppColors.background;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * .24),
        border: Border.all(
          color: darkSurface ? Colors.white24 : AppColors.line,
        ),
      ),
      child: isClub
          ? ClubLogo(size: size * .8)
          : logoUrl?.trim().isNotEmpty == true
              ? Image.network(
                  logoUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _placeholder(),
                )
              : _placeholder(),
    );
  }

  Widget _placeholder() => Icon(
        Icons.shield_outlined,
        size: size * .52,
        color: AppColors.blue,
      );
}
