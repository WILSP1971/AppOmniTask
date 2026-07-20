import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
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
    // Sin proyecto Firebase configurado no hay app por defecto — login no
    // debe fallar por eso, solo se omite el registro del dispositivo.
    if (Firebase.apps.isEmpty) return;

    // Pedir permiso es idempotente (SPEC-004 RF1): si el usuario ya
    // respondió antes, el SO no vuelve a mostrar el diálogo — seguro
    // llamarlo en cada login/registro/restauración de sesión. Si lo niega,
    // no se lanza; solo no llegarán notificaciones visibles (RNF4).
    await FirebaseMessaging.instance.requestPermission();

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    final platform = Platform.isIOS ? 'ios' : 'android';
    await ref.read(deviceRepositoryProvider).register(fcmToken: token, platform: platform);
  }
}
