import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/syllabus.dart';
import '../utils/japanese_display_text.dart';
import 'package:flutter/material.dart';
import 'shared_room_service.dart';
import 'user_service.dart';

class TimetableAddSlot {
  final String key;
  final String docId;
  final String day;
  final int period;
  final String semester;
  final int year;

  const TimetableAddSlot({
    required this.key,
    required this.docId,
    required this.day,
    required this.period,
    required this.semester,
    required this.year,
  });
}

class TimetableSlotConflict {
  final TimetableAddSlot slot;
  final String existingDocId;
  final String existingTitle;
  final String existingTeacher;
  final String existingSemester;

  const TimetableSlotConflict({
    required this.slot,
    required this.existingDocId,
    required this.existingTitle,
    required this.existingTeacher,
    required this.existingSemester,
  });
}

class TimetableAddResult {
  final int addedSlots;
  final int skippedSlots;

  const TimetableAddResult({
    required this.addedSlots,
    required this.skippedSlots,
  });
}

class SyllabusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SharedRoomService _sharedRoomService = SharedRoomService();

  String _timetableDocId({
    required int year,
    required String semester,
    required String day,
    required int period,
  }) {
    final safeSemester = semester.isEmpty ? '1' : semester;
    return '${year}_${safeSemester}_${day}_$period';
  }

  String _normalizeDay(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    const dayMap = {
      '月': 'Mon',
      '火': 'Tue',
      '水': 'Wed',
      '木': 'Thu',
      '金': 'Fri',
      '土': 'Sat',
      '日': 'Sun',
    };
    return dayMap[raw] ?? raw;
  }

  int _parsePeriod(dynamic value) {
    if (value is int) return value;
    if (value == null) return 0;
    return int.tryParse(value.toString()) ?? 0;
  }

  bool _isUniversalSemester(String semester) {
    return ['year_round', 'intensive', '0', ''].contains(semester);
  }

  bool _matchesSemester(String targetSemester, String classSemester) {
    if (_isUniversalSemester(classSemester)) return true;

    if (targetSemester == '1' ||
        targetSemester == 'spring' ||
        targetSemester == 'summer') {
      return ['1', 'spring', 'summer', '1q', '2q'].contains(classSemester);
    }
    if (targetSemester == '2' ||
        targetSemester == 'fall' ||
        targetSemester == 'winter') {
      return ['2', 'fall', 'winter', '3q', '4q'].contains(classSemester);
    }
    if (targetSemester == '1q') {
      return ['1q', '1', 'spring'].contains(classSemester);
    }
    if (targetSemester == '2q') {
      return ['2q', '1', 'spring'].contains(classSemester);
    }
    if (targetSemester == '3q') {
      return ['3q', '2', 'fall'].contains(classSemester);
    }
    if (targetSemester == '4q') {
      return ['4q', '2', 'fall'].contains(classSemester);
    }

    return true;
  }

  Iterable<Map<String, dynamic>> _validSlots(Syllabus syllabus) sync* {
    final seen = <String>{};
    for (final slot in syllabus.schedule) {
      final day = _normalizeDay(slot['day']);
      final period = _parsePeriod(slot['period']);
      if (day.isEmpty || period <= 0) continue;
      final key = '$day:$period';
      if (seen.add(key)) {
        yield {'day': day, 'period': period};
      }
    }

    if (seen.isEmpty && syllabus.day.isNotEmpty && syllabus.period > 0) {
      yield {'day': _normalizeDay(syllabus.day), 'period': syllabus.period};
    }
  }

  List<TimetableAddSlot> getAddSlots(Syllabus syllabus, {int? targetYear}) {
    final year = targetYear ?? syllabus.year;
    return _validSlots(syllabus).map((slot) {
      final day = slot['day'] as String;
      final period = slot['period'] as int;
      return TimetableAddSlot(
        key: '$day:$period',
        docId: _timetableDocId(
          year: year,
          semester: syllabus.semester,
          day: day,
          period: period,
        ),
        day: day,
        period: period,
        semester: syllabus.semester,
        year: year,
      );
    }).toList();
  }

  Future<List<TimetableSlotConflict>> getTimetableConflicts(
    Syllabus syllabus, {
    int? targetYear,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final slots = getAddSlots(syllabus, targetYear: targetYear);
    if (slots.isEmpty) return [];

    final year = targetYear ?? syllabus.year;
    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('timetable')
        .where('year', isEqualTo: year)
        .get();

    final conflicts = <TimetableSlotConflict>[];
    for (final slot in slots) {
      for (final doc in snapshot.docs) {
        if (doc.id == slot.docId) {
          final data = doc.data();
          conflicts.add(
            TimetableSlotConflict(
              slot: slot,
              existingDocId: doc.id,
              existingTitle:
                  displayJapanesePrimaryText(data['name']?.toString() ?? ''),
              existingTeacher:
                  displayJapanesePrimaryText(data['teacher']?.toString() ?? ''),
              existingSemester: data['semester']?.toString() ?? '',
            ),
          );
          continue;
        }

        final data = doc.data();
        final day = _normalizeDay(data['day']);
        final period = _parsePeriod(data['period']);
        final semester = data['semester']?.toString() ?? '';
        if (day == slot.day &&
            period == slot.period &&
            (_matchesSemester(slot.semester, semester) ||
                _matchesSemester(semester, slot.semester))) {
          conflicts.add(
            TimetableSlotConflict(
              slot: slot,
              existingDocId: doc.id,
              existingTitle:
                  displayJapanesePrimaryText(data['name']?.toString() ?? ''),
              existingTeacher:
                  displayJapanesePrimaryText(data['teacher']?.toString() ?? ''),
              existingSemester: semester,
            ),
          );
        }
      }
    }
    return conflicts;
  }

  List<String> _universityAliases(String universityId) {
    if (universityId == 'hokudai' || universityId == 'hokudai.ac.jp') {
      return const ['hokudai.ac.jp', 'hokudai'];
    }
    return [universityId];
  }

  // Search for syllabus entries
  Future<List<Syllabus>> searchSyllabus(
    String query,
    String day,
    int period, {
    String? semester,
    int? year,
  }) async {
    final universityId = await UserService().getCurrentUniversityId();
    // print(
    //     'Search Syllabus: Query="$query", Day=$day, Period=$period, Sem=$semester, Univ=$universityId');

    if (universityId == null) {
      // print('Search aborted: No University ID found');
      return [];
    }

    // Note: If we added 'semester' to the index, we could filter by it.
    // However, semester logic is complex (spring vs 1 vs year_round).
    // Let's filter semester in memory for now to ensure flexibility.

    List<Syllabus> results = [];

    try {
      if (day.isNotEmpty && period > 0) {
        final byId = <String, Syllabus>{};
        for (final candidateUniversityId in _universityAliases(universityId)) {
          final snapshot = await _firestore
              .collection('syllabus_master')
              .where('universityId', isEqualTo: candidateUniversityId)
              .where('year', isEqualTo: year ?? DateTime.now().year)
              .where('schedule',
                  arrayContains: {'day': day, 'period': period}).get();
          for (final doc in snapshot.docs) {
            byId[doc.id] = Syllabus.fromFirestore(doc);
          }
        }
        results = byId.values.toList();
        // print('Initial Fetch: ${results.length} items found for $day-$period');
      } else {
        // Fallback: search by title only if day/period missing (not implemented fully yet)
      }

      // Filter by Query (Title/Teacher) - Multi-keyword Substring Match
      if (query.isNotEmpty) {
        final keywords =
            query.trim().replaceAll('　', ' ').split(RegExp(r'\s+'));

        results = results.where((syllabus) {
          // Check if ALL keywords match at least one field (OR logic between fields, AND between keywords)
          // Actually user said: "Class Name Instructor Name". usually means (Name contains ClassName) AND (Instructor contains InstructorName)
          // But strict field mapping is hard.
          // Standard lenient search: For EACH keyword, it must appear in (Title OR Teacher).

          return keywords.every((keyword) {
            final kw = keyword.toLowerCase();
            return syllabus.title.toLowerCase().contains(kw) ||
                syllabus.teacher.toLowerCase().contains(kw);
          });
        }).toList();
      }

      // Filter by Semester (Memory)
      if (semester != null && semester.isNotEmpty) {
        // Semantic Filtering:
        // 'spring_group' (1) should include: '1', 'spring', 'summer', 'year_round', 'intensive', '0', ''
        // 'fall_group' (2) should include: '2', 'fall', 'winter', 'year_round', 'intensive', '0', ''

        final targetSem = semester; // e.g. '1' or '2' or 'spring'

        results = results.where((s) {
          return _matchesSemester(targetSem, s.semester);
        }).toList();
      }

      // print('Final Results: ${results.length} items');
    } catch (e) {
      // print('Error searching syllabus: $e');
    }

    return results;
  }

  Future<List<Syllabus>> searchSyllabusByText(
    String query, {
    int? year,
    int limit = 80,
  }) async {
    final universityId = await UserService().getCurrentUniversityId();
    final trimmed = query.trim().replaceAll('　', ' ');
    if (universityId == null || trimmed.isEmpty) return [];

    final targetYear = year ?? DateTime.now().year;
    final keywords = trimmed
        .split(RegExp(r'\s+'))
        .where((keyword) => keyword.isNotEmpty)
        .map((keyword) => keyword.toLowerCase())
        .toList();
    if (keywords.isEmpty) return [];

    final byId = <String, Syllabus>{};
    for (final candidateUniversityId in _universityAliases(universityId)) {
      final snapshot = await _firestore
          .collection('syllabus_master')
          .where('universityId', isEqualTo: candidateUniversityId)
          .where('year', isEqualTo: targetYear)
          .get();
      for (final doc in snapshot.docs) {
        final syllabus = Syllabus.fromFirestore(doc);
        final title = syllabus.title.toLowerCase();
        final teacher = syllabus.teacher.toLowerCase();
        final matched = keywords.every(
          (keyword) => title.contains(keyword) || teacher.contains(keyword),
        );
        if (matched) {
          byId[doc.id] = syllabus;
        }
      }
    }

    final results = byId.values.toList()
      ..sort((a, b) {
        final titleCompare = a.title.compareTo(b.title);
        if (titleCompare != 0) return titleCompare;
        return a.teacher.compareTo(b.teacher);
      });
    return results.take(limit).toList();
  }

  // Register a new class to Master, and optionally to User Timetable
  Future<String> registerNewClass(
    Syllabus syllabus, {
    bool addToTimetable = true,
    int? colorValue,
    Set<String> replaceConflictDocIds = const {},
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final customSyllabusId =
        'custom_${user.uid}_${syllabus.day}_${syllabus.period}_${DateTime.now().millisecondsSinceEpoch}';
    final customSyllabusRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('custom_syllabus')
        .doc(customSyllabusId);

    final batch = _firestore.batch();
    batch.set(customSyllabusRef, {
      ...syllabus.toMap(),
      'source': 'manual',
      'owner_uid': user.uid,
      'created_by': user.uid,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    if (addToTimetable) {
      final conflicts = await getTimetableConflicts(
        syllabus,
        targetYear: syllabus.year,
      );
      if (conflicts.isNotEmpty) {
        final shouldReplace = conflicts.every(
          (conflict) => replaceConflictDocIds.contains(conflict.existingDocId),
        );
        if (!shouldReplace) {
          throw Exception('同じコマに既存の授業があります');
        }
        for (final conflict in conflicts) {
          final existingRef = _firestore
              .collection('users')
              .doc(user.uid)
              .collection('timetable')
              .doc(conflict.existingDocId);
          batch.delete(existingRef);
        }
      }

      final userTimetableRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('timetable')
          .doc(_timetableDocId(
            year: syllabus.year,
            semester: syllabus.semester,
            day: syllabus.day,
            period: syllabus.period,
          ));

      final userTimetableData = {
        'name': syllabus.title,
        'room': syllabus.classroom,
        'room_source': syllabus.classroom.trim().isEmpty ? 'none' : 'manual',
        'teacher': syllabus.teacher,
        'color': colorValue ?? Colors.blue.shade100.toARGB32(),
        'syllabus_id': customSyllabusId,
        'syllabus_source': 'custom',
        'textbook': syllabus.textbook,
        'attended': 0,
        'absent': 0,
        'late': 0,
        'memo': '',
        'created_at': FieldValue.serverTimestamp(),
        'semester': syllabus.semester,
        'year': syllabus.year,
        'classKey': syllabus.classKey,
        'class_key': syllabus.classKey,
        'day': syllabus.day,
        'period': syllabus.period,
      };

      batch.set(userTimetableRef, userTimetableData);
    }

    await batch.commit();
    return customSyllabusId;
  }

  // Add existing syllabus to timetable
  Future<TimetableAddResult> addToTimetable(
    Syllabus syllabus, {
    int? targetYear,
    bool useSharedRoom = true,
    bool shareRoomInfo = false,
    Set<String> replaceConflictDocIds = const {},
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final batch = _firestore.batch();
    final sharedRoom = useSharedRoom && syllabus.classroom.trim().isEmpty
        ? await _sharedRoomService.getBestRoom(syllabus.classKey)
        : null;
    final roomName = syllabus.classroom.trim().isNotEmpty
        ? syllabus.classroom.trim()
        : sharedRoom?.roomName ?? '';
    final roomSource = syllabus.classroom.trim().isNotEmpty
        ? 'syllabus'
        : sharedRoom == null
            ? 'none'
            : 'shared';

    final year = targetYear ?? syllabus.year;
    final conflicts = await getTimetableConflicts(syllabus, targetYear: year);
    final conflictsBySlot = <String, List<TimetableSlotConflict>>{};
    for (final conflict in conflicts) {
      conflictsBySlot.putIfAbsent(conflict.slot.key, () => []).add(conflict);
    }

    var addedSlots = 0;
    var skippedSlots = 0;

    for (final slot in getAddSlots(syllabus, targetYear: year)) {
      final slotConflicts = conflictsBySlot[slot.key] ?? const [];
      if (slotConflicts.isNotEmpty) {
        final shouldReplace = slotConflicts.every(
          (conflict) => replaceConflictDocIds.contains(conflict.existingDocId),
        );
        if (!shouldReplace) {
          skippedSlots += 1;
          continue;
        }
        for (final conflict in slotConflicts) {
          final existingRef = _firestore
              .collection('users')
              .doc(user.uid)
              .collection('timetable')
              .doc(conflict.existingDocId);
          batch.delete(existingRef);
        }
      }

      final userTimetableRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('timetable')
          .doc(slot.docId);

      final userTimetableData = {
        'name': syllabus.title,
        'room': roomName,
        'room_source': roomSource,
        'teacher': syllabus.teacher,
        'color': Colors.blue.shade100.toARGB32(),
        'syllabus_id': syllabus.id,
        'syllabus_source': 'master',
        'textbook': syllabus.textbook,
        'attended': 0,
        'absent': 0,
        'late': 0,
        'memo': '',
        'created_at': FieldValue.serverTimestamp(),
        'semester': syllabus.semester,
        'year': year,
        'classKey': syllabus.classKey,
        'class_key': syllabus.classKey,
        'day': slot.day,
        'period': slot.period,
      };

      batch.set(userTimetableRef, userTimetableData);
      addedSlots += 1;
    }

    if (addedSlots == 0) {
      if (skippedSlots > 0) {
        throw Exception('重複しているコマを残したため、追加されるコマがありませんでした');
      }
      throw Exception('曜日・時限が取得できない授業です');
    }

    await batch.commit();

    if (shareRoomInfo && roomName.isNotEmpty) {
      await _sharedRoomService.shareRoom(
        classKey: syllabus.classKey,
        title: syllabus.title,
        teacher: syllabus.teacher,
        universityId: syllabus.universityId,
        roomName: roomName,
      );
    }

    return TimetableAddResult(
        addedSlots: addedSlots, skippedSlots: skippedSlots);
  }
}
