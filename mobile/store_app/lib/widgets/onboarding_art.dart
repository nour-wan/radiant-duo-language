import 'dart:math' as math;

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';

/// Animated pictures for the three welcome pages. Each one replays its entrance when its page
/// becomes [active], then keeps a gentle loop going.
const double kArtSize = 190;

/// Progress (0..1) of [t] between [from] and [to].
double _seg(double t, double from, double to, [Curve curve = Curves.linear]) =>
    curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

mixin _Replay<T extends StatefulWidget> on State<T>, TickerProviderStateMixin<T> {
  late final AnimationController intro = AnimationController(vsync: this, duration: introLength);
  late final AnimationController loop = AnimationController(vsync: this, duration: loopLength);

  Duration get introLength;
  Duration get loopLength;
  bool get active;

  void startIfActive() {
    if (!active) return;
    intro.forward(from: 0);
    loop.repeat();
  }

  @override
  void initState() {
    super.initState();
    startIfActive();
  }

  void replayOnActivate(bool wasActive) {
    if (active && !wasActive) startIfActive();
    if (!active) loop.stop();
  }

  @override
  void dispose() {
    intro.dispose();
    loop.dispose();
    super.dispose();
  }
}

class _Disc extends StatelessWidget {
  const _Disc({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) => ClipOval(
        child: Container(color: Theme.of(context).colorScheme.primaryContainer, child: child),
      );
}

// ---------------------------------------------------------------------------------------------
// 1 · Everything in one place: the categories orbit the disc and drop into a crate.

class IngredientsArt extends StatefulWidget {
  const IngredientsArt({super.key, required this.active});

  final bool active;

  static const images = ['canned-fruits', 'syrups', 'fruit-purees', 'raw-cocoa', 'cocoa-butter', 'coffee'];

  @override
  State<IngredientsArt> createState() => _IngredientsArtState();
}

class _IngredientsArtState extends State<IngredientsArt> with TickerProviderStateMixin, _Replay {
  late final AnimationController _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();

  @override
  Duration get introLength => const Duration(milliseconds: 600);
  @override
  Duration get loopLength => const Duration(milliseconds: 3000);
  @override
  bool get active => widget.active;

  @override
  void didUpdateWidget(IngredientsArt old) {
    super.didUpdateWidget(old);
    replayOnActivate(old.active);
  }

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  Widget _thumb(String name, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: size > 36 ? 3 : 2),
          boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 10, offset: Offset(0, 4))],
          image: DecorationImage(image: AssetImage('assets/onboarding/$name.jpg'), fit: BoxFit.cover),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const s = kArtSize, thumb = 46.0, radius = s / 2 + 6;
    final names = IngredientsArt.images;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: Listenable.merge([intro, loop, _orbit]),
        builder: (context, _) {
          final angle = _orbit.value * 2 * math.pi;
          final cycle = loop.value * 3.0; // seconds into the 3 s loop
          final step = 3.0 / names.length;
          // Crate dips a little each time an item lands in it
          var bump = 0.0;
          final falls = <Widget>[];
          for (var i = 0; i < names.length; i++) {
            final local = ((cycle - i * step) % 3.0) / 3.0;
            final down = _seg(local, 0, .35, const Cubic(.5, 0, .8, .6));
            final visible = local < .38;
            if (local >= .35 && local < .45) bump = math.max(bump, 1 - ((local - .35) / .1 - .5).abs() * 2);
            if (!visible || !widget.active) continue;
            falls.add(Positioned(
              left: s / 2 - 15 + (i - 2.5) * 5 * (1 - down),
              top: s / 2 - 96 + 82 * down,
              child: Opacity(opacity: _seg(local, 0, .08), child: Transform.scale(scale: .6 + .4 * down, child: _thumb(names[i], 30))),
            ));
          }
          final pop = _seg(intro.value, 0, 1, Curves.easeOutBack);
          return Stack(clipBehavior: Clip.none, children: [
            const Positioned.fill(child: _Disc()),
            for (var i = 0; i < names.length; i++)
              () {
                final a = angle + i / names.length * 2 * math.pi - math.pi / 2;
                return Positioned(
                  left: s / 2 + math.cos(a) * radius - thumb / 2,
                  top: s / 2 + math.sin(a) * radius - thumb / 2,
                  child: _thumb(names[i], thumb),
                );
              }(),
            // Crate: back edge, falling items, then the front with the logo
            Positioned(
              left: s / 2 - 36,
              top: s / 2 - 10,
              child: Transform.scale(
                scale: pop,
                child: Container(
                  width: 72,
                  height: 12,
                  decoration: const BoxDecoration(color: Color(0xFF1A4730), borderRadius: BorderRadius.vertical(top: Radius.circular(6))),
                ),
              ),
            ),
            ...falls,
            Positioned(
              left: s / 2 - 41,
              top: s / 2 - 2 + 3 * bump,
              child: Transform.scale(
                scale: pop,
                child: Container(
                  width: 82,
                  height: 46 - 3 * bump,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AlasColors.primary,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(12)),
                    boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 14, offset: Offset(0, 8))],
                  ),
                  child: const LeafLogo(size: 30, background: Colors.transparent),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// 2 · Delivery to your business: the truck drives up to the shop, then a tick and "pay on delivery".

class DeliveryArt extends StatefulWidget {
  const DeliveryArt({super.key, required this.active, required this.cashLabel});

  final bool active;
  final String cashLabel;

  @override
  State<DeliveryArt> createState() => _DeliveryArtState();
}

class _DeliveryArtState extends State<DeliveryArt> with TickerProviderStateMixin, _Replay {
  @override
  Duration get introLength => const Duration(milliseconds: 3200);
  @override
  Duration get loopLength => const Duration(milliseconds: 1200);
  @override
  bool get active => widget.active;

  @override
  void didUpdateWidget(DeliveryArt old) {
    super.didUpdateWidget(old);
    replayOnActivate(old.active);
  }

  @override
  Widget build(BuildContext context) {
    const s = kArtSize;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: Listenable.merge([intro, loop]),
        builder: (context, _) {
          final t = intro.value * 3.2; // seconds
          final drive = _seg(t, .2, 2.2, const Cubic(.25, .8, .3, 1));
          final moving = drive > 0 && drive < 1;
          final pinIn = _seg(t, .2, .8, Curves.easeOutBack);
          final bob = t > 1 ? math.sin(loop.value * 2 * math.pi) * 3 - 3 : 0.0;
          final tick = _seg(t, 2.2, 2.7, Curves.easeOutBack);
          final cash = _seg(t, 2.6, 3.1, Curves.easeOutBack);
          return Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: _Disc(
                child: Stack(children: [
                  Positioned(
                    left: -10,
                    right: -10,
                    bottom: 50,
                    height: 3,
                    child: CustomPaint(painter: _RoadPainter(moving ? t * 48 : 0)),
                  ),
                  const Positioned(left: 22, bottom: 53, child: CustomPaint(size: Size(50, 46), painter: _ShopPainter())),
                  Positioned(
                    left: 31,
                    bottom: 112,
                    child: Opacity(
                      opacity: pinIn.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, -30 * (1 - pinIn) + bob),
                        child: const CustomPaint(size: Size(32, 42), painter: _PinPainter()),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 18,
                    bottom: 44,
                    child: Transform.translate(
                      offset: Offset(150 * (1 - drive), 0),
                      child: CustomPaint(size: const Size(92, 61), painter: _TruckPainter(drive * 12 * math.pi)),
                    ),
                  ),
                ]),
              ),
            ),
            Positioned(
              right: 26,
              top: 24,
              child: Transform.scale(
                scale: tick,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AlasColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 6))],
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 26),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: Center(
                child: Transform.scale(
                  scale: cash,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Text(widget.cashLabel,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AlasColors.primary, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _RoadPainter extends CustomPainter {
  _RoadPainter(this.shift);

  final double shift;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF8FB58A);
    for (var x = -24 + shift % 24; x < size.width; x += 24) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 14, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) => old.shift != shift;
}

class _ShopPainter extends CustomPainter {
  const _ShopPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 50;
    canvas.scale(k);
    canvas.drawRRect(RRect.fromLTRBR(4, 16, 46, 46, const Radius.circular(3)), Paint()..color = Colors.white);
    canvas.drawPath(Path()..addPolygon(const [Offset(0, 16), Offset(6, 2), Offset(44, 2), Offset(50, 16)], true),
        Paint()..color = const Color(0xFFC0504D));
    final scallop = Paint()..color = const Color(0xFFE8A6A4);
    canvas.drawRect(const Rect.fromLTWH(0, 16, 50, 4), scallop);
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(Rect.fromLTWH(i * 12.5, 14, 12.5, 11), 0, math.pi, true, scallop);
    }
    canvas.drawRRect(RRect.fromLTRBR(18, 28, 32, 46, const Radius.circular(2)), Paint()..color = AlasColors.primary);
  }

  @override
  bool shouldRepaint(_ShopPainter old) => false;
}

class _PinPainter extends CustomPainter {
  const _PinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32);
    final p = Path()
      ..moveTo(16, 0)
      ..cubicTo(7, 0, 0, 7, 0, 16)
      ..cubicTo(0, 28, 16, 42, 16, 42)
      ..cubicTo(16, 42, 32, 28, 32, 16)
      ..cubicTo(32, 7, 25, 0, 16, 0)
      ..close();
    canvas.drawPath(p, Paint()..color = AlasColors.primary);
    canvas.drawCircle(const Offset(16, 16), 6, Paint()..color = AlasColors.cream);
  }

  @override
  bool shouldRepaint(_PinPainter old) => false;
}

class _TruckPainter extends CustomPainter {
  _TruckPainter(this.wheelAngle);

  final double wheelAngle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 96);
    canvas.drawRRect(RRect.fromLTRBR(4, 12, 58, 48, const Radius.circular(5)), Paint()..color = AlasColors.primary);
    canvas.drawPath(
      Path()..addPolygon(const [Offset(58, 22), Offset(78, 22), Offset(90, 36), Offset(90, 48), Offset(58, 48)], true),
      Paint()..color = const Color(0xFF2E6A47),
    );
    canvas.drawRRect(RRect.fromLTRBR(64, 26, 76, 35, const Radius.circular(2)), Paint()..color = const Color(0xFFD5E7CF));
    // The leaf on the side of the truck
    canvas.save();
    canvas.translate(13, 3);
    canvas.scale(.62);
    canvas.drawPath(leafPath(), Paint()..color = AlasColors.cream);
    canvas.restore();
    for (final cx in const [20.0, 74.0]) {
      canvas.drawCircle(Offset(cx, 50), 8, Paint()..color = const Color(0xFF2F1D12));
      canvas.save();
      canvas.translate(cx, 50);
      canvas.rotate(-wheelAngle);
      canvas.drawRect(const Rect.fromLTWH(-1, -6, 2, 12), Paint()..color = const Color(0xFFCCCCCC));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_TruckPainter old) => old.wheelAngle != wheelAngle;
}

/// The logo leaf in a 64x64 box: M17 41c9-2 16-9 18-23 9 6 14 16 10 25-4 9-17 10-24 4 7-2 13-7 17-15-5 5-11 9-21 9Z
Path leafPath() => Path()
  ..moveTo(17, 41)
  ..relativeCubicTo(9, -2, 16, -9, 18, -23)
  ..relativeCubicTo(9, 6, 14, 16, 10, 25)
  ..relativeCubicTo(-4, 9, -17, 10, -24, 4)
  ..relativeCubicTo(7, -2, 13, -7, 17, -15)
  ..relativeCubicTo(-5, 5, -11, 9, -21, 9)
  ..close();

// ---------------------------------------------------------------------------------------------
// 3 · Offers, discounts and coupons: a coupon slides in, an "Offer" tag swings, a gift hops.

class OffersArt extends StatefulWidget {
  const OffersArt({super.key, required this.active, required this.couponLabel, required this.offerLabel});

  final bool active;
  final String couponLabel, offerLabel;

  @override
  State<OffersArt> createState() => _OffersArtState();
}

class _OffersArtState extends State<OffersArt> with TickerProviderStateMixin, _Replay {
  static const _confetti = [Color(0xFF225A39), Color(0xFFE0A458), Color(0xFFC0504D), Color(0xFF68AA78), Color(0xFF452818)];

  @override
  Duration get introLength => const Duration(milliseconds: 1700);
  @override
  Duration get loopLength => const Duration(milliseconds: 2400);
  @override
  bool get active => widget.active;

  @override
  void didUpdateWidget(OffersArt old) {
    super.didUpdateWidget(old);
    replayOnActivate(old.active);
  }

  @override
  Widget build(BuildContext context) {
    const s = kArtSize;
    final text = Theme.of(context).textTheme;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: Listenable.merge([intro, loop]),
        builder: (context, _) {
          final t = intro.value * 1.7;
          final l = loop.value; // 0..1 over 2.4 s
          final wave = math.sin(l * 2 * math.pi);
          final slide = _seg(t, .15, .85, Curves.easeOutBack);
          final settled = t >= 1.6;
          final couponAngle = settled ? (-6 + 2 * (1 + wave)) : (-20 + 14 * slide);
          final tagIn = _seg(t, .7, 1.2, Curves.easeOutBack);
          final giftIn = _seg(t, 1.0, 1.5, Curves.easeOutBack);
          final hop = settled ? math.max(0.0, math.sin(l * 2 * math.pi)) : 0.0;
          final burst = _seg(t, .55, 1.65, Curves.easeOut);
          return Stack(clipBehavior: Clip.none, children: [
            const Positioned.fill(child: _Disc()),
            if (burst > 0 && burst < 1)
              for (var i = 0; i < 16; i++)
                () {
                  final a = i / 16 * 2 * math.pi;
                  return Positioned(
                    left: s / 2 - 3.5 + math.cos(a) * 100 * burst,
                    top: s * .45 - 5.5 + math.sin(a) * 100 * burst,
                    child: Opacity(
                      opacity: 1 - burst,
                      child: Transform.rotate(
                        angle: burst * 4.5,
                        child: Container(
                          width: 7,
                          height: 11,
                          decoration: BoxDecoration(color: _confetti[i % 5], borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                  );
                }(),
            // Coupon
            Positioned(
              left: s / 2 - 75,
              top: s / 2 - 50,
              child: Opacity(
                opacity: _seg(t, .15, .4),
                child: Transform.translate(
                  offset: Offset(-120 * (1 - slide), settled ? -2 * (1 + wave) : 0),
                  child: Transform.rotate(
                    angle: couponAngle * math.pi / 180,
                    child: PhysicalShape(
                      clipper: const _CouponClipper(),
                      color: AlasColors.primary,
                      elevation: 6,
                      shadowColor: const Color(0x66000000),
                      child: SizedBox(
                        width: 150,
                        height: 70,
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(children: [
                            const SizedBox(width: 44, child: Center(child: LeafLogo(size: 28, background: Colors.transparent))),
                            CustomPaint(size: const Size(2, 52), painter: _DashPainter()),
                            Expanded(
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text(widget.couponLabel,
                                    style: text.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, height: 1.2)),
                                Text('ALAS', style: text.labelSmall?.copyWith(color: AlasColors.cream, letterSpacing: 2)),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // "Offer" tag
            Positioned(
              right: 2,
              top: 16,
              child: Transform.scale(
                scale: tagIn,
                child: Transform.rotate(
                  angle: t >= 1.2 ? (-1 + 9 * wave) * math.pi / 180 : 0,
                  alignment: const Alignment(.8, 0),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 5, 12, 5),
                    decoration: const BoxDecoration(
                      color: Color(0xFFC0504D),
                      borderRadius: BorderRadius.horizontal(left: Radius.circular(6), right: Radius.circular(14)),
                      boxShadow: [BoxShadow(color: Color(0x2E000000), blurRadius: 12, offset: Offset(0, 6))],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.ltr, children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(widget.offerLabel, style: text.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, height: 1.2)),
                    ]),
                  ),
                ),
              ),
            ),
            // Gift
            Positioned(
              left: 6,
              bottom: 12,
              child: Transform.translate(
                offset: Offset(0, -8 * hop),
                child: Transform.rotate(
                  angle: -5 * hop * math.pi / 180,
                  child: Transform.scale(scale: giftIn, child: const CustomPaint(size: Size(58, 58), painter: _GiftPainter())),
                ),
              ),
            ),
            // Sparkles
            for (final (x, y, delay) in const [(150.0, 128.0, .1), (40.0, 14.0, .35), (118.0, -4.0, .6)])
              () {
                final v = math.sin(((l + delay) % 1) * math.pi);
                return Positioned(
                  left: x,
                  top: y,
                  child: Opacity(
                    opacity: settled ? v : 0,
                    child: Transform.rotate(
                      angle: v * math.pi / 2,
                      child: Transform.scale(scale: .4 + .6 * v, child: const Icon(Icons.auto_awesome, size: 18, color: Color(0xFFE0A458))),
                    ),
                  ),
                );
              }(),
          ]);
        },
      ),
    );
  }
}

class _CouponClipper extends CustomClipper<Path> {
  const _CouponClipper();

  @override
  Path getClip(Size size) {
    final body = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, size.height / 2), radius: 9))
      ..addOval(Rect.fromCircle(center: Offset(size.width, size.height / 2), radius: 9));
    return Path.combine(PathOperation.difference, body, notches);
  }

  @override
  bool shouldReclip(_CouponClipper old) => false;
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AlasColors.cream.withValues(alpha: .6);
    for (var y = 0.0; y < size.height; y += 7) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 4), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}

class _GiftPainter extends CustomPainter {
  const _GiftPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 58);
    const red = Color(0xFFC0504D);
    canvas.drawRRect(RRect.fromLTRBR(6, 24, 52, 56, const Radius.circular(4)), Paint()..color = const Color(0xFFE0A458));
    canvas.drawRRect(RRect.fromLTRBR(2, 16, 56, 28, const Radius.circular(3)), Paint()..color = const Color(0xFFC98B3F));
    canvas.drawRect(const Rect.fromLTWH(25, 16, 8, 40), Paint()..color = red);
    final bow = Path()
      ..moveTo(29, 16)
      ..cubicTo(23, 4, 11, 6, 15, 14)
      ..cubicTo(17, 17, 23, 16, 29, 16)
      ..moveTo(29, 16)
      ..cubicTo(35, 4, 47, 6, 43, 14)
      ..cubicTo(41, 17, 35, 16, 29, 16);
    canvas.drawPath(bow, Paint()..color = red);
  }

  @override
  bool shouldRepaint(_GiftPainter old) => false;
}
