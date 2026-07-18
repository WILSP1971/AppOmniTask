import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/router/app_router.dart';
import 'features/notifications/application/local_notifications_service.dart';
import 'features/notifications/application/push_message_listener.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await Firebase.initializeApp(); — requiere firebase_options.dart generado
  // con `flutterfire configure` (§20), específico de cada proyecto Firebase.

  // Sin esto, cualquier DateFormat con locale explícito (p.ej. 'es_CO' en el
  // detalle de actividad) lanza LocaleDataException al primer uso.
  await initializeDateFormatting('es_CO');

  final container = ProviderContainer();
  await container.read(localNotificationsServiceProvider).initialize();
  container.read(pushMessageListenerProvider); // servicio de proceso completo (§17)

  runApp(UncontrolledProviderScope(container: container, child: const OmniTaskApp()));
}

class OmniTaskApp extends ConsumerWidget {
  const OmniTaskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'OmniTask',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      routerConfig: router,
    );
  }
}
