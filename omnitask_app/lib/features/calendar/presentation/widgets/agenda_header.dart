import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../activity_colors.dart';

/// Encabezado de la Agenda (SPEC-001 §2): mes en azul con navegación ‹ ›,
/// campana con badge rojo (→ /notifications) y lupa de búsqueda sobre las
/// actividades ya cargadas en el mes visible. Reemplaza visualmente al AppBar
/// que tenía calendar_screen.dart, conservando sus mismas acciones.
///
/// Al ser un `PreferredSizeWidget` a medida (no un `AppBar` real), Flutter no
/// agrega solo el botón de menú del Drawer como sí hace con un AppBar de
/// verdad — sin el ☰ explícito de aquí, el Drawer (y "Actividades sin
/// programar" dentro de él) quedaba inalcanzable desde el Home (SPEC-004 RF3,
/// bug real reportado en producción v1.0.11).
class AgendaHeader extends StatelessWidget implements PreferredSizeWidget {
  const AgendaHeader({
    super.key,
    required this.focusedDay,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.unreadNotificationsCount,
    required this.onSearchChanged,
  });

  final DateTime focusedDay;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final int unreadNotificationsCount;
  final ValueChanged<String> onSearchChanged;

  @override
  Size get preferredSize => const Size.fromHeight(124);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final monthLabel =
        DateFormat.yMMMM('es_CO').format(focusedDay).toUpperCase();

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Abrir menú',
                  icon: const Icon(Icons.menu),
                  color: colorScheme.primary,
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
                IconButton(
                  tooltip: 'Mes anterior',
                  icon: const Icon(Icons.chevron_left),
                  color: colorScheme.primary,
                  onPressed: onPreviousMonth,
                ),
                Expanded(
                  child: Text(
                    monthLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Mes siguiente',
                  icon: const Icon(Icons.chevron_right),
                  color: colorScheme.primary,
                  onPressed: onNextMonth,
                ),
                IconButton(
                  tooltip: 'Notificaciones',
                  icon: Badge(
                    backgroundColor: kAccentPink,
                    isLabelVisible: unreadNotificationsCount > 0,
                    label: Text('$unreadNotificationsCount'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  onPressed: () => context.push('/notifications'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                onChanged: onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar en mis citas',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHigh,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
