import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/syllabus.dart';
import '../models/user_class.dart';
import '../services/shared_room_service.dart';
import '../services/syllabus_service.dart';
import '../widgets/app_custom_input_dialog.dart';
import 'package:textpass/utils/app_toast.dart';

class AddClassScreen extends StatefulWidget {
  final String initialDay; // 'Mon', 'Tue', etc.
  final int initialPeriod; // 1, 2, etc.
  final String? initialSemester; // '1', '2' etc.
  final int? initialYear;
  final UserClass? userClassToEdit;

  const AddClassScreen({
    super.key,
    required this.initialDay,
    required this.initialPeriod,
    this.initialSemester,
    this.initialYear,
    this.userClassToEdit,
  });

  @override
  State<AddClassScreen> createState() => _AddClassScreenState();
}

class _AddClassScreenState extends State<AddClassScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _teacherController = TextEditingController();
  final _classroomController = TextEditingController();
  final _textbookController = TextEditingController();
  bool _isLoading = false;
  bool _isScanning = false;
  bool _shareRoomInfo = true;
  int _selectedColor = Colors.blue.shade100.toARGB32();
  final _sharedRoomService = SharedRoomService();
  final _syllabusService = SyllabusService();

  final Map<String, String> _dayMap = {
    'Mon': '月',
    'Tue': '火',
    'Wed': '水',
    'Thu': '木',
    'Fri': '金',
    'Sat': '土',
  };

  final List<Color> _pastelColors = [
    Colors.blue.shade100,
    Colors.red.shade100,
    Colors.green.shade100,
    Colors.orange.shade100,
    Colors.purple.shade100,
    Colors.teal.shade100,
    Colors.pink.shade100,
    Colors.amber.shade100,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.userClassToEdit != null) {
      final c = widget.userClassToEdit!;
      _titleController.text = c.title;
      _teacherController.text = c.teacher;
      _classroomController.text = c.room;
      _textbookController.text = c.textbook;
      _selectedColor = c.colorValue;
      _shareRoomInfo = c.room.isNotEmpty;
    } else {
      // Random default color
      _selectedColor = (_pastelColors..shuffle()).first.toARGB32();
    }
  }

  Future<void> _saveClass() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ログインが必要です');

      if (widget.userClassToEdit != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final universityId = userDoc.data()?['universityId'] as String? ?? '';
        final roomName = _classroomController.text.trim();
        final currentClass = widget.userClassToEdit!;
        final canShareRoomInfo = _canShareRoomInfo;

        // Update existing class
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('timetable')
            .doc(widget.userClassToEdit!.id)
            .update({
          'name': _titleController.text.trim(),
          'teacher': _teacherController.text.trim(),
          'room': _classroomController.text.trim(),
          'room_source': roomName.isEmpty
              ? 'none'
              : canShareRoomInfo && _shareRoomInfo
                  ? 'shared'
                  : currentClass.syllabusSource == 'custom'
                      ? 'manual'
                      : 'user',
          'textbook': _textbookController.text.trim(),
          'color': _selectedColor,
        });

        if (canShareRoomInfo && roomName.isNotEmpty && _shareRoomInfo) {
          await _sharedRoomService.shareRoom(
            classKey: currentClass.classKey,
            title: _titleController.text.trim(),
            teacher: _teacherController.text.trim(),
            universityId: universityId,
            roomName: roomName,
          );
        } else if (canShareRoomInfo) {
          await _sharedRoomService.removeMySuggestion(currentClass.classKey);
        }

        if (mounted) {
          AppToast.show(context, '授業情報を更新しました');
          Navigator.pop(context, true);
        }
      } else {
        // Create new class
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final universityId = userDoc.data()?['universityId'] as String? ?? '';

        final syllabus = Syllabus(
          id: '', // Service will generate ID
          title: _titleController.text.trim(),
          teacher: _teacherController.text.trim(),
          day: widget.initialDay,
          period: widget.initialPeriod,
          classroom: _classroomController.text.trim(),
          textbook: _textbookController.text.trim(),
          createdBy: user.uid,
          createdAt: DateTime.now(),
          universityId: universityId,
          semester: widget.initialSemester ?? '1',
          year: widget.initialYear ?? 2025,
        );

        final conflicts = await _syllabusService.getTimetableConflicts(
          syllabus,
          targetYear: syllabus.year,
        );
        final replaceIds = conflicts.isEmpty
            ? <String>{}
            : await _showConflictDialog(conflicts);
        if (replaceIds == null) return;

        await _syllabusService.registerNewClass(
          syllabus,
          colorValue: _selectedColor,
          replaceConflictDocIds: replaceIds,
        );

        if (mounted) {
          AppToast.show(context, '授業を登録しました');
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'エラーが発生しました: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final String code = barcode.rawValue!;
        // ISBN check (simple length check for 10 or 13 digits)
        if (code.length == 10 || code.length == 13) {
          setState(() {
            _textbookController.text = code; // Set ISBN to field
            _isScanning = false; // Stop scanning
          });
          AppToast.show(context, 'ISBNを読み取りました');
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayJa = _dayMap[widget.initialDay] ?? widget.initialDay;
    final isEdit = widget.userClassToEdit != null;
    final canShareRoomInfo = _canShareRoomInfo;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '授業の編集' : '授業の新規登録'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isScanning
          ? Stack(
              children: [
                MobileScanner(
                  onDetect: _onBarcodeDetected,
                ),
                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ElevatedButton(
                      onPressed: () => setState(() => _isScanning = false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('スキャンをキャンセル'),
                    ),
                  ),
                ),
                const Center(
                  child: Text(
                    '教科書のバーコードをスキャンしてください',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(blurRadius: 4, color: Colors.black),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Color(_selectedColor),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$dayJa曜 ${widget.initialPeriod}限',
                            style: TextStyle(
                              color:
                                  Color(_selectedColor).computeLuminance() > 0.5
                                      ? Colors.black87
                                      : Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isEdit ? '授業情報を修正できます' : 'この授業の情報を入力してください',
                            style: TextStyle(
                              color:
                                  Color(_selectedColor).computeLuminance() > 0.5
                                      ? Colors.black54
                                      : Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Color Picker
                    const Text(
                      '授業カラー',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 50,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _pastelColors.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final color = _pastelColors[index];
                          final isSelected = color.toARGB32() == _selectedColor;
                          return GestureDetector(
                            onTap: () => setState(
                                () => _selectedColor = color.toARGB32()),
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(color: Colors.black, width: 3)
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withValues(alpha: 0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check,
                                      color: Colors.black54)
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Form Fields
                    _buildTextField(
                      controller: _titleController,
                      label: '講義名',
                      icon: Icons.school,
                      isRequired: true,
                      hint: '例: 線形代数I',
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _teacherController,
                      label: '教員名',
                      icon: Icons.person,
                      hint: '例: 北大 太郎',
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _classroomController,
                      label: '教室',
                      icon: Icons.room,
                      hint: '例: A201',
                    ),
                    if (canShareRoomInfo)
                      CheckboxListTile(
                        value: _shareRoomInfo,
                        onChanged: (value) {
                          setState(() => _shareRoomInfo = value ?? true);
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('同じ授業の学生に教室情報を共有する'),
                        subtitle: const Text('共有すると、他の学生が追加する時の教室候補になります。'),
                      ),
                    const SizedBox(height: 24),

                    // Textbook Section
                    const Text(
                      '教科書情報',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _textbookController,
                            label: '教科書名 / ISBN',
                            icon: Icons.menu_book,
                            hint: '教科書名またはISBN',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            onPressed: () => setState(() => _isScanning = true),
                            icon: const Icon(Icons.qr_code_scanner),
                            color: Colors.blue,
                            tooltip: 'バーコードをスキャン',
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 12, top: 4),
                      child: Text(
                        'ISBNを入力すると、フリマ検索がより正確になります',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveClass,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : Text(
                                isEdit ? '更新する' : '登録して時間割に追加',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  bool get _canShareRoomInfo {
    final editingClass = widget.userClassToEdit;
    if (editingClass == null) return false;
    if (editingClass.syllabusSource == 'custom') return false;
    if (editingClass.syllabusId.startsWith('custom_')) return false;
    return editingClass.classKey.isNotEmpty;
  }

  Future<Set<String>?> _showConflictDialog(
    List<TimetableSlotConflict> conflicts,
  ) async {
    final replaceDocIds = <String>{};
    return showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppCustomInputDialog(
          title: '重複するコマがあります',
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.orange,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: conflicts.map((conflict) {
              final shouldReplace =
                  replaceDocIds.contains(conflict.existingDocId);
              return CheckboxListTile(
                value: shouldReplace,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      replaceDocIds.add(conflict.existingDocId);
                    } else {
                      replaceDocIds.remove(conflict.existingDocId);
                    }
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  '${_dayMap[conflict.slot.day] ?? conflict.slot.day}曜 ${conflict.slot.period}限を置き換える',
                ),
                subtitle: Text('現在: ${conflict.existingTitle}'),
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
              child: const Text('この内容で登録'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool isRequired = false,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: isRequired ? '$label (必須)' : label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: isRequired
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return '$labelを入力してください';
              }
              return null;
            }
          : null,
    );
  }
}
