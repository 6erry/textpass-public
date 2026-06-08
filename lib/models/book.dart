import 'package:cloud_firestore/cloud_firestore.dart';

const listingTypeBook = 'book';
const listingTypeAcademicSupply = 'academic_supply';
const listingTypeCampusLifeBeta = 'campus_life_beta';

const purchaseModeInstant = 'instant';
const purchaseModeApprovalRequired = 'approval_required';

const allowedListingTypes = [
  listingTypeBook,
  listingTypeAcademicSupply,
  listingTypeCampusLifeBeta,
];

const listingTypeLabels = {
  listingTypeBook: '本・教材',
  listingTypeAcademicSupply: '授業用品',
  listingTypeCampusLifeBeta: '大学生活用品 β版',
};

const campusLifeBetaEnabled = false;

const allowedBookCategories = [
  '教科書',
  '参考書',
  '問題集',
  '専門書',
  '資格・検定本',
  '語学教材',
  'その他教材',
];

const allowedAcademicSupplyCategories = [
  '関数電卓',
  '白衣',
  '実験用品',
  '製図用品',
  '語学辞書',
  '実習・演習用品',
  '授業で使う道具',
  'その他授業用品',
];

const allowedCampusLifeBetaCategories = <String>[];

const prohibitedBookCategories = [
  '家電',
  '家具',
  '自転車',
  'PC本体',
  'スマートフォン',
  'タブレット',
  'ゲーム機',
  'ブランド品',
  'チケット',
  '金券',
  '食品',
  '飲料',
  '酒',
  'たばこ',
  '医薬品',
  '化粧品',
  '危険物',
  '代理出品',
  '買取品',
  '預かり品',
  '転売目的の商品',
  '授業と関係のない物品',
];

const conditionLabels = {
  'new': '新品・未使用',
  'like_new': '未使用に近い',
  'good': '目立った傷や汚れなし',
  'fair': 'やや傷や汚れあり',
  'poor': '傷や汚れあり',
};

const writingLevelLabels = {
  'none': '書き込みなし',
  'small': '少しあり',
  'medium': 'ところどころあり',
  'many': '多い',
};

const purchaseModeLabels = {
  purchaseModeInstant: 'すぐ購入可',
  purchaseModeApprovalRequired: '購入前に承認',
};

List<String> allowedCategoriesForListingType(String listingType) {
  switch (listingType) {
    case listingTypeAcademicSupply:
      return allowedAcademicSupplyCategories;
    case listingTypeCampusLifeBeta:
      return allowedCampusLifeBetaCategories;
    case listingTypeBook:
    default:
      return allowedBookCategories;
  }
}

bool isAllowedListingCategory(String listingType, String category) {
  return allowedCategoriesForListingType(listingType).contains(category);
}

double feeRateForListingType(String listingType) {
  switch (listingType) {
    case listingTypeAcademicSupply:
    case listingTypeCampusLifeBeta:
      return 0.08;
    case listingTypeBook:
    default:
      return 0.05;
  }
}

String defaultPurchaseModeForListingType(String listingType) {
  return purchaseModeInstant;
}

String normalizeHandoverType(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == 'いつでも' || trimmed == 'オンラインで相談') {
    return '要相談';
  }
  return trimmed;
}

class Book {
  final String id;
  final String title;
  final int price;
  final List<String> imageUrls; // Changed from imageUrl
  final String author;
  final String courseName;
  final String userId;
  final String? status;
  final String? isbn;
  final String universityId;
  final String listingType;
  final String category;
  final String? subcategory;
  final String condition;
  final String? conditionNote;
  final bool? hasWriting;
  final String? writingLevel;
  final bool? isWorkingConfirmed;
  final List<String>? includedItems;
  final String? cautionNote;
  final double feeRate;
  final int buyerFee;
  final bool prohibitedCheckConfirmed;
  final bool ownershipCheckConfirmed;
  final String moderationStatus;
  final String? moderationReason;
  final DateTime? moderatedAt;
  final String? moderatedBy;
  final String purchaseMode;

  final int likeCount;
  final int commentCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String handoverType;

  const Book({
    required this.id,
    required this.title,
    required this.price,
    required this.imageUrls,
    required this.author,
    required this.courseName,
    required this.userId,
    this.status,
    this.isbn,
    required this.universityId,
    this.listingType = listingTypeBook,
    this.category = '教科書',
    this.subcategory,
    this.condition = 'good',
    this.conditionNote,
    this.hasWriting,
    this.writingLevel,
    this.isWorkingConfirmed,
    this.includedItems,
    this.cautionNote,
    this.feeRate = 0.05,
    this.buyerFee = 100,
    this.prohibitedCheckConfirmed = true,
    this.ownershipCheckConfirmed = true,
    this.moderationStatus = 'active',
    this.moderationReason,
    this.moderatedAt,
    this.moderatedBy,
    this.purchaseMode = purchaseModeInstant,
    this.likeCount = 0,
    this.commentCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.handoverType = '要相談',
  });

  factory Book.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Handle migration from single imageUrl to list
    List<String> images = [];
    if (data['imageUrls'] != null) {
      images = List<String>.from(data['imageUrls']);
    } else if (data['imageUrl'] != null && data['imageUrl'] != '') {
      images = [data['imageUrl'] as String];
    }

    final listingType = allowedListingTypes.contains(data['listingType'])
        ? data['listingType'] as String
        : listingTypeBook;
    final category = data['category'] as String? ?? '教科書';
    final condition = conditionLabels.containsKey(data['condition'])
        ? data['condition'] as String
        : 'good';
    final purchaseMode = purchaseModeLabels.containsKey(data['purchaseMode'])
        ? data['purchaseMode'] as String
        : defaultPurchaseModeForListingType(listingType);

    return Book(
      id: doc.id,
      title: data['title'] as String? ?? '',
      price: (data['price'] is int)
          ? data['price'] as int
          : int.tryParse(data['price'].toString()) ?? 0,
      imageUrls: images,
      author: data['author'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      status: data['status'] as String?,
      isbn: data['isbn'] as String?,
      universityId: data['universityId'] as String? ?? 'hokudai',
      listingType: listingType,
      category:
          isAllowedListingCategory(listingType, category) ? category : '教科書',
      subcategory: data['subcategory'] as String?,
      condition: condition,
      conditionNote: data['conditionNote'] as String?,
      hasWriting: data['hasWriting'] as bool?,
      writingLevel: writingLevelLabels.containsKey(data['writingLevel'])
          ? data['writingLevel'] as String
          : null,
      isWorkingConfirmed: data['isWorkingConfirmed'] as bool?,
      includedItems: data['includedItems'] is List
          ? List<String>.from(data['includedItems'] as List)
          : null,
      cautionNote: data['cautionNote'] as String?,
      feeRate: (data['feeRate'] is num)
          ? (data['feeRate'] as num).toDouble()
          : feeRateForListingType(listingType),
      buyerFee: (data['buyerFee'] is int)
          ? data['buyerFee'] as int
          : int.tryParse(data['buyerFee']?.toString() ?? '') ?? 100,
      prohibitedCheckConfirmed:
          data['prohibitedCheckConfirmed'] as bool? ?? true,
      ownershipCheckConfirmed: data['ownershipCheckConfirmed'] as bool? ?? true,
      moderationStatus: data['moderationStatus'] as String? ?? 'active',
      moderationReason: data['moderationReason'] as String?,
      moderatedAt: (data['moderatedAt'] as Timestamp?)?.toDate(),
      moderatedBy: data['moderatedBy'] as String?,
      purchaseMode: purchaseMode,
      likeCount: data['likeCount'] as int? ?? 0,
      commentCount: data['commentCount'] as int? ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      handoverType: normalizeHandoverType(data['handoverType'] as String?),
    );
  }
}
