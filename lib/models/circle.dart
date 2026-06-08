import 'package:cloud_firestore/cloud_firestore.dart';

enum CircleCategory {
  sports,
  music,
  culture,
  academic,
  entertainment,
  other;

  String get label {
    switch (this) {
      case CircleCategory.sports:
        return '運動';
      case CircleCategory.music:
        return '音楽';
      case CircleCategory.culture:
        return '文化・芸術';
      case CircleCategory.academic:
        return '学術・技術';
      case CircleCategory.entertainment:
        return 'エンタメ・趣味';
      case CircleCategory.other:
        return 'その他';
    }
  }
}

enum CircleMemberRole {
  owner,
  admin,
  eventManager,
  member;

  String get value {
    switch (this) {
      case CircleMemberRole.owner:
        return 'owner';
      case CircleMemberRole.admin:
        return 'admin';
      case CircleMemberRole.eventManager:
        return 'event_manager';
      case CircleMemberRole.member:
        return 'member';
    }
  }

  String get label {
    switch (this) {
      case CircleMemberRole.owner:
        return 'サークル長';
      case CircleMemberRole.admin:
        return '管理者';
      case CircleMemberRole.eventManager:
        return 'イベント担当';
      case CircleMemberRole.member:
        return 'メンバー';
    }
  }

  bool get canManageCircle =>
      this == CircleMemberRole.owner || this == CircleMemberRole.admin;

  bool get canManageEvents =>
      canManageCircle || this == CircleMemberRole.eventManager;

  static CircleMemberRole fromValue(String? value) {
    return CircleMemberRole.values.firstWhere(
      (role) => role.value == value,
      orElse: () => CircleMemberRole.member,
    );
  }
}

class Circle {
  final String id; // Firestore Document ID
  final String? displayId; // User defined unique ID (e.g. hokudai_keion)
  final String name;
  final String description;
  final CircleCategory category;
  final String status; // 'pending', 'active'
  final List<String> memberUids; // All members
  final List<String> adminUids; // Admin members (subset of memberUids)
  final Map<String, CircleMemberRole> memberRoles;
  final String universityDomain;
  final String? inviteCode;
  final DateTime createdAt;
  final List<String> activityDays;
  final String? place;
  final String? memberCount;
  final String? genderRatio;
  final String? websiteUrl;
  final String? pinnedEventId;
  final String? iconUrl;
  final String universityId;
  final String? xId;
  final String? instagramId;
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

  Circle({
    required this.id,
    this.displayId,
    required this.name,
    this.description = '',
    this.category = CircleCategory.other,
    required this.status,
    this.memberUids = const [],
    this.adminUids = const [],
    this.memberRoles = const {},
    required this.universityDomain,
    this.inviteCode,
    required this.createdAt,
    this.activityDays = const [],
    this.place,
    this.memberCount,
    this.genderRatio,
    this.websiteUrl,
    this.pinnedEventId,
    this.iconUrl,
    required this.universityId,
    this.xId,
    this.instagramId,
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

  factory Circle.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final memberUids = List<String>.from(data['member_uids'] ?? []);
    final adminUids = List<String>.from(data['admin_uids'] ?? []);
    return Circle(
      id: doc.id,
      displayId: data['display_id'],
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      category: CircleCategory.values.firstWhere(
        (e) => e.name == (data['category'] ?? 'other'),
        orElse: () => CircleCategory.other,
      ),
      status: data['status'] ?? 'pending',
      memberUids: memberUids,
      adminUids: adminUids,
      memberRoles: _parseMemberRoles(
        data['member_roles'],
        memberUids,
        adminUids,
      ),
      universityDomain: data['university_domain'] ?? '',
      inviteCode: data['invite_code'],
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      activityDays: (data['activity_days'] is List)
          ? List<String>.from(data['activity_days'])
          : (data['activity_days'] is String)
              ? (data['activity_days'] as String)
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
              : [],
      place: data['place'],
      memberCount: data['member_count'],
      genderRatio: data['gender_ratio'],
      websiteUrl: data['website_url'],
      pinnedEventId: data['pinned_event_id'],
      iconUrl: data['icon_url'],
      universityId: data['universityId'] ?? 'hokudai',
      xId: data['x_id'],
      instagramId: data['instagram_id'],
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
      'display_id': displayId,
      'name': name,
      'description': description,
      'category': category.name,
      'status': status,
      'member_uids': memberUids,
      'admin_uids': adminUids,
      'member_roles': memberRoles.map((uid, role) => MapEntry(uid, role.value)),
      'university_domain': universityDomain,
      'invite_code': inviteCode,
      'created_at': Timestamp.fromDate(createdAt),
      'activity_days': activityDays,
      'place': place,
      'member_count': memberCount,
      'gender_ratio': genderRatio,
      'website_url': websiteUrl,
      'pinned_event_id': pinnedEventId,
      'icon_url': iconUrl,
      'universityId': universityId,
      'x_id': xId,
      'instagram_id': instagramId,
    };
  }

  CircleMemberRole roleFor(String uid) {
    final explicitRole = memberRoles[uid];
    if (explicitRole != null) return explicitRole;
    if (adminUids.contains(uid)) return CircleMemberRole.admin;
    if (memberUids.contains(uid)) return CircleMemberRole.member;
    return CircleMemberRole.member;
  }

  bool canManageCircle(String uid) => roleFor(uid).canManageCircle;

  bool canManageEvents(String uid) => roleFor(uid).canManageEvents;

  static Map<String, CircleMemberRole> _parseMemberRoles(
    dynamic raw,
    List<String> memberUids,
    List<String> adminUids,
  ) {
    if (raw is Map && raw.isNotEmpty) {
      return raw.map((uid, value) {
        return MapEntry(uid.toString(), CircleMemberRole.fromValue('$value'));
      });
    }

    final roles = <String, CircleMemberRole>{};
    for (final uid in memberUids) {
      roles[uid] = CircleMemberRole.member;
    }
    for (var i = 0; i < adminUids.length; i += 1) {
      final uid = adminUids[i];
      roles[uid] = i == 0 ? CircleMemberRole.owner : CircleMemberRole.admin;
    }
    return roles;
  }
}
