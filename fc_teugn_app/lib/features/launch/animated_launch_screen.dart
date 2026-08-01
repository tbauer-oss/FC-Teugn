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
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                FadeTransition(
                  opacity: Tween<double>(begin: .3, end: 1).animate(
                    _imageEntrance,
                  ),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.045, end: 1).animate(
                      _imageEntrance,
                    ),
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
                      child: FadeTransition(
                        opacity: _claimEntrance,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .25),
                            end: Offset.zero,
                          ).animate(_claimEntrance),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                AppIdentity.claim,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .45,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: 112,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    minHeight: 3,
                                    value: _progress.value,
                                    color: AppColors.yellow,
                                    backgroundColor:
                                        Colors.white.withValues(alpha: .22),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
    );
  }
}
