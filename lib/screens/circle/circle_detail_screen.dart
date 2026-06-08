import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/circle.dart';
import '../../models/event.dart';
import '../../services/circle_service.dart';
import '../../services/event_service.dart';
import '../../services/report_service.dart';
import '../../services/share_service.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/app_custom_input_dialog.dart';
import '../event/create_event_screen.dart';
import '../event/event_detail_screen.dart';
import 'edit_circle_profile_screen.dart';
import 'circle_member_list_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class CircleDetailScreen extends StatefulWidget {
  final String circleId;

  const CircleDetailScreen({super.key, required this.circleId});

  @override
  State<CircleDetailScreen> createState() => _CircleDetailScreenState();
}

class _CircleDetailScreenState extends State<CircleDetailScreen> {
  final _circleService = CircleService();
  final _eventService = EventService();

  Circle? _circle;
  bool _isLoading = true;
  bool _canManageCircle = false;
  bool _canManageEvents = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final circle = await _circleService.getCircleById(widget.circleId);
      if (circle != null) {
        final user = FirebaseAuth.instance.currentUser;
        final canManageCircle =
            user != null && circle.canManageCircle(user.uid);
        final canManageEvents =
            user != null && circle.canManageEvents(user.uid);

        if (mounted) {
          setState(() {
            _circle = circle;
            _canManageCircle = canManageCircle;
            _canManageEvents = canManageEvents;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      // print('Error loading circle: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openCreateEvent() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateEventScreen()),
    );
    _loadData();
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
          title: 'サークルを通報',
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
              onPressed: reason == null || _circle == null
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      await ReportService().submitContentReport(
                        targetType: 'circle',
                        targetId: _circle!.id,
                        reason: reason!,
                        detail: controller.text.trim(),
                        universityId: _circle!.universityId,
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

    if (_circle == null) {
      return const Scaffold(body: Center(child: Text('サークルが見つかりません')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_circle!.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              if (_circle != null) {
                ShareService().shareCircle(_circle!);
              }
            },
          ),
          if (_canManageCircle)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditCircleProfileScreen(circle: _circle!),
                  ),
                );
                if (result == true) {
                  _loadData();
                }
              },
            ),
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
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            if (_circle!.isActivePromotion)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: InformationCard(
                  title: 'PR掲載について',
                  message: prDisclaimerNotice,
                ),
              ),
            _buildInfoCard(),
            _buildDescription(),
            Divider(thickness: 8, color: Colors.grey.shade100, height: 8),
            _buildEventList(),
            if (_canManageCircle) _buildAuditLogs(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.white,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 80,
              height: 80,
              color: Colors.grey.shade100,
              child: _circle!.iconUrl != null
                  ? Image.network(_circle!.iconUrl!, fit: BoxFit.cover)
                  : const Icon(Icons.groups_2_outlined,
                      size: 36, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _circle!.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _circle!.category.label,
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (_circle!.isActivePromotion) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      PrBadge(label: _circle!.promotionLabel),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '団体によるPR掲載',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_canManageCircle) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CircleMemberListScreen(circle: _circle!),
                          ),
                        );
                      },
                      icon: const Icon(Icons.people),
                      label: const Text('メンバー確認'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildInfoRow(
              Icons.calendar_today, '活動日', _circle!.activityDays.join(', ')),
          const Divider(),
          _buildInfoRow(Icons.location_on, '活動場所', _circle!.place ?? ''),
          const Divider(),
          Row(
            children: [
              Expanded(
                  child: _buildInfoRow(
                      Icons.people, '人数', _circle!.memberCount ?? '')),
              Container(width: 1, height: 24, color: Colors.grey.shade300),
              Expanded(
                  child: _buildInfoRow(
                      Icons.wc, '男女比', _circle!.genderRatio ?? '')),
            ],
          ),
          if (_circle!.websiteUrl != null &&
              _circle!.websiteUrl!.isNotEmpty) ...[
            const Divider(),
            InkWell(
              onTap: () => _launchUrl(_circle!.websiteUrl!),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _circle!.websiteUrl!,
                        style: const TextStyle(color: Colors.blue),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if ((_circle!.xId != null && _circle!.xId!.isNotEmpty) ||
              (_circle!.instagramId != null &&
                  _circle!.instagramId!.isNotEmpty)) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  if (_circle!.xId != null && _circle!.xId!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: InkWell(
                        onTap: () =>
                            _launchUrl('https://x.com/${_circle!.xId}'),
                        child: Row(
                          children: [
                            const Text(
                              'X',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '@${_circle!.xId}',
                              style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_circle!.instagramId != null &&
                      _circle!.instagramId!.isNotEmpty)
                    InkWell(
                      onTap: () => _launchUrl(
                          'https://instagram.com/${_circle!.instagramId}'),
                      child: Row(
                        children: [
                          const Icon(Icons.camera_alt,
                              size: 20, color: Colors.purple),
                          const SizedBox(width: 4),
                          Text(
                            '@${_circle!.instagramId}',
                            style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '未設定' : value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'サークル紹介',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            _circle!.description.isEmpty ? '紹介文はありません' : _circle!.description,
            style: const TextStyle(height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildEventList() {
    return StreamBuilder<List<Event>>(
      stream: _eventService.getEvents(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('エラーが発生しました');
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allEvents = snapshot.data!;
        final circleEvents =
            allEvents.where((e) => e.circleId == widget.circleId).toList();

        if (circleEvents.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Text(
                  'イベント',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (_canManageEvents && _circle!.status == 'active')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openCreateEvent,
                      icon: const Icon(Icons.add),
                      label: const Text('このサークルのイベントを作成'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('イベントはまだありません')),
              ),
            ],
          );
        }

        Event? pinnedEvent;
        List<Event> otherEvents = [];

        if (_circle!.pinnedEventId != null) {
          try {
            pinnedEvent =
                circleEvents.firstWhere((e) => e.id == _circle!.pinnedEventId);
          } catch (_) {}
        }

        for (var event in circleEvents) {
          if (pinnedEvent != null && event.id == pinnedEvent.id) continue;
          otherEvents.add(event);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                'イベント',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            if (_canManageEvents && _circle!.status == 'active')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openCreateEvent,
                    icon: const Icon(Icons.add),
                    label: const Text('このサークルのイベントを作成'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            if (pinnedEvent != null)
              _buildEventItem(pinnedEvent, isPinned: true),
            ...otherEvents.map((e) => _buildEventItem(e)),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }

  Widget _buildEventItem(Event event, {bool isPinned = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPinned ? Colors.orange.shade300 : Colors.grey.shade200,
          width: isPinned ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
          );
          _loadData();
        },
        child: Column(
          children: [
            if (isPinned)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.push_pin, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      '固定されたイベント',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                  image: event.imageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(event.imageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: event.imageUrl == null
                    ? const Icon(Icons.event, color: Colors.grey)
                    : null,
              ),
              title: Text(
                event.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MM/dd (E) HH:mm', 'ja').format(event.startAt),
                    style: TextStyle(color: Theme.of(context).primaryColor),
                  ),
                  Text(event.location, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditLogs() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _circleService.auditLogsStream(_circle!.id),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '操作ログ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...docs.take(10).map((doc) {
                final data = doc.data();
                final createdAt = data['created_at'] as Timestamp?;
                final actorUid = data['actor_uid'] as String? ?? '';
                final changes = data['changes'] as Map<String, dynamic>? ?? {};
                return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: actorUid.startsWith('script:')
                      ? null
                      : FirebaseFirestore.instance
                          .collection('users')
                          .doc(actorUid)
                          .get(),
                  builder: (context, userSnapshot) {
                    final userData = userSnapshot.data?.data();
                    final actorName = actorUid.startsWith('script:')
                        ? 'システム'
                        : userData?['nickname'] ??
                            userData?['displayName'] ??
                            userData?['email'] ??
                            actorUid;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history,
                              size: 18, color: Colors.grey),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _auditActionLabel(data['action'] as String?),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (createdAt != null)
                                      DateFormat('M/d HH:mm')
                                          .format(createdAt.toDate()),
                                    actorName,
                                    _auditChangeSummary(changes),
                                  ]
                                      .where((text) => text.isNotEmpty)
                                      .join(' / '),
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  String _auditChangeSummary(Map<String, dynamic> changes) {
    final after = changes['after'];
    if (after is String) {
      return '変更後: ${CircleMemberRole.fromValue(after).label}';
    }
    final title = changes['title'] ?? changes['after_title'];
    if (title is String && title.isNotEmpty) return title;
    return '';
  }

  String _auditActionLabel(String? action) {
    switch (action) {
      case 'circle_created':
        return 'サークル作成';
      case 'member_joined':
        return 'メンバー参加';
      case 'member_role_updated':
        return 'ロール変更';
      case 'circle_profile_updated':
        return 'プロフィール更新';
      case 'event_created':
        return 'イベント作成';
      case 'event_updated':
        return 'イベント更新';
      case 'event_deleted':
        return 'イベント削除';
      case 'event_pinned':
        return 'イベント固定';
      case 'event_unpinned':
        return 'イベント固定解除';
      default:
        return '操作';
    }
  }
}
