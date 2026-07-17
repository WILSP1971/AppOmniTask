import 'package:freezed_annotation/freezed_annotation.dart';

import 'notification_preferences.dart';

part 'user.freezed.dart';
part 'user.g.dart';

/// Espejo de UserResponse (API, §6, §15, §16).
@freezed
class User with _$User {
  const factory User({
    required String id,
    required String fullName,
    required String email,
    required String phoneE164,
    required String timezone,
    required String role,
    required NotificationPreferences notificationPreferences,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
