import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../models/activity.dart';
import '../activity_colors.dart';

/// Wrapper de `table_calendar` (ADR-001, SPEC-001 §2, SPEC-005 RF1): TODO día
/// con actividades muestra un círculo relleno de su color (no solo el día
/// seleccionado, como en `agenda2.jpg`) + puntitos por tipo debajo; el día
/// seleccionado se distingue con un aro extra. El header propio (mes + ‹ ›)
/// vive en `AgendaHeader`, así que aquí `headerVisible` va en false para no
/// duplicarlo.
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

  /// Color más relevante del día — misma regla que usa `CalendarScreen` para
  /// las tarjetas de "Mis citas" (SPEC-005 RF1), vía `colorForDay`.
  Color _dayAccent(BuildContext context, DateTime day) {
    return colorForDay(_activitiesFor(day), Theme.of(context).colorScheme.primary);
  }

  /// Círculo de color de un día — lo usan tanto el día seleccionado (siempre,
  /// con o sin actividades, para que quede claro cuál está activo) como
  /// cualquier otro día del mes visible que SÍ tenga actividades (SPEC-005
  /// RF1: "identificar el día con programación con un color", no solo el
  /// seleccionado). [ringed] agrega un aro para distinguir el día
  /// seleccionado de los demás cuando ambos comparten el mismo color.
  Widget _dayCircle(BuildContext context, DateTime day, {required bool ringed}) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _dayAccent(context, day);
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
          border: ringed
              ? Border.all(color: colorScheme.onSurface.withValues(alpha: 0.6), width: 2)
              : null,
        ),
        child: Text(
          '${day.day}',
          // Checkpoint C8 (WCAG AA): con texto blanco fijo, el acento
          // `meeting`/steel blue (#4682B4) y otros acentos claros bajan de
          // 4.5:1 — se elige texto oscuro/claro según el brillo del fondo, y
          // el tamaño 19px bold ya califica como "texto grande" (umbral 3:1).
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
            fontSize: 19,
          ),
        ),
      ),
    );
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
        selectedBuilder: (context, day, focused) => _dayCircle(context, day, ringed: true),
        // `table_calendar` resuelve "hoy" ANTES que el default para el día
        // actual — sin este builder, un "hoy" sin seleccionar pero con
        // actividades se quedaría con el aro fino de `todayDecoration` sin
        // relleno de color, aunque `defaultBuilder` sí lo pintaría para
        // cualquier otro día.
        todayBuilder: (context, day, focused) {
          if (_activitiesFor(day).isEmpty) return null;
          return _dayCircle(context, day, ringed: false);
        },
        defaultBuilder: (context, day, focused) {
          // Días del mes visible que NO están seleccionados: si tienen
          // actividades, muestran su color igual que el círculo del
          // seleccionado (SPEC-005 RF1); si no tienen, se deja `null` para
          // que table_calendar pinte su default (y el aro de "hoy" si aplica).
          if (_activitiesFor(day).isEmpty) return null;
          return _dayCircle(context, day, ringed: false);
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
