import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme.dart';
import 'loading_controller.dart';

class AppLoadingHost extends ConsumerWidget {
  const AppLoadingHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appLoadingProvider);
    final blocking =
        controller.blockingVisible ? controller.blockingOperation : null;
    final background =
        controller.backgroundVisible ? controller.backgroundOperation : null;
    return PopScope(
      canPop: blocking == null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (background != null)
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(child: _BackgroundLoadingCard(background)),
            ),
          if (blocking != null) _BlockingLoadingOverlay(blocking),
        ],
      ),
    );
  }
}

/// Schlanker, neutraler Fortschrittsindikator ohne Vereinswappen.
///
/// Der Klassenname bleibt vorerst aus Kompatibilitätsgründen bestehen, damit
/// bestehende lokale Ladezustände nicht gleichzeitig umgebaut werden müssen.
class LogoLoadingIndicator extends StatelessWidget {
  const LogoLoadingIndicator({
    super.key,
    this.size = 64,
    this.progress,
    this.semanticsLabel = 'Inhalt wird geladen',
  });

  final double size;
  final double? progress;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
    final normalizedProgress = progress?.clamp(0, 1).toDouble();
    return Semantics(
      label: semanticsLabel,
      value: normalizedProgress == null
          ? null
          : '${(normalizedProgress * 100).round()} Prozent',
      liveRegion: true,
      child: SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(
          value: normalizedProgress ?? (reduceMotion ? .72 : null),
          strokeWidth: size < 40 ? 2.2 : 3.2,
          backgroundColor: context.appColors.outline,
          color: context.appWarning,
          strokeCap: StrokeCap.round,
        ),
      ),
    );
  }
}

class LogoLoadingPanel extends StatefulWidget {
  const LogoLoadingPanel({
    super.key,
    this.message = 'Daten werden geladen …',
    this.progress,
    this.completedItems,
    this.totalItems,
    this.compact = false,
    this.showImmediately = false,
  });

  final String message;
  final double? progress;
  final int? completedItems;
  final int? totalItems;
  final bool compact;
  final bool showImmediately;

  @override
  State<LogoLoadingPanel> createState() => _LogoLoadingPanelState();
}

class _LogoLoadingPanelState extends State<LogoLoadingPanel> {
  bool _visible = false;
  Timer? _showTimer;

  @override
  void initState() {
    super.initState();
    _visible = widget.showImmediately;
    if (!_visible) {
      _showTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return SizedBox(height: widget.compact ? 78 : 120);
    }
    final itemText = widget.completedItems != null && widget.totalItems != null
        ? '${widget.completedItems} von ${widget.totalItems} Einträgen verarbeitet'
        : null;
    return Semantics(
      label: widget.message,
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.all(widget.compact ? 12 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoLoadingIndicator(
              size: widget.compact ? 42 : 72,
              progress: widget.progress,
              semanticsLabel: widget.message,
            ),
            SizedBox(height: widget.compact ? 8 : 16),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (itemText != null) ...[
              const SizedBox(height: 4),
              Text(itemText, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (widget.progress != null && itemText == null) ...[
              const SizedBox(height: 4),
              Text(
                '${(widget.progress!.clamp(0, 1) * 100).round()} %',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LogoLoadingButtonContent extends StatelessWidget {
  const LogoLoadingButtonContent({
    super.key,
    required this.label,
    this.size = 22,
  });

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LogoLoadingIndicator(
            size: size,
            semanticsLabel: label,
          ),
          const SizedBox(width: 9),
          Text(label),
        ],
      );
}

class _BlockingLoadingOverlay extends StatelessWidget {
  const _BlockingLoadingOverlay(this.operation);

  final AppLoadingOperation operation;

  @override
  Widget build(BuildContext context) {
    final fullscreen = operation.mode == AppLoadingMode.fullscreen;
    return Positioned.fill(
      child: Semantics(
        label: operation.message,
        liveRegion: true,
        scopesRoute: true,
        explicitChildNodes: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (fullscreen)
              ColoredBox(color: context.appColors.surfaceMuted)
            else ...[
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                child: const ColoredBox(color: Color(0x66171918)),
              ),
            ],
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Material(
                  color: context.appColors.surface,
                  elevation: 12,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(24),
                  child: LogoLoadingPanel(
                    message: operation.message,
                    progress: operation.progress,
                    completedItems: operation.completedItems,
                    totalItems: operation.totalItems,
                    showImmediately: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundLoadingCard extends StatelessWidget {
  const _BackgroundLoadingCard(this.operation);

  final AppLoadingOperation operation;

  @override
  Widget build(BuildContext context) => Semantics(
        label: operation.message,
        liveRegion: true,
        child: Material(
          color: AppColors.black.withValues(alpha: .94),
          elevation: 6,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LogoLoadingIndicator(
                  size: 34,
                  progress: operation.progress,
                  semanticsLabel: operation.message,
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    operation.completedItems != null &&
                            operation.totalItems != null
                        ? '${operation.message}\n${operation.completedItems} von ${operation.totalItems}'
                        : operation.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
