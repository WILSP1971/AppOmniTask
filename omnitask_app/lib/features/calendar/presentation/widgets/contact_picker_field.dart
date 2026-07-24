import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isSearching = true);
      final results = await ref.read(contactRepositoryProvider).search(query.trim());
      if (!mounted) return;
      setState(() {
        // No ofrecer/duplicar un contacto ya seleccionado (§3 RF1, CA5).
        _results = results
            .where((c) => !widget.selectedContacts.any((s) => s.id == c.id))
            .toList();
        _isSearching = false;
      });
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
        if (_results.isNotEmpty)
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
