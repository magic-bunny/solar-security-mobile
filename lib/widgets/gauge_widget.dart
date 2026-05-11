import 'dart:math';
import 'package:flutter/material.dart';

class GaugeWidget extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String unit;

  const GaugeWidget({super.key, required this.label, required this.value, required this.max, required this.unit});

  @override
  Widget build(BuildContext context) {
    final ratio = (value / max).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GaugePainter(ratio, Theme.of(context).colorScheme.primary),
              child: Center(child: Text('${value.toStringAsFixed(1)}', style: Theme.of(context).textTheme.bodySmall)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('$label ($unit)', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double ratio;
  final Color color;
  _GaugePainter(this.ratio, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bg = Paint()..color = color.withOpacity(0.15)..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round;
    final fg = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(4), pi * 0.75, pi * 1.5, false, bg);
    canvas.drawArc(rect.deflate(4), pi * 0.75, pi * 1.5 * ratio, false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.ratio != ratio;
}
