import 'package:flutter/material.dart';

/// Color por tipo de actividad (§14) — compartido entre el calendario y las
/// listas de actividades para que el mismo tipo se vea igual en todas partes.
/// Paleta alineada al rediseño visual (referencias agenda2/agenda3).
Color colorForActivityType(String type) {
  switch (type) {
    case 'meeting':
      return const Color(0xFF4A6CF7);
    case 'task':
      return const Color(0xFFF5A623);
    case 'appointment':
    default:
      return const Color(0xFF26C6A6);
  }
}
