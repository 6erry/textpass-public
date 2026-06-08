import 'package:cloud_firestore/cloud_firestore.dart';
import 'circle.dart';

class Event {
  final String id;
  final String circleId;
  final CircleCategory category;
  final String title;
  final DateTime startAt;
  final String location;
  final List<String> tags;
  final String? imageUrl;
  final bool isDraft;
  final String description;
  final DateTime createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final int likeCount;
  final String universityId;
  final bool isPromoted;
  final bool isPr;
  final String promotionTier;
  final String promotionStatus;
  final DateTime? promotionStartAt;
  final DateTime? promotionEndAt;
  final String? promotionLabel;
  final String? promotionAdminMemo;
  final String? promotionExternalRef;
  final DateTime? promotionCreatedAt;
  final String? promotionCreatedBy;
  final DateTime? promotionUpdatedAt;
  final String? promotionUpdatedBy;

  Event({
    required this.id,
    required this.circleId,
    required this.category,
    required this.title,
    required this.startAt,
    required this.location,
    required this.tags,
    this.imageUrl,
    this.isDraft = false,
    this.description = '',
    required this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
    this.likeCount = 0,
    required this.universityId,
    this.isPromoted = false,
    this.isPr = false,
    this.promotionTier = 'none',
    this.promotionStatus = 'none',
    this.promotionStartAt,
    this.promotionEndAt,
    this.promotionLabel,
    this.promotionAdminMemo,
    this.promotionExternalRef,
    this.promotionCreatedAt,
    this.promotionCreatedBy,
    this.promotionUpdatedAt,
    this.promotionUpdatedBy,
  });

  factory Event.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Event(
      id: doc.id,
      circleId: data['circle_id'] ?? '',
      category: CircleCategory.values.firstWhere(
        (e) => e.name == (data['category'] ?? 'other'),
        orElse: () => CircleCategory.other,
      ),
      title: data['title'] ?? '',
      startAt: (data['start_at'] as Timestamp).toDate(),
      location: data['location'] ?? '',
      tags: (data['tags'] is List)
          ? List<String>.from(data['tags'])
          : (data['tags'] is String)
              ? (data['tags'] as String)
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
              : [],
      imageUrl: data['image_url'],
      isDraft: data['is_draft'] ?? false,
      description: data['description'] ?? '',
      createdAt: (data['created_at'] as Timestamp).toDate(),
      createdBy: data['created_by'],
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate(),
      updatedBy: data['updated_by'],
      likeCount: data['like_count'] ?? 0,
      universityId: data['universityId'] ?? 'hokudai',
      isPromoted: data['isPromoted'] == true,
      isPr: data['isPr'] == true,
      promotionTier: data['promotionTier'] ?? 'none',
      promotionStatus: data['promotionStatus'] ?? 'none',
      promotionStartAt: (data['promotionStartAt'] as Timestamp?)?.toDate(),
      promotionEndAt: (data['promotionEndAt'] as Timestamp?)?.toDate(),
      promotionLabel: data['promotionLabel'],
      promotionAdminMemo: data['promotionAdminMemo'],
      promotionExternalRef: data['promotionExternalRef'],
      promotionCreatedAt: (data['promotionCreatedAt'] as Timestamp?)?.toDate(),
      promotionCreatedBy: data['promotionCreatedBy'],
      promotionUpdatedAt: (data['promotionUpdatedAt'] as Timestamp?)?.toDate(),
      promotionUpdatedBy: data['promotionUpdatedBy'],
    );
  }

  bool get isActivePromotion {
    final now = DateTime.now();
    if (promotionStatus != 'active') return false;
    if (!isPromoted || !isPr) return false;
    if (promotionStartAt != null && promotionStartAt!.isAfter(now)) {
      return false;
    }
    if (promotionEndAt != null && !promotionEndAt!.isAfter(now)) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toMap() {
    return {
      'circle_id': circleId,
      'category': category.name,
      'title': title,
      'start_at': Timestamp.fromDate(startAt),
      'location': location,
      'tags': tags,
      'image_url': imageUrl,
      'is_draft': isDraft,
      'description': description,
      'created_at': Timestamp.fromDate(createdAt),
      'created_by': createdBy,
      'updated_at': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      'updated_by': updatedBy,
      'like_count': likeCount,
      'universityId': universityId,
      'isPromoted': isPromoted,
      'isPr': isPr,
      'promotionTier': promotionTier,
      'promotionStatus': promotionStatus,
      'promotionStartAt': promotionStartAt == null
          ? null
          : Timestamp.fromDate(promotionStartAt!),
      'promotionEndAt':
          promotionEndAt == null ? null : Timestamp.fromDate(promotionEndAt!),
      'promotionLabel': promotionLabel,
      'promotionAdminMemo': promotionAdminMemo,
      'promotionExternalRef': promotionExternalRef,
      'promotionCreatedAt': promotionCreatedAt == null
          ? null
          : Timestamp.fromDate(promotionCreatedAt!),
      'promotionCreatedBy': promotionCreatedBy,
      'promotionUpdatedAt': promotionUpdatedAt == null
          ? null
          : Timestamp.fromDate(promotionUpdatedAt!),
      'promotionUpdatedBy': promotionUpdatedBy,
    };
  }
}
