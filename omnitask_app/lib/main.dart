import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'features/notifications/application/local_notifications_service.dart';
import 'features/notifications/application/push_message_listener.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await Firebase.initializeApp(); — requiere firebase_options.dart generado
  // con `flutterfire configure` (§20), específico de cada proyecto Firebase.

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
