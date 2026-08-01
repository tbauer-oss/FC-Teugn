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
        FadeTransition(
          opacity: Tween<double>(begin: .12, end: 1).animate(imageEntrance),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.018, end: 1).animate(imageEntrance),
            child: Image.asset(
              AppIdentity.webSplashAsset,
              key: const ValueKey('fc-teugn-talents-web-splash-image'),
              fit: BoxFit.contain,
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
                Color(0x12000000),
                Color(0x00000000),
                Color(0xA8000000),
              ],
              stops: [0, .62, 1],
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
              child: FadeTransition(
                opacity: claimEntrance,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(26, 16, 26, 18),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .64),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .16),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: _LaunchProgress(
                    entrance: claimEntrance,
                    progress: progress,
                    compact: false,
                    centered: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LaunchProgress extends StatelessWidget {
  const _LaunchProgress({
    required this.entrance,
    required this.progress,
    required this.compact,
    this.centered = false,
  });

  final Animation<double> entrance;
  final double progress;
  final bool compact;
  final bool centered;

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
          crossAxisAlignment: compact || centered
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
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
