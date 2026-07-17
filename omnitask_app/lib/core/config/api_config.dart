import 'package:flutter/foundation.dart';

/// URL base de la API — resuelta en tiempo de compilación (§19). Sin
/// --dart-define explícito, un build de release cae en la URL real y uno de
/// depuración en el emulador de Android (10.0.2.2 = localhost del host); en
/// el simulador de iOS usar --dart-define=API_BASE_URL=http://localhost:8000/api/v1.
class ApiConfig {
  static const _prodBaseUrl = 'https://appsintranet.esculapiosis.com/APIOmniTask/api/v1';
  static const _devBaseUrl = 'http://10.0.2.2:8000/api/v1';

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: kReleaseMode ? _prodBaseUrl : _devBaseUrl,
  );
}
