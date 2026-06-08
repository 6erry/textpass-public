import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  // Get current university ID (Cached or fetched)
  String? _cachedUniversityId;

  Future<String?> getCurrentUniversityId() async {
    if (_cachedUniversityId != null) return _cachedUniversityId;

    final uid = currentUserId;
    if (uid == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final user = AppUser.fromFirestore(doc);
        _cachedUniversityId = user.universityId;
        return user.universityId;
      }
    } catch (e) {
      // print('Error getting university ID: $e');
    }
    return null;
  }

  // Get current AppUser
  Future<AppUser?> getCurrentUser() async {
    return getUser(currentUserId);
  }

  // Get specific user by ID
  Future<AppUser?> getUser(String? uid) async {
    if (uid == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return AppUser.fromFirestore(doc);
      }
    } catch (e) {
      // print('Error getting user: $e');
    }
    return null;
  }

  // Get saved searches (merged with alert keywords)
  Future<List<String>> getSavedSearches() async {
    final user = await getCurrentUser();
    return user?.alertKeywords ?? [];
  }

  // Stream of blocked user IDs
  Stream<List<String>> get blockedUserIdsStream {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) return [];
      final user = AppUser.fromFirestore(snapshot);
      return user.blockedUserIds;
    });
  }

  // Check if a user is blocked (one-time check)
  Future<bool> isBlocked(String targetUserId) async {
    final user = await getCurrentUser();
    return user?.blockedUserIds.contains(targetUserId) ?? false;
  }

  // Check if current user is admin
  Future<bool> isAdmin() async {
    final user = await getCurrentUser();
    return user?.isAdmin ?? false;
  }

  // Check if current user is banned
  Future<bool> isBanned() async {
    final user = await getCurrentUser();
    return user?.isBanned ?? false;
  }

  // Toggle saved search (add if not exists, remove if exists)
  // Returns true if added, false if removed
  Future<bool> toggleSavedSearch(String keyword) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('User not logged in');

    final docRef = _firestore.collection('users').doc(uid);
    final user = await getCurrentUser();
    if (user == null) throw Exception('User not found');

    List<String> currentSaved = List.from(user.alertKeywords);
    bool isAdded;

    if (currentSaved.contains(keyword)) {
      currentSaved.remove(keyword);
      isAdded = false;
    } else {
      // Limit to 5 keywords as per Keyword Alert requirement
      if (currentSaved.length >= 5) {
        throw Exception('登録できるキーワードは5つまでです');
      }
      currentSaved.add(keyword);
      isAdded = true;
    }

    await docRef.update({
      'alertKeywords': currentSaved,
    });

    return isAdded;
  }

  // Update timetable system preference
  Future<void> updateTimetableSystem(String system) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('User not logged in');

    if (system != 'semester' && system != 'quarter') {
      throw Exception('Invalid system type');
    }

    await _firestore.collection('users').doc(uid).update({
      'timetableSystem': system,
      'hasConfiguredTimetableSystem': true,
    });
  }

  // Update active periods
  Future<void> updateActivePeriods(List<int> periods) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('User not logged in');

    await _firestore.collection('users').doc(uid).update({
      'activePeriods': periods,
    });
  }

  Future<void> updateCurrentTimetable({
    required int year,
    required String term,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('User not logged in');

    await _firestore.collection('users').doc(uid).update({
      'currentTimetableYear': year,
      'currentTimetableTerm': term,
    });
  }

  // Check active transaction
  Future<bool> hasActiveTransaction(String targetUserId) async {
    final currentUid = currentUserId;
    if (currentUid == null) return false;

    try {
      final activeStatuses = ['paid', 'trading', 'shipped', 'sold'];

      // 1. 自分が Buyer のチャットを全取得
      final buyerSnapshot = await _firestore
          .collection('chat_rooms')
          .where('buyerId', isEqualTo: currentUid)
          .get();

      // 中身をアプリ側でチェック (相手がSeller かつ ステータスが進行中)
      for (var doc in buyerSnapshot.docs) {
        final data = doc.data();
        if (data['sellerId'] == targetUserId &&
            activeStatuses.contains(data['status'])) {
          return true; // 取引中あり！
        }
      }

      // 2. 自分が Seller のチャットを全取得
      final sellerSnapshot = await _firestore
          .collection('chat_rooms')
          .where('sellerId', isEqualTo: currentUid)
          .get();

      // 中身をアプリ側でチェック (相手がBuyer かつ ステータスが進行中)
      for (var doc in sellerSnapshot.docs) {
        final data = doc.data();
        if (data['buyerId'] == targetUserId &&
            activeStatuses.contains(data['status'])) {
          return true; // 取引中あり！
        }
      }

      return false;
    } catch (e) {
      // print('Error checking active transaction: $e');
      return false;
    }
  }
}
