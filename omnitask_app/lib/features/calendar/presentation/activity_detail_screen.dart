import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/activity.dart';
import '../application/activities_for_range_provider.dart';
import '../application/activity_actions_controller.dart';
import 'widgets/attachments_section.dart';
import 'widgets/meeting_section.dart';

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
                onPressed: () =>
                    ref.invalidate(activityDetailProvider(activityId)),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: activityAsync.maybeWhen(
        data: (activity) => FloatingActionButton.extended(
          icon: const Icon(Icons.edit_outlined),
          label: Text(activity.startsAt == null ? 'Programar' : 'Reprogramar'),
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusChip(status: activity.status),
                const SizedBox(height: 12),
                Text(activity.title,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                if (activity.startsAt != null)
                  _InfoRow(
                    icon: Icons.schedule_outlined,
                    text: localFormat.format(activity.startsAt!.toLocal()),
                  )
                else
                  _UnscheduledBanner(activityId: activity.id),
                if (activity.location != null) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                      icon: Icons.place_outlined, text: activity.location!),
                ],
                // SPEC-009 (§3 RF6): lista de contactos de la actividad; no se
                // muestra la sección si no hay contactos (mismo criterio
                // condicional que location/description).
                if (activity.contacts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: activity.contacts.length > 1
                        ? Icons.people_outline
                        : Icons.person_outline,
                    text: activity.contacts
                        .map((c) => '${c.fullName} (${c.phoneE164})')
                        .join(', '),
                  ),
                ],
                if (activity.description != null) ...[
                  const SizedBox(height: 12),
                  Text(activity.description!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        MeetingSection(activity: activity),
        if (activity.meetingUrl != null && activity.meetingUrl!.isNotEmpty)
          const SizedBox(height: 16),
        AttachmentsSection(activityId: activity.id),
        const SizedBox(height: 16),
        Text('Recordatorios', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (activity.reminders.isEmpty)
          Text('Sin recordatorios programados',
              style: TextStyle(color: Theme.of(context).colorScheme.outline))
        else
          Card(
            child: Column(
              children: activity.reminders
                  .map((r) => ListTile(
                        dense: true,
                        leading: Icon(r.channel == 'whatsapp'
                            ? Icons.chat_outlined
                            : Icons.notifications_outlined),
                        title: Text(DateFormat('d MMM, HH:mm')
                            .format(r.remindAt.toLocal())),
                        trailing: Text(r.status),
                      ))
                  .toList(),
            ),
          ),
        const SizedBox(height: 16),
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
    final colorScheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      'scheduled' => ('Programada', colorScheme.primary),
      'completed' => ('Completada', colorScheme.secondary),
      'cancelled' => ('Cancelada', colorScheme.error),
      _ => ('Pendiente por programar', colorScheme.tertiary),
    };
    return Chip(
      label: Text(label, style: TextStyle(color: color)),
      backgroundColor: color.withValues(alpha: 0.15),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _UnscheduledBanner extends StatelessWidget {
  const _UnscheduledBanner({required this.activityId});
  final String activityId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.event_busy_outlined, color: colorScheme.tertiary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Sin fecha asignada todavía')),
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
    final controller =
        ref.watch(activityActionsControllerProvider(activity.id).notifier);
    final actionState =
        ref.watch(activityActionsControllerProvider(activity.id));

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
            onPressed: actionState.isLoading
                ? null
                : () => _confirmCancel(context, controller),
            child: const Text('Cancelar'),
          ),
      ],
    );
  }

  Future<void> _confirmCancel(
      BuildContext context, ActivityActionsController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Cancelar esta actividad?'),
        content: const Text('Los recordatorios pendientes no se enviarán.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver')),
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
