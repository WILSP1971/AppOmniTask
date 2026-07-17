import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// El valor y el resultado de los pickers se manejan siempre en hora local
/// del dispositivo (§12) — la conversión a UTC ocurre en un único lugar,
/// justo antes de armar la petición, nunca dentro de este widget.
class DateTimeField extends StatelessWidget {
  const DateTimeField({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(
        value == null ? 'Seleccionar' : DateFormat('d MMM yyyy · HH:mm').format(value!),
      ),
      trailing: const Icon(Icons.edit_calendar_outlined),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 730)),
        );
        if (date == null || !context.mounted) return;

        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value ?? DateTime.now()),
        );
        if (time == null) return;

        onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
    );
  }
}
