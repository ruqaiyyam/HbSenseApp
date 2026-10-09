import 'package:flutter/material.dart';

/// Draws a repeating PPG waveform: a fast systolic upstroke, a dicrotic
/// notch, then a slower diastolic decay -- the actual shape of the signal
/// this whole device reads, rather than a generic heart icon.
class PulseWavePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  PulseWavePainter({required this.color, this.strokeWidth = 2.2});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final midY = size.height * 0.6;
    final cycleWidth = size.width / 3.1;

    path.moveTo(0, midY);
    for (int i = 0; i < 4; i++) {
      final x0 = i * cycleWidth;
      // baseline run-in
      path.lineTo(x0 + cycleWidth * 0.08, midY);
      // sharp systolic upstroke
      path.cubicTo(
        x0 + cycleWidth * 0.12, midY,
        x0 + cycleWidth * 0.16, size.height * 0.02,
        x0 + cycleWidth * 0.20, size.height * 0.02,
      );
      // fast fall toward the dicrotic notch
      path.cubicTo(
        x0 + cycleWidth * 0.24, size.height * 0.02,
        x0 + cycleWidth * 0.27, size.height * 0.48,
        x0 + cycleWidth * 0.32, size.height * 0.40,
      );
      // small secondary (dicrotic) bump
      path.cubicTo(
        x0 + cycleWidth * 0.37, size.height * 0.30,
        x0 + cycleWidth * 0.40, size.height * 0.34,
        x0 + cycleWidth * 0.46, size.height * 0.50,
      );
      // slow diastolic decay back to baseline
      path.cubicTo(
        x0 + cycleWidth * 0.60, size.height * 0.75,
        x0 + cycleWidth * 0.75, midY,
        x0 + cycleWidth * 1.0, midY,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant PulseWavePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
