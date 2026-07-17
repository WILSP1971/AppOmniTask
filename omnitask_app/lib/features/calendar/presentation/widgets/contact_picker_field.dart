import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/contact.dart';
import '../../../contacts/data/contact_repository.dart';

/// Autocompletar con debounce contra GET /contacts?search= (§14) — no trae
/// la lista completa de contactos al abrir el formulario; para una clínica
/// con cientos de pacientes, cargarlos todos de una vez sería innecesario.
class ContactPickerField extends ConsumerStatefulWidget {
  const ContactPickerField({super.key, required this.selectedContact, required this.onChanged});

  final Contact? selectedContact;
  final ValueChanged<Contact?> onChanged;

  @override
  ConsumerState<ContactPickerField> createState() => _ContactPickerFieldState();
}

class _ContactPickerFieldState extends ConsumerState<ContactPickerField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.selectedContact?.fullName ?? '');
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
    widget.onChanged(null);
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
        _results = results;
        _isSearching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Contacto (opcional)',
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
                  onTap: () {
                    _controller.text = contact.fullName;
                    widget.onChanged(contact);
                    setState(() => _results = []);
                    FocusScope.of(context).unfocus();
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
