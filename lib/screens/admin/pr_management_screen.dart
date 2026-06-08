import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/user_service.dart';
import '../../utils/legal_notices.dart';
import 'package:textpass/utils/app_toast.dart';

class PrManagementScreen extends StatefulWidget {
  const PrManagementScreen({super.key});

  @override
  State<PrManagementScreen> createState() => _PrManagementScreenState();
}

class _PrManagementScreenState extends State<PrManagementScreen> {
  final _idController = TextEditingController();
  final _labelController = TextEditingController(text: 'PR');
  final _memoController = TextEditingController();
  final _externalRefController = TextEditingController();

  String _targetType = 'events';
  String _promotionTier = 'boost_7d';
  bool _enabled = true;
  DateTime? _startAt = DateTime.now();
  DateTime? _endAt = DateTime.now().add(const Duration(days: 7));
  bool _isAdmin = false;
  bool _isChecking = true;
  bool _isSaving = false;
  DocumentSnapshot<Map<String, dynamic>>? _targetDoc;

  static const _tiers = {
    'boost_7d': 'boost_7d',
    'featured_14d': 'featured_14d',
    'season_featured': 'season_featured',
  };

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  @override
  void dispose() {
    _idController.dispose();
    _labelController.dispose();
    _memoController.dispose();
    _externalRefController.dispose();
    super.dispose();
  }

  Future<void> _checkAdmin() async {
    final isAdmin = await UserService().isAdmin();
    if (!mounted) return;
    setState(() {
      _isAdmin = isAdmin;
      _isChecking = false;
    });
  }

  Future<void> _loadTarget() async {
    final id = _idController.text.trim();
    if (id.isEmpty) {
      AppToast.show(context, '対象IDを入力してください');
      return;
    }
    final doc =
        await FirebaseFirestore.instance.collection(_targetType).doc(id).get();
    if (!mounted) return;
    if (!doc.exists) {
      setState(() => _targetDoc = null);
      AppToast.show(context, '対象が見つかりません');
      return;
    }
    final data = doc.data() ?? {};
    setState(() {
      _targetDoc = doc;
      _enabled = data['promotionStatus'] == 'active' &&
          data['isPromoted'] == true &&
          data['isPr'] == true;
      _promotionTier = _tiers.containsKey(data['promotionTier'])
          ? data['promotionTier'] as String
          : 'boost_7d';
      _labelController.text = data['promotionLabel'] as String? ?? 'PR';
      _memoController.text = data['promotionAdminMemo'] as String? ?? '';
      _externalRefController.text =
          data['promotionExternalRef'] as String? ?? '';
      _startAt =
          (data['promotionStartAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      _endAt = (data['promotionEndAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 7));
    });
  }

  Future<void> _save() async {
    if (!_isAdmin || _targetDoc == null || _isSaving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      final now = FieldValue.serverTimestamp();
      final payload = <String, Object?>{
        'isPromoted': _enabled,
        'isPr': _enabled,
        'promotionTier': _enabled ? _promotionTier : 'none',
        'promotionStatus': _enabled ? 'active' : 'hidden',
        'promotionStartAt':
            _enabled && _startAt != null ? Timestamp.fromDate(_startAt!) : null,
        'promotionEndAt':
            _enabled && _endAt != null ? Timestamp.fromDate(_endAt!) : null,
        'promotionLabel': _labelController.text.trim().isEmpty
            ? 'PR'
            : _labelController.text.trim(),
        'promotionAdminMemo': _memoController.text.trim(),
        'promotionExternalRef': _externalRefController.text.trim(),
        'promotionUpdatedAt': now,
        'promotionUpdatedBy': user.uid,
      };
      if (_enabled) {
        payload['promotionCreatedAt'] =
            _targetDoc!.data()?['promotionCreatedAt'] ?? now;
        payload['promotionCreatedBy'] =
            _targetDoc!.data()?['promotionCreatedBy'] ?? user.uid;
      }

      await _targetDoc!.reference.update(payload);
      if (!mounted) return;
      AppToast.show(context, 'PR表示設定を保存しました');
      await _loadTarget();
    } catch (e) {
      if (mounted) AppToast.show(context, '保存に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startAt : _endAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startAt = picked;
      } else {
        _endAt = picked.add(const Duration(hours: 23, minutes: 59));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_isAdmin) {
      return const Scaffold(body: Center(child: Text('管理者のみ利用できます')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('PR表示管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InformationCard(
            title: 'PR表示の扱い',
            message:
                'この画面は管理者が外部で成立した掲載を手動で表示設定するためのものです。アプリ内にPRの申込・購入・決済・価格表示・外部導線は作りません。',
            icon: Icons.admin_panel_settings_outlined,
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'events', label: Text('イベント')),
              ButtonSegment(value: 'circles', label: Text('サークル')),
            ],
            selected: {_targetType},
            onSelectionChanged: (values) {
              setState(() {
                _targetType = values.first;
                _targetDoc = null;
              });
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _idController,
            decoration: const InputDecoration(
              labelText: '対象ドキュメントID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loadTarget,
            icon: const Icon(Icons.search),
            label: const Text('対象を読み込む'),
          ),
          if (_targetDoc != null) ...[
            const SizedBox(height: 24),
            Text(
              _targetDoc!.data()?['title'] ??
                  _targetDoc!.data()?['name'] ??
                  _targetDoc!.id,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
              title: const Text('PR表示を有効にする'),
              subtitle: const Text('ユーザー画面にはPRバッジと非公式注記のみ表示されます'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _promotionTier,
              decoration: const InputDecoration(
                labelText: 'promotionTier',
                border: OutlineInputBorder(),
              ),
              items: _tiers.entries
                  .map((entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _promotionTier = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: '表示ラベル',
                hintText: 'PR',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text(_formatDate('開始', _startAt))),
                TextButton(
                  onPressed: () => _pickDate(isStart: true),
                  child: const Text('開始日'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text(_formatDate('終了', _endAt))),
                TextButton(
                  onPressed: () => _pickDate(isStart: false),
                  child: const Text('終了日'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _externalRefController,
              decoration: const InputDecoration(
                labelText: '管理用外部Ref',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _memoController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '管理メモ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String label, DateTime? date) {
    if (date == null) return '$label: 未設定';
    return '$label: ${date.year}/${date.month}/${date.day}';
  }
}
