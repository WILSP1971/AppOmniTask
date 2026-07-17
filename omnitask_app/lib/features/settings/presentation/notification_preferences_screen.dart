import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/auth_state.dart';
import '../../../models/notification_preferences.dart';
import '../../auth/application/auth_notifier.dart';

/// El botón de guardar se deshabilita si se desmarcan todas las opciones de
/// anticipación (§16) — de lo contrario sería fácil terminar sin ningún
/// recordatorio configurado sin darse cuenta.
class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends ConsumerState<NotificationPreferencesScreen> {
  static const _offsetOptions = {
    1440: '1 día antes',
    60: '1 hora antes',
    15: '15 minutos antes',
  };

  String? _channel;
  Set<int>? _offsets;

  void _hydrate(AuthAuthenticated auth) {
    if (_channel != null) return;
    _channel = auth.user.notificationPreferences.defaultChannel;
    _offsets = auth.user.notificationPreferences.reminderOffsetsMinutes.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final auth = authState.valueOrNull;
    if (auth is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _hydrate(auth);

    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: ListView(
        children: [
          const _SectionLabel('Canal por defecto'),
          RadioListTile<String>(
            value: 'push',
            groupValue: _channel,
            title: const Text('Solo push'),
            onChanged: (v) => setState(() => _channel = v),
          ),
          RadioListTile<String>(
            value: 'whatsapp',
            groupValue: _channel,
            title: const Text('Solo WhatsApp'),
            onChanged: (v) => setState(() => _channel = v),
          ),
          RadioListTile<String>(
            value: 'both',
            groupValue: _channel,
            title: const Text('Push y WhatsApp'),
            onChanged: (v) => setState(() => _channel = v),
          ),
          const Divider(),
          const _SectionLabel('¿Con cuánta anticipación?'),
          for (final entry in _offsetOptions.entries)
            CheckboxListTile(
              value: _offsets!.contains(entry.key),
              title: Text(entry.value),
              onChanged: (checked) => setState(() {
                if (checked!) {
                  _offsets!.add(entry.key);
                } else {
                  _offsets!.remove(entry.key);
                }
              }),
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton(
              onPressed: _offsets!.isEmpty || authState.isLoading ? null : _submit,
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    await ref.read(authNotifierProvider.notifier).updateProfile(
          preferences: NotificationPreferences(
            defaultChannel: _channel!,
            reminderOffsetsMinutes: _offsets!.toList()..sort(),
          ),
        );
    if (mounted) context.pop();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
