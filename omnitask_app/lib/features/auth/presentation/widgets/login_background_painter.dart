import 'package:flutter/material.dart';

import '../../../calendar/presentation/activity_colors.dart';

/// Fondo del Login (SPEC-005 RF4): 3 manchas de color difuminadas con
/// `MaskFilter.blur` sobre el fondo oscuro de la app — evoca `LoginAppFondo.jpeg`
/// sin copiar su paleta genérica, usando los acentos que ya existen en
/// OmniTask (steel blue, teal, naranja, rosa). Se pinta una sola vez
/// (`shouldRepaint` siempre falso): no hay animación que consuma batería
/// (RNF4) en una pantalla que ya compite con el arranque de la app.
class LoginBackgroundPainter extends CustomPainter {
  const LoginBackgroundPainter({required this.steelBlue});

  final Color steelBlue;

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset center, double radius, Color color, double sigma) {
      final paint = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
      canvas.drawCircle(center, radius, paint);
    }

    blob(Offset(size.width * 0.12, size.height * 0.08),
        size.width * 0.45, steelBlue, 60);
    blob(Offset(size.width * 0.95, size.height * 0.28),
        size.width * 0.38, const Color(0xFF26C6A6), 55);
    blob(Offset(size.width * 0.85, size.height * 0.92),
        size.width * 0.5, kAccentPink, 65);
    blob(Offset(size.width * 0.1, size.height * 0.85),
        size.width * 0.3, const Color(0xFFF5A623), 50);
  }

  @override
  bool shouldRepaint(covariant LoginBackgroundPainter oldDelegate) => false;
}
