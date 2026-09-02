import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

class ModernDashboardSectionLabel extends StatelessWidget {
  const ModernDashboardSectionLabel({
    required this.title,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, right: 2, bottom: 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: context.appColors.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .95,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class ModernDashboardPriorityStrip extends StatelessWidget {
  const ModernDashboardPriorityStrip({
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
    this.color,
    super.key,
  });

  final IconData icon;
  final String title;
  final int count;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.appWarning;
    final surfaces = context.appColors;
    return Material(
      color: surfaces.surfaceRaised,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: surfaces.shadow.withValues(
                  alpha: context.isDarkMode ? .18 : .045,
                ),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: surfaces.textMuted,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ModernDashboardMetric extends StatelessWidget {
  const ModernDashboardMetric({
    required this.icon,
    required this.label,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: context.appColors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
}

class ModernDashboardEventCard extends StatelessWidget {
  const ModernDashboardEventCard({
    required this.date,
    required this.title,
    required this.location,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.timeLabel,
    this.subtitle,
    this.metrics = const [],
    this.route,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.contentKey,
    super.key,
  });

  final DateTime date;
  final String title;
  final String location;
  final String? timeLabel;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final List<Widget> metrics;
  final Widget? route;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.appColors;
    final background = Color.alphaBlend(
      accent.withValues(alpha: context.isDarkMode ? .11 : .045),
      surfaces.surfaceRaised,
    );
    return Material(
      key: contentKey,
      color: background,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 11, 10, 9),
          decoration: BoxDecoration(
            border: Border.all(color: accent.withValues(alpha: .18)),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: surfaces.shadow.withValues(
                  alpha: context.isDarkMode ? .16 : .035,
                ),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ModernDateTile(date: date, accent: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(icon, size: 19, color: accent),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: surfaces.text,
                                  fontSize: 14,
                                  height: 1.18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (subtitle?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: surfaces.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (timeLabel?.trim().isNotEmpty == true)
                              timeLabel!,
                            if (location.trim().isNotEmpty) location.trim(),
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: surfaces.textMuted,
                            fontSize: 11.5,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (route != null) ...[
                          const SizedBox(height: 7),
                          route!,
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: surfaces.textMuted,
                    size: 22,
                  ),
                ],
              ),
              if (metrics.isNotEmpty || onAction != null) ...[
                const SizedBox(height: 9),
                Divider(height: 1, color: surfaces.outline),
                const SizedBox(height: 7),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final action = onAction == null
                        ? null
                        : TextButton.icon(
                            onPressed: onAction,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              foregroundColor: surfaces.text,
                              backgroundColor: accent.withValues(alpha: .11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                            icon: Icon(actionIcon, size: 17),
                            label: Text(
                              actionLabel!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          );
                    if (constraints.maxWidth < 310 && action != null) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(spacing: 11, runSpacing: 6, children: metrics),
                          const SizedBox(height: 6),
                          Align(
                              alignment: Alignment.centerRight, child: action),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 11,
                            runSpacing: 6,
                            children: metrics,
                          ),
                        ),
                        if (action != null) ...[
                          const SizedBox(width: 7),
                          action,
                        ],
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModernDateTile extends StatelessWidget {
  const _ModernDateTile({required this.date, required this.accent});

  final DateTime date;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        width: 47,
        constraints: const BoxConstraints(minHeight: 57),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _weekday(date.weekday),
              style: TextStyle(
                color: context.appColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              date.day.toString().padLeft(2, '0'),
              style: TextStyle(
                color: context.appColors.text,
                fontSize: 17,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              _month(date.month),
              style: TextStyle(
                color: context.appColors.textMuted,
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class ModernDashboardTimelineConnector extends StatelessWidget {
  const ModernDashboardTimelineConnector({
    required this.from,
    required this.to,
    super.key,
  });

  final Color from;
  final Color to;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 33),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 2,
            height: 8,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  from.withValues(alpha: .45),
                  to.withValues(alpha: .45)
                ],
              ),
            ),
          ),
        ),
      );
}

class ModernDashboardFunctionItem {
  const ModernDashboardFunctionItem({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final String trailing;
  final VoidCallback onTap;
  final Color? color;
}

class ModernDashboardFunctionList extends StatelessWidget {
  const ModernDashboardFunctionList({
    required this.items,
    super.key,
  });

  final List<ModernDashboardFunctionItem> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            const gap = 9.0;
            final width = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items)
                  SizedBox(
                    width: width,
                    child: _ModernFunctionRow(item: item, standalone: true),
                  ),
              ],
            );
          }
          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.appColors.surfaceRaised,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: context.appColors.outline),
              boxShadow: [
                BoxShadow(
                  color: context.appColors.shadow.withValues(
                    alpha: context.isDarkMode ? .16 : .03,
                  ),
                  blurRadius: 13,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _ModernFunctionRow(item: items[index]),
                  if (index < items.length - 1)
                    Divider(
                      height: 1,
                      indent: 50,
                      color: context.appColors.outline,
                    ),
                ],
              ],
            ),
          );
        },
      );
}

class _ModernFunctionRow extends StatelessWidget {
  const _ModernFunctionRow({required this.item, this.standalone = false});

  final ModernDashboardFunctionItem item;
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final accent = item.color ?? context.appColors.textMuted;
    return Material(
      color: context.appColors.surfaceRaised,
      borderRadius: standalone ? BorderRadius.circular(15) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 51),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: standalone
              ? BoxDecoration(
                  border: Border.all(color: context.appColors.outline),
                  borderRadius: BorderRadius.circular(15),
                )
              : null,
          child: Row(
            children: [
              Icon(item.icon, size: 20, color: accent),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (item.trailing.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    item.trailing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: context.appColors.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 3),
              Icon(
                Icons.chevron_right_rounded,
                color: context.appColors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _weekday(int weekday) => switch (weekday) {
      DateTime.monday => 'MO',
      DateTime.tuesday => 'DI',
      DateTime.wednesday => 'MI',
      DateTime.thursday => 'DO',
      DateTime.friday => 'FR',
      DateTime.saturday => 'SA',
      _ => 'SO',
    };

String _month(int month) => const [
      'JAN',
      'FEB',
      'MÄR',
      'APR',
      'MAI',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OKT',
      'NOV',
      'DEZ',
    ][month - 1];
