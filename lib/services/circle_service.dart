import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../models/circle.dart';
import '../services/user_service.dart';

class CircleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final UserService _userService = UserService();

  List<String> _universityAliases(String universityId) {
    if (universityId == 'hokudai' || universityId == 'hokudai.ac.jp') {
      return const ['hokudai', 'hokudai.ac.jp'];
    }
    return [universityId];
  }

  // Create a new circle
  Future<void> createCircle({
    required String name,
    required String description,
    required String universityDomain,
    required String displayId,
    required CircleCategory category,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // Check if displayId is unique
    final idCheck = await _firestore
        .collection('circles')
        .where('display_id', isEqualTo: displayId)
        .get();
    if (idCheck.docs.isNotEmpty) {
      throw Exception('このIDは既に使用されています');
    }

    final batch = _firestore.batch();
    final circleRef = _firestore.collection('circles').doc();

    final universityId = await _userService.getCurrentUniversityId();
    if (universityId == null) throw Exception('University ID not found');

    final circle = Circle(
      id: circleRef.id,
      displayId: displayId,
      name: name,
      description: description,
      category: category,
      status: 'pending',
      memberUids: [user.uid],
      adminUids: [user.uid],
      memberRoles: {user.uid: CircleMemberRole.owner},
      universityDomain: universityDomain,
      universityId: universityId, // Save universityId
      inviteCode: circleRef.id.substring(0, 6).toUpperCase(),
      createdAt: DateTime.now(),
    );

    batch.set(circleRef, circle.toMap());

    // Update user's belonging_circle_id
    final userRef = _firestore.collection('users').doc(user.uid);
    batch.update(userRef, {'belonging_circle_id': circleRef.id});
    _addAuditLogToBatch(
      batch,
      circleRef.id,
      actorUid: user.uid,
      action: 'circle_created',
      targetType: 'circle',
      targetId: circleRef.id,
      changes: {'name': name, 'role': CircleMemberRole.owner.value},
    );

    await batch.commit();
  }

  // Join a circle
  Future<void> joinCircle(String circleId) async {
    await FirebaseFunctions.instance
        .httpsCallable('joinCircleByInviteCode')
        .call({
      'inviteCode': circleId,
    });
  }

  // Get user's circle
  Future<Circle?> getUserCircle() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final circleId = userDoc.data()?['belonging_circle_id'] as String?;

    if (circleId == null) return null;

    final circleDoc =
        await _firestore.collection('circles').doc(circleId).get();
    if (!circleDoc.exists) return null;

    return Circle.fromFirestore(circleDoc);
  }

  // Find circle by invite code (Optional helper)
  Future<Circle?> findCircleByInviteCode(String code) async {
    final query = await _firestore
        .collection('circles')
        .where('invite_code', isEqualTo: code)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return Circle.fromFirestore(query.docs.first);
  }

  // Find circle by display ID
  Future<Circle?> findCircleByDisplayId(String displayId) async {
    final query = await _firestore
        .collection('circles')
        .where('display_id', isEqualTo: displayId)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return Circle.fromFirestore(query.docs.first);
  }

  // Get circle by ID
  Future<Circle?> getCircleById(String circleId) async {
    final doc = await _firestore.collection('circles').doc(circleId).get();
    if (!doc.exists) return null;
    return Circle.fromFirestore(doc);
  }

  // Update circle profile
  Future<void> updateCircleProfile(
    String circleId, {
    String? description,
    List<String>? activityDays,
    String? place,
    String? memberCount,
    String? genderRatio,
    String? websiteUrl,
    String? iconUrl,
    String? xId,
    String? instagramId,
  }) async {
    final updates = <String, dynamic>{};
    if (description != null) updates['description'] = description;
    if (activityDays != null) updates['activity_days'] = activityDays;
    if (place != null) updates['place'] = place;
    if (memberCount != null) updates['member_count'] = memberCount;
    if (genderRatio != null) updates['gender_ratio'] = genderRatio;
    if (websiteUrl != null) updates['website_url'] = websiteUrl;
    if (iconUrl != null) updates['icon_url'] = iconUrl;
    if (xId != null) updates['x_id'] = xId;
    if (instagramId != null) updates['instagram_id'] = instagramId;

    if (updates.isEmpty) return;
    await FirebaseFunctions.instance.httpsCallable('updateCircleProfile').call({
      'circleId': circleId,
      'updates': updates,
    });
  }

  Future<String> uploadCircleIcon(File file, String circleId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('User must be logged in');
    }
    final ref = FirebaseStorage.instance
        .ref()
        .child('circle_icons')
        .child('${uid}_$circleId.jpg');

    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  // Pin/Unpin event
  Future<void> pinEvent(String circleId, String? eventId) async {
    await FirebaseFunctions.instance.httpsCallable('pinCircleEvent').call({
      'circleId': circleId,
      'eventId': eventId,
    });
  }

  Future<List<Circle>> getCircles() async {
    final universityId = await _userService.getCurrentUniversityId();
    if (universityId == null) return [];

    final circlesById = <String, Circle>{};
    for (final candidateUniversityId in _universityAliases(universityId)) {
      final snapshot = await _firestore
          .collection('circles')
          .where('universityId', isEqualTo: candidateUniversityId)
          .get();
      for (final doc in snapshot.docs) {
        circlesById[doc.id] = Circle.fromFirestore(doc);
      }
    }
    return circlesById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> updateMemberRole({
    required String circleId,
    required String memberUid,
    required CircleMemberRole role,
  }) async {
    await FirebaseFunctions.instance
        .httpsCallable('updateCircleMemberRole')
        .call({
      'circleId': circleId,
      'memberUid': memberUid,
      'role': role.value,
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> auditLogsStream(String circleId) {
    return _firestore
        .collection('circles')
        .doc(circleId)
        .collection('audit_logs')
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots();
  }

  void _addAuditLogToBatch(
    WriteBatch batch,
    String circleId, {
    required String actorUid,
    required String action,
    required String targetType,
    String? targetId,
    Map<String, dynamic>? changes,
  }) {
    final logRef = _firestore
        .collection('circles')
        .doc(circleId)
        .collection('audit_logs')
        .doc();
    batch.set(
        logRef,
        _auditLogData(
          actorUid: actorUid,
          action: action,
          targetType: targetType,
          targetId: targetId,
          changes: changes,
        ));
  }

  Map<String, dynamic> _auditLogData({
    required String actorUid,
    required String action,
    required String targetType,
    String? targetId,
    Map<String, dynamic>? changes,
  }) {
    return {
      'actor_uid': actorUid,
      'action': action,
      'target_type': targetType,
      'target_id': targetId,
      'changes': changes ?? {},
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}
