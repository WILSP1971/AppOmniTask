import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';

import '../../../models/auth_state.dart';
import '../../auth/application/auth_notifier.dart';

/// El correo no se edita aquí a propósito (§16) — es la identidad de login,
/// cambiarla merece un flujo separado con re-verificación.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late String _timezone;
  bool _initialized = false;

  void _hydrate(AuthAuthenticated auth) {
    if (_initialized) return;
    _nameController = TextEditingController(text: auth.user.fullName);
    _phoneController = TextEditingController(text: auth.user.phoneE164);
    _timezone = auth.user.timezone;
    _initialized = true;
  }

  @override
  void dispose() {
    if (_initialized) {
      _nameController.dispose();
      _phoneController.dispose();
    }
    super.dispose();
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
      appBar: AppBar(title: const Text('Perfil')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre completo'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
            ),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Celular'),
              validator: (v) =>
                  (v == null || !v.startsWith('+')) ? 'Incluye el indicativo, ej. +57' : null,
            ),
            ListTile(
              title: const Text('Zona horaria'),
              subtitle: Text(_timezone),
              trailing: TextButton(
                onPressed: _redetectTimezone,
                child: const Text('Detectar de nuevo'),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: authState.isLoading ? null : _submit,
              child: const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _redetectTimezone() async {
    final detected = await FlutterTimezone.getLocalTimezone();
    setState(() => _timezone = detected);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authNotifierProvider.notifier).updateProfile(
          fullName: _nameController.text.trim(),
          phoneE164: _phoneController.text.trim(),
          timezone: _timezone,
        );
    if (mounted) context.pop();
  }
}
