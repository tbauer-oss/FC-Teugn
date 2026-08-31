import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.title = 'Route zum Auswärtsspiel',
    this.compact = false,
    super.key,
  });

  final String address;
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalizedAddress = address.trim();
    return Semantics(
      button: true,
      label: '$title: $normalizedAddress. In Google Maps öffnen',
      child: Material(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(
              alpha: .32,
            ),
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
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
                Icon(
                  Icons.map_rounded,
                  size: compact ? 19 : 21,
                  color: Theme.of(context).colorScheme.primary,
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
                  Icons.open_in_new_rounded,
                  size: compact ? 18 : 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
