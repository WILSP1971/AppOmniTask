import 'package:flutter/material.dart';

/// Selector de proveedor + URL de reunión (SPEC-003 §3 RF1/RF2). Valida
/// esquema http/https en el cliente antes de enviar — el servidor valida lo
/// mismo como defensa en profundidad (RNF2), pero el mensaje inmediato acá
/// evita un viaje de red para un error evidente.
class MeetingField extends StatelessWidget {
  const MeetingField({
    super.key,
    required this.provider,
    required this.urlController,
    required this.onProviderChanged,
  });

  final String? provider;
  final TextEditingController urlController;
  final ValueChanged<String?> onProviderChanged;

  static const providerLabels = {
    'meet': 'Google Meet',
    'teams': 'Microsoft Teams',
    'other': 'Otro',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: provider,
          decoration: const InputDecoration(labelText: 'Proveedor de reunión (opcional)'),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('Ninguno')),
            ...providerLabels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
          ],
          onChanged: onProviderChanged,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: urlController,
          decoration: const InputDecoration(
            labelText: 'Link de la reunión (opcional)',
            hintText: 'https://meet.google.com/xxx-xxxx-xxx',
          ),
          keyboardType: TextInputType.url,
          validator: _validateMeetingUrl,
        ),
      ],
    );
  }

  static String? _validateMeetingUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    final isValid = uri != null && uri.isAbsolute && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!isValid) return 'Ingresa un link válido (debe empezar con http:// o https://)';
    return null;
  }
}
