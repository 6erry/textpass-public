import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/user_class.dart';
import '../../screens/class_detail_screen.dart';
import '../../services/timetable_service.dart';

class NextClassCard extends StatefulWidget {
  const NextClassCard({super.key});

  @override
  State<NextClassCard> createState() => _NextClassCardState();
}

class _NextClassCardState extends State<NextClassCard> {
  final _timetableService = TimetableService();
  UserClass? _nextClass;
  DateTime? _classStartTime;
  bool _isLoading = true;
  Timer? _timer;
  String _timeUntilStart = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    // Update timer every minute
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateTimeDisplay();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final nextClass = await _timetableService.getNextClass();
      if (nextClass != null) {
        final times = await _timetableService.getPeriodTimes();
        final timeData = times[nextClass.period];
        if (timeData != null) {
          final now = DateTime.now();
          _classStartTime = DateTime(
            now.year,
            now.month,
            now.day,
            timeData['startHour']!,
            timeData['startMinute']!,
          );
        }
      }

      if (mounted) {
        setState(() {
          _nextClass = nextClass;
          _isLoading = false;
        });
        _updateTimeDisplay();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _updateTimeDisplay() {
    if (_classStartTime == null) return;
    final now = DateTime.now();
    final difference = _classStartTime!.difference(now);

    if (mounted) {
      setState(() {
        if (difference.isNegative) {
          _timeUntilStart = '授業中';
        } else {
          final minutes = difference.inMinutes;
          if (minutes < 60) {
            _timeUntilStart = '開始まであと $minutes分';
          } else {
            final hours = minutes ~/ 60;
            final mins = minutes % 60;
            _timeUntilStart = '開始まであと $hours時間$mins分';
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_nextClass == null) {
      return _buildFinishedCard();
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ClassDetailScreen(userClass: _nextClass!),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_convertDayToJa(_nextClass!.day)}曜 ${_nextClass!.period}限',
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (_timeUntilStart.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _timeUntilStart,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _nextClass!.title,
                style: const TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      color: Colors.grey, size: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _nextClass!.room.isNotEmpty ? _nextClass!.room : '教室未定',
                      style:
                          TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.person_outline,
                      color: Colors.grey, size: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _nextClass!.teacher,
                      style:
                          TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinishedCard() {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.event_available_outlined,
                  color: Colors.grey.shade700),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本日の授業予定',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '以降の授業はありません',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _convertDayToJa(String day) {
    const dayMap = {
      'Mon': '月',
      'Tue': '火',
      'Wed': '水',
      'Thu': '木',
      'Fri': '金',
      'Sat': '土',
      'Sun': '日',
    };
    return dayMap[day] ?? day;
  }
}
