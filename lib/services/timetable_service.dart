import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_class.dart';
import '../models/class_reminder.dart';
import 'user_service.dart';

class TimetableService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Hokudai Period Times (Standard)
  // 1: 08:45 - 10:15
  // 2: 10:30 - 12:00
  // 3: 13:00 - 14:30
  // 4: 14:45 - 16:15
  // 5: 16:30 - 18:00
  // 6: 18:15 - 19:45
  static const Map<int, Map<String, int>> _defaultPeriodTimes = {
    1: {'startHour': 8, 'startMinute': 45, 'endHour': 10, 'endMinute': 15},
    2: {'startHour': 10, 'startMinute': 30, 'endHour': 12, 'endMinute': 0},
    3: {'startHour': 13, 'startMinute': 0, 'endHour': 14, 'endMinute': 30},
    4: {'startHour': 14, 'startMinute': 45, 'endHour': 16, 'endMinute': 15},
    5: {'startHour': 16, 'startMinute': 30, 'endHour': 18, 'endMinute': 0},
    6: {'startHour': 18, 'startMinute': 15, 'endHour': 19, 'endMinute': 45},
  };

  Future<Map<int, Map<String, int>>> getPeriodTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<int, Map<String, int>> times = {};

    for (int i = 1; i <= 6; i++) {
      final startHour = prefs.getInt('period_${i}_start_hour');
      final startMinute = prefs.getInt('period_${i}_start_minute');
      final endHour = prefs.getInt('period_${i}_end_hour');
      final endMinute = prefs.getInt('period_${i}_end_minute');

      if (startHour != null &&
          startMinute != null &&
          endHour != null &&
          endMinute != null) {
        times[i] = {
          'startHour': startHour,
          'startMinute': startMinute,
          'endHour': endHour,
          'endMinute': endMinute,
        };
      } else {
        times[i] = _defaultPeriodTimes[i]!;
      }
    }
    return times;
  }

  Future<void> savePeriodTime(
      int period, TimeOfDay start, TimeOfDay end) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('period_${period}_start_hour', start.hour);
    await prefs.setInt('period_${period}_start_minute', start.minute);
    await prefs.setInt('period_${period}_end_hour', end.hour);
    await prefs.setInt('period_${period}_end_minute', end.minute);
  }

  Future<void> resetPeriodTimes() async {
    final prefs = await SharedPreferences.getInstance();
    for (int i = 1; i <= 6; i++) {
      await prefs.remove('period_${i}_start_hour');
      await prefs.remove('period_${i}_start_minute');
      await prefs.remove('period_${i}_end_hour');
      await prefs.remove('period_${i}_end_minute');
    }
  }

  int currentAcademicYear({DateTime? now}) {
    final date = now ?? DateTime.now();
    return date.month >= 4 ? date.year : date.year - 1;
  }

  String defaultCurrentTerm(String timetableSystem, {DateTime? now}) {
    final date = now ?? DateTime.now();
    if (timetableSystem == 'quarter') {
      if (date.month >= 4 && date.month <= 5) return '1q';
      if (date.month >= 6 && date.month <= 9) return '2q';
      if (date.month >= 10 && date.month <= 11) return '3q';
      return '4q';
    }
    return date.month >= 4 && date.month <= 9 ? 'spring_group' : 'fall_group';
  }

  bool classMatchesTerm(UserClass userClass, String term, String system) {
    final semester = userClass.semester;
    if (['intensive', 'year_round', '0', ''].contains(semester)) {
      return term == 'other_group';
    }

    if (system == 'semester') {
      if (term == 'spring_group') {
        return ['1', 'spring', 'summer', '1q', '2q'].contains(semester);
      }
      if (term == 'fall_group') {
        return ['2', 'fall', 'winter', '3q', '4q'].contains(semester);
      }
      return false;
    }

    if (term == '1q') return ['1q', '1', 'spring'].contains(semester);
    if (term == '2q') return ['2q', '1', 'spring'].contains(semester);
    if (term == '3q') return ['3q', '2', 'fall'].contains(semester);
    if (term == '4q') return ['4q', '2', 'fall'].contains(semester);
    return false;
  }

  Future<List<int>> getAvailableYears() async {
    final user = _auth.currentUser;
    final currentYear = currentAcademicYear();
    final years = <int>{
      currentYear - 2,
      currentYear - 1,
      currentYear,
      currentYear + 1
    };
    if (user == null) return years.toList()..sort();

    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('timetable')
        .get();
    for (final doc in snapshot.docs) {
      final year = doc.data()['year'];
      if (year is int) years.add(year);
    }

    final sorted = years.toList()..sort();
    return sorted;
  }

  // Get classes for a specific year
  Stream<List<UserClass>> getClasses(int year) {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('timetable')
        .where('year', isEqualTo: year)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => UserClass.fromFirestore(doc)).toList());
  }

  Future<UserClass?> getNextClass() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final appUser = await UserService().getCurrentUser();
    final timetableSystem = appUser?.timetableSystem ?? 'semester';
    final year = appUser?.currentTimetableYear ?? currentAcademicYear();
    final term =
        appUser?.currentTimetableTerm ?? defaultCurrentTerm(timetableSystem);

    final now = DateTime.now();
    final weekDayMap = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    final currentDayStr = weekDayMap[now.weekday];

    if (currentDayStr == null) return null;

    // Fetch all classes (small dataset) as 'day' field might not exist in docs
    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('timetable')
        .where('year', isEqualTo: year)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final classes = snapshot.docs
        .map((doc) => UserClass.fromFirestore(doc))
        .where((c) =>
            c.day == currentDayStr &&
            classMatchesTerm(c, term, timetableSystem))
        .toList();

    // Sort by period
    classes.sort((a, b) => a.period.compareTo(b.period));

    final periodTimes = await getPeriodTimes();

    // Find the first class that hasn't ended yet
    for (final userClass in classes) {
      final time = periodTimes[userClass.period];
      if (time == null) continue;

      final endTime = DateTime(
        now.year,
        now.month,
        now.day,
        time['endHour']!,
        time['endMinute']!,
      );

      if (endTime.isAfter(now)) {
        return userClass;
      }
    }

    return null; // All classes finished or no classes today
  }

  // --- Custom Reminders ---

  Stream<List<ClassReminder>> getReminders(String classId) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('timetable')
        .doc(classId)
        .collection('reminders')
        .orderBy('notifyAt')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ClassReminder.fromFirestore(doc))
            .toList());
  }

  Future<void> addReminder(String classId, ClassReminder reminder) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('timetable')
        .doc(classId)
        .collection('reminders')
        .doc(reminder.id)
        .set(reminder.toMap());
  }

  Future<void> updateReminder(String classId, ClassReminder reminder) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('timetable')
        .doc(classId)
        .collection('reminders')
        .doc(reminder.id)
        .update(reminder.toMap());
  }

  Future<void> deleteReminder(String classId, String reminderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('timetable')
        .doc(classId)
        .collection('reminders')
        .doc(reminderId)
        .delete();
  }
}
