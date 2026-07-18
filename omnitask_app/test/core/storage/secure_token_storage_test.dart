import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask_app/core/storage/secure_token_storage.dart';

void main() {
  test('guarda y lee el mismo par de tokens dentro del mismo proceso', () async {
    final storage = SecureTokenStorage();
    await storage.saveTokens('access-1', 'refresh-1');

    expect(await storage.readAccessToken(), 'access-1');
    expect(await storage.readRefreshToken(), 'refresh-1');
  });

  test('clear() borra ambos tokens', () async {
    final storage = SecureTokenStorage();
    await storage.saveTokens('access-1', 'refresh-1');

    await storage.clear();

    expect(await storage.readAccessToken(), isNull);
    expect(await storage.readRefreshToken(), isNull);
  });

  // No hay disco de por medio (a propósito, §26/§27): una instancia nueva —
  // que es justo lo que un proceso nuevo tras cerrar la app produce — nunca
  // ve los tokens de la instancia anterior, sin necesidad de simular el ciclo
  // de vida de Android/iOS para probarlo.
  test('una instancia nueva de SecureTokenStorage no ve los tokens de otra (equivalente a reabrir la app)', () async {
    final storageDeLaSesionAnterior = SecureTokenStorage();
    await storageDeLaSesionAnterior.saveTokens('access-1', 'refresh-1');

    final storageTrasReabrirLaApp = SecureTokenStorage();

    expect(await storageTrasReabrirLaApp.readAccessToken(), isNull);
    expect(await storageTrasReabrirLaApp.readRefreshToken(), isNull);
  });
}
