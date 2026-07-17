import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_item.freezed.dart';
part 'notification_item.g.dart';

/// Espejo de NotificationResponse (API, §17) — historial de lo que ya se
/// envió (push/WhatsApp), distinto de la bandeja de "pendientes por
/// programar" (§12) que es sobre actividades sin fecha.
@freezed
class NotificationItem with _$NotificationItem {
  const factory NotificationItem({
    required String id,
    required String channel,
    required String status,
    required String summary,
    String? activityId,
    required DateTime createdAt,
    DateTime? acknowledgedAt,
  }) = _NotificationItem;

  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      _$NotificationItemFromJson(json);
}
