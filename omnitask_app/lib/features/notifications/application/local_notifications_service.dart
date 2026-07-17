import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// FCM no muestra una notificación de sistema con la app en primer plano, en
/// ninguna de las dos plataformas (§17) — este servicio es el puente para
/// que igual se vea algo con la app abierta.
class LocalNotificationsService {
  LocalNotificationsService(this._plugin);
  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
    );
  }

  Future<void> show(RemoteMessage message) {
    return _plugin.show(
      id: message.hashCode,
      title: message.notification?.title ?? 'OmniTask',
      body: message.notification?.body ?? '',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('reminders', 'Recordatorios'),
      ),
      payload: message.data['activity_id'] as String?,
    );
  }
}

final localNotificationsServiceProvider = Provider<LocalNotificationsService>(
  (ref) => LocalNotificationsService(FlutterLocalNotificationsPlugin()),
);
