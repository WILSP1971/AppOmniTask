import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omnitask_app/core/storage/secure_token_storage.dart';
import 'package:omnitask_app/features/auth/application/auth_notifier.dart';
import 'package:omnitask_app/features/auth/data/auth_repository.dart';
import 'package:omnitask_app/features/notifications/application/device_registration_notifier.dart';
import 'package:omnitask_app/models/auth_state.dart';
import 'package:omnitask_app/models/notification_preferences.dart';
import 'package:omnitask_app/models/user.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

// Evita que AuthNotifier dispare FirebaseMessaging.instance.getToken() (que
// necesita canales de plataforma no disponibles en flutter test) — el
// registro de dispositivo es un efecto secundario documentado, no parte de
// la lógica de sesión que este archivo prueba (§15).
class FakeDeviceRegistration extends DeviceRegistration {
  @override
  FutureOr<void> build() {}

  @override
  Future<void> registerCurrentDevice() async {}
}

const _user = User(
  id: 'u1',
  fullName: 'María Fernanda',
  email: 'maria@clinicacampbell.com.co',
  phoneE164: '+573000000000',
  timezone: 'America/Bogota',
  role: 'professional',
  notificationPreferences: NotificationPreferences(),
);

void main() {
  late MockAuthRepository authRepository;
  late MockSecureTokenStorage tokenStorage;
  late ProviderContainer container;

  setUp(() {
    authRepository = MockAuthRepository();
    tokenStorage = MockSecureTokenStorage();

    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(authRepository),
      secureTokenStorageProvider.overrideWithValue(tokenStorage),
      deviceRegistrationProvider.overrideWith(FakeDeviceRegistration.new),
    ]);
    addTearDown(container.dispose);
  });

  group('build() — restaurar sesión al arrancar', () {
    test('sin refresh token guardado, queda unauthenticated', () async {
      when(() => tokenStorage.readRefreshToken()).thenAnswer((_) async => null);

      final state = await container.read(authNotifierProvider.future);
      expect(state, const AuthState.unauthenticated());
    });

    test('con un refresh token válido, restaura la sesión autenticada', () async {
      when(() => tokenStorage.readRefreshToken()).thenAnswer((_) async => 'old-refresh');
      when(() => authRepository.refresh('old-refresh'))
          .thenAnswer((_) async => ('new-access', 'new-refresh'));
      when(() => tokenStorage.saveTokens(any(), any())).thenAnswer((_) async {});
      when(() => authRepository.fetchMe()).thenAnswer((_) async => _user);

      final state = await container.read(authNotifierProvider.future);
      expect(state, const AuthState.authenticated(_user));
    });

    test('si el refresh falla al restaurar, limpia el storage y queda unauthenticated', () async {
      when(() => tokenStorage.readRefreshToken()).thenAnswer((_) async => 'expired-refresh');
      when(() => authRepository.refresh('expired-refresh')).thenThrow(Exception('401'));
      when(() => tokenStorage.clear()).thenAnswer((_) async {});

      final state = await container.read(authNotifierProvider.future);
      expect(state, const AuthState.unauthenticated());
      verify(() => tokenStorage.clear()).called(1);
    });
  });

  group('login', () {
    test('éxito guarda los tokens y autentica con el usuario', () async {
      when(() => tokenStorage.readRefreshToken()).thenAnswer((_) async => null);
      await container.read(authNotifierProvider.future);

      when(() => authRepository.login('maria@clinicacampbell.com.co', 'secreta123'))
          .thenAnswer((_) async => ('access-1', 'refresh-1'));
      when(() => tokenStorage.saveTokens('access-1', 'refresh-1')).thenAnswer((_) async {});
      when(() => authRepository.fetchMe()).thenAnswer((_) async => _user);

      await container
          .read(authNotifierProvider.notifier)
          .login('maria@clinicacampbell.com.co', 'secreta123');

      final state = container.read(authNotifierProvider);
      expect(state.value, const AuthState.authenticated(_user));
      verify(() => tokenStorage.saveTokens('access-1', 'refresh-1')).called(1);
    });

    test('credenciales inválidas dejan el estado en error, no autenticado', () async {
      when(() => tokenStorage.readRefreshToken()).thenAnswer((_) async => null);
      await container.read(authNotifierProvider.future);

      when(() => authRepository.login(any(), any())).thenThrow(Exception('401'));

      await container.read(authNotifierProvider.notifier).login('x@x.com', 'mal');

      final state = container.read(authNotifierProvider);
      expect(state.hasError, isTrue);
      expect(state.value, isNot(isA<AuthAuthenticated>()));
    });
  });

  group('logout', () {
    test('revoca el refresh token y limpia la sesión', () async {
      // build() intenta restaurar sesión con este mismo refresh token antes
      // de que el test llegue a probar logout() — hay que dejarlo resolver
      // limpio a "autenticado", si no refreshSession() lo atrapa como un
      // fallo y deja stubs sin usar a mitad de camino.
      when(() => tokenStorage.readRefreshToken()).thenAnswer((_) async => 'refresh-1');
      when(() => authRepository.refresh('refresh-1'))
          .thenAnswer((_) async => ('access-1', 'refresh-2'));
      when(() => tokenStorage.saveTokens(any(), any())).thenAnswer((_) async {});
      when(() => authRepository.fetchMe()).thenAnswer((_) async => _user);
      await container.read(authNotifierProvider.future);

      when(() => authRepository.logout('refresh-1')).thenAnswer((_) async {});
      when(() => tokenStorage.clear()).thenAnswer((_) async {});

      await container.read(authNotifierProvider.notifier).logout();

      final state = container.read(authNotifierProvider);
      expect(state.value, const AuthState.unauthenticated());
      verify(() => authRepository.logout('refresh-1')).called(1);
      verify(() => tokenStorage.clear()).called(1);
    });
  });
}
