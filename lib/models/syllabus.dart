import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/class_identity.dart';
import '../utils/japanese_display_text.dart';

class Syllabus {
  final String id;
  final String title;
  final String teacher;
  final String day; // 'Mon', 'Tue', etc.
  final int period; // 1, 2, etc.
  final String classroom;
  final String textbook;
  final String createdBy;
  final DateTime createdAt;
  final String universityId;
  final String semester; // Added semester field
  final List<Map<String, dynamic>> schedule; // Added schedule field
  final int year; // Added year field
  final String classKey;

  Syllabus({
    required this.id,
    required this.title,
    required this.teacher,
    required this.day,
    required this.period,
    required this.classroom,
    required this.textbook,
    required this.createdBy,
    required this.createdAt,
    required this.universityId,
    this.semester = '1', // Default to '1'
    this.schedule = const [],
    this.year = 2025, // Default to 2025
    String? classKey,
  }) : classKey = classKey ??
            buildClassKey(
              universityId: universityId,
              title: title,
              teacher: teacher,
            );

  static int _parsePeriod(dynamic value) {
    if (value is int) return value;
    if (value == null) return 0;
    return int.tryParse(value.toString()) ?? 0;
  }

  static List<Map<String, dynamic>> _parseRawDayPeriod(String rawDayPeriod) {
    if (rawDayPeriod.trim().isEmpty) return [];

    const dayMap = {
      '月': 'Mon',
      '火': 'Tue',
      '水': 'Wed',
      '木': 'Thu',
      '金': 'Fri',
      '土': 'Sat',
      '日': 'Sun',
      'Mon': 'Mon',
      'Tue': 'Tue',
      'Wed': 'Wed',
      'Thu': 'Thu',
      'Fri': 'Fri',
      'Sat': 'Sat',
      'Sun': 'Sun',
    };

    final schedule = <Map<String, dynamic>>[];
    final seen = <String>{};
    final pattern = RegExp(
      r'(月|火|水|木|金|土|日|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\.?\s*(\d+)(?:\s*[-〜~]\s*(\d+))?',
    );

    for (final match in pattern.allMatches(rawDayPeriod)) {
      final day = dayMap[match.group(1)];
      final start = int.tryParse(match.group(2) ?? '') ?? 0;
      final end = int.tryParse(match.group(3) ?? '') ?? start;
      if (day == null || start <= 0 || end <= 0) continue;
      for (var period = start; period <= end; period++) {
        final key = '$day:$period';
        if (seen.add(key)) {
          schedule.add({'day': day, 'period': period});
        }
      }
    }

    return schedule;
  }

  factory Syllabus.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    List<Map<String, dynamic>> schedule = [];
    if (data['schedule'] != null) {
      schedule = List<Map<String, dynamic>>.from(data['schedule']);
    }
    if (schedule.isEmpty) {
      schedule = _parseRawDayPeriod(data['raw_day_period']?.toString() ?? '');
    }

    // Legacy fallback: if schedule list exists, use the first entry for day/period
    String day = data['day'] ?? '';
    int period = _parsePeriod(data['period']);

    if (schedule.isNotEmpty && (day.isEmpty || period == 0)) {
      day = schedule[0]['day'] ?? '';
      period = _parsePeriod(schedule[0]['period']);
    }

    return Syllabus(
      id: doc.id,
      title: displayJapanesePrimaryText(data['title']?.toString() ?? ''),
      teacher: displayJapanesePrimaryText(data['teacher']?.toString() ?? ''),
      day: day,
      period: period,
      classroom: data['classroom'] ?? '',
      textbook: data['textbook'] ?? '',
      createdBy: data['created_by'] ?? '',
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      universityId: data['universityId'] ?? 'hokudai',
      semester: data['semester'] ?? '1',
      schedule: schedule,
      year: (data['year'] is int) ? data['year'] : 2025,
      classKey: data['classKey'] ?? data['class_key'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'teacher': teacher,
      'day': day,
      'period': period,
      'classroom': classroom,
      'textbook': textbook,
      'created_by': createdBy,
      'created_at': Timestamp.fromDate(createdAt),
      'universityId': universityId,
      'semester': semester,
      'schedule': schedule,
      'year': year,
      'classKey': classKey,
      'class_key': classKey,
    };
  }
}
