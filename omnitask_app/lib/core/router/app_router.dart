import 'dart:async';

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

/// Adapta el Stream del provider a un Listenable (§15) para que go_router
/// reevalúe `redirect` cada vez que AuthState cambia — sin esto, pasar de
/// unauthenticated a authenticated tras un login exitoso no movería a nadie
/// de pantalla hasta la siguiente navegación manual.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(authNotifierProvider.notifier);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authNotifier.stream),
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
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final activityId = message.data['activity_id'];
    if (activityId != null) router.push('/activities/$activityId');
  });

  FirebaseMessaging.instance.getInitialMessage().then((message) {
    final activityId = message?.data['activity_id'];
    if (activityId != null) router.push('/activities/$activityId');
  });

  return router;
});
