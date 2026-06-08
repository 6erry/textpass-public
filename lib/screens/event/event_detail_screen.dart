import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/event.dart';
import '../../models/circle.dart';
import '../../services/event_service.dart';
import '../../services/circle_service.dart';
import '../../services/notification_service.dart';
import '../../services/report_service.dart';
import '../../services/share_service.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/app_custom_dialog.dart';
import '../../widgets/app_custom_input_dialog.dart';
import 'create_event_screen.dart';
import '../circle/circle_detail_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class EventDetailScreen extends StatefulWidget {
  final Event event;

  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final _eventService = EventService();
  final _circleService = CircleService();
  final _notificationService = NotificationService();

  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isPinned = false;
  bool _isLiked = false;
  Circle? _circle;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;

      // Load Circle
      _circle = await _circleService.getCircleById(widget.event.circleId);

      // Check Admin
      if (user != null && _circle != null) {
        _isAdmin = _circle!.canManageEvents(user.uid);
      }

      // Check Pinned
      if (_circle != null) {
        _isPinned = _circle!.pinnedEventId == widget.event.id;
      }

      // Check Liked
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final likedEvents =
            List<String>.from(userDoc.data()?['likedEventIds'] ?? []);
        _isLiked = likedEvents.contains(widget.event.id);
      }
    } catch (e) {
      debugPrint('Error loading event data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _launchMap() async {
    final query = Uri.encodeComponent(widget.event.location);
    final url =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _deleteEvent() async {
    showDialog(
      context: context,
      builder: (dialogContext) => AppCustomDialog(
        title: 'イベント削除',
        message: '本当にこのイベントを削除しますか？\nこの操作は取り消せません。',
        icon: Icons.delete_forever,
        confirmText: '削除',
        confirmColor: Colors.red,
        onConfirm: () async {
          Navigator.pop(dialogContext); // Close dialog
          try {
            await _eventService.deleteEvent(
                widget.event.id, widget.event.circleId);
            if (mounted) {
              AppToast.show(context, 'イベントを削除しました');
              // Using mounted before poping the navigator.
            }
            if (mounted) {
              Navigator.pop(context); // Back to list
            }
          } catch (e) {
            if (mounted) {
              AppToast.show(context, 'エラー: $e');
            }
          }
        },
      ),
    );
  }

  Future<void> _togglePin() async {
    try {
      // If trying to pin (currently not pinned) AND there is already a pinned event
      if (!_isPinned &&
          _circle != null &&
          _circle!.pinnedEventId != null &&
          _circle!.pinnedEventId!.isNotEmpty) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AppCustomDialog(
            title: '固定イベントの変更',
            message: 'すでに他のイベントが固定されています。\nこのイベントを新しく固定しますか？',
            icon: Icons.push_pin,
            confirmText: '変更する',
            onConfirm: () => Navigator.pop(context, true),
          ),
        );

        if (confirm != true) return;
      }

      final newPinnedId = _isPinned ? null : widget.event.id;
      await _circleService.pinEvent(widget.event.circleId, newPinnedId);
      setState(() => _isPinned = !_isPinned);
      if (mounted) {
        AppToast.show(context, _isPinned ? 'イベントを固定しました' : 'イベントの固定を解除しました');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'エラー: $e');
      }
    }
  }

  Future<void> _toggleLike() async {
    try {
      final newStatus = !_isLiked;
      await _eventService.toggleLike(widget.event.id, newStatus);

      if (newStatus) {
        await _notificationService.scheduleEventNotification(widget.event);
      } else {
        await _notificationService.cancelEventNotification(widget.event.id);
      }

      setState(() => _isLiked = newStatus);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'エラー: $e');
    }
  }

  void _duplicateEvent() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEventScreen(eventToDuplicate: widget.event),
      ),
    );
  }

  Future<void> _showReportDialog() async {
    const reasons = [
      '不適切な内容',
      '大学公式と誤認させる表現',
      '迷惑行為',
      '詐欺・トラブル',
      'その他',
    ];
    final controller = TextEditingController();
    String? reason;
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AppCustomInputDialog(
          title: 'イベントを通報',
          icon: Icons.report_problem_outlined,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: reasons
                    .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                    .toList(),
                onChanged: (value) => setState(() => reason = value),
                hint: const Text('理由を選択'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '詳細（任意）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: reason == null
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      await ReportService().submitContentReport(
                        targetType: 'event',
                        targetId: widget.event.id,
                        reason: reason!,
                        detail: controller.text.trim(),
                        universityId: widget.event.universityId,
                      );
                      if (mounted) AppToast.show(context, '通報を受け付けました');
                    },
              child: const Text('送信'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  widget.event.imageUrl != null
                      ? Image.network(
                          widget.event.imageUrl!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child:
                                Icon(Icons.image, size: 80, color: Colors.grey),
                          ),
                        ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.5),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () {
                  ShareService().shareEvent(widget.event);
                },
              ),
              if (_isAdmin) ...[
                IconButton(
                  icon: Icon(
                      _isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                  tooltip: _isPinned ? '固定解除' : '固定する',
                  onPressed: _togglePin,
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: '複製して作成',
                  onPressed: _duplicateEvent,
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CreateEventScreen(eventToEdit: widget.event),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _deleteEvent,
                ),
              ],
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'report') _showReportDialog();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'report', child: Text('通報する')),
                ],
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context)
                            .primaryColor
                            .withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      widget.event.category.label,
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (widget.event.isActivePromotion) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        PrBadge(label: widget.event.promotionLabel),
                        const SizedBox(width: 8),
                        Text(
                          '団体によるPR掲載',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const InformationCard(
                      title: 'PR掲載について',
                      message: prDisclaimerNotice,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    widget.event.title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.calendar_today,
                                color: Colors.blue, size: 20),
                          ),
                          title: const Text('日時',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          subtitle: Text(
                            DateFormat('yyyy年MM月dd日(E) HH:mm', 'ja')
                                .format(widget.event.startAt),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87),
                          ),
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.location_on,
                                color: Colors.green, size: 20),
                          ),
                          title: const Text('場所',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          subtitle: Text(
                            widget.event.location,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.map, color: Colors.grey),
                            onPressed: _launchMap,
                          ),
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.group,
                                color: Colors.orange, size: 20),
                          ),
                          title: const Text('主催サークル',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          subtitle: InkWell(
                            onTap: () {
                              if (_circle != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CircleDetailScreen(
                                        circleId: _circle!.id),
                                  ),
                                );
                              }
                            },
                            child: Text(
                              _circle?.name ?? 'サークル情報を読み込み中...',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (widget.event.tags.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.event.tags.map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            '# $tag',
                            style: TextStyle(
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                  const Text(
                    'イベント詳細',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.event.description.isEmpty
                        ? '詳細情報はありません'
                        : widget.event.description,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                  if (_isAdmin) ...[
                    const SizedBox(height: 28),
                    _buildAdminMetadata(),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleLike,
        backgroundColor: Colors.white,
        child: Icon(
          _isLiked ? Icons.favorite : Icons.favorite_border,
          color: _isLiked ? Colors.red : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildAdminMetadata() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '管理情報',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _buildUserMetaRow(
            label: '作成者',
            uid: widget.event.createdBy,
            date: widget.event.createdAt,
          ),
          if (widget.event.updatedBy != null || widget.event.updatedAt != null)
            _buildUserMetaRow(
              label: '最終更新',
              uid: widget.event.updatedBy,
              date: widget.event.updatedAt,
            ),
        ],
      ),
    );
  }

  Widget _buildUserMetaRow({
    required String label,
    required String? uid,
    required DateTime? date,
  }) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: uid == null
          ? null
          : FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final name = data?['nickname'] ??
            data?['displayName'] ??
            data?['email'] ??
            uid ??
            '不明';
        final dateText =
            date == null ? '' : DateFormat('yyyy/MM/dd HH:mm').format(date);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '$label: $name${dateText.isEmpty ? '' : ' / $dateText'}',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
