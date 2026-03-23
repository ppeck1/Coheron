import 'dart:math' as math;
import 'package:flutter/material.dart';

class SpiderMath {
  static Offset polarToCartesian(Offset center, double radius, double angleRad) {
    return Offset(
      center.dx + radius * math.cos(angleRad),
      center.dy + radius * math.sin(angleRad),
    );
  }

  /// Axes are evenly spaced starting at -90° (top), going clockwise.
  static List<double> axisAngles(int axisCount) {
    final start = -math.pi / 2.0;
    final step = (2.0 * math.pi) / axisCount;
    return List<double>.generate(axisCount, (i) => start + (i * step));
  }

  static double clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  /// Project point onto axis direction; returns normalized radius [0..1] relative to maxRadius.
  static double valueFromPoint({
    required Offset center,
    required Offset point,
    required double axisAngle,
    required double maxRadius,
  }) {
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;

    // axis unit vector
    final ux = math.cos(axisAngle);
    final uy = math.sin(axisAngle);

    // projection length along axis
    final proj = dx * ux + dy * uy;
    final norm = proj / maxRadius;
    return clamp(norm, 0.0, 1.0);
  }

  static double distance(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
  }
}
