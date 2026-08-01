import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/club_logo.dart';

class AnimatedLaunchScreen extends StatefulWidget {
  const AnimatedLaunchScreen({
    super.key,
    this.duration = const Duration(milliseconds: 1750),
  });

  final Duration duration;

  @override
  State<AnimatedLaunchScreen> createState() => _AnimatedLaunchScreenState();
}

class _AnimatedLaunchScreenState extends State<AnimatedLaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoEntrance;
  late final Animation<double> _copyEntrance;
  late final Animation<double> _progress;
  bool _motionPreferenceApplied = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _logoEntrance = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.06, .56, curve: Curves.easeOutBack),
    );
    _copyEntrance = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.42, .82, curve: Curves.easeOutCubic),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.58, 1, curve: Curves.easeInOutCubic),
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
        label: 'FC Teugn Jugendfußball wird gestartet',
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final progress = _controller.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-.15 + progress * .28, -.18),
                      radius: 1.08,
                      colors: const [
                        Color(0xFF4A4300),
                        Color(0xFF1D201E),
                        Color(0xFF0A0C0B),
                      ],
                      stops: const [0, .5, 1],
                    ),
                  ),
                ),
                CustomPaint(
                  painter: _LaunchDetailPainter(progress: progress),
                ),
                SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ScaleTransition(
                            scale: Tween<double>(begin: .72, end: 1).animate(
                              _logoEntrance,
                            ),
                            child: FadeTransition(
                              opacity: _logoEntrance,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Transform.scale(
                                    scale: .9 + progress * .16,
                                    child: Container(
                                      width: 184,
                                      height: 184,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: RadialGradient(
                                          colors: [
                                            AppColors.yellow
                                                .withValues(alpha: .2),
                                            AppColors.yellow
                                                .withValues(alpha: 0),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 150,
                                    height: 150,
                                    padding: const EdgeInsets.all(13),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(38),
                                      border: Border.all(
                                        color: AppColors.yellow
                                            .withValues(alpha: .75),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.yellow
                                              .withValues(alpha: .18),
                                          blurRadius: 30,
                                          spreadRadius: 3,
                                        ),
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: .35),
                                          blurRadius: 22,
                                          offset: const Offset(0, 12),
                                        ),
                                      ],
                                    ),
                                    child: const RepaintBoundary(
                                      child: ClubLogo(size: 124),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          FadeTransition(
                            opacity: _copyEntrance,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, .22),
                                end: Offset.zero,
                              ).animate(_copyEntrance),
                              child: const Column(
                                children: [
                                  Text(
                                    'FC TEUGN',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.3,
                                    ),
                                  ),
                                  SizedBox(height: 5),
                                  Text(
                                    'JUGENDFUSSBALL',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.yellow,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 3.2,
                                    ),
                                  ),
                                  SizedBox(height: 14),
                                  Text(
                                    'EIN VEREIN. EIN TEAM.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFFAEB2AF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 42),
                          FadeTransition(
                            opacity: _copyEntrance,
                            child: SizedBox(
                              width: 118,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  minHeight: 3,
                                  value: _progress.value,
                                  color: AppColors.yellow,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: .14),
                                ),
                              ),
                            ),
                          ),
                        ],
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

class _LaunchDetailPainter extends CustomPainter {
  const _LaunchDetailPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppColors.yellow.withValues(alpha: .075)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final arcPaint = Paint()
      ..color = AppColors.yellow.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;

    final center = Offset(size.width * .5, size.height * .43);
    final radius = math.min(size.width, size.height) * .37;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * .72,
      math.pi * 1.2 * progress,
      false,
      arcPaint,
    );

    for (var index = -2; index <= 3; index++) {
      final startY = size.height * (.18 + index * .15);
      canvas.drawLine(
        Offset(-size.width * .1, startY),
        Offset(size.width * 1.1, startY + size.width * .36),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LaunchDetailPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
