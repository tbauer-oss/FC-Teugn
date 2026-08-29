import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_identity.dart';
import '../../core/app_theme.dart';

Future<void> showAppAboutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.appColors.surfaceMuted,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (context) => const _AppAboutSheet(),
  );
}

class _AppAboutSheet extends StatelessWidget {
  const _AppAboutSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          children: [
            Container(
              width: 92,
              height: 92,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.black,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.yellow.withValues(alpha: .65),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.yellow.withValues(alpha: .15),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Image.asset(
                AppIdentity.appIconAsset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              AppIdentity.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              AppIdentity.claim,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.appWarning,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 22),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final info = snapshot.data;
                final version = info == null
                    ? 'Version wird geladen …'
                    : 'Version ${info.version} · Build ${info.buildNumber}';
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: context.appColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.appColors.outline),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 18,
                        color: context.appWarning,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        version,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            Text(
              AppIdentity.copyright,
              style: TextStyle(
                color: context.appColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Entwickelt von ${AppIdentity.developer}',
              style: TextStyle(
                color: context.appColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
