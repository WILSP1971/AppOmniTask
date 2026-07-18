import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/secure_token_storage.dart';
import '../../../models/auth_state.dart';
import '../../../models/notification_preferences.dart';
import '../../notifications/application/device_registration_notifier.dart';
import '../data/auth_repository.dart';

part 'auth_notifier.g.dart';

/// Única puerta hacia el estado de sesión (§15). El router reacciona a este
/// provider (core/router/app_router.dart) — login/registro/logout nunca
/// navegan manualmente, solo cambian este estado.
@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  Future<AuthState> build() async {
    final refreshToken = await ref.watch(secureTokenStorageProvider).readRefreshToken();
    if (refreshToken == null) return const AuthState.unauthenticated();
    return _restoreSession();
  }

  Future<AuthState> _restoreSession() async {
    final refreshed = await _tryRefresh();
    if (!refreshed) return const AuthState.unauthenticated();

    final user = await ref.read(authRepositoryProvider).fetchMe();
    await ref.read(deviceRegistrationProvider.notifier).registerCurrentDevice();
    return AuthState.authenticated(user);
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final (accessToken, refreshToken) = await repo.login(email, password);
      await ref.read(secureTokenStorageProvider).saveTokens(accessToken, refreshToken);

      final user = await repo.fetchMe();
      await ref.read(deviceRegistrationProvider.notifier).registerCurrentDevice();
      return AuthState.authenticated(user);
    });
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required String phoneE164,
    required String timezone,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final (user, accessToken, refreshToken) = await repo.register(
        fullName: fullName,
        email: email,
        password: password,
        phoneE164: phoneE164,
        timezone: timezone,
      );
      await ref.read(secureTokenStorageProvider).saveTokens(accessToken, refreshToken);
      await ref.read(deviceRegistrationProvider.notifier).registerCurrentDevice();
      return AuthState.authenticated(user);
    });
  }

  /// Solo el efecto secundario (leer/guardar/limpiar tokens), sin tocar
  /// `state` — build() la llama antes de haber retornado un valor, y mutar
  /// `state` en ese punto corrompe el ciclo de vida del provider (quedaba
  /// atascado entre restaurar sesión y redirigir, el "loop" al abrir la app).
  Future<bool> _tryRefresh() async {
    final storage = ref.read(secureTokenStorageProvider);
    final refreshToken = await storage.readRefreshToken();
    if (refreshToken == null) return false;

    try {
      final (accessToken, newRefreshToken) =
          await ref.read(authRepositoryProvider).refresh(refreshToken);
      await storage.saveTokens(accessToken, newRefreshToken);
      return true;
    } catch (_) {
      await storage.clear();
      return false;
    }
  }

  /// Usada por el interceptor de Dio ante un 401 (core/network) — a
  /// diferencia de _tryRefresh(), build() ya terminó en este punto, así que
  /// sí es seguro mutar `state` para forzar el logout reactivo.
  Future<bool> refreshSession() async {
    final refreshed = await _tryRefresh();
    if (!refreshed) state = const AsyncData(AuthState.unauthenticated());
    return refreshed;
  }

  Future<void> logout() async {
    final storage = ref.read(secureTokenStorageProvider);
    final refreshToken = await storage.readRefreshToken();
    if (refreshToken != null) {
      await ref.read(authRepositoryProvider).logout(refreshToken).catchError((_) {});
    }
    await storage.clear();
    state = const AsyncData(AuthState.unauthenticated());
  }

  Future<void> updateProfile({
    String? fullName,
    String? phoneE164,
    String? timezone,
    NotificationPreferences? preferences,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await ref.read(authRepositoryProvider).updateProfile(
            fullName: fullName,
            phoneE164: phoneE164,
            timezone: timezone,
            preferences: preferences,
          );
      return AuthState.authenticated(user);
    });
  }
}
