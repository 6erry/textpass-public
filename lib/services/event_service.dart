import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/event.dart';
import '../models/circle.dart';
import 'user_service.dart';

class EventService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final UserService _userService = UserService();

  Future<String?> uploadImage(String path) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return null;
      final ref = _storage
          .ref()
          .child('events/${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(File(path));
      return await ref.getDownloadURL();
    } catch (e) {
      // print('Error uploading image: $e');
      return null;
    }
  }

  Future<void> createEvent({
    required String circleId,
    required String title,
    required DateTime startAt,
    required String location,
    required CircleCategory category,
    required List<String> tags,
    String? imageUrl,
    bool isDraft = false,
    String description = '',
  }) async {
    await FirebaseFunctions.instance.httpsCallable('createCircleEvents').call({
      'circleId': circleId,
      'events': [
        _eventPayload(
          title: title,
          startAt: startAt,
          location: location,
          category: category,
          tags: tags,
          imageUrl: imageUrl,
          isDraft: isDraft,
          description: description,
        ),
      ],
    });
  }

  Future<void> createEventsBatch(List<Event> events) async {
    if (events.isEmpty) return;
    final circleId = events.first.circleId;
    await FirebaseFunctions.instance.httpsCallable('createCircleEvents').call({
      'circleId': circleId,
      'events': events
          .map((event) => _eventPayload(
                title: event.title,
                startAt: event.startAt,
                location: event.location,
                category: event.category,
                tags: event.tags,
                imageUrl: event.imageUrl,
                isDraft: event.isDraft,
                description: event.description,
              ))
          .toList(),
    });
  }

  Stream<List<Event>> getEvents({CircleCategory? category}) async* {
    final universityId = await _userService.getCurrentUniversityId();
    if (universityId == null) {
      yield [];
      return;
    }

    Query query = _firestore
        .collection('events')
        .where('universityId', isEqualTo: universityId)
        .where('is_draft', isEqualTo: false)
        .orderBy('start_at');

    yield* query.snapshots().map((snapshot) {
      var events =
          snapshot.docs.map((doc) => Event.fromFirestore(doc)).toList();
      if (category != null) {
        events = events.where((event) => event.category == category).toList();
      }
      events.sort((a, b) {
        final promotedCompare = (b.isActivePromotion ? 1 : 0)
            .compareTo(a.isActivePromotion ? 1 : 0);
        if (promotedCompare != 0) return promotedCompare;
        return a.startAt.compareTo(b.startAt);
      });
      return events;
    });
  }

  Stream<List<Event>> getDraftEvents() async* {
    final universityId = await _userService.getCurrentUniversityId();
    if (universityId == null) {
      yield [];
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      yield [];
      return;
    }

    yield* _firestore
        .collection('events')
        .where('universityId', isEqualTo: universityId)
        .where('is_draft', isEqualTo: true)
        .orderBy('start_at')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Event.fromFirestore(doc)).toList();
    });
  }

  Future<void> updateEvent({
    required String eventId,
    required String circleId,
    required String title,
    required DateTime startAt,
    required String location,
    required CircleCategory category,
    required List<String> tags,
    String? imageUrl,
    bool isDraft = false,
    String description = '',
    DateTime? createdAt,
  }) async {
    await FirebaseFunctions.instance.httpsCallable('updateCircleEvent').call({
      'circleId': circleId,
      'eventId': eventId,
      'event': _eventPayload(
        title: title,
        startAt: startAt,
        location: location,
        category: category,
        tags: tags,
        imageUrl: imageUrl,
        isDraft: isDraft,
        description: description,
      ),
    });
  }

  Future<void> deleteEvent(String eventId, String circleId) async {
    await FirebaseFunctions.instance.httpsCallable('deleteCircleEvent').call({
      'circleId': circleId,
      'eventId': eventId,
    });
  }

  Future<void> toggleLike(String eventId, bool shouldLike) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final eventRef = _firestore.collection('events').doc(eventId);
    final userRef = _firestore.collection('users').doc(user.uid);

    await _firestore.runTransaction((transaction) async {
      final eventDoc = await transaction.get(eventRef);
      if (!eventDoc.exists) throw Exception('Event not found');

      final currentLikes = eventDoc.data()?['like_count'] ?? 0;
      int newLikes = shouldLike ? currentLikes + 1 : currentLikes - 1;
      if (newLikes < 0) newLikes = 0;

      transaction.update(eventRef, {'like_count': newLikes});

      if (shouldLike) {
        transaction.update(userRef, {
          'likedEventIds': FieldValue.arrayUnion([eventId])
        });
      } else {
        transaction.update(userRef, {
          'likedEventIds': FieldValue.arrayRemove([eventId])
        });
      }
    });
  }

  Stream<List<Event>> getTodaysEvents() async* {
    final universityId = await _userService.getCurrentUniversityId();
    if (universityId == null) {
      yield [];
      return;
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    yield* _firestore
        .collection('events')
        .where('universityId', isEqualTo: universityId)
        .where('is_draft', isEqualTo: false)
        .where('start_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('start_at', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Event.fromFirestore(doc)).toList();
    });
  }

  Map<String, dynamic> _eventPayload({
    required String title,
    required DateTime startAt,
    required String location,
    required CircleCategory category,
    required List<String> tags,
    String? imageUrl,
    bool isDraft = false,
    String description = '',
  }) {
    return {
      'title': title,
      'startAtMillis': startAt.millisecondsSinceEpoch,
      'location': location,
      'category': category.name,
      'tags': tags,
      'imageUrl': imageUrl,
      'isDraft': isDraft,
      'description': description,
    };
  }
}
