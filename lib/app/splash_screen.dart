import 'dart:math';

import 'package:flutter/material.dart';

/// Branded startup screen shown while [TrekApp] restores the session,
/// styled after Trek's web login screen (dark navy gradient, twinkling
/// stars, glowing orbs, the T-mark fading/scaling in) rather than a bare
/// spinner. A native static launch image (see `flutter_native_splash` in
/// pubspec.yaml) covers the gap before Flutter itself starts rendering;
/// this widget is the animated handoff from that static frame.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _flightController;
  late final AnimationController _revealController;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _stars = List.generate(36, (i) => _Star.random(Random(i)));
    // A long, non-reversing, repeating controller whose value (0..1) maps
    // linearly to real elapsed seconds — driving both the twinkle and the
    // continuous drift below. Long enough that the loop-back-to-0 seam is
    // never actually seen (the splash is on screen for a couple of seconds
    // at most).
    _flightController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _flightDurationSeconds),
    )..repeat();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _flightController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoOpacity = CurvedAnimation(
      parent: _revealController,
      curve: const Interval(0, 0.7, curve: Curves.easeOutCubic),
    );
    final logoScale = Tween<double>(begin: 0.9, end: 1.0).animate(logoOpacity);
    final taglineOpacity = CurvedAnimation(
      parent: _revealController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _StarFieldPainter(
              stars: _stars,
              animation: _flightController,
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  key: const ValueKey('splash-logo-fade'),
                  opacity: logoOpacity,
                  child: ScaleTransition(
                    scale: logoScale,
                    child: Image.asset(
                      'assets/icon/mark.png',
                      width: 96,
                      height: 96,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FadeTransition(
                  key: const ValueKey('splash-tagline-fade'),
                  opacity: taglineOpacity,
                  child: const Text(
                    'Your Trips.\nYour Plan.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const int _flightDurationSeconds = 3600;

/// Every star drifts diagonally (down and slightly left) rather than in
/// random directions — a shared heading reads as "flying through" a
/// starfield instead of stars scattering like confetti. Applied as a
/// multiple of each star's own [_Star.verticalSpeed] so nearer/farther
/// stars stay on the same diagonal.
const double _horizontalDriftRatio = -0.3;

class _Star {
  const _Star({
    required this.dx,
    required this.dy,
    required this.radius,
    required this.baseOpacity,
    required this.phase,
    required this.verticalSpeed,
  });

  factory _Star.random(Random random) {
    final isNear = random.nextBool();
    return _Star(
      dx: random.nextDouble(),
      dy: random.nextDouble(),
      radius: isNear ? 1.5 : 1.0,
      baseOpacity: 0.15 + random.nextDouble() * 0.35,
      phase: random.nextDouble() * pi * 2,
      // Bigger stars drift faster — reads as closer/nearer, giving the
      // field a sense of depth (parallax) rather than flat uniform motion.
      verticalSpeed:
          (isNear ? 0.045 : 0.022) * (0.75 + random.nextDouble() * 0.6),
    );
  }

  final double dx;
  final double dy;
  final double radius;
  final double baseOpacity;
  final double phase;

  /// Fraction of screen height this star drifts downward per second.
  final double verticalSpeed;
}

class _StarFieldPainter extends CustomPainter {
  _StarFieldPainter({required this.stars, required this.animation})
    : super(repaint: animation);

  final List<_Star> stars;
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final elapsedSeconds = animation.value * _flightDurationSeconds;
    for (final star in stars) {
      final twinkle =
          0.5 + 0.5 * sin(elapsedSeconds * (2 * pi / 3) + star.phase);
      paint.color = Colors.white.withValues(
        alpha: star.baseOpacity + twinkle * 0.2,
      );

      final dy = (star.dy + elapsedSeconds * star.verticalSpeed) % 1.0;
      final dx =
          (star.dx +
              elapsedSeconds * star.verticalSpeed * _horizontalDriftRatio) %
          1.0;

      canvas.drawCircle(
        Offset((dx + 1.0) % 1.0 * size.width, (dy + 1.0) % 1.0 * size.height),
        star.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) => true;
}
