import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/activity.dart';
import '../application/activities_for_range_provider.dart';
import '../application/activity_actions_controller.dart';

/// Detalle de solo lectura + acciones (§14). Si startsAt es null, muestra el
/// mismo banner de "pendiente por programar" que usa el backlog (§12), con
/// el mismo destino de navegación — no intenta formatear una fecha que no existe.
class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({super.key, required this.activityId});
  final String activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(activityDetailProvider(activityId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle')),
      body: activityAsync.when(
        data: (activity) => _DetailBody(activity: activity),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No se pudo cargar la actividad'),
              TextButton(
                onPressed: () => ref.invalidate(activityDetailProvider(activityId)),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: activityAsync.maybeWhen(
        data: (activity) => FloatingActionButton.extended(
          icon: const Icon(Icons.edit_outlined),
          label: Text(activity.startsAt == null ? 'Programar' : 'Editar'),
          onPressed: () => context.push('/activities/$activityId/edit'),
        ),
        orElse: () => null,
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localFormat = DateFormat('EEEE d MMM · HH:mm', 'es_CO');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusChip(status: activity.status),
        const SizedBox(height: 8),
        Text(activity.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (activity.startsAt != null)
          Text(localFormat.format(activity.startsAt!.toLocal()))
        else
          _UnscheduledBanner(activityId: activity.id),
        if (activity.location != null) ...[
          const SizedBox(height: 4),
          Text(activity.location!),
        ],
        if (activity.description != null) ...[
          const SizedBox(height: 12),
          Text(activity.description!),
        ],
        const Divider(height: 32),
        Text('Recordatorios', style: Theme.of(context).textTheme.titleMedium),
        if (activity.reminders.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Sin recordatorios programados'),
          )
        else
          ...activity.reminders.map((r) => ListTile(
                dense: true,
                leading: Icon(r.channel == 'whatsapp' ? Icons.chat_outlined : Icons.notifications_outlined),
                title: Text(DateFormat('d MMM, HH:mm').format(r.remindAt.toLocal())),
                trailing: Text(r.status),
              )),
        const Divider(height: 32),
        _ActionRow(activity: activity),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'scheduled' => ('Programada', Colors.blue),
      'completed' => ('Completada', Colors.green),
      'cancelled' => ('Cancelada', Colors.red),
      _ => ('Pendiente por programar', Colors.orange),
    };
    return Chip(label: Text(label), backgroundColor: color.withOpacity(0.15));
  }
}

class _UnscheduledBanner extends StatelessWidget {
  const _UnscheduledBanner({required this.activityId});
  final String activityId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.event_busy_outlined, color: Colors.orange),
          SizedBox(width: 8),
          Expanded(child: Text('Sin fecha asignada todavía')),
        ],
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(activityActionsControllerProvider(activity.id).notifier);
    final actionState = ref.watch(activityActionsControllerProvider(activity.id));

    return Wrap(
      spacing: 12,
      children: [
        if (activity.status != 'completed')
          FilledButton.tonal(
            onPressed: actionState.isLoading ? null : controller.markCompleted,
            child: const Text('Marcar como completada'),
          ),
        // Deliberadamente no hay botón de "eliminar" (§14): DELETE ya es este
        // mismo soft delete, exponer los dos como acciones separadas solo
        // confundiría sin agregar capacidad real.
        if (activity.status != 'cancelled')
          OutlinedButton(
            onPressed: actionState.isLoading ? null : () => _confirmCancel(context, controller),
            child: const Text('Cancelar'),
          ),
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context, ActivityActionsController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Cancelar esta actividad?'),
        content: const Text('Los recordatorios pendientes no se enviarán.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar actividad'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.cancel();
    if (context.mounted && confirmed == true) context.pop();
  }
}
