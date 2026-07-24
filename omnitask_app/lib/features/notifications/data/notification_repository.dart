import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../models/notification_item.dart';
import '../../../models/paged_response.dart';

class NotificationRepository {
  NotificationRepository(this._dio);
  final Dio _dio;

  Future<PagedResponse<NotificationItem>> fetchAll({bool unreadOnly = false, int page = 1}) async {
    final response = await _dio.get('/notifications', queryParameters: {
      'unread_only': unreadOnly,
      'page': page,
    });
    return PagedResponse.fromJson(
      response.data as Map<String, dynamic>,
      (json) => NotificationItem.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<int> fetchUnreadCount() async {
    final response = await _dio.get('/notifications/unread-count');
    return response.data['count'] as int;
  }

  Future<void> acknowledge(String id) => _dio.patch('/notifications/$id/ack');
  Future<void> acknowledgeAll() => _dio.post('/notifications/ack-all');

  /// SPEC-007: borra TODO el historial de notificaciones del usuario, sin
  /// deshacer posible — la confirmación vive en la UI, no aquí.
  Future<void> clearAll() => _dio.delete('/notifications');
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(dioClientProvider)),
);
