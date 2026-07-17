import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_preferences.freezed.dart';
part 'notification_preferences.g.dart';

/// Espejo de NotificationPreferencesDto (API, §16) — canal por defecto y
/// anticipación de los recordatorios automáticos de una actividad nueva.
@freezed
class NotificationPreferences with _$NotificationPreferences {
  const factory NotificationPreferences({
    @Default('both') String defaultChannel,
    @Default([1440, 60]) List<int> reminderOffsetsMinutes,
  }) = _NotificationPreferences;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      _$NotificationPreferencesFromJson(json);
}
