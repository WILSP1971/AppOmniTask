import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/notifications/application/local_notifications_service.dart';
import 'features/notifications/application/push_message_listener.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Proyecto omnitask-agenda (SPEC-004 §A) — el mismo que ya usa el backend
  // en producción vía firebase-admin.json. Los guards `Firebase.apps.isEmpty`
  // en device_registration_notifier.dart/push_message_listener.dart/
  // app_router.dart/devices_provider.dart dejan de saltarse desde aquí.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Sin esto, cualquier DateFormat con locale explícito (p.ej. 'es_CO' en el
  // detalle de actividad) lanza LocaleDataException al primer uso.
  await initializeDateFormatting('es_CO');

  final container = ProviderContainer();
  await container.read(localNotificationsServiceProvider).initialize();
  container
      .read(pushMessageListenerProvider); // servicio de proceso completo (§17)

  runApp(UncontrolledProviderScope(
      container: container, child: const OmniTaskApp()));
}

class OmniTaskApp extends ConsumerWidget {
  const OmniTaskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'OmniTask',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'CO')],
      locale: const Locale('es', 'CO'),
      routerConfig: router,
    );
  }
}
