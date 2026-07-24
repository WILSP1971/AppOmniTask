import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../models/activity.dart';
import 'appointment_card.dart';

/// "Mis citas" (SPEC-001 §2) — y, con otro [title], la sección "Pendientes
/// por programar" del Home (SPEC-004 RF4): mismo componente, misma tarjeta
/// (`AppointmentCard` ya maneja `startsAt == null` mostrando "--" en el badge
/// de fecha), sin nada nuevo que mantener.
/// Título + botón "+ Agregar" (→ /activities/new) y la lista de tarjetas.
///
/// [dayColor] (SPEC-005 RF1): si se da, todas las tarjetas comparten ese color
/// (el del día seleccionado en el calendario) en vez de derivarlo cada una de
/// su propio tipo. "Pendientes por programar" no tiene día — se deja en null
/// y cada tarjeta sigue coloreando por tipo como antes.
class AppointmentsSection extends StatelessWidget {
  const AppointmentsSection({
    super.key,
    required this.activities,
    required this.emptyLabel,
    this.title = 'Mis citas',
    this.dayColor,
  });

  final List<Activity> activities;
  final String emptyLabel;
  final String title;
  final Color? dayColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            TextButton.icon(
              onPressed: () => context.push('/activities/new'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (activities.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                emptyLabel,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activities.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) =>
                AppointmentCard(activity: activities[index], color: dayColor),
          ),
      ],
    );
  }
}
