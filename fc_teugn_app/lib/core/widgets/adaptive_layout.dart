import 'dart:math' as math;

import 'package:flutter/material.dart';

enum AppLayoutSize { veryNarrow, narrow, compact, medium, wide }

abstract final class AppBreakpoints {
  static const double veryNarrow = 360;
  static const double narrow = 480;
  static const double compact = 600;
  static const double medium = 720;
  static const double wide = 1024;

  static AppLayoutSize classify(double width) {
    if (width < veryNarrow) return AppLayoutSize.veryNarrow;
    if (width < narrow) return AppLayoutSize.narrow;
    if (width < compact) return AppLayoutSize.compact;
    if (width < wide) return AppLayoutSize.medium;
    return AppLayoutSize.wide;
  }

  static bool isCompact(double width) => width < compact;
}

/// Keeps a complete application surface inside one usable foldable pane.
///
/// The child receives a pane-sized [MediaQuery], so existing responsive
/// widgets classify the actually usable width instead of the full display
/// width across a hinge.
class AdaptiveHingePane extends StatelessWidget {
  const AdaptiveHingePane({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final pane = largestUsablePaneFor(media);
    final usesFullDisplay = (pane.width - media.size.width).abs() < .5 &&
        (pane.height - media.size.height).abs() < .5;
    if (usesFullDisplay) return child;

    final horizontal = pane.center.dx < media.size.width / 2
        ? -1.0
        : pane.center.dx > media.size.width / 2
            ? 1.0
            : 0.0;
    final vertical = pane.center.dy < media.size.height / 2
        ? -1.0
        : pane.center.dy > media.size.height / 2
            ? 1.0
            : 0.0;
    final paneSize = Size(
      math.max(0, pane.width),
      math.max(0, pane.height),
    );

    return Align(
      alignment: Alignment(horizontal, vertical),
      child: SizedBox.fromSize(
        key: const ValueKey('adaptive-hinge-pane'),
        size: paneSize,
        child: MediaQuery(
          data: media.copyWith(
            size: paneSize,
            displayFeatures: const [],
          ),
          child: child,
        ),
      ),
    );
  }
}

class AdaptiveActionSpec {
  const AdaptiveActionSpec({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
}

/// Lays actions out from the actual component width, not the device width.
///
/// Very narrow areas use one full-width action per row, foldable/phone widths
/// use two columns and genuinely wide content areas keep a single row.
class AdaptiveActionBar extends StatelessWidget {
  const AdaptiveActionBar({
    super.key,
    required this.actions,
    this.spacing = 8,
  });

  final List<AdaptiveActionSpec> actions;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final singleColumn = width < AppBreakpoints.veryNarrow ||
              (textScale >= 1.45 && width < AppBreakpoints.medium);
          final columns = singleColumn
              ? 1
              : width < 900
                  ? 2
                  : actions.length;
          final itemWidth = columns == 1
              ? width
              : (width - spacing * (columns - 1)) / columns;

          return Wrap(
            alignment: width >= 900 ? WrapAlignment.end : WrapAlignment.start,
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final action in actions)
                SizedBox(
                  width: itemWidth,
                  child: action.primary
                      ? FilledButton.icon(
                          onPressed: action.onPressed,
                          icon: Icon(action.icon),
                          label: AdaptiveButtonLabel(action.label),
                        )
                      : OutlinedButton.icon(
                          onPressed: action.onPressed,
                          icon: Icon(action.icon),
                          label: AdaptiveButtonLabel(action.label),
                        ),
                ),
            ],
          );
        },
      );
}

/// A button label that remains fully readable with Android's larger font
/// settings. Parent buttons may grow vertically instead of clipping text.
class AdaptiveButtonLabel extends StatelessWidget {
  const AdaptiveButtonLabel(
    this.label, {
    super.key,
    this.maxLines = 2,
  });

  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text(
        label,
        maxLines: maxLines,
        softWrap: true,
        textAlign: TextAlign.center,
        overflow: TextOverflow.visible,
      );
}

/// Shared dialog shell with a scrollable content zone and fixed actions.
///
/// It becomes fullscreen below the compact breakpoint and recalculates on
/// every window resize, including fold/unfold and orientation changes.
class AdaptiveDialogScaffold extends StatelessWidget {
  const AdaptiveDialogScaffold({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.subtitle,
    this.maxWidth = 760,
    this.contentPadding,
  });

  final String title;
  final String? subtitle;
  final Widget content;
  final List<Widget> actions;
  final double maxWidth;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final constrainedWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : media.size.width;
          final pane = largestUsablePaneFor(media);
          final availableWidth = math.min(constrainedWidth, pane.width);
          final availableHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : media.size.height;
          final fullscreen = availableWidth < AppBreakpoints.compact;
          final horizontalInset = fullscreen ? 0.0 : 24.0;
          final dialogWidth = fullscreen
              ? availableWidth
              : math.min(maxWidth, availableWidth - horizontalInset * 2);
          final dialogHeight = fullscreen
              ? availableHeight
              : math.min(860.0, availableHeight * .9);
          final dense = availableWidth < AppBreakpoints.veryNarrow;
          final paneAlignment = pane.center.dx < media.size.width / 2
              ? Alignment.centerLeft
              : pane.center.dx > media.size.width / 2
                  ? Alignment.centerRight
                  : Alignment.center;

          return Dialog(
            insetPadding: EdgeInsets.all(horizontalInset),
            alignment: paneAlignment,
            backgroundColor: Colors.transparent,
            child: Material(
              key: const ValueKey('adaptive-dialog-surface'),
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  fullscreen ? BorderRadius.zero : BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: math.max(0, dialogWidth),
                height: math.max(0, dialogHeight),
                child: SafeArea(
                  child: Column(
                    children: [
                      _AdaptiveDialogHeader(
                        title: title,
                        subtitle: subtitle,
                        dense: dense,
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey('adaptive-dialog-scroll-view'),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: contentPadding ??
                              EdgeInsets.fromLTRB(
                                dense ? 12 : 18,
                                16,
                                dense ? 12 : 18,
                                20 + media.viewInsets.bottom,
                              ),
                          child: SizedBox(
                            width: double.infinity,
                            child: content,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      _AdaptiveDialogActions(actions: actions),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}

@visibleForTesting
Rect largestUsablePaneFor(MediaQueryData media) {
  var selected = Offset.zero & media.size;
  for (final feature in media.displayFeatures) {
    final bounds = feature.bounds;
    final separatesVertically = bounds.width > 0 &&
        bounds.height >= media.size.height * .5 &&
        bounds.left > 0 &&
        bounds.right < media.size.width;
    final separatesHorizontally = bounds.height > 0 &&
        bounds.width >= media.size.width * .5 &&
        bounds.top > 0 &&
        bounds.bottom < media.size.height;
    if (separatesVertically) {
      final left = Rect.fromLTWH(0, 0, bounds.left, media.size.height);
      final right = Rect.fromLTWH(
        bounds.right,
        0,
        media.size.width - bounds.right,
        media.size.height,
      );
      selected =
          left.width * left.height >= right.width * right.height ? left : right;
    } else if (separatesHorizontally) {
      final top = Rect.fromLTWH(0, 0, media.size.width, bounds.top);
      final bottom = Rect.fromLTWH(
        0,
        bounds.bottom,
        media.size.width,
        media.size.height - bounds.bottom,
      );
      selected =
          top.width * top.height >= bottom.width * bottom.height ? top : bottom;
    }
  }
  return selected;
}

class _AdaptiveDialogHeader extends StatelessWidget {
  const _AdaptiveDialogHeader({
    required this.title,
    required this.subtitle,
    required this.dense,
  });

  final String title;
  final String? subtitle;
  final bool dense;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(dense ? 12 : 18, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Schließen',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      );
}

class _AdaptiveDialogActions extends StatelessWidget {
  const _AdaptiveDialogActions({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final stacked =
              constraints.maxWidth < AppBreakpoints.narrow || textScale >= 1.4;
          final padding = EdgeInsets.fromLTRB(
            constraints.maxWidth < AppBreakpoints.veryNarrow ? 12 : 16,
            10,
            constraints.maxWidth < AppBreakpoints.veryNarrow ? 12 : 16,
            12,
          );
          if (stacked) {
            return Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    SizedBox(width: double.infinity, child: actions[index]),
                    if (index != actions.length - 1) const SizedBox(height: 8),
                  ],
                ],
              ),
            );
          }
          return Padding(
            padding: padding,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              children: actions,
            ),
          );
        },
      );
}
