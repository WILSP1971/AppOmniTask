import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'local_notifications_service.dart';
import 'notifications_providers.dart';

part 'push_message_listener.g.dart';

/// Servicio de proceso completo, no ligado a ninguna pantalla — se lee una
/// sola vez en main.dart (§17). Al llegar un mensaje con la app en primer
/// plano, muestra el banner local y refresca el badge/la bandeja sin que la
/// persona tenga que deslizar para actualizar.
@Riverpod(keepAlive: true)
class PushMessageListener extends _$PushMessageListener {
  @override
  void build() {
    // Sin firebase_options.dart (generado por `flutterfire configure` contra
    // un proyecto Firebase real, §20) no hay app por defecto — suscribirse
    // igual haría que FirebaseMessaging.instance lance en el arranque. El
    // resto de la app (calendario, contactos, backlog) no depende de esto.
    if (Firebase.apps.isEmpty) return;
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    ref.read(localNotificationsServiceProvider).show(message);
    ref.invalidate(unreadNotificationsCountProvider);
    ref.invalidate(notificationsInboxProvider);
  }
}
