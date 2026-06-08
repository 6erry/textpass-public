import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_class.dart';
import '../models/class_reminder.dart';
import 'add_class_screen.dart';
import 'search_screen.dart';
import '../services/notification_service.dart';
import '../services/shared_room_service.dart';
import '../services/timetable_service.dart';
import '../services/syllabus_service.dart';
import '../models/syllabus.dart';
import '../widgets/app_custom_dialog.dart';
import '../widgets/app_custom_input_dialog.dart';
// import '../widgets/app_custom_input_dialog.dart'; // Duplicate removed
import 'package:textpass/utils/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/review.dart';
import '../repositories/review_repository.dart';
import 'review_compose_screen.dart';
import 'review_detail_screen.dart';

// Provider for Review List (Family)
final reviewListProvider = StreamProvider.family.autoDispose<List<Review>,
    ({String title, String teacher, String classKey})>((ref, arg) {
  return ref
      .read(reviewRepositoryProvider)
      .getReviewsForClass(arg.title, arg.teacher, classKey: arg.classKey);
});

class ClassDetailScreen extends StatefulWidget {
  final UserClass userClass;
  final Syllabus? previewSyllabus;

  const ClassDetailScreen({
    super.key,
    required this.userClass,
    this.previewSyllabus,
  });

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  late TextEditingController _memoController;
  final _notificationService = NotificationService();
  final _timetableService = TimetableService();
  final _syllabusService = SyllabusService();
  final _sharedRoomService = SharedRoomService();
  @override
  void initState() {
    super.initState();
    _memoController = TextEditingController(text: widget.userClass.memo);
  }

  Future<Set<String>?> _showConflictDialog(
    List<TimetableSlotConflict> conflicts,
  ) async {
    final replaceDocIds = <String>{};
    final bySlot = <String, List<TimetableSlotConflict>>{};
    for (final conflict in conflicts) {
      bySlot.putIfAbsent(conflict.slot.key, () => []).add(conflict);
    }

    return showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppCustomInputDialog(
          title: '重複するコマがあります',
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.orange,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: bySlot.entries.map((entry) {
              final slotConflicts = entry.value;
              final slot = slotConflicts.first.slot;
              final shouldReplace = slotConflicts.every(
                (conflict) => replaceDocIds.contains(conflict.existingDocId),
              );
              return CheckboxListTile(
                value: shouldReplace,
                onChanged: (value) {
                  setState(() {
                    for (final conflict in slotConflicts) {
                      if (value == true) {
                        replaceDocIds.add(conflict.existingDocId);
                      } else {
                        replaceDocIds.remove(conflict.existingDocId);
                      }
                    }
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('${_slotLabel(slot.day, slot.period)}を置き換える'),
                subtitle: Text(
                  slotConflicts.map((c) => '現在: ${c.existingTitle}').join('\n'),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, replaceDocIds),
              child: const Text('この内容で追加'),
            ),
          ],
        ),
      ),
    );
  }

  String _slotLabel(String day, int period) {
    const dayMap = {
      'Mon': '月',
      'Tue': '火',
      'Wed': '水',
      'Thu': '木',
      'Fri': '金',
      'Sat': '土',
      'Sun': '日',
    };
    return '${dayMap[day] ?? day}曜 $period限';
  }

  String _classScheduleLabel(UserClass userClass) {
    final syllabus = widget.previewSyllabus;
    if (syllabus == null) {
      return '${_dayToJa(userClass.day)}曜 ${userClass.period}限';
    }

    final slots = _syllabusService.getAddSlots(
      syllabus,
      targetYear: userClass.year,
    );
    if (slots.length <= 1) {
      return '${_dayToJa(userClass.day)}曜 ${userClass.period}限';
    }

    final labels = slots.map((slot) => _slotLabel(slot.day, slot.period));
    return '複数コマ: ${labels.join('・')}';
  }

  Future<void> _toggleNotification(bool value) async {
    // setState(() => _isNotificationEnabled = value); // Removed local state update

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 1. Update Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('timetable')
          .doc(widget.userClass.id)
          .update({'is_notification_enabled': value});

      // 2. Schedule/Cancel Local Notification
      // Use hashcode of ID for notification ID (ensure uniqueness)
      // Also ensure it fits in 32-bit integer
      final notificationId = widget.userClass.id.hashCode % 2147483647;

      if (value) {
        // Get start time for this period
        final periodTimes = await _timetableService.getPeriodTimes();
        final times = periodTimes[widget.userClass.period];
        if (times != null) {
          final startHour = times['startHour']!;
          final startMinute = times['startMinute']!;

          // Calculate 10 minutes before
          var notifyTime = TimeOfDay(hour: startHour, minute: startMinute);
          final now = DateTime.now();
          var dt =
              DateTime(now.year, now.month, now.day, startHour, startMinute);
          dt = dt.subtract(const Duration(minutes: 10));
          notifyTime = TimeOfDay.fromDateTime(dt);

          // Map day string to int (1=Mon, 7=Sun)
          final dayMap = {
            'Mon': 1,
            'Tue': 2,
            'Wed': 3,
            'Thu': 4,
            'Fri': 5,
            'Sat': 6,
            'Sun': 7
          };
          final weekday = dayMap[widget.userClass.day] ?? 1;

          await _notificationService.scheduleWeeklyNotification(
            id: notificationId,
            title: '授業開始10分前',
            body:
                'まもなく ${widget.userClass.period}限 ${widget.userClass.title} が始まります (教室: ${widget.userClass.room})',
            weekday: weekday,
            time: notifyTime,
          );

          if (mounted) {
            AppToast.show(context, '授業前通知をONにしました');
          }
        }
      } else {
        await _notificationService.cancelNotification(notificationId);
        if (mounted) {
          AppToast.show(context, '授業前通知をOFFにしました');
        }
      }
    } catch (e) {
      // Revert state on error
      // setState(() => _isNotificationEnabled = !value); // Removed local state
      if (mounted) {
        AppToast.show(context, '設定エラー: $e');
      }
    }
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  Widget _buildCompactTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _updateAttendance(String field, int value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('timetable')
          .doc(widget.userClass.id)
          .update({field: value});
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '更新エラー: $e');
      }
    }
  }

  Future<void> _saveMemo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('timetable')
          .doc(widget.userClass.id)
          .update({'memo': _memoController.text});
      if (mounted) {
        AppToast.show(context, 'メモを保存しました');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '保存エラー: $e');
      }
    }
  }

  Future<void> _applySharedRoom(UserClass userClass, String roomName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('timetable')
          .doc(userClass.id)
          .update({
        'room': roomName,
        'room_source': 'shared',
      });
      if (mounted) {
        AppToast.show(context, '共有された教室情報を反映しました');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '教室情報の反映に失敗しました');
      }
    }
  }

  Widget _buildSharedRoomCandidate(UserClass userClass) {
    return FutureBuilder<SharedRoomSuggestion?>(
      future: _sharedRoomService.getBestRoom(userClass.classKey),
      builder: (context, snapshot) {
        final suggestion = snapshot.data;
        if (suggestion == null ||
            suggestion.roomName.trim().isEmpty ||
            suggestion.roomName.trim() == userClass.room.trim()) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueGrey.shade100),
            ),
            child: Row(
              children: [
                const Icon(Icons.meeting_room_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '共有候補: ${suggestion.roomName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      _applySharedRoom(userClass, suggestion.roomName),
                  child: const Text('反映'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteClass() async {
    showDialog(
      context: context,
      builder: (dialogContext) => AppCustomDialog(
        title: '削除確認',
        message: 'この授業を時間割から削除しますか？',
        icon: Icons.delete_forever,
        confirmText: '削除',
        confirmColor: Colors.red,
        onConfirm: () async {
          Navigator.pop(dialogContext); // Close dialog
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;

            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('timetable')
                .doc(widget.userClass.id)
                .delete();

            if (mounted) Navigator.pop(context); // Close screen
          } catch (e) {
            if (mounted) {
              AppToast.show(context, '削除エラー: $e');
            }
          }
        },
      ),
    );
  }

  // ... (build method)

  void _showAddReminderDialog() {
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    bool isRecurring = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AppCustomInputDialog(
              title: '通知を追加',
              icon: Icons.notifications_active_outlined,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'タイトル (例: 数学テスト)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('日付'),
                    subtitle: Text(
                        '${selectedDate.year}/${selectedDate.month}/${selectedDate.day}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => selectedDate = picked);
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('時間'),
                    subtitle: Text(selectedTime.format(context)),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setState(() => selectedTime = picked);
                      }
                    },
                  ),
                  SwitchListTile(
                    title: const Text('毎週繰り返す'),
                    value: isRecurring,
                    onChanged: (val) => setState(() => isRecurring = val),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (titleController.text.isEmpty) return;

                    final notifyAt = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedTime.hour,
                      selectedTime.minute,
                    );

                    final reminder = ClassReminder(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: titleController.text,
                      notifyAt: notifyAt,
                      isRecurring: isRecurring,
                      // Ensure ID fits in 32-bit integer (approx 2 billion)
                      // millisecondsSinceEpoch is much larger, so we take modulo
                      notificationId:
                          DateTime.now().millisecondsSinceEpoch % 2147483647,
                    );

                    try {
                      await _timetableService.addReminder(
                          widget.userClass.id, reminder);
                      await _notificationService.scheduleReminder(reminder,
                          className: widget.userClass.title);
                      if (context.mounted) {
                        Navigator.pop(context);
                        AppToast.show(context, '通知を設定しました');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppToast.show(context, '設定エラー: $e');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('追加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditReminderDialog(ClassReminder originalReminder) {
    final titleController = TextEditingController(text: originalReminder.title);
    DateTime selectedDate = originalReminder.notifyAt;
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(originalReminder.notifyAt);
    bool isRecurring = originalReminder.isRecurring;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AppCustomInputDialog(
              title: '通知を編集',
              icon: Icons.notifications_active_outlined,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'タイトル (例: 数学テスト)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('日付'),
                    subtitle: Text(
                        '${selectedDate.year}/${selectedDate.month}/${selectedDate.day}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => selectedDate = picked);
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('時間'),
                    subtitle: Text(selectedTime.format(context)),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setState(() => selectedTime = picked);
                      }
                    },
                  ),
                  SwitchListTile(
                    title: const Text('毎週繰り返す'),
                    value: isRecurring,
                    onChanged: (val) => setState(() => isRecurring = val),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (titleController.text.isEmpty) return;

                    final notifyAt = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedTime.hour,
                      selectedTime.minute,
                    );

                    int notificationId = originalReminder.notificationId;
                    if (notificationId > 2147483647 ||
                        notificationId < -2147483648) {
                      notificationId =
                          DateTime.now().millisecondsSinceEpoch % 2147483647;
                    }

                    final updatedReminder = ClassReminder(
                      id: originalReminder.id,
                      title: titleController.text,
                      notifyAt: notifyAt,
                      isRecurring: isRecurring,
                      notificationId: notificationId,
                    );

                    try {
                      await _timetableService.updateReminder(
                          widget.userClass.id, updatedReminder);

                      if (!context.mounted) return;
                      await _notificationService
                          .cancelNotification(originalReminder.notificationId);
                      await _notificationService.scheduleReminder(
                          updatedReminder,
                          className: widget.userClass.title);

                      if (context.mounted) {
                        Navigator.pop(context);
                        AppToast.show(context, '通知を更新しました');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppToast.show(context, '更新エラー: $e');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('更新'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('ログインが必要です')));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('timetable')
          .doc(widget.userClass.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('エラー')),
            body: Center(child: Text('エラーが発生しました: ${snapshot.error}')),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('読み込み中')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          // Check if it's a preview or review view
          if (widget.userClass.id == 'preview' ||
              widget.userClass.id == 'preview_review') {
            // Preview Mode: Use widget.userClass directly
            final currentClass = widget.userClass;
            final color = Color(currentClass.colorValue);
            final textColor =
                color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
            final isReviewView = widget.userClass.id == 'preview_review';

            return Scaffold(
              appBar: AppBar(
                title: Text(isReviewView ? '授業詳細 (レビュー)' : '授業詳細 (プレビュー)'),
                backgroundColor: color,
                foregroundColor: textColor,
                actions: [
                  if (!isReviewView)
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        try {
                          final syllabus = widget.previewSyllabus ??
                              Syllabus(
                                id: currentClass.syllabusId.isNotEmpty
                                    ? currentClass.syllabusId
                                    : '',
                                title: currentClass.title,
                                teacher: currentClass.teacher,
                                classKey: currentClass.classKey,
                                classroom: currentClass.room,
                                day: currentClass.day,
                                period: currentClass.period,
                                textbook: currentClass.textbook,
                                createdBy: '',
                                createdAt: DateTime.now(),
                                universityId: '',
                                year: currentClass.year,
                              );

                          final conflicts =
                              await _syllabusService.getTimetableConflicts(
                            syllabus,
                            targetYear: currentClass.year,
                          );
                          final replaceIds = conflicts.isEmpty
                              ? <String>{}
                              : await _showConflictDialog(conflicts);
                          if (replaceIds == null) return;

                          await _syllabusService.addToTimetable(
                            syllabus,
                            targetYear: currentClass.year,
                            replaceConflictDocIds: replaceIds,
                          );

                          if (context.mounted) {
                            AppToast.show(context, '時間割に追加しました');
                            Navigator.pop(context, true);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            AppToast.show(context, '追加エラー: $e');
                          }
                        }
                      },
                    ),
                  Consumer(
                    builder: (context, ref, _) {
                      return FutureBuilder<bool>(
                        future: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) return false;
                          // Logic to check if reviewed.
                          // Ideally we'd use a provider for standard access, but direct repo call is okay for simple check here.
                          // Or even better, just let the compose screen handle it and return early?
                          // User wants "Unable to write if already posted".
                          // So disabling or hiding the button is better UX.
                          if (widget.userClass.id == 'preview' ||
                              widget.userClass.id == 'preview_review') {
                            return false;
                          }

                          // Using a simple future here might be tricky with `actions` rebuild.
                          // Let's just handle it in the onPressed for now, or use a Consumer/FutureBuilder separately.
                          // Simpler: Just check in onPressed. If decided to disable button visually, we need state.
                          return false; // dynamic check in onPressed
                        }(),
                        builder: (context, snapshot) {
                          return IconButton(
                            icon: const Icon(Icons.rate_review),
                            onPressed: () async {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user == null) {
                                AppToast.show(context, 'ログインが必要です');
                                return;
                              }

                              // Check for existing review
                              final repo = ref.read(reviewRepositoryProvider);
                              final hasReviewed = await repo.hasUserReviewed(
                                  user.uid,
                                  currentClass.title,
                                  currentClass.teacher,
                                  classKey: currentClass.classKey);

                              if (hasReviewed && context.mounted) {
                                AppToast.show(context, '既にレビューを投稿済みです');
                                return;
                              }

                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ReviewComposeScreen(
                                      userClass: currentClass,
                                    ),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Review Header (Consumer) - Added for Preview/Review Mode
                    Consumer(
                      builder: (context, ref, child) {
                        final reviewsAsync = ref.watch(reviewListProvider((
                          title: currentClass.title,
                          teacher: currentClass.teacher,
                          classKey: currentClass.classKey
                        )));

                        return reviewsAsync.when(
                          data: (reviews) {
                            final average = ref
                                .read(reviewRepositoryProvider)
                                .calculateAverageRating(reviews);
                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.amber.shade200),
                              ),
                              child: InkWell(
                                onTap: () {
                                  // Navigate to compose screen if not duplicate
                                  // For now, maybe just show list?
                                  // The logic below says "Show reviews".
                                  // We should probably list them here or allow expanding?
                                  // The main view just shows the rating header and then (not visible in my view) probably lists reviews below or navigate?
                                  // Wait, looking at lines 615+ in original file, it has the Header info, Attendance, Reminders.
                                  // Where are the actual reviews listed?
                                  // Ah, I missed where the review LIST is.
                                  // The `ClassDetailScreen` I viewed earlier (lines 647-695) ONLY shows the average rating card.
                                  // It DOES NOT list the reviews?
                                  // Let me check the rest of the file.
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.star,
                                        color: Colors.amber, size: 28),
                                    const SizedBox(width: 8),
                                    Text(
                                      reviews.isNotEmpty
                                          ? '$average (${reviews.length}件)'
                                          : '評価なし',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.brown),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          loading: () => const SizedBox(
                              height: 50,
                              child:
                                  Center(child: CircularProgressIndicator())),
                          error: (_, __) => const SizedBox.shrink(),
                        );
                      },
                    ),
                    // Header Info
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentClass.title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          if (!isReviewView) ...[
                            Text(
                              _classScheduleLabel(currentClass),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text('教室: ${currentClass.room}'),
                          ],
                          Text('教員: ${currentClass.teacher}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        isReviewView
                            ? 'これはレビュー検索プレビューです。\n時間割に追加するにはシラバスから検索してください。'
                            : 'この授業はまだ時間割に追加されていません。\n追加するには戻って「+」ボタンを押してください。',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // List Reviews Here
                    const Text(
                      'みんなのレビュー',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    // Warning Text
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 20, color: Colors.grey),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '教員や授業に対する名誉毀損や侮辱にあたる書き込みは禁止されています。',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Consumer(
                      builder: (context, ref, child) {
                        final reviewsAsync = ref.watch(reviewListProvider((
                          title: currentClass.title,
                          teacher: currentClass.teacher,
                          classKey: currentClass.classKey
                        )));
                        return reviewsAsync.when(
                          data: (reviews) {
                            if (reviews.isEmpty) {
                              return const Center(
                                  child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('レビューはまだありません'),
                              ));
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: reviews.length,
                              itemBuilder: (context, index) {
                                final review = reviews[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 0,
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                          color: Colors.grey.shade200)),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ReviewDetailScreen(
                                              review: review),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.star,
                                                  color: Colors.amber,
                                                  size: 20),
                                              const SizedBox(width: 4),
                                              Text(
                                                review.rating.toString(),
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16),
                                              ),
                                              const Spacer(),
                                              Text(
                                                '${review.year}年度',
                                                style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              if (review.difficulty == 'easy')
                                                _buildCompactTag(
                                                    '楽単', Colors.green),
                                              if (review.difficulty == 'hard')
                                                _buildCompactTag(
                                                    '鬼単', Colors.red),
                                              _buildCompactTag(
                                                  review.hasTest
                                                      ? 'テスト有'
                                                      : 'テスト無',
                                                  review.hasTest
                                                      ? Colors.orange
                                                      : Colors.blueGrey),
                                              _buildCompactTag(
                                                  review.hasReport
                                                      ? '課題有'
                                                      : '課題無',
                                                  review.hasReport
                                                      ? Colors.orange
                                                      : Colors.blueGrey),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            review.comment,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(height: 1.5),
                                          ),
                                          if (review.comment.length >
                                              30) // Simple check, or just always show if maxLines hit logic needed
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: TextButton(
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          ReviewDetailScreen(
                                                              review: review),
                                                    ),
                                                  );
                                                },
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  minimumSize:
                                                      const Size(50, 20),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                child: const Text('続きをよむ',
                                                    style: TextStyle(
                                                        fontSize: 12)),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text('エラー: $e'),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(title: const Text('授業詳細')),
            body: const Center(child: Text('授業が見つかりません')),
          );
        }

        // Reconstruct UserClass from snapshot to ensure latest data
        final data = snapshot.data!.data() as Map<String, dynamic>;
        // We need to ensure the ID is preserved
        data['id'] = widget.userClass.id;
        final currentClass = UserClass.fromMap(data);

        // Update local state variables if needed, but ideally use currentClass directly
        // However, counters are stateful in this widget.
        // We should sync them if the stream updates, OR just use the stream data.
        // If we use stream data, we don't need local state for counters?
        // But the counters have local optimistic updates.
        // Let's rely on the stream for the source of truth.
        // But wait, if we update Firestore, the stream will update, and the UI will rebuild.
        // So we can remove local state for counters and just use currentClass.attended etc.

        final color = Color(currentClass.colorValue);
        final textColor =
            color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

        return Scaffold(
          appBar: AppBar(
            title: const Text('授業詳細'),
            backgroundColor: color,
            foregroundColor: textColor,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddClassScreen(
                        initialDay: currentClass.day,
                        initialPeriod: currentClass.period,
                        userClassToEdit: currentClass,
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: _deleteClass,
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Review Header (Consumer)
                Consumer(
                  builder: (context, ref, child) {
                    final reviewsAsync = ref.watch(reviewListProvider((
                      title: currentClass.title,
                      teacher: currentClass.teacher,
                      classKey: currentClass.classKey
                    )));

                    return reviewsAsync.when(
                      data: (reviews) {
                        final average = ref
                            .read(reviewRepositoryProvider)
                            .calculateAverageRating(reviews);
                        // If no reviews, average is 0.0
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.star,
                                  color: Colors.amber, size: 28),
                              const SizedBox(width: 8),
                              Text(
                                reviews.isNotEmpty
                                    ? '$average (${reviews.length}件)'
                                    : '評価なし',
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.brown),
                              ),
                            ],
                          ),
                        );
                      },
                      loading: () => const SizedBox(
                          height: 50,
                          child: Center(child: CircularProgressIndicator())),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  },
                ),
                // Header Info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              currentClass.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          // Notification Switch
                          Column(
                            children: [
                              Switch(
                                value: currentClass.isNotificationEnabled,
                                onChanged: _toggleNotification,
                                activeTrackColor: color,
                              ),
                              Text(
                                currentClass.isNotificationEnabled
                                    ? '通知ON'
                                    : '通知OFF',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: currentClass.isNotificationEnabled
                                      ? color
                                      : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _classScheduleLabel(currentClass),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('教員: ${currentClass.teacher}'),
                      Text('教室: ${currentClass.room}'),
                      _buildSharedRoomCandidate(currentClass),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Attendance Counter
                const Text(
                  '出席管理',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildCounter('出席', currentClass.attended, (val) {
                      _updateAttendance('attended', val);
                    }, Colors.green),
                    _buildCounter('遅刻', currentClass.late, (val) {
                      _updateAttendance('late', val);
                    }, Colors.orange),
                    _buildCounter('欠席', currentClass.absent, (val) {
                      _updateAttendance('absent', val);
                    }, Colors.red),
                  ],
                ),
                const Divider(height: 48),

                // --- Reminders Section ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '課題・テスト通知',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline,
                          color: Colors.blue),
                      onPressed: _showAddReminderDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<ClassReminder>>(
                  stream: _timetableService.getReminders(currentClass.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('読み込みエラー');
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final reminders = snapshot.data!;
                    if (reminders.isEmpty) {
                      return const Text('登録された通知はありません',
                          style: TextStyle(color: Colors.grey));
                    }
                    return Column(
                      children: reminders.map((reminder) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              reminder.isRecurring ? Icons.repeat : Icons.event,
                              color: Colors.orange,
                            ),
                            title: Text(reminder.title),
                            subtitle: Text(reminder.isRecurring
                                ? '毎週 ${_weekdayToString(reminder.notifyAt.weekday)} ${_formatTime(reminder.notifyAt)}'
                                : '${_formatDate(reminder.notifyAt)} ${_formatTime(reminder.notifyAt)}'),
                            onTap: () => _showEditReminderDialog(reminder),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.grey),
                              onPressed: () => _deleteReminder(reminder),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Memo
                const Text(
                  'メモ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  // Note: Controller needs to be updated if text changes from outside?
                  // Or just use initialValue?
                  // If we use controller, we need to update it when stream changes.
                  // But modifying controller in build is bad.
                  // For now, let's keep the controller but maybe update it in a listener?
                  // Or just let the user edit it.
                  // If the user edits elsewhere, this might not update.
                  // But memo is usually edited here.
                  // Let's stick to the controller initialized in initState for now.
                  // Ideally, we should update the controller if the remote text is different and not being edited.
                  controller: _memoController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'テスト日程や課題などをメモ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _saveMemo,
                    child: const Text('保存'),
                  ),
                ),
                const Divider(height: 48),

                // Textbook
                const Text(
                  '教科書',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (currentClass.textbook.isNotEmpty) ...[
                  Text(currentClass.textbook),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SearchScreen(
                              initialQuery: currentClass.textbook,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.search),
                      label: const Text('フリマで教科書を探す'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ] else
                  const Text('教科書情報は登録されていません'),
                const SizedBox(height: 48),

                // --- Review List Section ---
                const Text(
                  'みんなのレビュー',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  '※講師や特定の人物への誹謗中傷となるコメントは控えてください。',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, child) {
                    final reviewsAsync = ref.watch(reviewListProvider((
                      title: currentClass.title,
                      teacher: currentClass.teacher,
                      classKey: currentClass.classKey
                    )));

                    return reviewsAsync.when(
                      data: (reviews) {
                        if (reviews.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                                child: Text('まだレビューはありません',
                                    style: TextStyle(color: Colors.grey))),
                          );
                        }
                        return Column(
                          children: reviews.map((review) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(children: [
                                          const Icon(Icons.star,
                                              color: Colors.amber, size: 20),
                                          const SizedBox(width: 4),
                                          Text(review.rating.toString(),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                        ]),
                                        Text(
                                          review.userId ==
                                                  FirebaseAuth
                                                      .instance.currentUser?.uid
                                              ? 'あなた'
                                              : '匿名',
                                          style: const TextStyle(
                                              fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        _buildTag(
                                            review.difficulty == 'easy'
                                                ? '楽単'
                                                : (review.difficulty == 'hard'
                                                    ? '鬼単'
                                                    : '普通'),
                                            review.difficulty == 'easy'
                                                ? Colors.green
                                                : (review.difficulty == 'hard'
                                                    ? Colors.red
                                                    : Colors.grey)),
                                        if (review.hasTest)
                                          _buildTag('テスト有', Colors.blue),
                                        if (review.hasReport)
                                          _buildTag('レポート有', Colors.orange),
                                        if (review.attendance == 'always')
                                          _buildTag('出席毎回', Colors.purple),
                                      ],
                                    ),
                                    if (review.comment.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(review.comment),
                                    ]
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text('エラー: $e'),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Center(
                  child: Consumer(
                    builder: (context, ref, _) {
                      return FutureBuilder<bool>(
                        future: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) return false;
                          if (widget.userClass.id == 'preview' ||
                              widget.userClass.id == 'preview_review') {
                            return false;
                          }

                          return ref
                              .read(reviewRepositoryProvider)
                              .hasUserReviewed(user.uid, currentClass.title,
                                  currentClass.teacher,
                                  classKey: currentClass.classKey);
                        }(),
                        builder: (context, snapshot) {
                          final hasReviewed = snapshot.data ?? false;

                          return ElevatedButton.icon(
                            onPressed: () {
                              if (hasReviewed) {
                                AppToast.show(context, '既にレビューを投稿済みです');
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ReviewComposeScreen(
                                      userClass: currentClass),
                                ),
                              ).then((_) {
                                // Refresh logic?
                              });
                            },
                            icon: const Icon(Icons.rate_review),
                            label: Text(hasReviewed ? 'レビュー投稿済み' : 'レビューを書く'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 32, vertical: 12),
                              backgroundColor:
                                  hasReviewed ? Colors.grey : null, // Grey out
                              foregroundColor: hasReviewed
                                  ? Colors.white
                                  : null, // Ensure text is visible
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 80), // Bottom padding
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCounter(
      String label, int count, Function(int) onChanged, Color color) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () => onChanged(count > 0 ? count - 1 : 0),
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Text('$count',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => onChanged(count + 1),
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Reminder Helpers ---

  String _weekdayToString(int weekday) {
    const days = ['月', '火', '水', '木', '金', '土', '日'];
    return days[weekday - 1];
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteReminder(ClassReminder reminder) async {
    try {
      await _timetableService.deleteReminder(widget.userClass.id, reminder.id);
      await _notificationService.cancelNotification(reminder.notificationId);
      if (mounted) {
        AppToast.show(context, '通知を削除しました');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '削除エラー: $e');
      }
    }
  }

  String _dayToJa(String dayCode) {
    const map = {
      'Mon': '月',
      'Tue': '火',
      'Wed': '水',
      'Thu': '木',
      'Fri': '金',
      'Sat': '土',
      'Sun': '日'
    };
    return map[dayCode] ?? dayCode;
  }
}
