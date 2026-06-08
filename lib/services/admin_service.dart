import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Check if current user is admin (security check for UI)
  Future<bool> _verifyAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    return doc.data()?['isAdmin'] == true;
  }

  // Fetch all reports
  Stream<QuerySnapshot<Map<String, dynamic>>> getReportsStream() {
    return _firestore
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Delete content (Book or Event)
  Future<void> deleteContent(String collection, String docId) async {
    if (!await _verifyAdmin()) throw Exception('Unauthorized');

    // Update status to 'deleted_by_admin' instead of physical delete
    // to keep records, or physical delete if preferred.
    // Requirement says "Delete (Hide)", so let's update status or delete.
    // For items/events, usually physical delete or status change.
    // Let's do physical delete for now as per "Delete" button,
    // but maybe better to just set a flag?
    // Let's try physical delete as requested in "Violation Content Deletion".

    await _firestore.collection(collection).doc(docId).delete();

    // Also mark report as resolved if this was from a report?
    // The UI will handle report resolution separately or we can do it here.
  }

  Future<void> moderateContent({
    required String collection,
    required String docId,
    required String status,
    String? reason,
  }) async {
    if (!await _verifyAdmin()) throw Exception('Unauthorized');

    final uid = _auth.currentUser?.uid;
    final payload = <String, Object?>{
      'moderationStatus': status,
      'moderationReason': reason,
      'moderatedAt': FieldValue.serverTimestamp(),
      'moderatedBy': uid,
    };
    if (collection == 'books') {
      payload['status'] = status == 'active' ? 'available' : 'hidden';
    } else {
      payload['status'] = status;
    }
    await _firestore.collection(collection).doc(docId).update(payload);
  }

  // Ban user
  Future<void> banUser(String uid) async {
    if (!await _verifyAdmin()) throw Exception('Unauthorized');

    await _firestore.collection('users').doc(uid).update({
      'isBanned': true,
    });
  }

  // Unban user (optional, but good to have)
  Future<void> unbanUser(String uid) async {
    if (!await _verifyAdmin()) throw Exception('Unauthorized');

    await _firestore.collection('users').doc(uid).update({
      'isBanned': false,
    });
  }

  // Resolve report
  Future<void> resolveReport(String reportId) async {
    if (!await _verifyAdmin()) throw Exception('Unauthorized');

    await _firestore.collection('reports').doc(reportId).update({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': _auth.currentUser?.uid,
    });
  }

  // Fetch unresolved reports
  Stream<QuerySnapshot<Map<String, dynamic>>> getUnresolvedReportsStream() {
    return _firestore
        .collection('reports')
        .where('status', isNotEqualTo: 'resolved')
        .orderBy('status') // Required for inequality filter
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Search users by email or UID
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> searchUser(
      String query) async {
    if (!await _verifyAdmin()) throw Exception('Unauthorized');

    if (query.isEmpty) return [];

    // Search by UID
    final uidDoc = await _firestore.collection('users').doc(query).get();
    if (uidDoc.exists) {
      return [uidDoc];
    }

    // Search by Email
    final emailQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: query)
        .get();

    if (emailQuery.docs.isNotEmpty) {
      return emailQuery.docs;
    }

    return [];
  }

  // Create Announcement
  Future<void> createAnnouncement(
      String title, String content, bool isImportant) async {
    if (!await _verifyAdmin()) throw Exception('Unauthorized');

    await _firestore.collection('announcements').add({
      'title': title,
      'content': content,
      'isImportant': isImportant,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid,
    });
  }
}
