import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../../models/activity.dart';
import '../../notifications/application/notifications_providers.dart';
import '../application/activities_for_range_provider.dart';
import '../application/visible_range_provider.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(activitiesForRangeProvider);
    final unreadCount = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          IconButton(
            icon: Badge(
              label: Text('$unreadCount'),
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.inbox_outlined),
            onPressed: () => context.push('/backlog'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: activitiesAsync.when(
        data: (activities) => SfCalendar(
          view: CalendarView.week,
          dataSource: _ActivityDataSource(activities),
          onViewChanged: (details) {
            final range = DateTimeRange(
              start: details.visibleDates.first,
              end: details.visibleDates.last,
            );
            ref.read(visibleRangeProvider.notifier).setRange(range);
          },
          onTap: (details) {
            final activity = details.appointments?.first as Activity?;
            if (activity != null) context.push('/activities/${activity.id}');
          },
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
}

/// Filtra por startsAt != null como salvaguarda explícita (§12): aunque el
/// backend no debería devolver actividades sin fecha en este endpoint, una
/// actividad sin fecha en la grilla sería un bug visible de inmediato.
class _ActivityDataSource extends CalendarDataSource {
  _ActivityDataSource(List<Activity> activities) {
    appointments = activities.where((a) => a.startsAt != null).toList();
  }

  @override
  DateTime getStartTime(int index) => (appointments![index] as Activity).startsAt!.toLocal();

  @override
  DateTime getEndTime(int index) =>
      (appointments![index] as Activity).endsAt?.toLocal() ??
      getStartTime(index).add(const Duration(minutes: 30));

  @override
  String getSubject(int index) => (appointments![index] as Activity).title;
}
