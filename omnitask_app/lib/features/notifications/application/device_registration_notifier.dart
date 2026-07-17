import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/device_repository.dart';

part 'device_registration_notifier.g.dart';

/// Se llama justo después de login/registro y al restaurar sesión (§8, §15).
/// El registro es un upsert por fcm_token en el backend — reinstalar la app
/// o cambiar de cuenta reasigna el token en vez de duplicarlo.
@riverpod
class DeviceRegistration extends _$DeviceRegistration {
  @override
  FutureOr<void> build() {}

  Future<void> registerCurrentDevice() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    final platform = Platform.isIOS ? 'ios' : 'android';
    await ref.read(deviceRepositoryProvider).register(fcmToken: token, platform: platform);
  }
}
