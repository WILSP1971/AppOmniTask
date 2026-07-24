import 'package:flutter/material.dart';

import '../../../models/activity.dart';

/// Color por tipo de actividad (§14) — compartido entre el calendario y las
/// listas de actividades para que el mismo tipo se vea igual en todas partes.
/// Paleta alineada al rediseño visual (referencias agenda2/agenda3).
Color colorForActivityType(String type) {
  switch (type) {
    case 'meeting':
      // SPEC-005 RF3: azul steel, mismo valor que AppTheme._darkPrimary.
      return const Color(0xFF4682B4);
    case 'task':
      return const Color(0xFFF5A623);
    case 'birthday':
      // SPEC-006: distinto de los 3 tipos existentes.
      return kAccentPink;
    case 'appointment':
    default:
      return const Color(0xFF26C6A6);
  }
}

/// Ícono por tipo de actividad (SPEC-005 RF2) — se muestra en una esquina de
/// `AppointmentCard` ya que el color de la tarjeta pasa a representar el día,
/// no el tipo.
IconData iconForActivityType(String type) {
  switch (type) {
    case 'meeting':
      return Icons.groups;
    case 'task':
      return Icons.task_alt;
    case 'birthday':
      return Icons.cake;
    case 'appointment':
    default:
      return Icons.event;
  }
}

/// Color del día en el calendario (SPEC-005 RF1): el del tipo de la primera
/// actividad de la lista, o [fallback] si el día no tiene actividades. Un solo
/// lugar para esta regla — la usan tanto `MonthCalendar` (círculo del día)
/// como `CalendarScreen` (color de las tarjetas de "Mis citas" de ese día),
/// así siempre coinciden.
Color colorForDay(List<Activity> dayActivities, Color fallback) {
  if (dayActivities.isEmpty) return fallback;
  return colorForActivityType(dayActivities.first.type);
}

/// Acentos de UI del rediseño visual (SPEC-001 §3) — NO son tipos de
/// actividad nuevos, solo color de detalles de interfaz: el punto de
/// notificación no leída (kAccentPink) y el FAB central del bottom nav
/// (kAccentPurpleFab).
const kAccentPink = Color(0xFFEC4899);
const kAccentPurpleFab = Color(0xFF5B6EF5);
