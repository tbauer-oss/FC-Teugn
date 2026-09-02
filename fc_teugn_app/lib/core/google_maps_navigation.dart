import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';

/// Erstellt einen plattformübergreifenden Google-Maps-Link, der auf Android,
/// iOS und im Web mit derselben Adresse funktioniert.
Uri googleMapsSearchUri(String address) => Uri.https(
      'www.google.com',
      '/maps/search/',
      <String, String>{
        'api': '1',
        'query': address.trim(),
      },
    );

/// Liefert für ein Auswärtsspiel genau eine Navigationsadresse.
///
/// Die postalische Adresse hat immer Vorrang vor einem bloßen Platznamen.
/// Damit verwenden Spieltag, Kalender und Spieleübersicht dieselbe Quelle und
/// Google Maps springt nicht zwischen einem ungenauen und dem richtigen Ziel.
String? resolvedMatchNavigationAddress({
  required bool isAway,
  String? address,
  String? location,
}) {
  if (!isAway) return null;
  final postalAddress = address?.trim() ?? '';
  if (postalAddress.isNotEmpty) return postalAddress;
  final venue = location?.trim() ?? '';
  return venue.isEmpty ? null : venue;
}

Future<bool> launchAddressInGoogleMaps(String address) async {
  final normalizedAddress = address.trim();
  if (normalizedAddress.isEmpty) return false;
  final uri = googleMapsSearchUri(normalizedAddress);
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return true;
    }
    return launchUrl(uri, mode: LaunchMode.platformDefault);
  } catch (_) {
    try {
      return launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      return false;
    }
  }
}

Future<void> openAddressInGoogleMaps(
  BuildContext context,
  String address,
) async {
  final opened = await launchAddressInGoogleMaps(address);
  if (opened || !context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(
      content: Text(
        'Google Maps konnte nicht geöffnet werden. Bitte versuche es erneut.',
      ),
    ),
  );
}

/// Kompakte, auf schmalen Displays umbrechende Kartenaktion für eine Adresse.
class GoogleMapsAddressAction extends StatelessWidget {
  const GoogleMapsAddressAction({
    required this.address,
    this.title = 'Route in Google Maps',
    this.compact = false,
    super.key,
  });

  final String address;
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalizedAddress = address.trim();
    final navigationColor = context.appInfo;
    return Semantics(
      button: true,
      label: '$title: $normalizedAddress. In Google Maps öffnen',
      child: Material(
        color: Color.alphaBlend(
          navigationColor.withValues(
            alpha: context.isDarkMode ? .18 : .09,
          ),
          context.appColors.surfaceRaised,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 12 : 14),
          side: BorderSide(
            color: navigationColor.withValues(alpha: .42),
          ),
        ),
        child: InkWell(
          onTap: () => openAddressInGoogleMaps(context, normalizedAddress),
          borderRadius: BorderRadius.circular(compact ? 12 : 14),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 8 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: compact ? 32 : 36,
                  height: compact ? 32 : 36,
                  decoration: BoxDecoration(
                    color: navigationColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.navigation_rounded,
                    size: compact ? 18 : 20,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        normalizedAddress,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_outward_rounded,
                  size: compact ? 18 : 20,
                  color: navigationColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
