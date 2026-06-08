import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../utils/navigator_key.dart';
import '../routes/app_router.dart';
import '../models/event.dart';
import '../models/app_notification.dart';
import '../models/class_reminder.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize Timezone
      tz_data.initializeTimeZones();
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      // print('NotificationService: Local timezone set to $timeZoneName');

      // 1. Request Permission
      NotificationSettings settings =
          await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted permission');
      } else {
        debugPrint('User declined or has not accepted permission');
        // We continue initialization even if permission is denied,
        // as local notifications might still work or permissions can be granted later.
      }

      // Request Exact Alarms Permission (Android 12+)
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestExactAlarmsPermission();
      }

      // 2. Initialize Local Notifications (for foreground display)
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // Note: iOS permissions are handled by firebase_messaging requestPermission
      const DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings();

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
      );

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          if (details.payload != null) {
            _handlePayload(details.payload!);
          }
        },
      );

      // 3. Handle Foreground Messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');

        if (message.notification != null) {
          debugPrint(
              'Message also contained a notification: ${message.notification}');
          _showLocalNotification(message);
        }
      });

      // 4. Handle Background/Terminated Messages
      // When app is opened from a terminated state
      RemoteMessage? initialMessage =
          await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessage(initialMessage);
      }

      // When app is opened from background state
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

      // 5. Get and Save Token
      await _saveTokenToDatabase();
      _firebaseMessaging.onTokenRefresh.listen(_saveTokenToDatabase);

      _isInitialized = true;
    } catch (e, stackTrace) {
      debugPrint('NotificationService: Initialization failed: $e');
      debugPrint(stackTrace.toString());
      // Consider reporting to Crashlytics
    }
  }

  void _handleMessage(RemoteMessage message) {
    final type = message.data['type'];
    if (type == 'chat') {
      final chatId = message.data['chatId'];
      if (chatId != null) {
        navigatorKey.currentState?.pushNamed('/chat_room', arguments: chatId);
      }
    } else if (type == 'bundle') {
      navigatorKey.currentState?.pushNamed(AppRouter.bundleRequests);
    }
  }

  void _handlePayload(String payload) {
    // Payload format: "type:id"
    final parts = payload.split(':');
    if (parts.length == 2 && parts[0] == 'chat') {
      final chatId = parts[1];
      navigatorKey.currentState?.pushNamed('/chat_room', arguments: chatId);
    } else if (payload == 'bundle') {
      navigatorKey.currentState?.pushNamed(AppRouter.bundleRequests);
    }
  }

  Future<void> _saveTokenToDatabase([String? token]) async {
    if (token == null &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      final apnsToken = await _firebaseMessaging.getAPNSToken();
      if (apnsToken == null) {
        debugPrint('NotificationService: APNS token is not ready yet.');
        return;
      }
    }

    String? fcmToken = token ?? await _firebaseMessaging.getToken();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null && fcmToken != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmTokens': FieldValue.arrayUnion([fcmToken]),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null && android != null) {
      // Construct payload
      String? payload;
      if (message.data['type'] == 'chat' && message.data['chatId'] != null) {
        payload = 'chat:${message.data['chatId']}';
      } else if (message.data['type'] == 'bundle') {
        payload = 'bundle';
      }

      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel', // id
            'High Importance Notifications', // title
            channelDescription:
                'This channel is used for important notifications.',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    }
  }

  // Call this on logout to remove token
  Future<void> deleteToken() async {
    // Ideally remove the specific token from Firestore, but for now just delete locally
    await _firebaseMessaging.deleteToken();
  }

  // Schedule Event Notification
  Future<void> scheduleEventNotification(Event event) async {
    // Schedule for 1 hour before start
    final scheduledDate = event.startAt.subtract(const Duration(hours: 1));
    if (scheduledDate.isBefore(DateTime.now())) return;

    await _localNotifications.zonedSchedule(
      event.id.hashCode,
      'イベントのリマインド',
      'もうすぐ「${event.title}」が始まります！',
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'event_reminders',
          'Event Reminders',
          channelDescription: 'Reminders for liked events',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // Cancel Event Notification
  Future<void> cancelEventNotification(String eventId) async {
    await _localNotifications.cancel(eventId.hashCode);
  }

  // Schedule Weekly Class Notification
  Future<void> scheduleReminder(ClassReminder reminder,
      {required String className}) async {
    // print(
    // 'NotificationService: Scheduling reminder for ${reminder.title} (ID: ${reminder.notificationId})');
    // print('NotificationService: Raw notifyAt: ${reminder.notifyAt}');

    // print(
    // 'NotificationService: Current TZ time: $localNow (Timezone: ${localNow.location.name})');

    if (reminder.isRecurring) {
      // Calculate next occurrence for weekly reminder
      // Note: This logic assumes the reminder.notifyAt contains the correct time and weekday
      // Since ClassReminder stores a specific DateTime, we extract weekday and time from it.

      final now = DateTime.now();
      var scheduledDate = DateTime(
        now.year,
        now.month,
        now.day,
        reminder.notifyAt.hour,
        reminder.notifyAt.minute,
      );

      // Adjust to the correct weekday
      while (scheduledDate.weekday != reminder.notifyAt.weekday) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }
      // If time has passed for today, move to next week
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 7));
      }

      final scheduledTZDate = tz.TZDateTime.from(scheduledDate, tz.local);
      // print('NotificationService: Scheduled recurring for $scheduledTZDate');

      await _localNotifications.zonedSchedule(
        reminder.notificationId,
        className, // Use className as title
        reminder.title, // Use reminder title as body
        scheduledTZDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'class_reminders_v2',
            'Class Reminders',
            channelDescription: 'Reminders for class tasks',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // Weekly
      );
    } else {
      // One-time reminder
      if (reminder.notifyAt.isBefore(DateTime.now())) return;

      final scheduledTZDate = tz.TZDateTime.from(reminder.notifyAt, tz.local);
      // print('NotificationService: Scheduled one-time for $scheduledTZDate');

      await _localNotifications.zonedSchedule(
        reminder.notificationId,
        className, // Use className as title
        reminder.title, // Use reminder title as body
        scheduledTZDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'class_reminders_v2',
            'Class Reminders',
            channelDescription: 'Reminders for class tasks',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  Future<void> scheduleWeeklyNotification({
    required int id,
    required String title,
    required String body,
    required int weekday, // 1 (Mon) - 7 (Sun)
    required TimeOfDay time,
  }) async {
    // Calculate next occurrence
    final now = DateTime.now();
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // Adjust to the correct weekday
    while (scheduledDate.weekday != weekday) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    // If time has passed for today, move to next week
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }

    await _localNotifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'class_reminders_v2',
          'Class Reminders',
          channelDescription: 'Weekly reminders for classes',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // Weekly
    );
  }

  Future<void> cancelNotification(int id) async {
    // Ensure ID is within 32-bit integer range
    if (id > 2147483647 || id < -2147483648) {
      // print('Notification ID $id is out of range. Skipping cancellation.');
      return;
    }
    await _localNotifications.cancel(id);
  }

  // --- Activity Feed (Firestore) Methods ---

  // Send a notification to a specific user
  Future<void> sendNotification({
    required String toUserId,
    required String title,
    required String body,
    required NotificationType type,
    String? relatedId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    // Don't send notification to self
    if (currentUser != null && currentUser.uid == toUserId) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(toUserId)
        .collection('notifications')
        .add({
      'title': title,
      'body': body,
      'type': type.name,
      'relatedId': relatedId,
      'fromUid': currentUser?.uid,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Get notifications stream
  Stream<List<AppNotification>> getNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AppNotification.fromFirestore(doc))
            .toList());
  }

  // Get unread count stream
  Stream<int> getUnreadCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Mark a notification as read
  Future<void> markAsRead(String notificationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  // Mark all as read
  Stream<int> getUnreadCountStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(0);

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> markAllAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final batch = FirebaseFirestore.instance.batch();
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();

    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }
}
