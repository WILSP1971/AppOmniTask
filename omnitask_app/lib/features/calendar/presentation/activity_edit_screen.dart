import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/activity.dart';
import '../../../models/activity_draft.dart';
import '../../../models/contact.dart';
import '../application/activities_for_range_provider.dart';
import '../application/activity_form_controller.dart';
import 'widgets/contact_picker_field.dart';
import 'widgets/date_time_field.dart';
import 'widgets/meeting_field.dart';

/// Un único formulario sirve para crear, editar y "programar" una actividad
/// sin fecha (§14) — asignar fecha por primera vez y reprogramar son, para
/// el backend, el mismo PATCH.
class ActivityEditScreen extends ConsumerStatefulWidget {
  const ActivityEditScreen({super.key, this.activityId});
  final String? activityId;

  @override
  ConsumerState<ActivityEditScreen> createState() => _ActivityEditScreenState();
}

class _ActivityEditScreenState extends ConsumerState<ActivityEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _meetingUrlController = TextEditingController();
  String _type = 'appointment';
  Contact? _contact;
  bool _hasDate = true;
  DateTime? _startsAt;
  DateTime? _endsAt;
  String? _meetingProvider;
  bool _initialized = false;

  bool get _isEditing => widget.activityId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _meetingUrlController.dispose();
    super.dispose();
  }

  void _hydrateFrom(Activity? existing) {
    if (_initialized || existing == null) return;

    _titleController.text = existing.title;
    _descriptionController.text = existing.description ?? '';
    _type = existing.type;
    _hasDate = existing.startsAt != null;
    _startsAt = existing.startsAt?.toLocal();
    _endsAt = existing.endsAt?.toLocal();
    _meetingUrlController.text = existing.meetingUrl ?? '';
    _meetingProvider = existing.meetingProvider;
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      _hydrateFrom(ref.watch(activityDetailProvider(widget.activityId!)).valueOrNull);
    }

    final formState = ref.watch(activityFormControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar actividad' : 'Nueva actividad')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      items: const [
                        DropdownMenuItem(value: 'meeting', child: Text('Reunión')),
                        DropdownMenuItem(value: 'appointment', child: Text('Cita')),
                        DropdownMenuItem(value: 'task', child: Text('Tarea')),
                        DropdownMenuItem(value: 'birthday', child: Text('Cumpleaños')),
                        DropdownMenuItem(value: 'activity', child: Text('Actividad')),
                      ],
                      onChanged: (value) => setState(() => _type = value!),
                      decoration: const InputDecoration(labelText: 'Tipo'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(labelText: 'Título'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'El título es obligatorio' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(labelText: 'Descripción'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    ContactPickerField(
                      selectedContact: _contact,
                      onChanged: (contact) => setState(() => _contact = contact),
                    ),
                    SwitchListTile(
                      title: const Text('Sin fecha por ahora'),
                      subtitle: const Text('Se guarda como pendiente por programar'),
                      value: !_hasDate,
                      onChanged: (noDate) => setState(() => _hasDate = !noDate),
                    ),
                    if (_hasDate) ...[
                      DateTimeField(
                        label: 'Inicio',
                        value: _startsAt,
                        onChanged: (value) => setState(() => _startsAt = value),
                      ),
                      DateTimeField(
                        label: 'Fin',
                        value: _endsAt,
                        onChanged: (value) => setState(() => _endsAt = value),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MeetingField(
                  provider: _meetingProvider,
                  urlController: _meetingUrlController,
                  onProviderChanged: (value) => setState(() => _meetingProvider = value),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: formState.isLoading ? null : _submit,
            child: Text(_isEditing ? 'Guardar cambios' : 'Crear'),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_hasDate && _startsAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una fecha de inicio, o marca "Sin fecha por ahora"')),
      );
      return;
    }
    if (_hasDate && _startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La hora de fin debe ser posterior al inicio')),
      );
      return;
    }

    final description =
        _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim();
    final meetingUrl =
        _meetingUrlController.text.trim().isEmpty ? null : _meetingUrlController.text.trim();
    // Si no hay URL, el provider queda huérfano y no se envía: evita guardar
    // un meetingProvider sin meetingUrl (dato inconsistente).
    final meetingProvider = meetingUrl == null ? null : _meetingProvider;
    final controller = ref.read(activityFormControllerProvider.notifier);

    final saved = _isEditing
        ? await controller.updateActivity(
            widget.activityId!,
            title: _titleController.text.trim(),
            description: description,
            startsAt: _hasDate ? _startsAt : null,
            clearStartsAt: !_hasDate,
            endsAt: _hasDate ? _endsAt : null,
            clearEndsAt: !_hasDate,
            meetingUrl: meetingUrl,
            meetingProvider: meetingProvider,
          )
        : await controller.create(ActivityDraft(
            type: _type,
            title: _titleController.text.trim(),
            description: description,
            contactId: _contact?.id,
            startsAt: _hasDate ? _startsAt : null,
            endsAt: _hasDate ? _endsAt : null,
            meetingUrl: meetingUrl,
            meetingProvider: meetingProvider,
          ));

    if (saved != null && mounted) context.pop();
  }
}
