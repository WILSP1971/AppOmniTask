import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omnitask_app/core/network/dio_client.dart';
import 'package:omnitask_app/core/storage/secure_token_storage.dart';
import 'package:omnitask_app/features/auth/application/auth_notifier.dart';
import 'package:omnitask_app/models/auth_state.dart';

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

/// Reemplaza la sesión real por una controlada por el test: build() resuelve
/// de inmediato y refreshSession() devuelve lo que el test decida, sin tocar
/// AuthRepository ni almacenamiento seguro.
class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._refreshSucceeds);
  final bool _refreshSucceeds;

  @override
  Future<AuthState> build() async => const AuthState.unauthenticated();

  @override
  Future<bool> refreshSession() async => _refreshSucceeds;
}

/// Simula el backend a nivel de transporte (no de interceptor): responde
/// 401 la primera vez y 200 después — así la petición pasa por el camino
/// real de Dio (respuesta -> validateStatus -> DioException -> onError) en
/// vez de un handler.reject() de onRequest, que no atraviesa los demás
/// interceptores de la misma forma que una respuesta HTTP real.
class _FlakyAdapter implements HttpClientAdapter {
  int _callCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _callCount++;
    if (_callCount == 1) {
      return ResponseBody.fromString(
        '{}',
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late MockSecureTokenStorage tokenStorage;

  setUp(() {
    tokenStorage = MockSecureTokenStorage();
    when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => 'stale-token');
  });

  Dio buildDio(ProviderContainer container) {
    // dioClientProvider (no DioClient directamente) es lo que entrega un Ref
    // real — DioClient exige un Ref, y ProviderContainer no lo es.
    final dio = container.read(dioClientProvider);
    dio.httpClientAdapter = _FlakyAdapter();
    return dio;
  }

  test('un 401 dispara refreshSession y reintenta la misma petición (§12, §15)', () async {
    final container = ProviderContainer(overrides: [
      authNotifierProvider.overrideWith(() => _StubAuthNotifier(true)),
      secureTokenStorageProvider.overrideWithValue(tokenStorage),
    ]);
    addTearDown(container.dispose);

    final response = await buildDio(container).get('/activities');

    expect(response.statusCode, 200);
    expect(response.data, {'ok': true});
  });

  test('si refreshSession también falla, el 401 original se propaga', () async {
    final container = ProviderContainer(overrides: [
      authNotifierProvider.overrideWith(() => _StubAuthNotifier(false)),
      secureTokenStorageProvider.overrideWithValue(tokenStorage),
    ]);
    addTearDown(container.dispose);

    await expectLater(
      buildDio(container).get('/activities'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 401)),
    );
  });
}
