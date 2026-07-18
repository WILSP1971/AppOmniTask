import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../models/auth_state.dart';
import '../auth/logout_action.dart';

/// Menú lateral (§28): Calendario, Consultas (actividades por fecha /
/// sin programar) y Cerrar sesión. Solo en las pantallas que el propio menú
/// enlaza — Calendario, Consultas y Pendientes por programar — para que
/// moverse entre ellas sea consistente sin duplicar el menú en pantallas más
/// profundas (detalle/edición/ajustes) que ya tienen su propia navegación.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider).valueOrNull;
    final user = auth is AuthAuthenticated ? auth.user : null;
    final currentLocation = GoRouterState.of(context).matchedLocation;

    void closeAndGo(String location) {
      Navigator.pop(context);
      if (location != currentLocation) context.go(location);
    }

    void closeAndPush(String location) {
      Navigator.pop(context);
      if (location != currentLocation) context.push(location);
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('OmniTask', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  if (user != null) ...[
                    const SizedBox(height: 4),
                    Text(user.fullName, overflow: TextOverflow.ellipsis),
                    Text(
                      user.email,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Calendario'),
              selected: currentLocation == '/',
              onTap: () => closeAndGo('/'),
            ),
            ExpansionTile(
              leading: const Icon(Icons.search_outlined),
              title: const Text('Consultas'),
              initiallyExpanded: currentLocation == '/consultas/por-fecha' || currentLocation == '/backlog',
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 32, right: 16),
                  leading: const Icon(Icons.event_note_outlined),
                  title: const Text('Actividades calendario según fecha'),
                  selected: currentLocation == '/consultas/por-fecha',
                  onTap: () => closeAndPush('/consultas/por-fecha'),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 32, right: 16),
                  leading: const Icon(Icons.inbox_outlined),
                  title: const Text('Actividades sin programar'),
                  selected: currentLocation == '/backlog',
                  onTap: () => closeAndPush('/backlog'),
                ),
              ],
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
              title: Text('Cerrar sesión', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                confirmAndLogout(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }
}
