import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../models/activity.dart';
import '../../application/activity_actions_controller.dart';
import '../activity_colors.dart';

/// Tarjeta de "Mis citas" (SPEC-001 §2): badge de fecha (día grande + mes
/// abreviado en español) coloreado por tipo, título, lugar, rango de hora y
/// menú de 3 puntos con las mismas acciones que ya existían en la fila de
/// Agenda del calendario anterior (abrir detalle) más editar/eliminar, que
/// hoy viven en ActivityDetailScreen (reprogramar / cancelar) — se exponen
/// aquí como atajo directo sin duplicar esa lógica (mismas rutas y mismo
/// controller de acciones).
class AppointmentCard extends ConsumerWidget {
  const AppointmentCard({super.key, required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final typeColor = colorForActivityType(activity.type);
    final start = activity.startsAt?.toLocal();
    final end = activity.endsAt?.toLocal();
    final timeFormat = DateFormat.Hm('es_CO');
    final timeLabel = start == null
        ? null
        : end == null
            ? timeFormat.format(start)
            : '${timeFormat.format(start)} – ${timeFormat.format(end)}';

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/activities/${activity.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateBadge(day: start, color: typeColor),
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
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (activity.location != null &&
                      activity.location!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.place_outlined,
                            size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            activity.location!,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (timeLabel != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule_outlined,
                            size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          timeLabel,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _AppointmentMenu(activity: activity),
          ],
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.day, required this.color});

  final DateTime? day;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final monthLabel =
        day == null ? '' : DateFormat.MMM('es_CO').format(day!).replaceAll('.', '');
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            day == null ? '--' : '${day!.day}',
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (day != null)
            Text(
              monthLabel,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _AppointmentMenu extends ConsumerWidget {
  const _AppointmentMenu({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      tooltip: 'Más opciones para ${activity.title}',
      onSelected: (value) async {
        switch (value) {
          case 'detail':
            context.push('/activities/${activity.id}');
          case 'edit':
            context.push('/activities/${activity.id}/edit');
          case 'delete':
            await _confirmDelete(context, ref);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'detail', child: Text('Ver detalle')),
        const PopupMenuItem(value: 'edit', child: Text('Editar')),
        if (activity.status != 'cancelled')
          const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Eliminar esta actividad?'),
        content: const Text(
            'Se cancelará y sus recordatorios pendientes no se enviarán.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(activityActionsControllerProvider(activity.id).notifier)
          .cancel();
    }
  }
}
