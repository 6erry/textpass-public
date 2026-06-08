import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/class_identity.dart';
import '../utils/japanese_display_text.dart';

class UserClass {
  final String id;
  final String title;
  final String teacher;
  final String room;
  final String day; // 'Mon', 'Tue', etc.
  final int period; // 1-7
  final int colorValue;
  final int attended;
  final int absent;
  final int late;
  final String memo;
  final String syllabusId;
  final String syllabusSource;
  final String textbook;
  final bool isNotificationEnabled;
  final String semester; // Added semester field
  final int year; // Added year field (e.g. 2025)
  final String classKey;

  UserClass({
    required this.id,
    required this.title,
    required this.teacher,
    required this.room,
    required this.day,
    required this.period,
    required this.colorValue,
    this.attended = 0,
    this.absent = 0,
    this.late = 0,
    this.memo = '',
    this.syllabusId = '',
    this.syllabusSource = '',
    this.textbook = '',
    this.isNotificationEnabled = false,
    this.semester = '1', // Default to '1'
    this.year = 2025, // Default to current year for now
    String? classKey,
  }) : classKey = classKey ??
            buildClassKey(
              universityId: 'hokudai.ac.jp',
              title: title,
              teacher: teacher,
            );

  factory UserClass.fromMap(Map<String, dynamic> data) {
    // Helper to safely parse int
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    // Helper to safely parse color
    int parseColor(dynamic value) {
      if (value is int) return value;
      if (value is String) {
        return int.tryParse(value) ?? Colors.blue.shade100.toARGB32();
      }
      return Colors.blue.shade100.toARGB32();
    }

    return UserClass(
      id: data['id']?.toString() ?? '',
      title: displayJapanesePrimaryText(data['name']?.toString() ?? ''),
      teacher: displayJapanesePrimaryText(data['teacher']?.toString() ?? ''),
      room: data['room']?.toString() ?? '',
      day: data['day']?.toString() ??
          'Mon', // Assuming 'day' is stored in data, otherwise need to pass it
      period: parseInt(data['period']), // Assuming 'period' is stored
      colorValue: parseColor(data['color']),
      attended: parseInt(data['attended']),
      absent: parseInt(data['absent']),
      late: parseInt(data['late']),
      memo: data['memo']?.toString() ?? '',
      syllabusId: data['syllabus_id']?.toString() ?? '',
      syllabusSource: data['syllabus_source']?.toString() ?? '',
      textbook: data['textbook']?.toString() ?? '',
      isNotificationEnabled: data['is_notification_enabled'] as bool? ?? false,
      semester: data['semester']?.toString() ?? '1',
      year: parseInt(data['year']) == 0 ? 2025 : parseInt(data['year']),
      classKey: data['classKey']?.toString() ?? data['class_key']?.toString(),
    );
  }

  factory UserClass.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final parts = doc.id.split('_');
    final storedDay = data['day']?.toString();
    final storedPeriod = data['period'];
    final legacyDay = parts.isNotEmpty ? parts[0] : 'Mon';
    final legacyPeriod = parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : 1;
    final safeDay =
        (storedDay != null && storedDay.isNotEmpty) ? storedDay : legacyDay;
    final safePeriod = storedPeriod is int
        ? storedPeriod
        : int.tryParse(storedPeriod?.toString() ?? '') ?? legacyPeriod;

    // Inject ID, Day, Period into data for fromMap if they are missing from the map itself
    // But fromFirestore logic relies on doc.id for day/period.
    // Let's keep fromFirestore as is, but maybe reuse logic?
    // For now, just keep fromFirestore independent or delegate.

    return UserClass(
      id: doc.id,
      title: displayJapanesePrimaryText(data['name']?.toString() ?? ''),
      teacher: displayJapanesePrimaryText(data['teacher']?.toString() ?? ''),
      room: data['room']?.toString() ?? '',
      day: safeDay,
      period: safePeriod,
      colorValue: (data['color'] is int)
          ? data['color']
          : (int.tryParse(data['color'].toString()) ??
              Colors.blue.shade100.toARGB32()),
      attended: (data['attended'] is int)
          ? data['attended']
          : int.tryParse(data['attended'].toString()) ?? 0,
      absent: (data['absent'] is int)
          ? data['absent']
          : int.tryParse(data['absent'].toString()) ?? 0,
      late: (data['late'] is int)
          ? data['late']
          : int.tryParse(data['late'].toString()) ?? 0,
      memo: data['memo']?.toString() ?? '',
      syllabusId: data['syllabus_id']?.toString() ?? '',
      syllabusSource: data['syllabus_source']?.toString() ?? '',
      textbook: data['textbook']?.toString() ?? '',
      isNotificationEnabled: data['is_notification_enabled'] as bool? ?? false,
      semester: data['semester']?.toString() ?? '1',
      year: (data['year'] is int) ? data['year'] : 2025,
      classKey: data['classKey']?.toString() ?? data['class_key']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': title,
      'teacher': teacher,
      'room': room,
      'color': colorValue,
      'attended': attended,
      'absent': absent,
      'late': late,
      'memo': memo,
      'syllabus_id': syllabusId,
      'syllabus_source': syllabusSource,
      'textbook': textbook,
      'is_notification_enabled': isNotificationEnabled,
      'semester': semester,
      'year': year,
      'classKey': classKey,
      'class_key': classKey,
    };
  }
}
