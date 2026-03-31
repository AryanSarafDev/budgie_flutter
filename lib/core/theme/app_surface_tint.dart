import 'package:flutter/material.dart';

class AppSurfaceTint {
  static Color background(ColorScheme scheme) {
    return scheme.surfaceDim;
  }

  static Color card(ColorScheme scheme) {
    return Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.06),
      scheme.surfaceDim,
    );
  }
}