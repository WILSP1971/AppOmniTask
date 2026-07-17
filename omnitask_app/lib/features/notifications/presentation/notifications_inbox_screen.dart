import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/notification_item.dart';
import '../data/notification_repository.dart';
import '../application/notifications_providers.dart';

class NotificationsInboxScreen extends ConsumerWidget {
  const NotificationsInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsInboxProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(notificationRepositoryProvider).acknowledgeAll();
              ref.invalidate(notificationsInboxProvider);
              ref.invalidate(unreadNotificationsCountProvider);
            },
            child: const Text('Marcar todas'),
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (paged) => paged.items.isEmpty
            ? const Center(child: Text('No tienes notificaciones todavía'))
            : ListView.separated(
                itemCount: paged.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _NotificationTile(item: paged.items[i]),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No se pudo cargar la bandeja'),
              TextButton(
                onPressed: () => ref.invalidate(notificationsInboxProvider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});
  final NotificationItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnread = item.acknowledgedAt == null;

    return ListTile(
      tileColor:
          isUnread ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
      leading: Icon(
        item.channel == 'whatsapp' ? Icons.chat_outlined : Icons.notifications_outlined,
      ),
      title: Text(
        item.summary,
        style: TextStyle(fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal),
      ),
      subtitle: Text(_relativeTime(item.createdAt)),
      trailing: _StatusDot(status: item.status),
      onTap: () async {
        if (isUnread) {
          await ref.read(notificationRepositoryProvider).acknowledge(item.id);
          ref.invalidate(notificationsInboxProvider);
          ref.invalidate(unreadNotificationsCountProvider);
        }
        if (item.activityId != null && context.mounted) {
          context.push('/activities/${item.activityId}');
        }
      },
    );
  }
}

/// Pinta el status de entrega — informativo sobre todo para WhatsApp, ya que
/// FCM no reporta al backend cuándo un push se entrega o se lee (§17).
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'read' => Colors.green,
      'delivered' => Colors.blue,
      'sent' => Colors.grey,
      'failed' => Colors.red,
      _ => Colors.grey,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

String _relativeTime(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime.toLocal());
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return DateFormat('d MMM, HH:mm').format(dateTime.toLocal());
}
