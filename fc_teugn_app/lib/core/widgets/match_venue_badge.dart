import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/event.dart';

class MatchVenueBadge extends StatelessWidget {
  const MatchVenueBadge({
    super.key,
    required this.type,
    this.compact = false,
  });

  final MatchVenueType type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (icon, foreground, background, border) = switch (type) {
      MatchVenueType.home => (
          Icons.home_rounded,
          AppColors.gold,
          AppColors.yellowSoft,
          AppColors.gold.withValues(alpha: .34),
        ),
      MatchVenueType.away => (
          Icons.directions_bus_rounded,
          AppColors.blue,
          AppColors.blue.withValues(alpha: .08),
          AppColors.blue.withValues(alpha: .28),
        ),
      MatchVenueType.tournament => (
          Icons.emoji_events_rounded,
          AppColors.gold,
          AppColors.yellowSoft,
          AppColors.gold.withValues(alpha: .34),
        ),
    };
    return Semantics(
      label: type == MatchVenueType.home
          ? 'Heimspiel'
          : type == MatchVenueType.away
              ? 'Auswärtsspiel'
              : 'Turnier',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 13 : 15, color: foreground),
            const SizedBox(width: 4),
            Text(
              type.label,
              style: TextStyle(
                color: foreground,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
