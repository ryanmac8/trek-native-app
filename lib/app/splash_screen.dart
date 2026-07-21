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
  late final AnimationController _starController;
  late final AnimationController _revealController;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _stars = List.generate(36, (i) => _Star.random(Random(i)));
    _starController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _starController.dispose();
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
              animation: _starController,
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

class _Star {
  const _Star({
    required this.dx,
    required this.dy,
    required this.radius,
    required this.baseOpacity,
    required this.phase,
  });

  factory _Star.random(Random random) {
    return _Star(
      dx: random.nextDouble(),
      dy: random.nextDouble(),
      radius: random.nextBool() ? 1.5 : 1.0,
      baseOpacity: 0.15 + random.nextDouble() * 0.35,
      phase: random.nextDouble() * pi * 2,
    );
  }

  final double dx;
  final double dy;
  final double radius;
  final double baseOpacity;
  final double phase;
}

class _StarFieldPainter extends CustomPainter {
  _StarFieldPainter({required this.stars, required this.animation})
    : super(repaint: animation);

  final List<_Star> stars;
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final t = animation.value;
    for (final star in stars) {
      final twinkle = 0.5 + 0.5 * sin(t * pi * 2 + star.phase);
      paint.color = Colors.white.withValues(
        alpha: star.baseOpacity + twinkle * 0.2,
      );
      canvas.drawCircle(
        Offset(star.dx * size.width, star.dy * size.height),
        star.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) => true;
}
