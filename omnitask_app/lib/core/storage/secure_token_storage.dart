import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Access/refresh token solo en memoria del proceso — deliberado, no un
/// descuido: si se guardaran en disco (keystore/keychain), la sesión
/// sobreviviría a que el usuario deslice la app para cerrarla. Al morir el
/// proceso (cierre real, no solo pasar a segundo plano) no queda nada que
/// restaurar y la próxima apertura pide login de nuevo.
class SecureTokenStorage {
  String? _accessToken;
  String? _refreshToken;

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  Future<String?> readAccessToken() async => _accessToken;
  Future<String?> readRefreshToken() async => _refreshToken;

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
  }
}

final secureTokenStorageProvider = Provider<SecureTokenStorage>(
  (ref) => SecureTokenStorage(),
);
