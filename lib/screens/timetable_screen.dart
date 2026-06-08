import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_class.dart';
import '../services/timetable_service.dart';
import '../services/user_service.dart';
import '../widgets/app_custom_dialog.dart';
import '../widgets/app_custom_input_dialog.dart';
import '../widgets/app_selection_dialog.dart';
import 'syllabus_search_screen.dart';
import 'class_detail_screen.dart';
import 'timetable_settings_screen.dart';
import 'review_search_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class TimetableScreen extends StatefulWidget {
  final bool isActive;

  const TimetableScreen({super.key, this.isActive = true});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final _timetableService = TimetableService();
  final _userService = UserService();
  final List<String> _days = ['月', '火', '水', '木', '金'];
  final int _periods = 6;

  // State
  late int _selectedYear;
  String _timetableSystem = 'semester'; // 'semester' or 'quarter'
  String _selectedTab = 'spring_group'; // Initial tab
  List<int> _availableYears = const [];
  bool _isLoadingSettings = true;
  bool _hasConfiguredTimetableSystem = true;
  bool _guideRequested = false;
  bool _guidePending = false;
  int? _currentTimetableYear;
  String? _currentTimetableTerm;

  Map<int, Map<String, int>> _periodTimes = {};
  List<int> _activePeriods = [1, 2, 3, 4, 5];

  @override
  void initState() {
    super.initState();
    _selectedYear = _timetableService.currentAcademicYear();
    _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant TimetableScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive &&
        widget.isActive &&
        !_isLoadingSettings &&
        _hasConfiguredTimetableSystem) {
      _requestToolbarGuideAfterGrid();
    }
  }

  Future<void> _loadInitialData() async {
    final times = await _timetableService.getPeriodTimes();
    final user = await _userService.getCurrentUser();
    final years = await _timetableService.getAvailableYears();
    if (mounted) {
      setState(() {
        final system = user?.timetableSystem ?? 'semester';
        final currentYear = user?.currentTimetableYear ??
            _timetableService.currentAcademicYear();
        final currentTerm = user?.currentTimetableTerm ??
            _timetableService.defaultCurrentTerm(system);
        _periodTimes = times;
        _timetableSystem = system;
        _selectedYear = currentYear;
        _activePeriods = user?.activePeriods ?? [1, 2, 3, 4, 5];
        _hasConfiguredTimetableSystem =
            user?.hasConfiguredTimetableSystem ?? false;
        _currentTimetableYear = currentYear;
        _currentTimetableTerm = currentTerm;
        _availableYears = years;
        if (!_availableYears.contains(_selectedYear)) {
          _availableYears = [..._availableYears, _selectedYear]..sort();
        }

        _selectedTab = _normalizeTabForSystem(currentTerm, system);
        _isLoadingSettings = false;
      });
      if (widget.isActive && user?.hasConfiguredTimetableSystem == true) {
        _requestToolbarGuideAfterGrid();
      }
    }
  }

  Stream<List<UserClass>> get _timetableStream {
    return _timetableService.getClasses(_selectedYear);
  }

  List<int> get _yearMenuItems {
    if (_availableYears.isEmpty) return [_selectedYear];
    if (_availableYears.contains(_selectedYear)) return _availableYears;
    return [..._availableYears, _selectedYear]..sort();
  }

  void _showEditDialog(String day, int period) {
    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: '$day曜 $period限',
        message: '授業を登録しますか？',
        icon: Icons.class_outlined,
        confirmText: 'シラバスから検索',
        onConfirm: () async {
          Navigator.pop(context);
          // When adding via cell tap, we need to decide which term to use.
          // For now, use the currently selected tab to infer semester/term.
          String initialSemester = _inferSemesterFromTab();

          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SyllabusSearchScreen(
                initialDay: _days.contains(day)
                    ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'][_days.indexOf(day)]
                    : null,
                initialPeriod: period,
                initialSemester: initialSemester,
                initialYear: _selectedYear,
              ),
            ),
          );

          if (result == true && mounted) {
            setState(() {
              // Force rebuild to refresh stream
            });
          }
        },
      ),
    );
  }

  void _showDetailDialog(UserClass userClass) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClassDetailScreen(userClass: userClass),
      ),
    );
  }

  Future<void> _showAddClassWizard({String? forceSystem}) async {
    final system = forceSystem ?? _timetableSystem;

    String selectedSemester = '1';

    Future<String?> showSelectionDialog(
      String title,
      List<AppSelectionOption<String>> options,
    ) {
      return showAppSelectionDialog<String>(
        context: context,
        title: title,
        options: options,
        selectedValue: selectedSemester,
      );
    }

    if (system == 'semester') {
      final sem = await showSelectionDialog('学期を選択', const [
        AppSelectionOption(
            label: '前期', value: '1', icon: Icons.wb_sunny_outlined),
        AppSelectionOption(
            label: '後期', value: '2', icon: Icons.ac_unit_outlined),
        AppSelectionOption(
            label: '集中講義・その他', value: 'intensive', icon: Icons.more_horiz),
      ]);
      if (sem == null) return;
      selectedSemester = sem;
    } else if (system == 'quarter') {
      final sem = await showSelectionDialog('タームを選択', const [
        AppSelectionOption(
            label: '第1ターム', value: '1q', icon: Icons.looks_one_outlined),
        AppSelectionOption(
            label: '第2ターム', value: '2q', icon: Icons.looks_two_outlined),
        AppSelectionOption(
            label: '第3ターム', value: '3q', icon: Icons.looks_3_outlined),
        AppSelectionOption(
            label: '第4ターム', value: '4q', icon: Icons.looks_4_outlined),
        AppSelectionOption(
            label: '集中講義・その他', value: 'intensive', icon: Icons.more_horiz),
      ]);
      if (sem == null) return;
      selectedSemester = sem;
    } else {
      selectedSemester = 'intensive';
    }

    _showAddClassDialog(initialSemester: selectedSemester);
  }

  void _showAddClassDialog({String initialSemester = '1'}) {
    String selectedDay = 'Mon';
    int selectedPeriod = 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppCustomInputDialog(
          title: '時間割に追加',
          icon: Icons.add_circle_outline,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '選択中の学期: ${_getSemesterLabel(initialSemester)}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedDay,
                decoration: const InputDecoration(labelText: '曜日'),
                items: _days.asMap().entries.map((entry) {
                  final dayCode =
                      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'][entry.key];
                  return DropdownMenuItem(
                    value: dayCode,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (val) => setState(() => selectedDay = val!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: selectedPeriod,
                decoration: const InputDecoration(labelText: '時限'),
                // Filter dropdown items by active periods
                items: List.generate(_periods, (i) => i + 1)
                    .where((p) => _activePeriods.contains(p))
                    .map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text('$p限'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => selectedPeriod = val!),
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
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SyllabusSearchScreen(
                      initialDay: selectedDay,
                      initialPeriod: selectedPeriod,
                      initialSemester: initialSemester,
                      initialYear: _selectedYear,
                    ),
                  ),
                );

                if (result == true && mounted) {
                  setState(() {});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('検索へ'),
            ),
          ],
        ),
      ),
    );
  }

  String _inferSemesterFromTab() {
    // Return a reasonable default based on current tab
    if (_selectedTab == 'spring_group') return '1';
    if (_selectedTab == 'fall_group') return '2';
    if (_selectedTab == '1q') return '1q';
    if (_selectedTab == '2q') return '2q';
    if (_selectedTab == '3q') return '3q';
    if (_selectedTab == '4q') return '4q';
    if (_selectedTab == 'other_group') return 'intensive';
    return '1';
  }

  String _getSemesterLabel(String sem) {
    if (sem == '1') return '前期';
    if (sem == '2') return '後期';
    if (sem == '1q') return '1ターム';
    if (sem == '2q') return '2ターム';
    if (sem == '3q') return '3ターム';
    if (sem == '4q') return '4ターム';
    if (sem == 'intensive') return '集中/その他';
    if (sem == 'year_round') return '通年';
    return sem;
  }

  bool _classMatchesSelectedTab(UserClass userClass) {
    return _timetableService.classMatchesTerm(
        userClass, _selectedTab, _timetableSystem);
  }

  String _normalizeTabForSystem(String? term, String system) {
    if (system == 'semester') {
      if (term == 'fall_group' || term == 'other_group') return term!;
      return 'spring_group';
    }
    if (['1q', '2q', '3q', '4q', 'other_group'].contains(term)) return term!;
    return '1q';
  }

  bool get _isCurrentTimetableSelected {
    return _currentTimetableYear == _selectedYear &&
        _currentTimetableTerm == _selectedTab;
  }

  Future<void> _setCurrentTimetable() async {
    await _userService.updateCurrentTimetable(
      year: _selectedYear,
      term: _selectedTab,
    );
    if (!mounted) return;
    setState(() {
      _currentTimetableYear = _selectedYear;
      _currentTimetableTerm = _selectedTab;
    });
    AppToast.show(context, '現在の時間割に設定しました');
  }

  Future<void> _chooseInitialSystem(String system) async {
    await _userService.updateTimetableSystem(system);
    await _userService.updateActivePeriods(const [1, 2, 3, 4, 5]);
    final year = _timetableService.currentAcademicYear();
    final term = _timetableService.defaultCurrentTerm(system);
    await _userService.updateCurrentTimetable(year: year, term: term);
    if (!mounted) return;
    setState(() {
      _timetableSystem = system;
      _selectedYear = year;
      _activePeriods = const [1, 2, 3, 4, 5];
      _selectedTab = term;
      _currentTimetableYear = year;
      _currentTimetableTerm = term;
      _hasConfiguredTimetableSystem = true;
    });
    _requestToolbarGuideAfterGrid();
  }

  void _requestToolbarGuideAfterGrid() {
    if (_guideRequested || _guidePending || !mounted || !widget.isActive) {
      return;
    }
    setState(() {
      _guidePending = true;
    });
  }

  Future<void> _showToolbarGuideIfNeeded() async {
    if (_guideRequested || !mounted || !widget.isActive) return;
    final prefs = await SharedPreferences.getInstance();
    const key = 'timetable_toolbar_guide_seen_v2';
    if (prefs.getBool(key) == true || !mounted) return;

    _guideRequested = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '時間割タブのボタン',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              _buildGuideRow(
                Icons.check_circle_outline,
                '現在の時間割',
                'ホームの「次の授業」に使う年度・学期を設定します。',
              ),
              _buildGuideRow(
                Icons.rate_review_outlined,
                '授業レビュー検索',
                '授業名や教員名から、過去のレビューを探せます。',
              ),
              _buildGuideRow(
                Icons.settings,
                '時間割設定',
                '表示単位や、表示する時限を変更できます。',
              ),
              _buildGuideRow(
                Icons.add,
                '授業を追加',
                'シラバス検索または手動作成で時間割に授業を追加します。',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('わかりました'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await prefs.setBool(key, true);
  }

  void _showPendingGuideAfterThisFrame() {
    if (!_guidePending || !widget.isActive) return;
    _guidePending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showToolbarGuideIfNeeded();
    });
  }

  Widget _buildGuideRow(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 20, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialSystemScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('時間割')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '時間割の表示単位を選択',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'あとから設定で変更できます。まずは普段使う形式を選んでください。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 28),
                _buildSystemChoiceButton(
                  title: '前期・後期で表示',
                  subtitle: '半期単位で授業を管理する',
                  icon: Icons.calendar_view_week_outlined,
                  onTap: () => _chooseInitialSystem('semester'),
                ),
                const SizedBox(height: 12),
                _buildSystemChoiceButton(
                  title: 'タームごとに表示',
                  subtitle: '1Tから4Tまで分けて管理する',
                  icon: Icons.grid_view_outlined,
                  onTap: () => _chooseInitialSystem('quarter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSystemChoiceButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: Theme.of(context).primaryColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const semesterSegments = [
      ButtonSegment(
          value: 'spring_group',
          label: Text('前期'),
          icon: Icon(Icons.wb_sunny_outlined)),
      ButtonSegment(
          value: 'fall_group',
          label: Text('後期'),
          icon: Icon(Icons.ac_unit_outlined)),
      ButtonSegment(
          value: 'other_group',
          label: Text('集中/他'),
          icon: Icon(Icons.more_horiz)),
    ];

    const quarterSegments = [
      ButtonSegment(value: '1q', label: Text('1T')),
      ButtonSegment(value: '2q', label: Text('2T')),
      ButtonSegment(value: '3q', label: Text('3T')),
      ButtonSegment(value: '4q', label: Text('4T')),
      ButtonSegment(value: 'other_group', label: Text('他')),
    ];

    if (_isLoadingSettings) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasConfiguredTimetableSystem) {
      return _buildInitialSystemScreen();
    }

    return StreamBuilder<List<UserClass>>(
      stream: _timetableStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return Scaffold(
              appBar: AppBar(title: const Text('時間割')),
              body: Center(child: Text('エラーが発生しました: ${snapshot.error}')));
        }

        final allClasses = snapshot.data ?? [];
        final classes = allClasses.where(_classMatchesSelectedTab).toList();
        _showPendingGuideAfterThisFrame();

        // Prepare Map for Table
        final classMap = {
          for (var c in classes) '${_dayToJa(c.day)}_${c.period}': c
        };

        return Scaffold(
          appBar: AppBar(
            title: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedYear,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.black87),
                items: _yearMenuItems.map((y) {
                  return DropdownMenuItem(
                      value: y,
                      child: Text('$y年度',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.black87)));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedYear = val);
                },
              ),
            ),
            centerTitle: false,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<String>(
                    segments: _timetableSystem == 'semester'
                        ? semesterSegments
                        : quarterSegments,
                    selected: {_selectedTab},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() {
                        _selectedTab = newSelection.first;
                      });
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: IconButton(
                  icon: Icon(
                    _isCurrentTimetableSelected
                        ? Icons.check_rounded
                        : Icons.check_circle_outline_rounded,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: _isCurrentTimetableSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                    foregroundColor: _isCurrentTimetableSelected
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary,
                    disabledBackgroundColor:
                        Theme.of(context).colorScheme.primary,
                    disabledForegroundColor: Colors.white,
                    side: _isCurrentTimetableSelected
                        ? BorderSide.none
                        : BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.35),
                          ),
                  ),
                  tooltip:
                      _isCurrentTimetableSelected ? '現在の時間割' : 'この時間割を現在に設定',
                  onPressed:
                      _isCurrentTimetableSelected ? null : _setCurrentTimetable,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.rate_review_outlined),
                tooltip: '授業レビュー検索',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ReviewSearchScreen(),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TimetableSettingsScreen(),
                    ),
                  );
                  _loadInitialData();
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Table(
              columnWidths: const {
                0: FixedColumnWidth(50),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
                3: FlexColumnWidth(),
                4: FlexColumnWidth(),
                5: FlexColumnWidth(),
              },
              border: TableBorder.all(color: Colors.grey.shade300),
              children: [
                // Header Row
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey.shade50),
                  children: [
                    const SizedBox(height: 40),
                    ..._days.map((day) => Container(
                          height: 40,
                          alignment: Alignment.center,
                          child: Text(day,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey)),
                        )),
                  ],
                ),

                // Body Rows
                ...List.generate(_periods, (index) => index + 1)
                    .where((period) => _activePeriods.contains(period))
                    .map((period) {
                  final times = _periodTimes[period];
                  String startStr = '';
                  String endStr = '';
                  if (times != null) {
                    final start = TimeOfDay(
                        hour: times['startHour']!,
                        minute: times['startMinute']!);
                    final end = TimeOfDay(
                        hour: times['endHour']!, minute: times['endMinute']!);
                    startStr =
                        '${start.hour}:${start.minute.toString().padLeft(2, '0')}';
                    endStr =
                        '${end.hour}:${end.minute.toString().padLeft(2, '0')}';
                  }

                  return TableRow(
                    children: [
                      // Time Column Cell
                      Container(
                        height: 100,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(startStr,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                            Text('$period',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey)),
                            Text(endStr,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                      ),
                      // Day Cells
                      ..._days.map((day) {
                        final key = '${day}_$period';
                        final userClass = classMap[key];
                        return Container(
                          height: 100,
                          padding: const EdgeInsets.all(2),
                          child: _buildClassCell(userClass, day, period),
                        );
                      }),
                    ],
                  );
                }),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            heroTag: 'timetable_fab',
            onPressed: _showAddClassWizard,
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildClassCell(UserClass? userClass, String day, int period) {
    if (userClass == null) {
      return InkWell(
        onTap: () => _showEditDialog(day, period),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
        ),
      );
    }

    final textColor = _getTextColor(Color(userClass.colorValue));

    return InkWell(
      onTap: () => _showDetailDialog(userClass),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Color(userClass.colorValue),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            )
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              userClass.title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            if (userClass.room.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 10, color: textColor.withValues(alpha: 0.7)),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      userClass.room,
                      style: TextStyle(
                        fontSize: 9,
                        color: textColor.withValues(alpha: 0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Color _getTextColor(Color backgroundColor) {
    return ThemeData.estimateBrightnessForColor(backgroundColor) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
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
