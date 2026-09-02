import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/google_maps_navigation.dart';
import '../../core/models/event.dart';
import '../../core/providers.dart';

class DashboardRouteChip extends ConsumerWidget {
  const DashboardRouteChip({required this.event, super.key});

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (event.fixtureIsHome != false) return const SizedBox.shrink();
    final address = resolvedMatchNavigationAddress(
      isAway: true,
      address: event.address,
      location: event.location,
    );
    if (address == null) return const SizedBox.shrink();
    final estimate = ref.watch(matchRouteEstimateProvider(event.id));
    final value = estimate.valueOrNull;
    final routeLabel = value == null
        ? 'Route ab Teugn'
        : '${_distance(value.distanceKm)} km · ca. ${value.durationMinutes} Min.';
    return Semantics(
      button: true,
      label: '$routeLabel, Navigation öffnen',
      child: Material(
        color: const Color(0xFF1677B8).withValues(
          alpha: context.isDarkMode ? .22 : .10,
        ),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => openAddressInGoogleMaps(context, address),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.navigation_rounded,
                  size: 15,
                  color: Color(0xFF1677B8),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        routeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1677B8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (value != null)
                        Text(
                          'Routenschätzung · ${value.attribution}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.appColors.textMuted,
                            fontSize: 7.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 14,
                  color: Color(0xFF1677B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _distance(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
}
