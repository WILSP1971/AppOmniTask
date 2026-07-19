import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../models/activity.dart';
import '../activity_colors.dart';

/// Wrapper de `table_calendar` (ADR-001, SPEC-001 §2): día seleccionado en
/// círculo relleno de color, puntitos por tipo bajo los días con actividad.
/// El header propio (mes + ‹ ›) vive en `AgendaHeader`, así que aquí
/// `headerVisible` va en false para no duplicarlo.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.activitiesByDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;

  /// Actividades agrupadas por día (clave normalizada a año/mes/día, sin
  /// hora) — ya filtradas por el mes visible en el orquestador.
  final Map<DateTime, List<Activity>> activitiesByDay;

  final void Function(DateTime selected, DateTime focused) onDaySelected;
  final void Function(DateTime focused) onPageChanged;

  List<Activity> _activitiesFor(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return activitiesByDay[key] ?? const [];
  }

  /// Color más relevante del día: el primer tipo distinto encontrado entre
  /// sus actividades, o el primary del tema si no hay actividades ese día.
  Color _dayAccent(BuildContext context, DateTime day) {
    final activities = _activitiesFor(day);
    if (activities.isEmpty) return Theme.of(context).colorScheme.primary;
    return colorForActivityType(activities.first.type);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TableCalendar<Activity>(
      locale: 'es_CO',
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      focusedDay: focusedDay,
      currentDay: DateTime.now(),
      headerVisible: false,
      startingDayOfWeek: StartingDayOfWeek.monday,
      daysOfWeekHeight: 24,
      selectedDayPredicate: (day) => isSameDay(day, selectedDay),
      eventLoader: _activitiesFor,
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        weekendStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: true,
        defaultTextStyle: TextStyle(color: colorScheme.onSurface),
        weekendTextStyle: TextStyle(color: colorScheme.onSurface),
        outsideTextStyle:
            TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        todayDecoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colorScheme.primary, width: 1.4),
        ),
        todayTextStyle: TextStyle(color: colorScheme.onSurface),
        markersAutoAligned: true,
        markersAnchor: 0.85,
        markerSize: 5,
        markersMaxCount: 3,
        canMarkersOverflow: false,
      ),
      calendarBuilders: CalendarBuilders<Activity>(
        selectedBuilder: (context, day, focused) {
          final accent = _dayAccent(context, day);
          // Checkpoint C8 (WCAG AA, contraste >=4.5:1): el texto blanco fijo
          // fallaba (~2:1) sobre los acentos claros (task #F5A623,
          // appointment #26C6A6). Se elige texto oscuro/claro según el brillo
          // estimado del fondo en vez de blanco siempre.
          final textColor =
              ThemeData.estimateBrightnessForColor(accent) == Brightness.light
                  ? Colors.black87
                  : Colors.white;
          return Center(
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                // Checkpoint C8: con texto blanco, el acento `meeting`
                // (#4A6CF7) solo llega a ~4.39:1 (falla el umbral normal de
                // 4.5:1). En 19px bold califica como "texto grande" WCAG
                // (>=18.66px bold), donde el umbral baja a 3:1 y sí se
                // cumple para los 3 acentos.
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                ),
              ),
            ),
          );
        },
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return null;
          final types = <String>{};
          for (final activity in events) {
            types.add(activity.type);
            if (types.length == 3) break;
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: types
                .map((type) => Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: colorForActivityType(type),
                        shape: BoxShape.circle,
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}
