import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/navigation/app_bottom_nav.dart';
import '../../../core/navigation/app_drawer.dart';
import '../../../models/activity.dart';
import '../../notifications/application/notifications_providers.dart';
import '../application/activities_for_range_provider.dart';
import '../application/visible_range_provider.dart';
import 'widgets/agenda_header.dart';
import 'widgets/appointments_section.dart';
import 'widgets/month_calendar.dart';

/// Home rediseñado (SPEC-001 §2): orquesta AgendaHeader (mes + notificaciones
/// + búsqueda) + MonthCalendar (table_calendar, ADR-001) + AppointmentsSection
/// ("Mis citas" del día seleccionado), con el Drawer existente y el bottom
/// nav flotante nuevo. El FAB de nueva actividad vive únicamente en el bottom
/// nav (slot central de AppBottomNav); este Scaffold no define un
/// floatingActionButton propio.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedDay = DateTime(now.year, now.month, now.day);
    _selectedDay = _focusedDay;

    // visibleRangeProvider arranca con un rango de SEMANA
    // (`_weekRangeContaining` en visible_range_provider.dart, pensado para el
    // SfCalendar anterior). Con table_calendar el Home siempre muestra un
    // mes completo, así que hay que corregir ese estado inicial al mes
    // visible apenas se monta la pantalla — si no, activitiesForRangeProvider
    // solo trae ~7 días en la carga inicial y los puntitos del resto del mes
    // en MonthCalendar no aparecen hasta el primer cambio de mes manual (bug
    // C4). Riverpod prohíbe mutar un provider durante CUALQUIER lifecycle de
    // un widget que lo consume, incluido initState ("Tried to modify a
    // provider while the widget tree was building") — la única vía soportada
    // sin tocar `visible_range_provider.dart` (application/**, fuera de
    // alcance) es diferir la corrección con `Future(() {...})`, tal como
    // indica el propio mensaje de error de Riverpod. Esto implica que
    // `activitiesForRangeProvider` sí construye una primera vez con el rango
    // de semana por defecto y esa petición llega a salir — pero se descarta
    // casi de inmediato (antes de pintar ningún frame) al corregirse a nivel
    // de microtask, sin reintentos en bucle: es EXACTAMENTE una corrección
    // extra en la carga inicial, nunca más de una, y los cambios de mes
    // posteriores (_handleMonthChanged) siguen disparando una única llamada
    // cada uno.
    Future(() {
      if (!mounted) return;
      final range = _monthRange(_focusedDay);
      if (range != ref.read(visibleRangeProvider)) {
        ref.read(visibleRangeProvider.notifier).setRange(range);
      }
    });
  }

  /// Solo actualiza (y por lo tanto refetch) el rango visible si el mes
  /// realmente cambió — misma guarda que evitaba el bucle con SfCalendar
  /// (ADR-001/C2), ahora innecesaria en la práctica porque `onPageChanged`
  /// de table_calendar solo se dispara al cambiar de página, pero se
  /// conserva explícita para no depender de ese detalle de implementación.
  void _handleMonthChanged(DateTime focusedDay) {
    final range = _monthRange(focusedDay);
    setState(() => _focusedDay = focusedDay);
    if (range != ref.read(visibleRangeProvider)) {
      ref.read(visibleRangeProvider.notifier).setRange(range);
    }
  }

  void _handleDaySelected(DateTime selected, DateTime focused) {
    setState(() {
      _selectedDay = selected;
      _focusedDay = focused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activitiesAsync = ref.watch(activitiesForRangeProvider);
    final unreadCount =
        ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AgendaHeader(
        focusedDay: _focusedDay,
        onPreviousMonth: () => _handleMonthChanged(
            DateTime(_focusedDay.year, _focusedDay.month - 1)),
        onNextMonth: () => _handleMonthChanged(
            DateTime(_focusedDay.year, _focusedDay.month + 1)),
        unreadNotificationsCount: unreadCount,
        onSearchChanged: (value) => setState(() => _searchQuery = value),
      ),
      body: activitiesAsync.when(
        // Mantiene el calendario y la lista montados durante el refetch por
        // cambio de mes: sin esto, `when` vuelve a `loading` y se pierde la
        // posición/selección visible mientras llegan los nuevos datos.
        skipLoadingOnReload: true,
        data: (activities) {
          final byDay = _groupByDay(activities);
          final selectedDayActivities = _filterForSelectedDay(activities);

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MonthCalendar(
                  focusedDay: _focusedDay,
                  selectedDay: _selectedDay,
                  activitiesByDay: byDay,
                  onDaySelected: _handleDaySelected,
                  onPageChanged: _handleMonthChanged,
                ),
                const SizedBox(height: 20),
                AppointmentsSection(
                  activities: selectedDayActivities,
                  emptyLabel: _searchQuery.isNotEmpty
                      ? 'Sin resultados para "$_searchQuery"'
                      : 'No tienes citas este día',
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No se pudo cargar el calendario'),
              TextButton(
                onPressed: () => ref.invalidate(activitiesForRangeProvider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }

  List<Activity> _filterForSelectedDay(List<Activity> activities) {
    final query = _searchQuery.trim().toLowerCase();
    return activities.where((activity) {
      final startsAt = activity.startsAt?.toLocal();
      if (startsAt == null || !isSameDay(startsAt, _selectedDay)) {
        return false;
      }
      if (query.isEmpty) return true;
      return activity.title.toLowerCase().contains(query) ||
          (activity.location?.toLowerCase().contains(query) ?? false);
    }).toList()
      ..sort((a, b) => a.startsAt!.compareTo(b.startsAt!));
  }

  Map<DateTime, List<Activity>> _groupByDay(List<Activity> activities) {
    final map = <DateTime, List<Activity>>{};
    for (final activity in activities) {
      final startsAt = activity.startsAt?.toLocal();
      if (startsAt == null) continue;
      final key = DateTime(startsAt.year, startsAt.month, startsAt.day);
      map.putIfAbsent(key, () => []).add(activity);
    }
    return map;
  }
}

DateTimeRange _monthRange(DateTime month) {
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 1);
  return DateTimeRange(start: start, end: end);
}
