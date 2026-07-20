import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../notifications/application/device_registration_notifier.dart';
import '../../notifications/data/device_repository.dart';
import '../application/devices_provider.dart';

/// El dispositivo actual se marca con una etiqueta en vez de un botón de
/// cerrar sesión (§16) — quitarlo de la lista sería fácil de tocar sin
/// querer y dejaría a la persona sin push en el mismo teléfono que usa.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(myDevicesProvider);
    final currentToken = ref.watch(currentFcmTokenProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos')),
      body: devicesAsync.when(
        // SPEC-004 RF2: sin Firebase inicializado (o sin permiso otorgado
        // todavía) esta lista llega vacía — un control explícito, no solo el
        // registro automático de auth_notifier.dart, para que la persona
        // pueda activarlo desde aquí sin tener que cerrar sesión y volver a
        // entrar.
        data: (devices) => devices.isEmpty
            ? _EmptyDevicesState(onActivated: () => ref.invalidate(myDevicesProvider))
            : ListView(
                children: [
                  for (final device in devices)
                    ListTile(
                      leading: Icon(
                        device.platform == 'ios' ? Icons.phone_iphone : Icons.phone_android,
                      ),
                      title: Text(device.platform == 'ios' ? 'iPhone' : 'Android'),
                      subtitle: Text(
                        'Última actividad: ${DateFormat('d MMM, HH:mm').format(device.lastSeenAt.toLocal())}',
                      ),
                      trailing: device.fcmToken == currentToken
                          ? const Chip(label: Text('Este dispositivo'))
                          : IconButton(
                              icon: const Icon(Icons.logout),
                              onPressed: () => _signOut(ref, device.id),
                            ),
                    ),
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No se pudo cargar la lista'),
              TextButton(
                onPressed: () => ref.invalidate(myDevicesProvider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(WidgetRef ref, String deviceId) async {
    await ref.read(deviceRepositoryProvider).delete(deviceId);
    ref.invalidate(myDevicesProvider);
  }
}

class _EmptyDevicesState extends ConsumerStatefulWidget {
  const _EmptyDevicesState({required this.onActivated});
  final VoidCallback onActivated;

  @override
  ConsumerState<_EmptyDevicesState> createState() => _EmptyDevicesStateState();
}

class _EmptyDevicesStateState extends ConsumerState<_EmptyDevicesState> {
  bool _activating = false;

  Future<void> _activate() async {
    setState(() => _activating = true);
    try {
      await ref.read(deviceRegistrationProvider.notifier).registerCurrentDevice();
      widget.onActivated();
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined,
                size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text(
              'Aún no hay dispositivos. Activa las notificaciones para recibir recordatorios.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _activating ? null : _activate,
              icon: _activating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_active_outlined),
              label: const Text('Activar notificaciones en este dispositivo'),
            ),
          ],
        ),
      ),
    );
  }
}
