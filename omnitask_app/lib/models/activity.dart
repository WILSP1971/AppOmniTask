import 'package:freezed_annotation/freezed_annotation.dart';

import 'reminder_summary.dart';

part 'activity.freezed.dart';
part 'activity.g.dart';

/// Espejo de ActivityResponse (API, §6, §9, §14). `startsAt` nullable es un
/// estado de primera clase (actividad "sin fecha", §3) — nunca un valor
/// centinela. `reminders` solo viene poblado en el detalle (GET /activities/{id}).
@freezed
class Activity with _$Activity {
  const factory Activity({
    required String id,
    required String userId,
    String? contactId,
    required String type,
    required String title,
    String? description,
    required String status,
    DateTime? startsAt,
    DateTime? endsAt,
    required String timezone,
    String? location,
    required DateTime createdAt,
    required DateTime updatedAt,
    // SPEC-003 (§6, §3 RF1): reunión manual (Meet/Teams/otro), opcional.
    String? meetingUrl,
    String? meetingProvider,
    @Default(<ReminderSummary>[]) List<ReminderSummary> reminders,
  }) = _Activity;

  factory Activity.fromJson(Map<String, dynamic> json) => _$ActivityFromJson(json);
}
