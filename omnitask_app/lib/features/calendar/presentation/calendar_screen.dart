import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../../core/navigation/app_drawer.dart';
import '../../../models/activity.dart';
import '../../backlog/application/unscheduled_activities_provider.dart';
import '../../notifications/application/notifications_providers.dart';
import '../application/activities_for_range_provider.dart';
import '../application/visible_range_provider.dart';
import 'activity_colors.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  // Vive en el State (no se recrea en cada build, §26/§27): permite leer
  // _controller.view dentro de onViewChanged/appointmentBuilder para
  // distinguir Agenda (lista) de Día/Semana (rejilla de horas).
  final _controller = CalendarController();

  @override
  void initState() {
    super.initState();
    _controller.view = CalendarView.week;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleViewChanged(ViewChangedDetails details) {
    final view = _controller.view ?? CalendarView.week;

    // Agenda no reporta un rango visible como las demás vistas: onViewChanged
    // trae un solo `visibleDates` (el día ancla), así que un from==to dejaría
    // la lista de "próximas citas" vacía. Se pide una ventana amplia hacia
    // adelante en vez del día exacto — y se redondea a inicio de mes para no
    // recalcular en cada micro-scroll dentro de la misma ventana.
    final range = view == CalendarView.schedule
        ? _scheduleWindowFrom(details.visibleDates.first)
        : DateTimeRange(
            start: details.visibleDates.first, end: details.visibleDates.last);

    // onViewChanged se dispara en cada layout del calendario, no solo al
    // navegar o cambiar de vista; solo actualizar (y refetch) si el rango
    // realmente cambió, para no entrar en bucle (§26/§27).
    if (range != ref.read(visibleRangeProvider)) {
      ref.read(visibleRangeProvider.notifier).setRange(range);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activitiesAsync = ref.watch(activitiesForRangeProvider);
    final unreadCount =
        ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
    final unscheduledCount =
        ref.watch(unscheduledActivitiesProvider).valueOrNull?.length ?? 0;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          IconButton(
            tooltip: 'Pendientes por programar',
            icon: Badge(
              label: Text('$unscheduledCount'),
              isLabelVisible: unscheduledCount > 0,
              child: const Icon(Icons.inbox_outlined),
            ),
            onPressed: () => context.push('/backlog'),
          ),
          IconButton(
            tooltip: 'Notificaciones',
            icon: Badge(
              label: Text('$unreadCount'),
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: activitiesAsync.when(
        // Mantener el calendario montado durante el refetch por cambio de
        // rango: sin esto, `when` vuelve a `loading`, desmonta el SfCalendar y
        // al recrearse vuelve a disparar onViewChanged -> bucle (titileo).
        skipLoadingOnReload: true,
        data: (activities) => SfCalendar(
          controller: _controller,
          view: CalendarView.week,
          // El header ya ofrece el selector Día/Semana/Mes/Agenda con esto —
          // sin necesidad de un segmented control propio.
          allowedViews: const [
            CalendarView.day,
            CalendarView.week,
            CalendarView.month,
            CalendarView.schedule,
          ],
          // Día/Semana abren centradas en la hora actual (una cita a las 6:34
          // PM ya no queda enterrada al fondo de la rejilla de la mañana).
          initialDisplayDate: DateTime.now(),
          dataSource: _ActivityDataSource(activities),
          appointmentBuilder: _buildAppointment,
          onViewChanged: _handleViewChanged,
          onTap: (details) {
            final activity = details.appointments?.first as Activity?;
            if (activity != null) context.push('/activities/${activity.id}');
          },
          backgroundColor: colorScheme.surface,
          todayHighlightColor: colorScheme.primary,
          cellBorderColor: colorScheme.outlineVariant.withValues(alpha: 0.3),
          headerStyle: CalendarHeaderStyle(
            backgroundColor: colorScheme.surface,
            textStyle: TextStyle(
              color: colorScheme.primary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          viewHeaderStyle: ViewHeaderStyle(
            backgroundColor: colorScheme.surface,
            dayTextStyle: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            dateTextStyle: TextStyle(color: colorScheme.onSurface),
          ),
          monthViewSettings: MonthViewSettings(
            appointmentDisplayMode: MonthAppointmentDisplayMode.indicator,
            monthCellStyle: MonthCellStyle(
              backgroundColor: colorScheme.surface,
              trailingDatesBackgroundColor: colorScheme.surface,
              leadingDatesBackgroundColor: colorScheme.surface,
              textStyle: TextStyle(color: colorScheme.onSurface),
              trailingDatesTextStyle:
                  TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              leadingDatesTextStyle:
                  TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            ),
          ),
          timeSlotViewSettings: TimeSlotViewSettings(
            timeTextStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          scheduleViewSettings: ScheduleViewSettings(
            appointmentItemHeight: 72,
            monthHeaderSettings: MonthHeaderSettings(
              backgroundColor: colorScheme.surface,
              monthTextStyle: TextStyle(
                color: colorScheme.primary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            weekHeaderSettings: WeekHeaderSettings(
              backgroundColor: colorScheme.surfaceContainerHigh,
              weekTextStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            dayHeaderSettings: DayHeaderSettings(
              dayTextStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant, fontSize: 11),
              dateTextStyle: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          selectionDecoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primary,
          ),
        ),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/activities/new'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildAppointment(
      BuildContext context, CalendarAppointmentDetails details) {
    if (details.isMoreAppointmentRegion) {
      return _MoreAppointmentsChip(count: details.appointments.length);
    }

    final activity = details.appointments.first as Activity;
    if (_controller.view == CalendarView.schedule) {
      return _ScheduleAppointmentTile(activity: activity);
    }
    return _TimeSlotAppointmentBox(activity: activity, bounds: details.bounds);
  }
}

DateTimeRange _scheduleWindowFrom(DateTime anchor) {
  final start = DateTime(anchor.year, anchor.month, 1);
  final end = DateTime(start.year, start.month + 3, 1);
  return DateTimeRange(start: start, end: end);
}

/// Caja de la cita en Día/Semana — reemplaza el render por defecto de
/// Syncfusion (§problema reportado: en la última columna se veía recortada y
/// el título casi no se distinguía). Con bounds explícitos y texto con
/// elipsis, el título siempre es legible sin desbordar la columna.
class _TimeSlotAppointmentBox extends StatelessWidget {
  const _TimeSlotAppointmentBox({required this.activity, required this.bounds});

  final Activity activity;
  final Rect bounds;

  @override
  Widget build(BuildContext context) {
    final compact = bounds.height < 34;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 1),
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: compact ? 1 : 3),
      decoration: BoxDecoration(
        color: colorForActivityType(activity.type),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.topLeft,
      child: Text(
        activity.title,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.15),
        overflow: TextOverflow.ellipsis,
        maxLines: compact ? 1 : 3,
      ),
    );
  }
}

/// Tarjeta de la vista Agenda (estilo agenda2/agenda3 del rediseño visual) —
/// badge de color por tipo + título + rango de hora en local (los datos
/// siempre llegan en UTC, §9) + chevron que refuerza el onTap ya existente.
class _ScheduleAppointmentTile extends StatelessWidget {
  const _ScheduleAppointmentTile({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeFormat = DateFormat.Hm();
    final start = activity.startsAt?.toLocal();
    final end = activity.endsAt?.toLocal();
    final timeLabel = start == null
        ? null
        : end == null
            ? timeFormat.format(start)
            : '${timeFormat.format(start)} – ${timeFormat.format(end)}';
    final typeColor = colorForActivityType(activity.type);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconForActivityType(activity.type),
                color: typeColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  activity.title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
                if (timeLabel != null)
                  Text(
                    timeLabel,
                    style: TextStyle(
                        fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

IconData _iconForActivityType(String type) {
  switch (type) {
    case 'meeting':
      return Icons.groups_outlined;
    case 'task':
      return Icons.task_alt_outlined;
    case 'appointment':
    default:
      return Icons.event_outlined;
  }
}

class _MoreAppointmentsChip extends StatelessWidget {
  const _MoreAppointmentsChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '+$count más',
        style: TextStyle(
            fontSize: 11, color: Theme.of(context).colorScheme.primary),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Filtra por startsAt != null como salvaguarda explícita (§12): aunque el
/// backend no debería devolver actividades sin fecha en este endpoint, una
/// actividad sin fecha en la grilla sería un bug visible de inmediato.
class _ActivityDataSource extends CalendarDataSource {
  _ActivityDataSource(List<Activity> activities) {
    appointments = activities.where((a) => a.startsAt != null).toList();
  }

  @override
  DateTime getStartTime(int index) =>
      (appointments![index] as Activity).startsAt!.toLocal();

  @override
  DateTime getEndTime(int index) =>
      (appointments![index] as Activity).endsAt?.toLocal() ??
      getStartTime(index).add(const Duration(minutes: 30));

  @override
  String getSubject(int index) => (appointments![index] as Activity).title;
}
