import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

class AnimatedLogo extends StatefulWidget {
  final double size;
  final Color? color;
  const AnimatedLogo({super.key, this.size = 220, this.color});

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo> with TickerProviderStateMixin {
  late final AnimationController _drawCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _textCtrl;

  @override
  void initState() {
    super.initState();
    _drawCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..forward();
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _textCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _drawCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _textCtrl.forward();
    });
  }

  @override
  void dispose() {
    _drawCtrl.dispose();
    _glowCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_drawCtrl, _glowCtrl, _textCtrl]),
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size * 1.2),
        painter: _LogoPainter(
          drawProgress: _drawCtrl.value,
          glowIntensity: _glowCtrl.value,
          textOpacity: _textCtrl.value,
          color: widget.color ?? Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double drawProgress;
  final double glowIntensity;
  final double textOpacity;
  final Color color;

  _LogoPainter({
    required this.drawProgress,
    required this.glowIntensity,
    required this.textOpacity,
    required this.color,
  });

  static final Path _cloudPath = parseSvgPathData(
    'M12.54,12.43V8h0a1.14,1.14,0,1,0-1,0v4.42H7.27V9.6'
    'a1.14,1.14,0,0,0-.53-2.15A1.14,1.14,0,0,0,6.22,9.6v2.83'
    'H6a3.82,3.82,0,1,1,1.4-7.38A5.22,5.22,0,0,1,16.84,5'
    'a4,4,0,0,1,1.23-.2h0a3.83,3.83,0,0,1,0,7.66h-.25V9.6'
    'a1.14,1.14,0,1,0-1.06,0v2.83Z',
  );

  static final Path _dropsPath = parseSvgPathData(
    'M7.27,15.39a2,2,0,0,1,1.54,2,2.07,2.07,0,1,1-2.59-2V12.43h1Z'
    'm-.53,3a1,1,0,1,0,0-2,1,1,0,0,0,0,2Z'
    'm11.08-3a2.07,2.07,0,1,1-1.06,0V12.44h1.06Z'
    'm-.53,3a1,1,0,0,0,.39-1.94,1,1,0,1,0-.39,1.94Z'
    'm-4.75-.43h0a2.06,2.06,0,1,1-1,0v-5.5h1.06Z'
    'm-.54,3a1,1,0,1,0-.93-.62A1,1,0,0,0,12,20.94Z',
  );

  void _drawAnimated(Canvas canvas, Path path, double progress, Paint stroke, Paint glow) {
    for (final metric in path.computeMetrics()) {
      final len = metric.length * progress;
      if (len <= 0) continue;
      final sub = metric.extractPath(0, len);
      canvas.drawPath(sub, glow);
      canvas.drawPath(sub, stroke);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Paths live in ~6..18 x ~2..21 coordinate space
    // Scale to fill widget, centered
    final pathBounds = _cloudPath.getBounds().expandToInclude(_dropsPath.getBounds());
    final scaleX = size.width * 0.85 / pathBounds.width;
    final scaleY = size.height * 0.7 / pathBounds.height;
    final s = scaleX < scaleY ? scaleX : scaleY;
    final dx = (size.width - pathBounds.width * s) / 2 - pathBounds.left * s;
    final dy = size.height * 0.05 - pathBounds.top * s;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(s);

    final c = color;
    final glowAlpha = 0.3 + glowIntensity * 0.5;
    final glowBlur = 0.5 + glowIntensity * 3.0;

    final strokePaint = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final glowPaint = Paint()
      ..color = c.withValues(alpha: glowAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5 + glowIntensity * 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur);

    // Cloud draws over 0..100%
    _drawAnimated(canvas, _cloudPath, drawProgress, strokePaint, glowPaint);

    // Drops start at 30%
    final dp = ((drawProgress - 0.3) / 0.7).clamp(0.0, 1.0);
    _drawAnimated(canvas, _dropsPath, dp, strokePaint, glowPaint);

    canvas.restore();

    // "v.o.z" text fades in after draw completes
    if (textOpacity > 0) {
      final ts = ui.TextStyle(
        color: c.withValues(alpha: textOpacity),
        fontSize: size.width * 0.16,
        fontWeight: FontWeight.w600,
        letterSpacing: 6,
        shadows: [
          Shadow(
            color: c.withValues(alpha: textOpacity * (0.3 + glowIntensity * 0.5)),
            blurRadius: 2 + glowIntensity * 12,
          ),
        ],
      );
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
        ..pushStyle(ts)
        ..addText('v.o.z');
      final p = builder.build()..layout(ui.ParagraphConstraints(width: size.width));
      canvas.drawParagraph(p, Offset(0, size.height * 0.82));
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.drawProgress != drawProgress ||
      old.glowIntensity != glowIntensity ||
      old.textOpacity != textOpacity ||
      old.color != color;
}
