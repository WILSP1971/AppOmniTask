import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../models/contact.dart';
import '../../../contacts/data/contact_repository.dart';

/// Autocompletar con debounce contra GET /contacts?search= (§14) — no trae
/// la lista completa de contactos al abrir el formulario; para una clínica
/// con cientos de pacientes, cargarlos todos de una vez sería innecesario.
///
/// SPEC-009 (§3 RF1): multi-selección — gestiona una lista de contactos
/// seleccionados, mostrados como chips con botón de quitar.
class ContactPickerField extends ConsumerStatefulWidget {
  const ContactPickerField({super.key, required this.selectedContacts, required this.onChanged});

  final List<Contact> selectedContacts;
  final ValueChanged<List<Contact>> onChanged;

  @override
  ConsumerState<ContactPickerField> createState() => _ContactPickerFieldState();
}

class _ContactPickerFieldState extends ConsumerState<ContactPickerField> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Contact> _results = [];
  bool _isSearching = false;

  /// Mensaje de error real de la última búsqueda fallida (RF6, SPEC-011) —
  /// `null` cuando no hay error (búsqueda en curso, sin resultados u OK).
  String? _errorMessage;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _results = [];
        _errorMessage = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      // RF7: limpiar el error de un intento previo antes de reintentar, para
      // no dejar un mensaje viejo pegado en pantalla.
      setState(() {
        _isSearching = true;
        _errorMessage = null;
      });
      try {
        final results = await ref.read(contactRepositoryProvider).search(query.trim());
        if (!mounted) return;
        setState(() {
          // No ofrecer/duplicar un contacto ya seleccionado (§3 RF1, CA5).
          _results = results
              .where((c) => !widget.selectedContacts.any((s) => s.id == c.id))
              .toList();
        });
      } catch (e) {
        // RF6: mensaje de error real en pantalla (modo diagnóstico), no un
        // genérico — así una falla en el celular del Lead es diagnosticable
        // sin `adb`.
        if (!mounted) return;
        setState(() {
          _results = [];
          _errorMessage = describeSearchError(e);
        });
      } finally {
        // RF5 (fix principal): el spinner SIEMPRE se apaga, pase lo que
        // pase — evita el spinner infinito ante una excepción de `search()`.
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _addContact(Contact contact) {
    if (widget.selectedContacts.any((c) => c.id == contact.id)) return;
    widget.onChanged([...widget.selectedContacts, contact]);
    _controller.clear();
    setState(() => _results = []);
    FocusScope.of(context).unfocus();
  }

  void _removeContact(Contact contact) {
    widget.onChanged(widget.selectedContacts.where((c) => c.id != contact.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.selectedContacts.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.selectedContacts
                .map((contact) => InputChip(
                      label: Text(contact.fullName),
                      onDeleted: () => _removeContact(contact),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Contactos (opcional)',
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
          onChanged: _onQueryChanged,
        ),
        // RF7: tres estados distintos bajo el campo — buscando (spinner en el
        // propio TextField, arriba), error (mensaje real, estilo de error) y
        // sin resultados (consulta OK con lista vacía, texto tenue) frente a
        // resultados (lista). Nunca se muestran a la vez.
        if (!_isSearching && _errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline,
                    size: 16, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          )
        else if (!_isSearching &&
            _errorMessage == null &&
            _results.isEmpty &&
            _controller.text.trim().length >= 2)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sin coincidencias',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12.5,
              ),
            ),
          )
        else if (_results.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor)),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final contact = _results[i];
                return ListTile(
                  title: Text(contact.fullName),
                  subtitle: Text(contact.phoneE164),
                  onTap: () => _addContact(contact),
                );
              },
            ),
          ),
      ],
    );
  }
}
