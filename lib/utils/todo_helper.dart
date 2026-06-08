import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class TodoHelper {
  static bool hasTask(Map<String, dynamic> data, String userId) {
    final status = data['status'] as String? ?? 'paid';
    final meetingStatus = data['meetingStatus'] as String? ?? 'initial';
    final proposerId = data['proposerId'] as String?;
    final meetingTime = data['meetingTime'] as Timestamp?;
    final pendingReviews = data['pendingReviews'] as List<dynamic>?;
    final cancellationStatus = data['cancellationStatus'] as String?;
    final cancellationRequesterId = data['cancellationRequesterId'] as String?;

    if (cancellationStatus == 'requesting' &&
        cancellationRequesterId != null &&
        cancellationRequesterId != userId) {
      return true;
    }

    if (status == 'paid') {
      if (meetingStatus == 'initial') {
        return true;
      }

      if (meetingStatus == 'pending') {
        if (proposerId != null && proposerId != userId) {
          return true;
        }
        return false;
      }

      if (meetingStatus == 'agreed') {
        return meetingTime != null && _isSameDay(meetingTime.toDate());
      }

      if (meetingStatus == 'rejected') return true;
      return false;
    } else if (status == 'completed') {
      if (pendingReviews != null && pendingReviews.contains(userId)) {
        return true;
      }
      return false;
    }

    return false;
  }

  static String getTaskTitle(Map<String, dynamic> data, String userId) {
    final status = data['status'] as String? ?? 'paid';
    final meetingStatus = data['meetingStatus'] as String? ?? 'initial';
    final proposerId = data['proposerId'] as String?;
    final cancellationStatus = data['cancellationStatus'] as String?;
    final cancellationRequesterId = data['cancellationRequesterId'] as String?;

    if (cancellationStatus == 'requesting' &&
        cancellationRequesterId != null &&
        cancellationRequesterId != userId) {
      return 'キャンセル申請を確認';
    }

    if (status == 'completed') return '取引相手を評価';
    if (meetingStatus == 'pending' && proposerId != userId) {
      return '受け渡し条件を確認';
    }
    if (meetingStatus == 'agreed') return '本日の受け渡し';
    if (meetingStatus == 'rejected') return '受け渡し場所を再調整';
    return '受け渡し場所を決める';
  }

  static String getTaskMessage(
      Map<String, dynamic> data, String userId, String title, bool isBuyer) {
    final status = data['status'] as String? ?? 'paid';
    final meetingStatus = data['meetingStatus'] as String? ?? 'initial';
    final proposerId = data['proposerId'] as String?;
    final meetingTime = data['meetingTime'] as Timestamp?;
    final meetingPlace = data['meetingPlace'] as String?;
    final cancellationStatus = data['cancellationStatus'] as String?;
    final cancellationRequesterId = data['cancellationRequesterId'] as String?;

    if (cancellationStatus == 'requesting' &&
        cancellationRequesterId != null &&
        cancellationRequesterId != userId) {
      return '相手からキャンセル申請が届いています。内容を確認し、承認または拒否してください。';
    }

    if (status == 'paid') {
      if (meetingStatus == 'initial') {
        return '「$title」の取引が開始しました。受け渡し日時と場所を提案してください。';
      }

      if (meetingStatus == 'pending') {
        if (proposerId != null && proposerId != userId) {
          return '「$title」について、相手から日時と場所の提案が届いています。';
        }
        return '「$title」について、相手の返答を待っています。';
      }

      if (meetingStatus == 'agreed' && meetingTime != null) {
        final meetingDate = meetingTime.toDate();
        final timeString = DateFormat('HH:mm').format(meetingDate);
        final placeString = meetingPlace ?? '指定場所';
        return '本日 $timeString に $placeString で「$title」を受け渡し予定です。';
      }

      if (meetingStatus == 'rejected') {
        return '「$title」の提案が見送りになりました。新しい日時と場所を調整してください。';
      }

      if (isBuyer) {
        return '「$title」の取引が進行中です。';
      } else {
        return '「$title」が購入されました。';
      }
    } else if (status == 'completed') {
      return '「$title」の取引が完了しました。相手を評価してください。';
    }

    return '「$title」のタスクがあります';
  }

  static String getTaskMeta(Map<String, dynamic> data) {
    final meetingTime = data['meetingTime'] as Timestamp?;
    final meetingPlace = data['meetingPlace'] as String?;
    if (meetingTime == null) return '未設定';
    final date = meetingTime.toDate();
    final dateText = _isSameDay(date)
        ? '今日 ${DateFormat('HH:mm').format(date)}'
        : DateFormat('M/d HH:mm').format(date);
    if (meetingPlace == null || meetingPlace.isEmpty) return dateText;
    return '$dateText / $meetingPlace';
  }

  static bool _isSameDay(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}
