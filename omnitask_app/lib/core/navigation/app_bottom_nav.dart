import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/calendar/presentation/activity_colors.dart';

/// Barra flotante redondeada de 5 slots (SPEC-001 §2): tema (no-funcional por
/// ahora — la app no tiene toggle claro/oscuro implementado, §16 de esta
/// SPEC), calendario (/), FAB central "+" (/activities/new), notificaciones
/// (/notifications) y ajustes (/settings). Usa rutas EXISTENTES del router
/// (C5) — convive con el Drawer, no lo reemplaza.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentLocation = GoRouterState.of(context).matchedLocation;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const _NavIcon(
              icon: Icons.dark_mode_outlined,
              tooltip: 'Tema (próximamente)',
              selected: false,
              onTap: null,
            ),
            _NavIcon(
              icon: Icons.calendar_month_outlined,
              tooltip: 'Calendario',
              selected: currentLocation == '/',
              onTap: () {
                if (currentLocation != '/') context.go('/');
              },
            ),
            _FabSlot(
              onTap: () => context.push('/activities/new'),
            ),
            _NavIcon(
              icon: Icons.notifications_outlined,
              tooltip: 'Notificaciones',
              selected: currentLocation == '/notifications',
              onTap: () {
                if (currentLocation != '/notifications') {
                  context.push('/notifications');
                }
              },
            ),
            _NavIcon(
              icon: Icons.settings_outlined,
              tooltip: 'Ajustes',
              selected: currentLocation == '/settings',
              onTap: () {
                if (currentLocation != '/settings') {
                  context.push('/settings');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final disabled = onTap == null;
    final color = selected
        ? colorScheme.primary
        : disabled
            // Opacidad reducida (a11y/UX, no solo el tooltip) para que se lea
            // como "aún no disponible" y no como un botón roto sin respuesta.
            ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
            : colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: color),
      ),
    );
  }
}

class _FabSlot extends StatelessWidget {
  const _FabSlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Nueva actividad',
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: kAccentPurpleFab,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}
