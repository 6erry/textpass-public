import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/app_notification.dart';
import '../models/book.dart';
import '../models/event.dart';
import '../services/notification_service.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/notification_tile.dart';
import 'book_detail_screen.dart';
import 'bundle_requests_screen.dart';
import 'event/event_detail_screen.dart';
import 'transaction_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('ja', timeago.JaMessages());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お知らせ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'すべて既読にする',
            onPressed: () {
              NotificationService().markAllAsRead();
            },
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: NotificationService().getNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('エラーが発生しました: ${snapshot.error}'));
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.notifications_off_outlined,
              title: 'お知らせはありません',
              message: '新しいお知らせが届くとここに表示されます',
            );
          }

          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return NotificationTile(
                notification: notification,
                onTap: () => _handleNotificationTap(context, notification),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _handleNotificationTap(
      BuildContext context, AppNotification notification) async {
    if (notification.relatedId == null) return;
    final currentContext = context;

    // Show loading indicator
    showDialog(
      context: currentContext,
      barrierDismissible: false,
      builder: (dialogContext) =>
          const Center(child: CircularProgressIndicator()),
    );

    try {
      switch (notification.type) {
        case NotificationType.like:
        case NotificationType.comment:
          // Assume relatedId is bookId for now (since we implemented it for books)
          // TODO: Distinguish between Book and Event likes if we implement Event likes later
          final doc = await FirebaseFirestore.instance
              .collection('books')
              .doc(notification.relatedId)
              .get();

          if (!currentContext.mounted) return;
          Navigator.pop(currentContext); // Hide loading

          if (doc.exists) {
            final book = Book.fromFirestore(doc);
            if (currentContext.mounted) {
              Navigator.push(
                currentContext,
                MaterialPageRoute(
                  builder: (context) => BookDetailScreen(book: book),
                ),
              );
            }
          } else {
            if (currentContext.mounted) {
              AppToast.show(currentContext, 'この商品は削除された可能性があります');
            }
          }
          break;

        case NotificationType.transaction:
        case NotificationType.message: // Added
          // relatedId is chatRoomId (usually) or bookId?
          // Let's assume relatedId is chatRoomId for transaction notifications
          final chatDoc = await FirebaseFirestore.instance
              .collection('chat_rooms')
              .doc(notification.relatedId)
              .get();

          if (!chatDoc.exists) {
            if (!currentContext.mounted) return;
            Navigator.pop(currentContext);
            AppToast.show(currentContext, 'この取引は存在しません');
            return;
          }

          final bookId = chatDoc.data()?['bookId'];
          if (bookId == null) {
            if (!currentContext.mounted) return;
            Navigator.pop(currentContext);
            return;
          }

          final bookDoc = await FirebaseFirestore.instance
              .collection('books')
              .doc(bookId)
              .get();

          if (!currentContext.mounted) return;
          Navigator.pop(currentContext); // Hide loading

          if (bookDoc.exists) {
            final book = Book.fromFirestore(bookDoc);
            if (currentContext.mounted) {
              Navigator.push(
                currentContext,
                MaterialPageRoute(
                  builder: (context) => TransactionScreen(
                    chatRoomId: notification.relatedId!,
                    book: book,
                  ),
                ),
              );
            }
          }
          break;

        case NotificationType.event:
          final doc = await FirebaseFirestore.instance
              .collection('events')
              .doc(notification.relatedId)
              .get();

          if (!currentContext.mounted) return;
          Navigator.pop(currentContext); // Hide loading

          if (doc.exists) {
            final event = Event.fromFirestore(doc);
            if (currentContext.mounted) {
              Navigator.push(
                currentContext,
                MaterialPageRoute(
                  builder: (context) => EventDetailScreen(event: event),
                ),
              );
            }
          } else {
            if (currentContext.mounted) {
              AppToast.show(currentContext, 'このイベントは削除された可能性があります');
            }
          }
          break;

        case NotificationType.bundle:
          if (currentContext.mounted) {
            Navigator.pop(currentContext);
            Navigator.push(
              currentContext,
              MaterialPageRoute(
                builder: (context) => const BundleRequestsScreen(),
              ),
            );
          }
          break;

        case NotificationType.system:
          if (currentContext.mounted) {
            Navigator.pop(currentContext); // Hide loading
          }
          // Do nothing or show dialog
          break;
      }
    } catch (e) {
      if (currentContext.mounted) {
        Navigator.pop(currentContext); // Hide loading
        AppToast.show(currentContext, 'エラーが発生しました: $e');
      }
    }
  }
}
