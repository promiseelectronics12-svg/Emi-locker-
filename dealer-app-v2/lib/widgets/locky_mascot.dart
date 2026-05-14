import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

const _lockyBrand = Color(0xFF00A86B);
const _lockyBrandDark = Color(0xFF059669);
const _lockyMuted = Color(0xFF6B7280);

/// Locky — EMI Locker loading mascot.
///
/// A cute padlock character built entirely in Flutter (no assets).
/// Has blinking eyes, random eye movement, shackle wobble, breathing
/// animation, and bouncing loading dots.
///
/// Usage:
///   LockyMascot()                  // default 120px, dots shown
///   LockyMascot(size: 80)          // smaller
///   LockyMascot(showDots: false)   // no dots (e.g. inline use)
class LockyMascot extends StatefulWidget {
  const LockyMascot({
    super.key,
    this.size = 120.0,
    this.showDots = true,
    this.label,
  });

  final double size;
  final bool showDots;

  /// Optional label below the dots (e.g. "Loading devices…")
  final String? label;

  @override
  State<LockyMascot> createState() => _LockyMascotState();
}

class _LockyMascotState extends State<LockyMascot>
    with TickerProviderStateMixin {
  late final AnimationController _breathCtrl;
  late final AnimationController _blinkCtrl;
  late final AnimationController _wobbleCtrl;
  late final AnimationController _dotCtrl;
  late final AnimationController _entryCtrl;

  final _rng = math.Random();
  double _eyeX = 0.0;
  double _eyeY = 0.0;

  Timer? _eyeTimer;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );

    _wobbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _scheduleNextBlink();
    _scheduleNextEyeMove();
  }

  void _scheduleNextBlink() {
    _blinkTimer = Timer(
      Duration(milliseconds: 2800 + _rng.nextInt(3500)),
      () async {
        if (!mounted) return;
        await _blinkCtrl.forward();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await _blinkCtrl.reverse();
        // Double blink occasionally
        if (_rng.nextDouble() < 0.25) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await _blinkCtrl.forward();
          await _blinkCtrl.reverse();
        }
        _scheduleNextBlink();
      },
    );
  }

  void _scheduleNextEyeMove() {
    _eyeTimer = Timer(Duration(milliseconds: 1400 + _rng.nextInt(2200)), () {
      if (!mounted) return;
      const positions = [
        Offset(0.0, 0.0),
        Offset(-0.7, 0.0),
        Offset(0.7, 0.0),
        Offset(0.0, -0.35),
        Offset(-0.5, -0.25),
        Offset(0.5, -0.25),
        Offset(-0.4, 0.2),
        Offset(0.4, 0.2),
      ];
      final pos = positions[_rng.nextInt(positions.length)];
      setState(() {
        _eyeX = pos.dx;
        _eyeY = pos.dy;
      });
      _scheduleNextEyeMove();
    });
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    _blinkCtrl.dispose();
    _wobbleCtrl.dispose();
    _dotCtrl.dispose();
    _entryCtrl.dispose();
    _eyeTimer?.cancel();
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entryAnim = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOutBack,
    );

    return AnimatedBuilder(
      animation: _entryCtrl,
      builder: (context, child) => Transform.scale(
        scale: entryAnim.value,
        child: Opacity(opacity: _entryCtrl.value.clamp(0.0, 1.0), child: child),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_breathCtrl, _blinkCtrl, _wobbleCtrl]),
            builder: (context, _) {
              final breathScale = Tween<double>(begin: 0.97, end: 1.0).evaluate(
                CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut),
              );
              final blinkProgress = Tween<double>(begin: 1.0, end: 0.0)
                  .evaluate(
                    CurvedAnimation(
                      parent: _blinkCtrl,
                      curve: Curves.easeInOut,
                    ),
                  );
              final wobble = Tween<double>(begin: -0.025, end: 0.025).evaluate(
                CurvedAnimation(parent: _wobbleCtrl, curve: Curves.easeInOut),
              );

              return Transform.scale(
                scale: breathScale,
                child: SizedBox(
                  width: widget.size,
                  height: widget.size * 1.15,
                  child: CustomPaint(
                    painter: _LockyPainter(
                      eyeX: _eyeX,
                      eyeY: _eyeY,
                      blinkProgress: blinkProgress,
                      wobble: wobble,
                    ),
                  ),
                ),
              );
            },
          ),
          if (widget.showDots) ...[
            const SizedBox(height: 18),
            _LockyDots(controller: _dotCtrl),
          ],
          if (widget.label != null) ...[
            const SizedBox(height: 10),
            Text(
              widget.label!,
              style: const TextStyle(
                color: _lockyMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Bouncing dots ──────────────────────────────────────────────────────────────

class _LockyDots extends StatelessWidget {
  const _LockyDots({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = ((t - i * 0.18) % 1.0).clamp(0.0, 1.0);
            final bounce = phase < 0.5 ? math.sin(phase * math.pi) * 9.0 : 0.0;
            final opacity =
                0.35 + (phase < 0.5 ? phase * 1.3 : 0.0).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.translate(
                offset: Offset(0, -bounce),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _lockyBrand.withValues(alpha: opacity),
                    shape: BoxShape.circle,
                    boxShadow: bounce > 3
                        ? [
                            BoxShadow(
                              color: _lockyBrand.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Painter ────────────────────────────────────────────────────────────────────

class _LockyPainter extends CustomPainter {
  const _LockyPainter({
    required this.eyeX,
    required this.eyeY,
    required this.blinkProgress,
    required this.wobble,
  });

  final double eyeX;
  final double eyeY;
  final double blinkProgress; // 1.0 = open, 0.0 = closed
  final double wobble; // radians, ±0.025

  static const _brand = _lockyBrand;
  static const _brandDark = _lockyBrandDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Layout constants — all relative to canvas size
    final bodyL = w * 0.09;
    final bodyT = h * 0.40;
    final bodyR = w * 0.91;
    final bodyB = h * 0.96;
    final bodyRad = Radius.circular(w * 0.18);

    final shackleL = w * 0.27;
    final shackleR = w * 0.73;
    final shackleTopY = h * 0.05;
    final shackleBottomY = h * 0.48;
    final shackleStroke = w * 0.115;

    // ── Drop shadow ──────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromLTRBR(bodyL + 2, bodyT + 8, bodyR + 2, bodyB + 4, bodyRad),
      Paint()
        ..color = _brand.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // ── Body gradient ────────────────────────────────────────
    final bodyRect = Rect.fromLTRB(bodyL, bodyT, bodyR, bodyB);
    final bodyRRect = RRect.fromRectAndRadius(bodyRect, bodyRad);

    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_brand, _brandDark],
        ).createShader(bodyRect),
    );

    // Body inner top highlight
    canvas.drawRRect(
      RRect.fromLTRBR(
        bodyL + 3,
        bodyT + 3,
        bodyR - 3,
        bodyT + 26,
        const Radius.circular(14),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );

    // ── Shackle (wobble rotates around its midpoint base) ────
    final wobblePivot = Offset(w / 2, shackleBottomY);
    canvas.save();
    canvas.translate(wobblePivot.dx, wobblePivot.dy);
    canvas.rotate(wobble);
    canvas.translate(-wobblePivot.dx, -wobblePivot.dy);

    final shacklePath = Path()
      ..moveTo(shackleL + shackleStroke / 2, shackleBottomY)
      ..lineTo(shackleL + shackleStroke / 2, (shackleTopY + shackleBottomY) / 2)
      ..arcToPoint(
        Offset(
          shackleR - shackleStroke / 2,
          (shackleTopY + shackleBottomY) / 2,
        ),
        radius: Radius.circular((shackleR - shackleL) / 2),
        clockwise: false,
      )
      ..lineTo(shackleR - shackleStroke / 2, shackleBottomY);

    // White outer glow on shackle
    canvas.drawPath(
      shacklePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = shackleStroke + 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Shackle fill
    canvas.drawPath(
      shacklePath,
      Paint()
        ..color = _brandDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = shackleStroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Shackle inner highlight
    canvas.drawPath(
      shacklePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = shackleStroke * 0.4
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();

    // ── Eyes ─────────────────────────────────────────────────
    final eyeCenterY = bodyT + (bodyB - bodyT) * 0.33;
    final eyeSpacing = w * 0.21;
    final eyeR = w * 0.105;
    final pupilR = w * 0.048;
    final maxOffset = eyeR * 0.38;

    for (final side in [-1.0, 1.0]) {
      final cx = w / 2 + side * eyeSpacing;
      final cy = eyeCenterY;

      // Eye white circle
      canvas.drawCircle(
        Offset(cx, cy),
        eyeR,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );

      // Subtle eye shadow ring
      canvas.drawCircle(
        Offset(cx, cy),
        eyeR,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      if (blinkProgress > 0.05) {
        // Eye open — draw pupil + shine
        canvas.save();
        // Clip to eye circle so pupil doesn't bleed out
        canvas.clipPath(
          Path()
            ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: eyeR)),
        );

        // Blink: scale vertically from center
        canvas.translate(cx, cy);
        canvas.scale(1.0, blinkProgress);
        canvas.translate(-cx, -cy);

        final px = cx + eyeX * maxOffset;
        final py = cy + eyeY * maxOffset;

        // Pupil
        canvas.drawCircle(
          Offset(px, py),
          pupilR,
          Paint()..color = _brandDark.withValues(alpha: 0.88),
        );

        // Pupil shine
        canvas.drawCircle(
          Offset(px + pupilR * 0.38, py - pupilR * 0.38),
          pupilR * 0.32,
          Paint()..color = Colors.white,
        );

        canvas.restore();
      } else {
        // Fully closed — eyelid line
        canvas.drawLine(
          Offset(cx - eyeR * 0.65, cy),
          Offset(cx + eyeR * 0.65, cy),
          Paint()
            ..color = _brandDark.withValues(alpha: 0.7)
            ..strokeWidth = 2.8
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // ── Cheek blush (subtle warmth) ───────────────────────────
    for (final side in [-1.0, 1.0]) {
      canvas.drawCircle(
        Offset(
          w / 2 + side * (eyeSpacing + eyeR * 0.7),
          eyeCenterY + eyeR * 1.15,
        ),
        eyeR * 0.55,
        Paint()..color = Colors.white.withValues(alpha: 0.1),
      );
    }

    // ── Keyhole ──────────────────────────────────────────────
    final khCx = w / 2;
    final khCy = bodyT + (bodyB - bodyT) * 0.68;
    final khR = w * 0.09;
    final khSlotW = khR * 0.52;
    final khSlotH = khR * 1.05;

    final keyholePaint = Paint()..color = Colors.white.withValues(alpha: 0.88);

    // Keyhole circle
    canvas.drawCircle(Offset(khCx, khCy), khR, keyholePaint);

    // Keyhole slot
    canvas.drawRRect(
      RRect.fromLTRBR(
        khCx - khSlotW / 2,
        khCy + khR * 0.35,
        khCx + khSlotW / 2,
        khCy + khR * 0.35 + khSlotH,
        const Radius.circular(3),
      ),
      keyholePaint,
    );
  }

  @override
  bool shouldRepaint(_LockyPainter old) =>
      old.eyeX != eyeX ||
      old.eyeY != eyeY ||
      old.blinkProgress != blinkProgress ||
      old.wobble != wobble;
}
