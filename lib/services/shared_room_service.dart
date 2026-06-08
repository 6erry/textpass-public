import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SharedRoomSuggestion {
  final String roomName;
  final int count;
  final DateTime updatedAt;

  const SharedRoomSuggestion({
    required this.roomName,
    required this.count,
    required this.updatedAt,
  });
}

class SharedRoomService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _suggestionsRef(String classKey) {
    return _firestore
        .collection('shared_room_info')
        .doc(classKey)
        .collection('suggestions');
  }

  Future<void> shareRoom({
    required String classKey,
    required String title,
    required String teacher,
    required String universityId,
    required String roomName,
  }) async {
    final user = _auth.currentUser;
    final cleanRoom = roomName.trim();
    if (user == null || classKey.isEmpty || cleanRoom.isEmpty) return;

    final parentRef = _firestore.collection('shared_room_info').doc(classKey);
    final suggestionRef = parentRef.collection('suggestions').doc(user.uid);
    final batch = _firestore.batch();

    batch.set(
        parentRef,
        {
          'class_key': classKey,
          'title': title,
          'teacher': teacher,
          'university_id': universityId,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    batch.set(
        suggestionRef,
        {
          'room_name': cleanRoom,
          'created_by': user.uid,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> removeMySuggestion(String classKey) async {
    final user = _auth.currentUser;
    if (user == null || classKey.isEmpty) return;
    await _suggestionsRef(classKey).doc(user.uid).delete();
  }

  Future<SharedRoomSuggestion?> getBestRoom(String classKey) async {
    if (classKey.isEmpty) return null;

    final snapshot = await _suggestionsRef(classKey).limit(50).get();
    if (snapshot.docs.isEmpty) return null;

    final counts = <String, int>{};
    final labels = <String, String>{};
    final latest = <String, DateTime>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final rawRoom = (data['room_name'] as String? ?? '').trim();
      if (rawRoom.isEmpty) continue;

      final key = rawRoom.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      final updatedAt =
          (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime(1970);

      counts[key] = (counts[key] ?? 0) + 1;
      labels[key] = rawRoom;
      if ((latest[key] ?? DateTime(1970)).isBefore(updatedAt)) {
        latest[key] = updatedAt;
      }
    }

    if (counts.isEmpty) return null;

    final bestKey = counts.keys.reduce((a, b) {
      final countCompare = counts[a]!.compareTo(counts[b]!);
      if (countCompare != 0) return countCompare > 0 ? a : b;
      return latest[a]!.isAfter(latest[b]!) ? a : b;
    });

    return SharedRoomSuggestion(
      roomName: labels[bestKey]!,
      count: counts[bestKey]!,
      updatedAt: latest[bestKey]!,
    );
  }
}
