import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_identity.dart';
import '../../core/app_theme.dart';

class AnimatedLaunchScreen extends StatefulWidget {
  const AnimatedLaunchScreen({
    super.key,
    this.duration = const Duration(milliseconds: 2550),
  });

  final Duration duration;

  @override
  State<AnimatedLaunchScreen> createState() => _AnimatedLaunchScreenState();
}

class _AnimatedLaunchScreenState extends State<AnimatedLaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _imageEntrance;
  late final Animation<double> _claimEntrance;
  late final Animation<double> _progress;
  bool _motionPreferenceApplied = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _imageEntrance = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .58, curve: Curves.easeOutCubic),
    );
    _claimEntrance = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.46, .84, curve: Curves.easeOutCubic),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.12, 1, curve: Curves.easeInOutCubic),
    );
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionPreferenceApplied) return;
    _motionPreferenceApplied = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Semantics(
        label: '${AppIdentity.name} wird gestartet',
        image: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useMobileLayout = constraints.maxWidth < 720 ||
                constraints.maxHeight > constraints.maxWidth * 1.15;
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => useMobileLayout
                  ? _MobileLaunchStage(
                      imageEntrance: _imageEntrance,
                      claimEntrance: _claimEntrance,
                      progress: _progress.value,
                    )
                  : _DesktopLaunchStage(
                      imageEntrance: _imageEntrance,
                      claimEntrance: _claimEntrance,
                      progress: _progress.value,
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _MobileLaunchStage extends StatelessWidget {
  const _MobileLaunchStage({
    required this.imageEntrance,
    required this.claimEntrance,
    required this.progress,
  });

  final Animation<double> imageEntrance;
  final Animation<double> claimEntrance;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('mobile-launch-stage'),
      fit: StackFit.expand,
      children: [
        FadeTransition(
          opacity: Tween<double>(begin: .3, end: 1).animate(imageEntrance),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.045, end: 1).animate(imageEntrance),
            child: Image.asset(
              AppIdentity.splashAsset,
              key: const ValueKey('fc-teugn-talents-splash-image'),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x00000000),
                Color(0x00000000),
                Color(0xB8000000),
              ],
              stops: [0, .72, 1],
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: _LaunchProgress(
                entrance: claimEntrance,
                progress: progress,
                compact: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopLaunchStage extends StatelessWidget {
  const _DesktopLaunchStage({
    required this.imageEntrance,
    required this.claimEntrance,
    required this.progress,
  });

  final Animation<double> imageEntrance;
  final Animation<double> claimEntrance;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('desktop-launch-stage'),
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF050505), Color(0xFF111111), Color(0xFF030303)],
            ),
          ),
        ),
        const Positioned(
          top: -260,
          right: -180,
          width: 720,
          height: 720,
          child: _GoldGlow(opacity: .16),
        ),
        const Positioned(
          bottom: -320,
          left: -220,
          width: 760,
          height: 760,
          child: _GoldGlow(opacity: .09),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final posterHeight = math.min(
                      constraints.maxHeight,
                      820.0,
                    );
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FadeTransition(
                          opacity: Tween<double>(begin: .2, end: 1).animate(
                            imageEntrance,
                          ),
                          child: ScaleTransition(
                            scale: Tween<double>(begin: .94, end: 1).animate(
                              imageEntrance,
                            ),
                            child: Container(
                              height: posterHeight,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color:
                                      AppColors.yellow.withValues(alpha: .48),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        AppColors.yellow.withValues(alpha: .14),
                                    blurRadius: 48,
                                    spreadRadius: 2,
                                  ),
                                  const BoxShadow(
                                    color: Colors.black,
                                    blurRadius: 32,
                                    offset: Offset(0, 18),
                                  ),
                                ],
                              ),
                              child: AspectRatio(
                                aspectRatio: 852 / 1846,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(27),
                                  child: Image.asset(
                                    AppIdentity.splashAsset,
                                    key: const ValueKey(
                                      'fc-teugn-talents-splash-image',
                                    ),
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 72),
                        Flexible(
                          child: FadeTransition(
                            opacity: claimEntrance,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(.08, 0),
                                end: Offset.zero,
                              ).animate(claimEntrance),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 500),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'FC TEUGN',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 8,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'TALENTS',
                                        style: TextStyle(
                                          color: AppColors.yellow,
                                          fontSize: 68,
                                          height: .95,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 28),
                                    Container(
                                      width: 64,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: AppColors.yellow,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                    const SizedBox(height: 28),
                                    const Text(
                                      AppIdentity.claim,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        height: 1.35,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Jugendfußball gemeinsam organisieren.',
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: .62),
                                        fontSize: 15,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 44),
                                    _LaunchProgress(
                                      entrance: claimEntrance,
                                      progress: progress,
                                      compact: false,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GoldGlow extends StatelessWidget {
  const _GoldGlow({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.yellow.withValues(alpha: opacity),
            AppColors.yellow.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _LaunchProgress extends StatelessWidget {
  const _LaunchProgress({
    required this.entrance,
    required this.progress,
    required this.compact,
  });

  final Animation<double> entrance;
  final double progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: entrance,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, compact ? .25 : .12),
          end: Offset.zero,
        ).animate(entrance),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            if (compact)
              const Text(
                AppIdentity.claim,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .45,
                  shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                ),
              )
            else
              Text(
                'App wird vorbereitet …',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .4,
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: compact ? 112 : 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: progress,
                  color: AppColors.yellow,
                  backgroundColor: Colors.white.withValues(alpha: .22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
