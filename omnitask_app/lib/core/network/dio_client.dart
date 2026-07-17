import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../config/api_config.dart';
import '../storage/secure_token_storage.dart';

/// Adjunta el access token a cada petición y, ante un 401, dispara el mismo
/// flujo de /auth/refresh (con rotación) que usa AuthNotifier al restaurar
/// sesión — es la misma función, dos disparadores distintos (§12, §15).
class DioClient {
  DioClient(this._ref) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _ref.read(secureTokenStorageProvider).readAccessToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            final refreshed = await _ref.read(authNotifierProvider.notifier).refreshSession();
            if (refreshed) {
              final retryRequest = await _dio.fetch(error.requestOptions);
              return handler.resolve(retryRequest);
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Ref _ref;
  final Dio _dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));

  Dio get instance => _dio;
}

final dioClientProvider = Provider<Dio>((ref) => DioClient(ref).instance);

/// Extrae el mensaje real del sobre {"error": {"code", "message"}} de la API
/// (§6) en vez de mostrar un genérico "Error 401" / "Error 500".
String mapApiError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final message = data['error']?['message'];
      if (message is String) return message;
    }
  }
  return 'Algo falló. Intenta de nuevo.';
}
