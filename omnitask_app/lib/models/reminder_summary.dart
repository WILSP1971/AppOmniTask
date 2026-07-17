import 'package:freezed_annotation/freezed_annotation.dart';

part 'reminder_summary.freezed.dart';
part 'reminder_summary.g.dart';

/// Espejo de ReminderSummaryResponse — solo viaja embebido en el detalle de
/// una actividad (§6, §14), nunca como recurso propio.
@freezed
class ReminderSummary with _$ReminderSummary {
  const factory ReminderSummary({
    required String id,
    required DateTime remindAt,
    required String channel,
    required String status,
  }) = _ReminderSummary;

  factory ReminderSummary.fromJson(Map<String, dynamic> json) =>
      _$ReminderSummaryFromJson(json);
}
