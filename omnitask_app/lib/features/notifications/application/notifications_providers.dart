import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../models/notification_item.dart';
import '../../../models/paged_response.dart';
import '../data/notification_repository.dart';

part 'notifications_providers.g.dart';

/// Endpoint propio y liviano (§17): alimenta el badge de la campana sin
/// traer el listado completo solo para contar cuántos faltan por leer.
@riverpod
Future<int> unreadNotificationsCount(UnreadNotificationsCountRef ref) {
  return ref.watch(notificationRepositoryProvider).fetchUnreadCount();
}

@riverpod
Future<PagedResponse<NotificationItem>> notificationsInbox(NotificationsInboxRef ref) {
  return ref.watch(notificationRepositoryProvider).fetchAll();
}
