import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth_state.dart';
import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/backlog/presentation/backlog_screen.dart';
import '../../features/calendar/presentation/activity_detail_screen.dart';
import '../../features/calendar/presentation/activity_edit_screen.dart';
import '../../features/calendar/presentation/calendar_screen.dart';
import '../../features/notifications/presentation/notifications_inbox_screen.dart';
import '../../features/settings/presentation/devices_screen.dart';
import '../../features/settings/presentation/notification_preferences_screen.dart';
import '../../features/settings/presentation/profile_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

/// Puente entre authNotifierProvider y el Listenable que go_router necesita
/// (§15): AsyncNotifierProvider no expone un Stream propio para observar
/// desde fuera de Riverpod, así que se usa ref.listen para llamar
/// notifyListeners() en cada cambio — sin esto, pasar de unauthenticated a
/// authenticated tras un login exitoso no movería a nadie de pantalla hasta
/// la siguiente navegación manual.
class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier(Ref ref) {
    ref.listen(authNotifierProvider, (previous, next) => notifyListeners());
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshNotifier(ref),
    redirect: (context, state) {
      final auth = ref.read(authNotifierProvider).valueOrNull;
      final isAuthRoute =
          state.matchedLocation == '/login' || state.matchedLocation == '/register';

      if (auth == null || auth is AuthUnknown) return null; // aún restaurando sesión
      final isAuthenticated = auth is AuthAuthenticated;

      if (!isAuthenticated && !isAuthRoute) return '/login';
      if (isAuthenticated && isAuthRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/', builder: (context, state) => const CalendarScreen()),
      GoRoute(path: '/backlog', builder: (context, state) => const BacklogScreen()),
      GoRoute(
        path: '/activities/new',
        builder: (context, state) => const ActivityEditScreen(),
      ),
      GoRoute(
        path: '/activities/:id',
        builder: (context, state) =>
            ActivityDetailScreen(activityId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/activities/:id/edit',
        builder: (context, state) =>
            ActivityEditScreen(activityId: state.pathParameters['id']),
      ),
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationsInboxScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/settings/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(
        path: '/settings/notifications',
        builder: (context, state) => const NotificationPreferencesScreen(),
      ),
      GoRoute(path: '/settings/devices', builder: (context, state) => const DevicesScreen()),
    ],
  );

  // Cubre los dos casos reales de deep link desde un push (§12, §17): la app
  // ya estaba en segundo plano, o el tap es lo que la abre desde cero
  // (cold start) — omitir el segundo es el bug clásico de "solo funciona a veces".
  // Sin firebase_options.dart (§20) no hay app por defecto y estas llamadas
  // lanzarían en el primer frame; se omiten hasta que Firebase esté configurado.
  if (Firebase.apps.isNotEmpty) {
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final activityId = message.data['activity_id'];
      if (activityId != null) router.push('/activities/$activityId');
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      final activityId = message?.data['activity_id'];
      if (activityId != null) router.push('/activities/$activityId');
    });
  }

  return router;
});
