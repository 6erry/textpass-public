import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/app_notification.dart';
import '../services/notification_service.dart';

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    this.onTap,
  });

  final AppNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        if (!notification.isRead) {
          NotificationService().markAsRead(notification.id);
        }
        onTap?.call();
      },
      child: Container(
        color: notification.isRead ? Colors.white : Colors.blue.shade50,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIcon(),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeago.format(notification.createdAt, locale: 'ja'),
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (!notification.isRead)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 8),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (notification.fromUid != null) {
      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(notification.fromUid)
            .get(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final photoUrl = data?['photoURL'] as String?;

          return CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null
                ? const Icon(Icons.person, color: Colors.grey)
                : null,
          );
        },
      );
    }

    IconData iconData;
    Color color;

    switch (notification.type) {
      case NotificationType.like:
        iconData = Icons.favorite;
        color = Colors.pink;
        break;
      case NotificationType.comment:
        iconData = Icons.chat_bubble;
        color = Colors.green;
        break;
      case NotificationType.transaction:
        iconData = Icons.shopping_bag;
        color = Colors.blue;
        break;
      case NotificationType.system:
        iconData = Icons.info;
        color = Colors.orange;
        break;
      case NotificationType.event:
        iconData = Icons.event;
        color = Colors.purple;
        break;
      case NotificationType.bundle:
        iconData = Icons.library_books_outlined;
        color = Colors.indigo;
        break;
      case NotificationType.message: // Added
        iconData = Icons.mail;
        color = Colors.teal;
        break;
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: color.withValues(alpha: 0.1),
      child: Icon(iconData, color: color, size: 24),
    );
  }
}
