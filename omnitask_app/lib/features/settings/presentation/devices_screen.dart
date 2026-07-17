import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
        data: (devices) => ListView(
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
