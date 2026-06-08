import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../models/circle.dart';
import '../../models/event.dart';
import '../../services/event_service.dart';
import '../../services/circle_service.dart';
import 'draft_events_screen.dart';
import 'package:textpass/utils/app_toast.dart';

enum EventCreationMode { single, multiple, recurring }

class CreateEventScreen extends StatefulWidget {
  final Event? eventToEdit;
  final Event? eventToDuplicate;

  const CreateEventScreen({
    super.key,
    this.eventToEdit,
    this.eventToDuplicate,
  });

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _eventService = EventService();
  final _circleService = CircleService();
  final _imagePicker = ImagePicker();

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _locationController;
  late TextEditingController _descController;

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late CircleCategory _selectedCategory;
  bool _isLoading = false;
  Circle? _myCircle;
  File? _imageFile;
  String? _currentImageUrl;

  // Modes
  EventCreationMode _creationMode = EventCreationMode.single;

  // Multiple Mode State
  final Set<DateTime> _selectedDates = {};
  DateTime _focusedDay = DateTime.now();

  // Recurring Mode State
  DateTimeRange? _dateRange;
  final Set<int> _selectedWeekdays = {}; // 1 = Mon, 7 = Sun

  // Predefined tags
  final List<String> _availableTags = [
    'ご飯あり',
    '飲み会',
    'スポーツ',
    'インカレ',
    '初心者歓迎',
    'ガチ勢',
    'まったり',
    '音楽',
    'ゲーム',
    '勉強会'
  ];
  final Set<String> _selectedTags = {};

  @override
  void initState() {
    super.initState();
    _loadMyCircle();

    // Initialize controllers
    final event = widget.eventToEdit ?? widget.eventToDuplicate;
    _titleController = TextEditingController(text: event?.title ?? '');
    _locationController = TextEditingController(text: event?.location ?? '');
    _descController = TextEditingController(text: event?.description ?? '');

    // Date & Time
    if (widget.eventToEdit != null) {
      _selectedDate = widget.eventToEdit!.startAt;
      _selectedTime = TimeOfDay.fromDateTime(widget.eventToEdit!.startAt);
    } else {
      _selectedDate = DateTime.now();
      _selectedTime = TimeOfDay.now();
    }

    if (widget.eventToDuplicate != null) {
      // Reset date for duplicate as per requirement
      _selectedDate = DateTime.now();
    }

    _selectedCategory = event?.category ?? CircleCategory.other;
    if (event != null) {
      _selectedTags.addAll(event.tags);
      _currentImageUrl = event.imageUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadMyCircle() async {
    final circle = await _circleService.getUserCircle();
    setState(() => _myCircle = circle);
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() => _selectedTime = picked);
    }
  }

  List<DateTime> _calculateRecurringDates() {
    if (_dateRange == null || _selectedWeekdays.isEmpty) return [];

    List<DateTime> dates = [];
    DateTime current = _dateRange!.start;
    while (current.isBefore(_dateRange!.end) ||
        current.isAtSameMomentAs(_dateRange!.end)) {
      if (_selectedWeekdays.contains(current.weekday)) {
        dates.add(DateTime(
          current.year,
          current.month,
          current.day,
          _selectedTime.hour,
          _selectedTime.minute,
        ));
      }
      current = current.add(const Duration(days: 1));
    }
    return dates;
  }

  Future<void> _submit({bool isDraft = false}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_myCircle == null) return;

    List<DateTime> targetDates = [];

    // Validation & Date Calculation based on Mode
    if (_creationMode == EventCreationMode.single) {
      targetDates.add(DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      ));
    } else if (_creationMode == EventCreationMode.multiple) {
      if (_selectedDates.isEmpty) {
        AppToast.show(context, '日付を選択してください');
        return;
      }
      // Sort dates
      final sortedDates = _selectedDates.toList()..sort();
      for (var date in sortedDates) {
        targetDates.add(DateTime(
          date.year,
          date.month,
          date.day,
          _selectedTime.hour,
          _selectedTime.minute,
        ));
      }
    } else if (_creationMode == EventCreationMode.recurring) {
      if (_dateRange == null) {
        AppToast.show(context, '期間を選択してください');
        return;
      }
      if (_selectedWeekdays.isEmpty) {
        AppToast.show(context, '曜日を選択してください');
        return;
      }
      targetDates = _calculateRecurringDates();
      if (targetDates.isEmpty) {
        AppToast.show(context, '選択された期間・曜日に該当する日付がありません');
        return;
      }
    }

    if (targetDates.length > 30) {
      AppToast.show(context, '一度に作成できるイベントは30件までです');
      return;
    }

    setState(() => _isLoading = true);
    try {
      String? imageUrl = _currentImageUrl;
      if (_imageFile != null) {
        imageUrl = await _eventService.uploadImage(_imageFile!.path);
      }

      // If editing a single event (and staying in single mode), use updateEvent
      if (widget.eventToEdit != null &&
          _creationMode == EventCreationMode.single) {
        await _eventService.updateEvent(
          eventId: widget.eventToEdit!.id,
          circleId: _myCircle!.id,
          title: _titleController.text,
          startAt: targetDates.first,
          location: _locationController.text,
          category: _selectedCategory,
          tags: _selectedTags.toList(),
          imageUrl: imageUrl,
          isDraft: isDraft,
          description: _descController.text,
          createdAt:
              (widget.eventToEdit!.isDraft && !isDraft) ? DateTime.now() : null,
        );
      } else {
        // Batch Creation (works for single new event too)
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .get();
        final uniId = userDoc.data()?['universityId'] as String? ?? '';

        final events = targetDates.map((date) {
          final eventRef =
              FirebaseFirestore.instance.collection('events').doc();
          return Event(
            id: eventRef.id,
            circleId: _myCircle!.id,
            title: _titleController.text,
            startAt: date,
            location: _locationController.text,
            category: _selectedCategory,
            tags: _selectedTags.toList(),
            imageUrl: imageUrl,
            isDraft: isDraft,
            description: _descController.text,
            createdAt: DateTime.now(),
            universityId: uniId,
          );
        }).toList();

        await _eventService.createEventsBatch(events);
      }

      if (mounted) {
        String msg = isDraft ? '下書き保存しました' : 'イベントを公開しました';
        if (targetDates.length > 1) {
          msg = '${targetDates.length}件の$msg';
        }
        AppToast.show(context, msg);
        Navigator.pop(context);
        if (widget.eventToEdit != null) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'エラー: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_myCircle == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.eventToEdit != null ? 'イベント編集' : 'イベント作成'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          if (widget.eventToEdit == null && _myCircle != null)
            TextButton.icon(
              icon: const Icon(Icons.folder_open, size: 20),
              label: const Text('下書き'),
              style: TextButton.styleFrom(foregroundColor: Colors.grey[800]),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DraftEventsScreen(circleId: _myCircle!.id),
                  ),
                );
              },
            ),
          TextButton(
            onPressed: _isLoading ? null : () => _submit(isDraft: false),
            child: Text(
              _isLoading ? '保存中...' : '公開',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCoverImagePicker(),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleInput(),
                    const SizedBox(height: 24),

                    // Mode Switcher (Only for new events or duplication)
                    if (widget.eventToEdit == null) ...[
                      _buildModeSwitcher(),
                      const SizedBox(height: 24),
                    ],

                    _buildDateTimeLocationSection(),
                    const SizedBox(height: 24),
                    _buildCategoryAndTagsSection(),
                    const SizedBox(height: 24),
                    _buildDescriptionInput(),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed:
                            _isLoading ? null : () => _submit(isDraft: true),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Colors.grey),
                        ),
                        child: const Text('下書きとして保存',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return Center(
      child: SegmentedButton<EventCreationMode>(
        segments: const [
          ButtonSegment<EventCreationMode>(
            value: EventCreationMode.single,
            label: Text('単発'),
            icon: Icon(Icons.event),
          ),
          ButtonSegment<EventCreationMode>(
            value: EventCreationMode.multiple,
            label: Text('複数'),
            icon: Icon(Icons.calendar_month),
          ),
          ButtonSegment<EventCreationMode>(
            value: EventCreationMode.recurring,
            label: Text('繰り返し'),
            icon: Icon(Icons.repeat),
          ),
        ],
        selected: {_creationMode},
        onSelectionChanged: (Set<EventCreationMode> newSelection) {
          setState(() {
            _creationMode = newSelection.first;
          });
        },
        style: const ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Widget _buildCoverImagePicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.grey.shade200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_imageFile != null)
                Image.file(_imageFile!, fit: BoxFit.cover)
              else if (_currentImageUrl != null)
                Image.network(_currentImageUrl!, fit: BoxFit.cover)
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo,
                        size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'カバー写真を追加',
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              if (_imageFile != null || _currentImageUrl != null)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.edit, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          '変更',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleInput() {
    return TextFormField(
      controller: _titleController,
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      decoration: const InputDecoration(
        hintText: 'イベントタイトルを入力',
        border: InputBorder.none,
        hintStyle: TextStyle(color: Colors.black26),
      ),
      validator: (value) => value == null || value.isEmpty ? 'タイトルは必須です' : null,
    );
  }

  Widget _buildDateTimeLocationSection() {
    Widget content;

    if (_creationMode == EventCreationMode.recurring) {
      // Recurring Mode UI
      final dateCount = _calculateRecurringDates().length;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildListTileInput(
            icon: Icons.date_range,
            label: _dateRange == null
                ? '期間を選択'
                : '${DateFormat('yyyy/MM/dd').format(_dateRange!.start)} 〜 ${DateFormat('yyyy/MM/dd').format(_dateRange!.end)}',
            onTap: () => _selectDateRange(context),
          ),
          const Divider(height: 1),
          _buildListTileInput(
            icon: Icons.access_time,
            label: _selectedTime.format(context),
            onTap: () => _selectTime(context),
          ),
          const SizedBox(height: 16),
          const Text('曜日を選択', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (int i = 1; i <= 7; i++)
                FilterChip(
                  label: Text(_getWeekdayLabel(i)),
                  selected: _selectedWeekdays.contains(i),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedWeekdays.add(i);
                      } else {
                        _selectedWeekdays.remove(i);
                      }
                    });
                  },
                  showCheckmark: false,
                  selectedColor: Colors.orange.shade100,
                  labelStyle: TextStyle(
                    color: _selectedWeekdays.contains(i)
                        ? Colors.orange.shade900
                        : Colors.black,
                    fontWeight: _selectedWeekdays.contains(i)
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCountPreview(dateCount),
        ],
      );
    } else if (_creationMode == EventCreationMode.multiple) {
      // Multiple Mode UI
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableCalendar(
            firstDay: DateTime.now(),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: _focusedDay,
            currentDay: DateTime.now(),
            calendarFormat: CalendarFormat.month,
            selectedDayPredicate: (day) {
              return _selectedDates.any((d) => isSameDay(d, day));
            },
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
                // Toggle selection
                // Normalize date to remove time part for comparison
                final normalizedDate = DateTime(
                    selectedDay.year, selectedDay.month, selectedDay.day);

                // Check if already selected (using simple iteration or set lookup if normalized)
                // Since _selectedDates stores normalized dates:
                if (_selectedDates.any((d) => isSameDay(d, normalizedDate))) {
                  _selectedDates
                      .removeWhere((d) => isSameDay(d, normalizedDate));
                } else {
                  _selectedDates.add(normalizedDate);
                }
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            calendarStyle: CalendarStyle(
              selectedDecoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('選択された日付', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_selectedDates.isEmpty)
            const Text('日付が選択されていません', style: TextStyle(color: Colors.grey)),
          Wrap(
            spacing: 8,
            children: [
              for (final date in _selectedDates.toList()..sort())
                Chip(
                  label: Text(DateFormat('MM/dd').format(date)),
                  onDeleted: () {
                    setState(() {
                      _selectedDates.remove(date);
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          _buildListTileInput(
            icon: Icons.access_time,
            label: _selectedTime.format(context),
            onTap: () => _selectTime(context),
          ),
          const SizedBox(height: 16),
          _buildCountPreview(_selectedDates.length),
        ],
      );
    } else {
      // Single Mode UI
      content = Column(
        children: [
          _buildListTileInput(
            icon: Icons.calendar_today,
            label: DateFormat('yyyy/MM/dd (E)', 'ja').format(_selectedDate),
            onTap: () => _selectDate(context),
          ),
          const Divider(height: 1),
          _buildListTileInput(
            icon: Icons.access_time,
            label: _selectedTime.format(context),
            onTap: () => _selectTime(context),
          ),
        ],
      );
    }

    return Column(
      children: [
        content,
        const Divider(height: 1),
        _buildListTileInput(
          icon: Icons.location_on,
          child: TextFormField(
            controller: _locationController,
            decoration: const InputDecoration(
              hintText: '開催場所を入力',
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            validator: (value) =>
                value == null || value.isEmpty ? '場所は必須です' : null,
          ),
        ),
      ],
    );
  }

  Widget _buildCountPreview(int count) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            '合計 $count 件のイベントを作成します',
            style: const TextStyle(
                color: Colors.blue, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _getWeekdayLabel(int weekday) {
    const labels = ['月', '火', '水', '木', '金', '土', '日'];
    return labels[weekday - 1];
  }

  Widget _buildListTileInput({
    required IconData icon,
    String? label,
    Widget? child,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey.shade600),
            const SizedBox(width: 16),
            Expanded(
              child: child ??
                  Text(
                    label ?? '',
                    style: const TextStyle(fontSize: 16),
                  ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryAndTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('カテゴリ',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: CircleCategory.values.map((category) {
            final isSelected = _selectedCategory == category;
            return ChoiceChip(
              label: Text(category.label),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) setState(() => _selectedCategory = category);
              },
              selectedColor: Colors.orange.shade100,
              labelStyle: TextStyle(
                color: isSelected ? Colors.orange.shade800 : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        const Text('タグ',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableTags.map((tag) {
            final isSelected = _selectedTags.contains(tag);
            return FilterChip(
              label: Text(tag),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedTags.add(tag);
                  } else {
                    _selectedTags.remove(tag);
                  }
                });
              },
              selectedColor: Colors.blue.shade100,
              labelStyle: TextStyle(
                color: isSelected ? Colors.blue.shade800 : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              checkmarkColor: Colors.blue.shade800,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDescriptionInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('詳細',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: TextFormField(
            controller: _descController,
            decoration: const InputDecoration(
              hintText: 'イベントの詳細を入力してください',
              border: InputBorder.none,
            ),
            maxLines: 8,
          ),
        ),
      ],
    );
  }
}
