import 'package:flutter/material.dart';
import '../services/timetable_service.dart';
import '../services/user_service.dart';
import 'package:textpass/utils/app_toast.dart';

class TimetableSettingsScreen extends StatefulWidget {
  const TimetableSettingsScreen({super.key});

  @override
  State<TimetableSettingsScreen> createState() =>
      _TimetableSettingsScreenState();
}

class _TimetableSettingsScreenState extends State<TimetableSettingsScreen> {
  final _timetableService = TimetableService();
  Map<int, Map<String, int>> _periodTimes = {};
  List<int> _activePeriods = [1, 2, 3, 4, 5];
  bool _isLoading = true;

  final _userService = UserService();
  String _currentSystem = 'semester';
  int _currentTimetableYear = 2025;
  String _currentTimetableTerm = 'spring_group';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final times = await _timetableService.getPeriodTimes();
    final user = await _userService.getCurrentUser();
    final system = user?.timetableSystem ?? 'semester';
    if (mounted) {
      setState(() {
        _periodTimes = times;
        _currentSystem = system;
        _activePeriods = user?.activePeriods ?? [1, 2, 3, 4, 5];
        _currentTimetableYear = user?.currentTimetableYear ??
            _timetableService.currentAcademicYear();
        _currentTimetableTerm = user?.currentTimetableTerm ??
            _timetableService.defaultCurrentTerm(system);
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSystem(String? value) async {
    if (value == null) return;
    await _userService.updateTimetableSystem(value);
    await _userService.updateCurrentTimetable(
      year: _currentTimetableYear,
      term: _timetableService.defaultCurrentTerm(value),
    );
    await _loadSettings(); // Reload to confirm
    if (mounted) {
      AppToast.show(context, '時間割の表示単位を変更しました');
    }
  }

  Future<void> _togglePeriod(int period, bool? isActive) async {
    if (isActive == null) return;

    final newActive = List<int>.from(_activePeriods);
    if (isActive) {
      if (!newActive.contains(period)) {
        newActive.add(period);
        newActive.sort();
      }
    } else {
      newActive.remove(period);
    }

    // Optimization: Optimistic UI update
    setState(() {
      _activePeriods = newActive;
    });

    try {
      await _userService.updateActivePeriods(newActive);
    } catch (e) {
      // Revert if failed
      await _loadSettings();
      if (mounted) {
        AppToast.show(context, '設定の保存に失敗しました');
      }
    }
  }

  Future<void> _resetSettings() async {
    await _timetableService.resetPeriodTimes();
    await _loadSettings();
    if (mounted) {
      AppToast.show(context, '時間割をデフォルトに戻しました');
    }
  }

  Future<void> _editTime(int period, bool isStart) async {
    final current = _periodTimes[period]!;
    final initialTime = TimeOfDay(
      hour: isStart ? current['startHour']! : current['endHour']!,
      minute: isStart ? current['startMinute']! : current['endMinute']!,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      final start = isStart
          ? picked
          : TimeOfDay(
              hour: current['startHour']!, minute: current['startMinute']!);
      final end = isStart
          ? TimeOfDay(hour: current['endHour']!, minute: current['endMinute']!)
          : picked;

      // Basic validation
      final startDouble = start.hour + start.minute / 60.0;
      final endDouble = end.hour + end.minute / 60.0;

      if (startDouble >= endDouble) {
        if (mounted) {
          AppToast.show(context, '開始時間は終了時間より前である必要があります');
        }
        return;
      }

      await _timetableService.savePeriodTime(period, start, end);
      await _loadSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('時間割設定'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'デフォルトに戻す',
            onPressed: _resetSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                ListTile(
                  title: const Text('表示単位'),
                  subtitle: Text(_currentSystem == 'semester'
                      ? '前期・後期でまとめて表示'
                      : 'タームごとに分けて表示'),
                  trailing: DropdownButton<String>(
                    value: _currentSystem,
                    underline: Container(),
                    items: const [
                      DropdownMenuItem(value: 'semester', child: Text('前期・後期')),
                      DropdownMenuItem(value: 'quarter', child: Text('ターム別')),
                    ],
                    onChanged: _toggleSystem,
                  ),
                ),
                ListTile(
                  title: const Text('現在の時間割'),
                  subtitle: Text(
                    '$_currentTimetableYear年度 / ${_termLabel(_currentTimetableTerm)}',
                  ),
                  leading: const Icon(Icons.check_circle_outline),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: 6,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final period = index + 1;
                      final times = _periodTimes[period];
                      final isActive = _activePeriods.contains(period);

                      // Handle missing times gracefully if any
                      if (times == null) return const SizedBox.shrink();

                      final start = TimeOfDay(
                          hour: times['startHour']!,
                          minute: times['startMinute']!);
                      final end = TimeOfDay(
                          hour: times['endHour']!, minute: times['endMinute']!);

                      return ListTile(
                        leading: Checkbox(
                          value: isActive,
                          onChanged: (val) => _togglePeriod(period, val),
                        ),
                        title: Text('$period限',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isActive ? Colors.black87 : Colors.grey,
                              decoration:
                                  isActive ? null : TextDecoration.lineThrough,
                            )),
                        subtitle: isActive
                            ? Row(
                                children: [
                                  _buildTimeChip(
                                      start, () => _editTime(period, true)),
                                  const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('〜'),
                                  ),
                                  _buildTimeChip(
                                      end, () => _editTime(period, false)),
                                ],
                              )
                            : const Text('表示しない',
                                style: TextStyle(color: Colors.grey)),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTimeChip(TimeOfDay time, VoidCallback onTap) {
    return ActionChip(
      label: Text(time.format(context)),
      onPressed: onTap,
      backgroundColor: Colors.grey.shade100,
    );
  }

  String _termLabel(String term) {
    const labels = {
      'spring_group': '前期',
      'fall_group': '後期',
      'other_group': '集中講義・その他',
      '1q': '第1ターム',
      '2q': '第2ターム',
      '3q': '第3ターム',
      '4q': '第4ターム',
    };
    return labels[term] ?? term;
  }
}
