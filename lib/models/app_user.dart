import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String id;
  final String email;
  final String universityId;
  final String faculty; // 学部
  final String department; // 学科
  final String grade; // 学年
  final String nickname;
  final String? photoUrl;
  final bool isProfileComplete;
  final bool isAdmin;
  final bool isBanned;
  final List<String> fcmTokens;
  final List<String> blockedUserIds;
  final List<String> alertKeywords;
  final String? stripeAccountId;
  final bool isStripeOnboarded;
  final DateTime createdAt;
  final String timetableSystem; // 'semester' or 'quarter'
  final List<int> activePeriods;
  final bool hasConfiguredTimetableSystem;
  final int? currentTimetableYear;
  final String? currentTimetableTerm;
  final int transactionCount;
  final int sellerCompletedCount;
  final int buyerCompletedCount;
  final double? positiveReviewRate;
  final double? averageRating;
  final double? sellerAverageRating;
  final double? buyerAverageRating;
  final int cancelledCount;
  final int noShowCount;
  final DateTime? lastTransactionAt;

  AppUser({
    required this.id,
    required this.email,
    required this.universityId,
    required this.faculty,
    required this.department,
    required this.grade,
    required this.nickname,
    this.photoUrl,
    this.isProfileComplete = false,
    this.isAdmin = false,
    this.isBanned = false,
    this.fcmTokens = const [],
    this.blockedUserIds = const [],
    this.alertKeywords = const [],
    this.stripeAccountId,
    this.isStripeOnboarded = false,
    required this.createdAt,
    this.timetableSystem = 'semester',
    this.activePeriods = const [1, 2, 3, 4, 5],
    this.hasConfiguredTimetableSystem = false,
    this.currentTimetableYear,
    this.currentTimetableTerm,
    this.transactionCount = 0,
    this.sellerCompletedCount = 0,
    this.buyerCompletedCount = 0,
    this.positiveReviewRate,
    this.averageRating,
    this.sellerAverageRating,
    this.buyerAverageRating,
    this.cancelledCount = 0,
    this.noShowCount = 0,
    this.lastTransactionAt,
  });

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      id: doc.id,
      email: data['email'] ?? '',
      universityId: data['universityId'] ?? 'hokudai',
      faculty: data['faculty'] ?? '',
      department: data['department'] ?? '',
      grade: data['grade'] ?? '',
      nickname: data['nickname'] ?? '',
      photoUrl: data['photoUrl'],
      isProfileComplete: data['isProfileComplete'] ?? false,
      isAdmin: data['isAdmin'] ?? false,
      isBanned: data['isBanned'] ?? false,
      fcmTokens: List<String>.from(data['fcmTokens'] ?? []),
      blockedUserIds: List<String>.from(data['blockedUserIds'] ?? []),
      alertKeywords: List<String>.from(data['alertKeywords'] ?? []),
      stripeAccountId:
          data['stripeAccountId'] ?? data['stripeConnectedAccountId'],
      isStripeOnboarded: data['isStripeOnboarded'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      timetableSystem: data['timetableSystem'] ?? 'semester',
      activePeriods: List<int>.from(data['activePeriods'] ?? [1, 2, 3, 4, 5]),
      hasConfiguredTimetableSystem:
          data['hasConfiguredTimetableSystem'] == true ||
              data['timetableSystemConfigured'] == true,
      currentTimetableYear: data['currentTimetableYear'] is int
          ? data['currentTimetableYear']
          : int.tryParse(data['currentTimetableYear']?.toString() ?? ''),
      currentTimetableTerm: data['currentTimetableTerm']?.toString(),
      transactionCount: (data['transactionCount'] as num?)?.toInt() ?? 0,
      sellerCompletedCount:
          (data['sellerCompletedCount'] as num?)?.toInt() ?? 0,
      buyerCompletedCount: (data['buyerCompletedCount'] as num?)?.toInt() ?? 0,
      positiveReviewRate: (data['positiveReviewRate'] as num?)?.toDouble(),
      averageRating: (data['averageRating'] as num?)?.toDouble(),
      sellerAverageRating: (data['sellerAverageRating'] as num?)?.toDouble(),
      buyerAverageRating: (data['buyerAverageRating'] as num?)?.toDouble(),
      cancelledCount: (data['cancelledCount'] as num?)?.toInt() ?? 0,
      noShowCount: (data['noShowCount'] as num?)?.toInt() ?? 0,
      lastTransactionAt: (data['lastTransactionAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'universityId': universityId,
      'faculty': faculty,
      'department': department,
      'grade': grade,
      'nickname': nickname,
      'photoUrl': photoUrl,
      'isProfileComplete': isProfileComplete,
      'isAdmin': isAdmin,
      'isBanned': isBanned,
      'fcmTokens': fcmTokens,
      'blockedUserIds': blockedUserIds,
      'alertKeywords': alertKeywords,
      'stripeAccountId': stripeAccountId,
      'isStripeOnboarded': isStripeOnboarded,
      'createdAt': Timestamp.fromDate(createdAt),
      'timetableSystem': timetableSystem,
      'activePeriods': activePeriods,
      'hasConfiguredTimetableSystem': hasConfiguredTimetableSystem,
      'currentTimetableYear': currentTimetableYear,
      'currentTimetableTerm': currentTimetableTerm,
      'transactionCount': transactionCount,
      'sellerCompletedCount': sellerCompletedCount,
      'buyerCompletedCount': buyerCompletedCount,
      'positiveReviewRate': positiveReviewRate,
      'averageRating': averageRating,
      'sellerAverageRating': sellerAverageRating,
      'buyerAverageRating': buyerAverageRating,
      'cancelledCount': cancelledCount,
      'noShowCount': noShowCount,
      if (lastTransactionAt != null)
        'lastTransactionAt': Timestamp.fromDate(lastTransactionAt!),
    };
  }
}
