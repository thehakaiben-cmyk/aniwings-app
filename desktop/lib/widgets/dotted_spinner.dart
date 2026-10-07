import 'dart:math' as math;
import 'package:flutter/material.dart';

class DottedSpinner extends StatefulWidget {
  final Color color;
  final double size;
  final int dotCount;
  final Duration duration;

  const DottedSpinner({
    super.key,
    this.color = const Color(0xFFE25B73),
    this.size = 40.0,
    this.dotCount = 8,
    this.duration = const Duration(
      milliseconds: 2400,
    ), // Slower, relaxed rotation speed
  });

  @override
  State<DottedSpinner> createState() => _DottedSpinnerState();
}

class _DottedSpinnerState extends State<DottedSpinner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _DottedSpinnerPainter(
                progress: _controller.value,
                color: widget.color,
                dotCount: widget.dotCount,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DottedSpinnerPainter extends CustomPainter {
  final double progress;
  final Color color;
  final int dotCount;

  _DottedSpinnerPainter({
    required this.progress,
    required this.color,
    required this.dotCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final maxDotRadius = (math.pi * radius) / dotCount * 0.70;
    final activeIndex = progress * dotCount;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * 2 * math.pi);
    canvas.translate(-center.dx, -center.dy);

    for (int i = 0; i < dotCount; i++) {
      final angle = i * (2 * math.pi / dotCount) - (math.pi / 2);

      final x = center.dx + radius * math.cos(angle) * 0.78;
      final y = center.dy + radius * math.sin(angle) * 0.78;

      final diff = (activeIndex - i) % dotCount;
      final opacity = (1.0 - (diff / dotCount) * 0.75).clamp(0.20, 1.0);
      final currentDotRadius = maxDotRadius * (1.0 - (diff / dotCount) * 0.60);

      final pos = Offset(x, y);

      // Clean solid dot rendering - zero glow or blur
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      canvas.drawCircle(pos, currentDotRadius, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DottedSpinnerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.dotCount != dotCount;
  }
}
