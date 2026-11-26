import 'package:flutter/material.dart';

/// A crisp, vector-rendered Google 'G' logo with official brand colors.
/// Renders without external asset files or network dependencies.
class GoogleLogo extends StatelessWidget {
  final double size;

  const GoogleLogo({super.key, this.size = 20.0});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Official Google branding colors
    const Color googleBlue = Color(0xFF4285F4);
    const Color googleRed = Color(0xFFEA4335);
    const Color googleYellow = Color(0xFFFBBC05);
    const Color googleGreen = Color(0xFF34A853);

    final Paint paint = Paint()..isAntiAlias = true;

    // Center and radius
    final Offset center = Offset(w / 2, h / 2);
    final double outerRadius = w / 2;
    final double strokeWidth = w * 0.22;
    final double innerRadius = outerRadius - strokeWidth;

    paint.style = PaintingStyle.fill;

    // Blue horizontal bar & right quadrant
    final Path bluePath = Path()
      ..moveTo(center.dx, center.dy - strokeWidth / 2)
      ..lineTo(center.dx + outerRadius, center.dy - strokeWidth / 2)
      ..lineTo(center.dx + outerRadius, center.dy + strokeWidth / 2)
      ..arcTo(
        Rect.fromCircle(center: center, radius: outerRadius),
        0.0,
        0.8,
        false,
      )
      ..lineTo(
        center.dx + innerRadius * 0.7,
        center.dy + innerRadius * 0.7,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: innerRadius),
        0.8,
        -0.8,
        false,
      )
      ..lineTo(center.dx, center.dy + strokeWidth / 2)
      ..close();
    paint.color = googleBlue;
    canvas.drawPath(bluePath, paint);

    // Green bottom arc
    final Path greenPath = Path()
      ..arcTo(
        Rect.fromCircle(center: center, radius: outerRadius),
        0.52,
        1.6,
        false,
      )
      ..lineTo(
        center.dx - innerRadius * 0.6,
        center.dy + innerRadius * 0.8,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: innerRadius),
        2.12,
        -1.6,
        false,
      )
      ..close();
    paint.color = googleGreen;
    canvas.drawPath(greenPath, paint);

    // Yellow left arc
    final Path yellowPath = Path()
      ..arcTo(
        Rect.fromCircle(center: center, radius: outerRadius),
        1.95,
        1.7,
        false,
      )
      ..lineTo(
        center.dx - innerRadius * 0.7,
        center.dy - innerRadius * 0.7,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: innerRadius),
        3.65,
        -1.7,
        false,
      )
      ..close();
    paint.color = googleYellow;
    canvas.drawPath(yellowPath, paint);

    // Red top arc
    final Path redPath = Path()
      ..arcTo(
        Rect.fromCircle(center: center, radius: outerRadius),
        3.5,
        1.85,
        false,
      )
      ..lineTo(
        center.dx + innerRadius * 0.65,
        center.dy - innerRadius * 0.75,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: innerRadius),
        5.35,
        -1.85,
        false,
      )
      ..close();
    paint.color = googleRed;
    canvas.drawPath(redPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
