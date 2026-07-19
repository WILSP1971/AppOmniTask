import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/logout_action.dart';
import '../../../models/auth_state.dart';
import '../../auth/application/auth_notifier.dart';

/// Perfil, notificaciones, dispositivos y cerrar sesión son cuatro cosas de
/// naturaleza distinta (§16) — un menú con destinos claros, no un formulario
/// largo mezclándolas.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider).valueOrNull;
    final user = auth is AuthAuthenticated ? auth.user : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user != null) ...[
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(user.fullName),
                subtitle: Text(user.email),
                onTap: () => context.push('/settings/profile'),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notificaciones'),
                  subtitle:
                      const Text('Canal y anticipación de los recordatorios'),
                  onTap: () => context.push('/settings/notifications'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: const Text('Dispositivos'),
                  subtitle: const Text('Sesiones activas de push'),
                  onTap: () => context.push('/settings/devices'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
              title: Text(
                'Cerrar sesión',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => confirmAndLogout(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}
