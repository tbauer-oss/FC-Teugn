import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_identity.dart';
import '../../core/app_theme.dart';

class AnimatedLaunchScreen extends StatefulWidget {
  const AnimatedLaunchScreen({
    super.key,
    this.duration = const Duration(milliseconds: 2550),
    this.waitingForData = false,
    this.statusMessage,
    this.errorMessage,
    this.onRetry,
    this.playMobileIntroVideo = false,
    this.onIntroCompleted,
  });

  final Duration duration;
  final bool waitingForData;
  final String? statusMessage;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final bool playMobileIntroVideo;
  final VoidCallback? onIntroCompleted;

  @override
  State<AnimatedLaunchScreen> createState() => _AnimatedLaunchScreenState();
}

class _AnimatedLaunchScreenState extends State<AnimatedLaunchScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final Animation<double> _imageEntrance;
  late final Animation<double> _claimEntrance;
  late final Animation<double> _progress;
  VideoPlayerController? _introVideoController;
  Timer? _videoWatchdog;
  bool _motionPreferenceApplied = false;
  bool _introVideoInitialized = false;
  bool _introFinished = false;
  bool _introCompletionReported = false;

  static const _introTransitionDuration = Duration(milliseconds: 320);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (widget.playMobileIntroVideo) {
      unawaited(_prepareIntroVideo());
    }
  }

  Future<void> _prepareIntroVideo() async {
    final videoController =
        VideoPlayerController.asset(AppIdentity.mobileIntroVideoAsset);
    _introVideoController = videoController;
    videoController.addListener(_handleIntroVideoState);
    try {
      await videoController.initialize().timeout(const Duration(seconds: 8));
      if (!mounted || _introFinished) return;
      await videoController.setLooping(false);
      await videoController.setVolume(1);
      if (!mounted || _introFinished) return;
      setState(() => _introVideoInitialized = true);
      await videoController.play();
      _armVideoWatchdog();
    } catch (_) {
      // Ein defekter Decoder oder eine nicht verfügbare Videospur darf den
      // App-Start nie blockieren. In diesem Fall übernimmt sofort das Bild.
      _finishIntro();
    }
  }

  void _handleIntroVideoState() {
    if (_introFinished) return;
    final value = _introVideoController?.value;
    if (value == null || !value.isInitialized) return;
    if (value.isCompleted) _finishIntro();
  }

  void _armVideoWatchdog() {
    _videoWatchdog?.cancel();
    final value = _introVideoController?.value;
    if (value == null || !value.isInitialized) return;
    final remaining = value.duration - value.position;
    _videoWatchdog = Timer(
      (remaining.isNegative ? Duration.zero : remaining) +
          const Duration(seconds: 10),
      _finishIntro,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final videoController = _introVideoController;
    if (_introFinished ||
        !widget.playMobileIntroVideo ||
        videoController == null ||
        !videoController.value.isInitialized) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(videoController.play());
        _armVideoWatchdog();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _videoWatchdog?.cancel();
        unawaited(videoController.pause());
        break;
    }
  }

  void _finishIntro() {
    if (_introFinished) return;
    _videoWatchdog?.cancel();
    _introVideoController?.removeListener(_handleIntroVideoState);
    if (mounted) {
      setState(() => _introFinished = true);
    } else {
      _introFinished = true;
    }
    unawaited(_reportIntroCompletion());
  }

  Future<void> _reportIntroCompletion() async {
    final reduceMotion = mounted && MediaQuery.disableAnimationsOf(context);
    if (!reduceMotion) await Future<void>.delayed(_introTransitionDuration);
    if (!mounted || _introCompletionReported) return;
    _introCompletionReported = true;
    widget.onIntroCompleted?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionPreferenceApplied) return;
    _motionPreferenceApplied = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      if (widget.playMobileIntroVideo) _finishIntro();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoWatchdog?.cancel();
    _introVideoController?.removeListener(_handleIntroVideoState);
    unawaited(_introVideoController?.dispose());
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
              builder: (context, child) {
                final progress = widget.waitingForData &&
                        _controller.status == AnimationStatus.completed
                    ? null
                    : _progress.value;
                return widget.playMobileIntroVideo || useMobileLayout
                    ? _MobileLaunchStage(
                        imageEntrance: _imageEntrance,
                        claimEntrance: _claimEntrance,
                        progress: progress,
                        statusMessage: widget.statusMessage,
                        errorMessage: widget.errorMessage,
                        onRetry: widget.onRetry,
                        playIntroVideo: widget.playMobileIntroVideo,
                        introVideoController: _introVideoController,
                        introVideoInitialized: _introVideoInitialized,
                        introFinished: _introFinished,
                        transitionDuration: _introTransitionDuration,
                      )
                    : _DesktopLaunchStage(
                        imageEntrance: _imageEntrance,
                        claimEntrance: _claimEntrance,
                        progress: progress,
                        statusMessage: widget.statusMessage,
                        errorMessage: widget.errorMessage,
                        onRetry: widget.onRetry,
                      );
              },
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
    required this.statusMessage,
    required this.errorMessage,
    required this.onRetry,
    required this.playIntroVideo,
    required this.introVideoController,
    required this.introVideoInitialized,
    required this.introFinished,
    required this.transitionDuration,
  });

  final Animation<double> imageEntrance;
  final Animation<double> claimEntrance;
  final double? progress;
  final String? statusMessage;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final bool playIntroVideo;
  final VideoPlayerController? introVideoController;
  final bool introVideoInitialized;
  final bool introFinished;
  final Duration transitionDuration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wideViewport = constraints.maxWidth / constraints.maxHeight > .72;
        final splashImage = Image.asset(
          playIntroVideo
              ? AppIdentity.mobileApkSplashAsset
              : AppIdentity.splashAsset,
          key: const ValueKey('fc-teugn-talents-splash-image'),
          // Das APK-Motiv soll auf allen Handy- und Foldable-Formaten
          // vollständig sichtbar bleiben. Die schwarzen Motivflächen bilden
          // dabei einen natürlichen, verzerrungsfreien Rand.
          fit: playIntroVideo || wideViewport ? BoxFit.contain : BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
        );
        return Stack(
          key: const ValueKey('mobile-launch-stage'),
          fit: StackFit.expand,
          children: [
            if (playIntroVideo)
              AnimatedOpacity(
                key: const ValueKey('mobile-launch-still-layer'),
                opacity: introVideoInitialized || introFinished ? 1 : 0,
                duration: transitionDuration,
                curve: Curves.easeInOutCubic,
                child: splashImage,
              )
            else
              FadeTransition(
                opacity:
                    Tween<double>(begin: .3, end: 1).animate(imageEntrance),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1.045, end: 1)
                      .animate(imageEntrance),
                  child: splashImage,
                ),
              ),
            if (playIntroVideo &&
                introVideoInitialized &&
                introVideoController != null)
              AnimatedOpacity(
                key: const ValueKey('mobile-launch-video-layer'),
                opacity: introFinished ? 0 : 1,
                duration: transitionDuration,
                curve: Curves.easeInOutCubic,
                child: _ResponsiveIntroVideo(
                  controller: introVideoController!,
                ),
              ),
            if (!playIntroVideo || introFinished) ...[
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
                      statusMessage: statusMessage,
                      errorMessage: errorMessage,
                      onRetry: onRetry,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ResponsiveIntroVideo extends StatelessWidget {
  const _ResponsiveIntroVideo({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    return ClipRect(
      child: FittedBox(
        // Das MP4 ist technisch quer, sein eigentliches Motiv liegt aber
        // hochkant in der Bildmitte. "cover" entfernt auf Handys nur die
        // ungenutzten Seitenflächen und hält das Motiv groß und lesbar.
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          key: const ValueKey('fc-teugn-talents-intro-video'),
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _DesktopLaunchStage extends StatelessWidget {
  const _DesktopLaunchStage({
    required this.imageEntrance,
    required this.claimEntrance,
    required this.progress,
    required this.statusMessage,
    required this.errorMessage,
    required this.onRetry,
  });

  final Animation<double> imageEntrance;
  final Animation<double> claimEntrance;
  final double? progress;
  final String? statusMessage;
  final String? errorMessage;
  final VoidCallback? onRetry;

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
                    statusMessage: statusMessage,
                    errorMessage: errorMessage,
                    onRetry: onRetry,
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
    this.statusMessage,
    this.errorMessage,
    this.onRetry,
  });

  final Animation<double> entrance;
  final double? progress;
  final bool compact;
  final bool centered;
  final String? statusMessage;
  final String? errorMessage;
  final VoidCallback? onRetry;

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
                statusMessage ?? 'App wird vorbereitet …',
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .4,
                ),
              ),
            if (compact && statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                statusMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .78),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (errorMessage == null) ...[
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
            ] else ...[
              const SizedBox(height: 10),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Erneut verbinden'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
