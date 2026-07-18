import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/app_drawer.dart';
import '../../../models/activity.dart';
import '../application/activities_by_date_provider.dart';
import 'activity_colors.dart';

/// "Actividades calendario según fecha" (§28, menú lateral → Consultas):
/// pedir un día puntual en vez de navegar la rejilla del calendario.
class ActivitiesByDateScreen extends ConsumerStatefulWidget {
  const ActivitiesByDateScreen({super.key});

  @override
  ConsumerState<ActivitiesByDateScreen> createState() =>
      _ActivitiesByDateScreenState();
}

class _ActivitiesByDateScreenState
    extends ConsumerState<ActivitiesByDateScreen> {
  late DateTime _selectedDay = _today();

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(
          () => _selectedDay = DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activitiesAsync = ref.watch(activitiesByDateProvider(_selectedDay));
    final dateLabel = DateFormat('EEEE d \'de\' MMMM \'de\' yyyy', 'es_CO')
        .format(_selectedDay);

    return Scaffold(
      appBar: AppBar(title: const Text('Actividades por fecha')),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(_capitalize(dateLabel),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickDate,
              ),
            ),
          ),
          Expanded(
            child: activitiesAsync.when(
              data: (activities) => activities.isEmpty
                  ? const Center(
                      child: Text('No hay actividades programadas ese día'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: activities.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _ActivityTile(activity: activities[i]),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No se pudo cargar la lista'),
                    TextButton(
                      onPressed: () => ref
                          .invalidate(activitiesByDateProvider(_selectedDay)),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _capitalize(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat.Hm();
    final start = activity.startsAt?.toLocal();
    final end = activity.endsAt?.toLocal();
    final timeLabel = start == null
        ? null
        : end == null
            ? timeFormat.format(start)
            : '${timeFormat.format(start)} – ${timeFormat.format(end)}';

    return Card(
      child: ListTile(
        leading: Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            color: colorForActivityType(activity.type),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(activity.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: timeLabel == null ? null : Text(timeLabel),
        onTap: () => context.push('/activities/${activity.id}'),
      ),
    );
  }
}
