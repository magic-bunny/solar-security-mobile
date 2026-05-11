import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/solar_utils.dart';

/// Animated VRM energy flow: Solar Panel → Battery → Load
class VrmEnergyFlow extends StatefulWidget {
  final Map<String, dynamic> mppt;
  final int systemVoltage;
  const VrmEnergyFlow({super.key, required this.mppt, this.systemVoltage = 12});
  @override
  State<VrmEnergyFlow> createState() => _VrmEnergyFlowState();
}

class _VrmEnergyFlowState extends State<VrmEnergyFlow> with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  double _d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final m = widget.mppt;
    final battV = _d(m['V']);
    final battI = _d(m['I']);
    final pvV = _d(m['VPV']);
    final pvW = _d(m['PPV']);
    final soc = batteryPercentage(battV, systemVoltage: widget.systemVoltage);
    final cs = m['CS']?.toString() ?? '0';
    final err = m['ERR']?.toString() ?? '0';
    final pvActive = pvW > 0;
    final battCharging = battI > 0;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => CustomPaint(
          painter: _VrmPainter(
            animValue: _anim.value,
            soc: soc, battV: battV, battI: battI, pvV: pvV, pvW: pvW,
            stateLabel: mpptStateLabel(cs), errorLabel: mpptErrorLabel(err),
            pvActive: pvActive, battCharging: battCharging,
          ),
          child: const SizedBox(width: double.infinity, height: 280),
        ),
      ),
    );
  }
}

class _VrmPainter extends CustomPainter {
  final double animValue, battV, battI, pvV, pvW;
  final int soc;
  final String stateLabel, errorLabel;
  final bool pvActive, battCharging;

  _VrmPainter({
    required this.animValue, required this.soc, required this.battV,
    required this.battI, required this.pvV, required this.pvW,
    required this.stateLabel, required this.errorLabel,
    required this.pvActive, required this.battCharging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Layout: 3 boxes in a row — PV | Battery | Load
    final boxW = w * 0.28, boxH = h * 0.55;
    final pvRect = Rect.fromLTWH(w * 0.02, h * 0.25, boxW, boxH);
    final battRect = Rect.fromLTWH(w * 0.36, h * 0.25, boxW, boxH);
    final loadRect = Rect.fromLTWH(w * 0.70, h * 0.25, boxW, boxH);

    // Draw boxes
    _drawBox(canvas, pvRect, const Color(0xFF2E7D32), 'PV POWER');
    _drawBox(canvas, battRect, const Color(0xFF1565C0), 'BATTERY');
    _drawBox(canvas, loadRect, const Color(0xFFE65100), 'LOAD');

    // Draw connection lines + animated dots
    if (pvActive) _drawFlow(canvas, pvRect.centerRight, battRect.centerLeft, const Color(0xFF4CAF50));
    if (battCharging || battI < 0) _drawFlow(canvas, battRect.centerRight, loadRect.centerLeft, const Color(0xFFFF9800));

    // PV values
    _drawText(canvas, '${pvW.toStringAsFixed(0)}W', pvRect.center.translate(0, -8), 20, Colors.white);
    _drawText(canvas, '${pvV.toStringAsFixed(1)}V', pvRect.center.translate(0, 16), 12, Colors.white70);
    _drawText(canvas, stateLabel, pvRect.bottomCenter.translate(0, -14), 10, Colors.white60);

    // Battery values
    _drawBatteryIcon(canvas, battRect);
    _drawText(canvas, '$soc%', battRect.center.translate(0, -8), 22, Colors.white);
    _drawText(canvas, '${battV.toStringAsFixed(1)}V  ${battI.toStringAsFixed(1)}A', battRect.center.translate(0, 18), 11, Colors.white70);

    // Load values
    final loadW = (battV * battI.abs()).toStringAsFixed(0);
    _drawText(canvas, '${loadW}W', loadRect.center.translate(0, -4), 18, Colors.white);

    // Error
    if (errorLabel != 'No error') {
      _drawText(canvas, errorLabel, Offset(w / 2, h - 10), 10, Colors.redAccent);
    }
  }

  void _drawBox(Canvas canvas, Rect rect, Color color, String title) {
    final paint = Paint()..color = color.withValues(alpha: 0.15)..style = PaintingStyle.fill;
    final border = Paint()..color = color.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(rr, paint);
    canvas.drawRRect(rr, border);
    _drawText(canvas, title, Offset(rect.center.dx, rect.top + 14), 10, color, fontWeight: FontWeight.w600);
  }

  void _drawFlow(Canvas canvas, Offset from, Offset to, Color color) {
    final linePaint = Paint()..color = color.withValues(alpha: 0.3)..strokeWidth = 2;
    canvas.drawLine(from, to, linePaint);
    // Animated dots
    for (var i = 0; i < 4; i++) {
      final t = (animValue + i * 0.25) % 1.0;
      final pos = Offset.lerp(from, to, t)!;
      final dotPaint = Paint()..color = color;
      canvas.drawCircle(pos, 3, dotPaint);
    }
  }

  void _drawBatteryIcon(Canvas canvas, Rect box) {
    final cx = box.center.dx, top = box.top + 24;
    final bw = 30.0, bh = 14.0;
    final br = Rect.fromCenter(center: Offset(cx, top), width: bw, height: bh);
    final border = Paint()..color = Colors.white54..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawRRect(RRect.fromRectAndRadius(br, const Radius.circular(2)), border);
    // tip
    canvas.drawRect(Rect.fromLTWH(br.right, top - 3, 3, 6), Paint()..color = Colors.white54);
    // fill
    final fillW = bw * (soc / 100).clamp(0, 1);
    final fillColor = soc > 50 ? Colors.greenAccent : (soc > 20 ? Colors.orangeAccent : Colors.redAccent);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(br.left + 1, br.top + 1, fillW - 2, bh - 2), const Radius.circular(1)),
      Paint()..color = fillColor,
    );
  }

  void _drawText(Canvas canvas, String text, Offset pos, double size, Color color, {FontWeight fontWeight = FontWeight.normal}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: fontWeight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _VrmPainter old) => true;
}
