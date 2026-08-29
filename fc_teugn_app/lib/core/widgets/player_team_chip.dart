import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/player.dart';

class PlayerTeamChip extends StatelessWidget {
  const PlayerTeamChip({
    required this.player,
    this.compact = false,
    super.key,
  });

  final PlayerModel player;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final unassigned = player.teamId == null;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: unassigned
            ? context.appWarning.withValues(alpha: .12)
            : context.appInfo.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: unassigned
              ? context.appWarning.withValues(alpha: .35)
              : context.appInfo.withValues(alpha: .22),
        ),
      ),
      child: Text(
        player.teamCode,
        style: TextStyle(
          color: unassigned ? context.appWarning : context.appInfo,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
