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
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    ref.read(localNotificationsServiceProvider).show(message);
    ref.invalidate(unreadNotificationsCountProvider);
    ref.invalidate(notificationsInboxProvider);
  }
}
