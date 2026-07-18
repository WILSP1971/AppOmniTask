import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/app_drawer.dart';
import '../application/unscheduled_activities_provider.dart';

/// Bandeja de "pendientes por programar" (§4, §12) — distinta de la bandeja
/// de notificaciones (§17): esta es sobre actividades sin fecha, no sobre
/// mensajes ya enviados.
class BacklogScreen extends ConsumerWidget {
  const BacklogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backlogAsync = ref.watch(unscheduledActivitiesProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(title: const Text('Pendientes por programar')),
      body: backlogAsync.when(
        data: (items) => items.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_available_outlined,
                        size: 48, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 12),
                    const Text(
                        'No tienes actividades pendientes por programar'),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(Icons.event_busy_outlined,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer),
                      ),
                      title: Text(item.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: (item.description?.isNotEmpty ?? false)
                          ? Text(item.description!)
                          : null,
                      trailing: FilledButton.tonal(
                        onPressed: () =>
                            context.push('/activities/${item.id}/edit'),
                        child: const Text('Programar'),
                      ),
                      onTap: () => context.push('/activities/${item.id}'),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No se pudo cargar la lista'),
              TextButton(
                onPressed: () => ref.invalidate(unscheduledActivitiesProvider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
