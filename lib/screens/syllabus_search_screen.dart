import 'package:flutter/material.dart';
import '../models/syllabus.dart';
import '../models/user_class.dart';
import '../services/syllabus_service.dart';
import '../services/timetable_service.dart';
import '../widgets/app_custom_input_dialog.dart';
import 'add_class_screen.dart';
import 'class_detail_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class SyllabusSearchScreen extends StatefulWidget {
  final String? initialDay; // e.g., 'Mon'
  final int? initialPeriod; // e.g., 3
  final String? initialSemester; // e.g., '1'
  final int? initialYear; // e.g. 2025

  const SyllabusSearchScreen({
    super.key,
    this.initialDay,
    this.initialPeriod,
    this.initialSemester,
    this.initialYear,
  });

  @override
  State<SyllabusSearchScreen> createState() => _SyllabusSearchScreenState();
}

class _SyllabusSearchScreenState extends State<SyllabusSearchScreen> {
  final _searchController = TextEditingController();
  final _syllabusService = SyllabusService();
  final _timetableService = TimetableService();
  List<Syllabus> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  final Map<String, String> _dayMap = {
    'Mon': '月',
    'Tue': '火',
    'Wed': '水',
    'Thu': '木',
    'Fri': '金',
    'Sat': '土',
  };

  int get _targetYear =>
      widget.initialYear ?? _timetableService.currentAcademicYear();

  @override
  void initState() {
    super.initState();
    // If day/period are provided, auto-search
    if (widget.initialDay != null && widget.initialPeriod != null) {
      _searchSyllabus();
    }
  }

  Future<void> _searchSyllabus() async {
    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final results = await _syllabusService.searchSyllabus(
        _searchController.text.trim(),
        widget.initialDay ?? '',
        widget.initialPeriod ?? 0,
        semester: widget.initialSemester,
        year: _targetYear,
      );

      setState(() {
        _searchResults = results;
        // // print('Syllabus search results: ${results.length}');
        _isLoading = false;
      });
    } catch (e) {
      // // print('Error searching syllabus: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        AppToast.show(context, '検索エラー: $e');
      }
    }
  }

  Future<void> _addToTimetable(Syllabus syllabus) async {
    try {
      final options = await _showRoomOptionsDialog(syllabus);
      if (options == null) return;

      final conflicts = await _syllabusService.getTimetableConflicts(
        syllabus,
        targetYear: _targetYear,
      );
      final conflictDecision = conflicts.isEmpty
          ? const _ConflictDecision()
          : await _showConflictDialog(conflicts);
      if (conflictDecision == null) return;

      final result = await _syllabusService.addToTimetable(
        syllabus,
        targetYear: _targetYear,
        useSharedRoom: options.useSharedRoom,
        shareRoomInfo: options.shareRoomInfo,
        replaceConflictDocIds: conflictDecision.replaceDocIds,
      );
      if (mounted) {
        final message = result.skippedSlots > 0
            ? '時間割に追加しました（${result.skippedSlots}コマは既存授業を残しました）'
            : '時間割に追加しました';
        AppToast.show(context, message);
        Navigator.pop(context, true); // Return true to indicate update
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '追加エラー: $e');
      }
    }
  }

  Future<_ConflictDecision?> _showConflictDialog(
    List<TimetableSlotConflict> conflicts,
  ) async {
    final replaceDocIds = <String>{};
    final bySlot = <String, List<TimetableSlotConflict>>{};
    for (final conflict in conflicts) {
      bySlot.putIfAbsent(conflict.slot.key, () => []).add(conflict);
    }

    return showDialog<_ConflictDecision>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppCustomInputDialog(
          title: '重複するコマがあります',
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.orange,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '既存の授業を残すコマには追加しません。置き換えるコマだけ選択してください。',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              ...bySlot.entries.map((entry) {
                final slotConflicts = entry.value;
                final slot = slotConflicts.first.slot;
                final shouldReplace = slotConflicts.every(
                  (conflict) => replaceDocIds.contains(conflict.existingDocId),
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CheckboxListTile(
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
                      slotConflicts.map((conflict) {
                        final teacher = conflict.existingTeacher.isEmpty
                            ? ''
                            : ' / ${conflict.existingTeacher}';
                        return '現在: ${conflict.existingTitle}$teacher';
                      }).join('\n'),
                    ),
                  ),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                context,
                _ConflictDecision(replaceDocIds: replaceDocIds),
              ),
              child: const Text('この内容で追加'),
            ),
          ],
        ),
      ),
    );
  }

  Future<_RoomAddOptions?> _showRoomOptionsDialog(Syllabus syllabus) async {
    final hasOfficialRoom = syllabus.classroom.trim().isNotEmpty;
    var useSharedRoom = true;
    var shareRoomInfo = hasOfficialRoom;

    if (!hasOfficialRoom && syllabus.classKey.isEmpty) {
      return const _RoomAddOptions();
    }

    return showDialog<_RoomAddOptions>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppCustomInputDialog(
          title: '時間割に追加',
          icon: Icons.add_circle_outline,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_targetYear年度の時間割に追加します。',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              if (hasOfficialRoom) ...[
                Text(
                  '教室: ${syllabus.classroom.trim()}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: shareRoomInfo,
                  onChanged: (value) {
                    setState(() => shareRoomInfo = value ?? false);
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('教室情報を共有候補にする'),
                  subtitle: const Text('同じ授業を追加する学生に、教室候補として表示されます。'),
                ),
              ] else
                CheckboxListTile(
                  value: useSharedRoom,
                  onChanged: (value) {
                    setState(() => useSharedRoom = value ?? true);
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('共有された教室候補があれば使う'),
                  subtitle: const Text('他の学生が共有した教室情報を自分の時間割に反映します。'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                context,
                _RoomAddOptions(
                  useSharedRoom: useSharedRoom,
                  shareRoomInfo: shareRoomInfo,
                ),
              ),
              child: const Text('追加する'),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToAddClass() async {
    if (widget.initialDay == null || widget.initialPeriod == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddClassScreen(
          initialDay: widget.initialDay!,
          initialPeriod: widget.initialPeriod!,
          initialSemester: widget.initialSemester,
          initialYear: widget.initialYear,
        ),
      ),
    );

    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayJa = _dayMap[widget.initialDay] ?? widget.initialDay;

    return Scaffold(
      appBar: AppBar(
        title: const Text('シラバス検索'),
        actions: [
          TextButton(
            onPressed: _navigateToAddClass,
            child: const Text('手動作成',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (widget.initialDay != null && widget.initialPeriod != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Text(
                      '$dayJa曜 ${widget.initialPeriod}限 の授業を探しています',
                      style: TextStyle(
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                Text(
                  '$_targetYear年度のシラバスから検索',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: '講義名・講師名で検索',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onSubmitted: (_) => _searchSyllabus(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _searchSyllabus,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('検索'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final syllabus = _searchResults[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: ListTile(
                              title: Text(syllabus.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(_syllabusSubtitle(syllabus)),
                              trailing: IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                color: Colors.blue,
                                onPressed: () => _addToTimetable(syllabus),
                              ),
                              onTap: () async {
                                final userClass = UserClass(
                                  id: 'preview',
                                  title: syllabus.title,
                                  teacher: syllabus.teacher,
                                  room: syllabus.classroom,
                                  day: widget.initialDay ?? syllabus.day,
                                  period:
                                      widget.initialPeriod ?? syllabus.period,
                                  colorValue: Colors.blue.shade100.toARGB32(),
                                  textbook: syllabus.textbook,
                                  isNotificationEnabled: false,
                                  semester: syllabus.semester,
                                  year: _targetYear,
                                  classKey: syllabus.classKey,
                                );
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ClassDetailScreen(
                                      userClass: userClass,
                                      previewSyllabus: syllabus,
                                    ),
                                  ),
                                );

                                if (result == true && context.mounted) {
                                  Navigator.pop(context, true);
                                }
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    if (!_hasSearched) return const SizedBox.shrink();

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            '授業が見つかりませんでした',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          if (widget.initialDay != null && widget.initialPeriod != null)
            ElevatedButton.icon(
              onPressed: _navigateToAddClass,
              icon: const Icon(Icons.add),
              label: const Text('新しい授業を登録する'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  String _slotLabel(String day, int period) {
    final dayJa = _dayMap[day] ?? day;
    return '$dayJa曜 $period限';
  }

  String _syllabusSubtitle(Syllabus syllabus) {
    final parts = <String>[];
    final schedule = _scheduleSummary(syllabus);
    if (schedule.isNotEmpty) parts.add(schedule);
    if (syllabus.teacher.isNotEmpty) parts.add(syllabus.teacher);
    if (syllabus.classroom.trim().isNotEmpty) {
      parts.add(syllabus.classroom.trim());
    }
    return parts.join(' / ');
  }

  String _scheduleSummary(Syllabus syllabus) {
    final slots = _syllabusService.getAddSlots(
      syllabus,
      targetYear: _targetYear,
    );
    if (slots.isEmpty) return '';
    final labels =
        slots.map((slot) => '${_dayMap[slot.day] ?? slot.day}${slot.period}');
    if (slots.length == 1) return labels.first;
    return '複数コマ: ${labels.join('・')}';
  }
}

class _RoomAddOptions {
  final bool useSharedRoom;
  final bool shareRoomInfo;

  const _RoomAddOptions({
    this.useSharedRoom = true,
    this.shareRoomInfo = false,
  });
}

class _ConflictDecision {
  final Set<String> replaceDocIds;

  const _ConflictDecision({this.replaceDocIds = const {}});
}
