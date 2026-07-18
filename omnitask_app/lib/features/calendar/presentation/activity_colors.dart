import 'package:flutter/material.dart';

/// Color por tipo de actividad (§14) — compartido entre el calendario y las
/// listas de actividades para que el mismo tipo se vea igual en todas partes.
Color colorForActivityType(String type) {
  switch (type) {
    case 'meeting':
      return const Color(0xFF3F51B5);
    case 'task':
      return const Color(0xFFEF6C00);
    case 'appointment':
    default:
      return const Color(0xFF0E7C72);
  }
}
