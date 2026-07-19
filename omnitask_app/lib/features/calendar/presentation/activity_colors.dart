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

/// Acentos de UI del rediseño visual (SPEC-001 §3) — NO son tipos de
/// actividad nuevos, solo color de detalles de interfaz: el punto de
/// notificación no leída (kAccentPink) y el FAB central del bottom nav
/// (kAccentPurpleFab).
const kAccentPink = Color(0xFFEC4899);
const kAccentPurpleFab = Color(0xFF5B6EF5);
