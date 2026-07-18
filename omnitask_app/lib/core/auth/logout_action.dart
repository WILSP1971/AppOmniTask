import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_notifier.dart';

/// Compartido entre el menú lateral y Ajustes (§16, §28) — un solo lugar para
/// el diálogo de confirmación y la llamada a logout().
Future<void> confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('¿Cerrar sesión?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar sesión')),
      ],
    ),
  );
  // Sin navegación manual: el redirect del router reacciona a authNotifierProvider (§15, §16).
  if (confirmed == true) await ref.read(authNotifierProvider.notifier).logout();
}
