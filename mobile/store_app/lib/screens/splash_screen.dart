import 'dart:math' as math;

import 'package:alas_shared/alas_shared.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'onboarding_screen.dart';
import 'shell.dart';

/// Opening animation: a syrup drop falls, splashes into a green wave and the logo rises out of it.
/// It starts from the native splash picture (green leaf on cream), and a tap skips it.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// Preference key: the customer can turn the opening sound off (Account → Settings).
  static const soundKey = 'sounds.enabled';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const _total = 3300.0; // ms
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3300))..addStatusListener(_onStatus);
  bool _left = false;
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    _c.forward();
    if (context.read<AppSettings>().prefs.getBool(SplashScreen.soundKey) ?? true) _playSound();
  }

  /// The opening sound, timed with the animation. It plays on the notification stream, so a phone
  /// on silent or vibrate stays quiet, and it doesn't pause music the customer is listening to.
  Future<void> _playSound() async {
    try {
      final p = _player = AudioPlayer();
      await p.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notificationEvent,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ));
      await p.play(AssetSource('sounds/splash.m4a'), volume: .8);
    } catch (_) {
      // No sound is fine
    }
  }

  @override
  void dispose() {
    _c.dispose();
    // Let the last notes ring out after the screen is gone, then free the player
    final p = _player;
    if (p != null) Future.delayed(const Duration(seconds: 3), p.dispose);
    super.dispose();
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) _leave();
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    final onboarded = context.read<AppSettings>().prefs.getBool('onboarded') ?? false;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, _, _) => onboarded ? const Shell() : const OnboardingScreen(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)), child: child),
      ),
    ));
  }

  /// Progress (0..1) of the part of the animation between [from] and [to] milliseconds.
  double _seg(double ms, double from, double to, [Curve curve = Curves.linear]) =>
      curve.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AlasColors.background,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _leave,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final ms = _c.value * _total;
              final rise = _seg(ms, 1550, 2350, Curves.easeOutBack);
              final name = _seg(ms, 2150, 2700, Curves.easeOut);
              final tag = _seg(ms, 2450, 3000, Curves.easeOut);
              final shine = _seg(ms, 2300, 3150, Curves.easeInOut);
              final intro = _seg(ms, 0, 300, Curves.easeIn);
              return Stack(fit: StackFit.expand, children: [
                CustomPaint(painter: _SplashPainter(ms, _seg)),
                // The native splash leaf, fading out as the drop starts falling
                if (intro < 1)
                  Center(
                    child: Opacity(
                      opacity: 1 - intro,
                      child: Transform.scale(
                        scale: 1 - intro * .4,
                        child: const LeafLogo(size: 186, background: Colors.transparent, foreground: AlasColors.logoGreen),
                      ),
                    ),
                  ),
                Align(
                  alignment: const Alignment(0, .04),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Opacity(
                      opacity: rise.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - rise)),
                        child: Transform.scale(
                          scale: .6 + .4 * rise,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: Stack(children: [
                              const LeafLogo(size: 112, background: Color(0xFF1D4A31)),
                              if (shine > 0 && shine < 1)
                                Positioned.fill(
                                  child: FractionalTranslation(
                                    translation: Offset((rtl ? 1.2 - 2.4 * shine : -1.2 + 2.4 * shine), 0),
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment(-1, -.3),
                                          end: Alignment(1, .3),
                                          colors: [Color(0x00FFFFFF), Color(0x8CFFFFFF), Color(0x00FFFFFF)],
                                          stops: [.35, .5, .65],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _fadeUp(name, Text(context.tr('brand.full'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AlasColors.cream, fontWeight: FontWeight.w700))),
                    const SizedBox(height: 6),
                    _fadeUp(tag, Text(context.tr('brand.tagline'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFFD9C9AE)))),
                  ]),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _fadeUp(double v, Widget child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: child)),
      );
}

class _SplashPainter extends CustomPainter {
  _SplashPainter(this.ms, this.seg);

  final double ms;
  final double Function(double ms, double from, double to, [Curve curve]) seg;

  static const _deep = Color(0xFF173D28);
  static const _mid = Color(0xFF2E6A47);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .52);
    final impactY = center.dy - 4;

    // The drop falls, then squashes flat on impact
    final fall = seg(ms, 250, 1000, const Cubic(.55, 0, .9, .5));
    final squash = seg(ms, 1000, 1250, Curves.easeOut);
    if (fall > 0 && squash < 1) {
      const w = 44.0, h = w * 56 / 40;
      final y = -h + (impactY - (-h)) * fall + 20 * squash;
      canvas.save();
      canvas.translate(center.dx, y);
      canvas.scale(1 + 1.2 * squash, 1 - .85 * squash);
      _drop(canvas, w, h, 1 - squash);
      canvas.restore();
    }

    // Small droplets thrown up on impact
    final spray = seg(ms, 1000, 1600, Curves.easeOut);
    if (spray > 0 && spray < 1) {
      final p = Paint()..color = AlasColors.primary.withValues(alpha: 1 - spray);
      for (var i = 0; i < 12; i++) {
        final a = math.pi + (i / 11) * math.pi;
        final d = Offset(math.cos(a) * (50 + (i % 3) * 18), math.sin(a) * (40 + (i % 4) * 14));
        canvas.drawCircle(Offset(center.dx, impactY) + d * spray, 4.5 * (1 - .6 * spray), p);
      }
    }

    // The green wave floods the screen from the impact point
    final flood = seg(ms, 1050, 1950, const Cubic(.3, .7, .2, 1));
    if (flood > 0) {
      final full = math.sqrt(size.width * size.width + size.height * size.height);
      final r = full * flood;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: const [_mid, AlasColors.logoGreen, _deep], stops: const [0, .5, 1])
              .createShader(Rect.fromCircle(center: center, radius: full * .6)),
      );
    }

    // Ripples spreading out under the logo
    for (final start in const [1100.0, 1400.0, 1700.0]) {
      final t = seg(ms, start, start + 1600, Curves.easeOut);
      if (t <= 0 || t >= 1) continue;
      canvas.drawCircle(
        center,
        50 * (.4 + 2.6 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AlasColors.cream.withValues(alpha: .5 * (1 - t)),
      );
    }
  }

  void _drop(Canvas canvas, double w, double h, double opacity) {
    // SVG: M20 2C20 2 4 24 4 36a16 16 0 0 0 32 0C36 24 20 2 20 2Z in a 40x56 box, drawn centred on x
    final s = w / 40;
    canvas.translate(-w / 2, 0);
    final path = Path()
      ..moveTo(20 * s, 2 * s)
      ..cubicTo(20 * s, 2 * s, 4 * s, 24 * s, 4 * s, 36 * s)
      ..arcToPoint(Offset(36 * s, 36 * s), radius: Radius.circular(16 * s), clockwise: false)
      ..cubicTo(36 * s, 24 * s, 20 * s, 2 * s, 20 * s, 2 * s)
      ..close();
    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.3, .2),
          radius: .7,
          colors: [const Color(0xFF4E8F64).withValues(alpha: opacity), const Color(0xFF1D4A31).withValues(alpha: opacity)],
        ).createShader(rect),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(13 * s, 34 * s), width: 7 * s, height: 14 * s),
      Paint()..color = Colors.white.withValues(alpha: .45 * opacity),
    );
  }

  @override
  bool shouldRepaint(_SplashPainter old) => old.ms != ms;
}
