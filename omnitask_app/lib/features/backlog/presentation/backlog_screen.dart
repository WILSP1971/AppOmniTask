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
            ? const Center(child: Text('No tienes actividades pendientes por programar'))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(items[i].title),
                  subtitle: Text(items[i].description ?? ''),
                  trailing: TextButton(
                    child: const Text('Programar'),
                    onPressed: () => context.push('/activities/${items[i].id}/edit'),
                  ),
                ),
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
