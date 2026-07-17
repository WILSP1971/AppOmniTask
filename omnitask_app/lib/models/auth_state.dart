import 'package:freezed_annotation/freezed_annotation.dart';

import 'user.dart';

part 'auth_state.freezed.dart';

/// Estado de sesión (§15). `unknown` es el arranque, mientras AuthNotifier
/// intenta restaurar la sesión con el refresh token guardado — el router
/// no redirige hasta salir de ese estado.
@freezed
sealed class AuthState with _$AuthState {
  const factory AuthState.unknown() = AuthUnknown;
  const factory AuthState.unauthenticated() = AuthUnauthenticated;
  const factory AuthState.authenticated(User user) = AuthAuthenticated;
}
