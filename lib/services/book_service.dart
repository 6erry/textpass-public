import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/book.dart';
import 'user_service.dart';

class BookService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserService _userService = UserService();

  Future<List<Book>> getBooks() async {
    final universityId = await _userService.getCurrentUniversityId();
    if (universityId == null) return [];

    final snapshot = await _firestore
        .collection('books')
        .where('universityId', isEqualTo: universityId)
        .where('status', isEqualTo: 'available')
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map((doc) => Book.fromFirestore(doc)).toList();
  }

  Future<Book?> getBook(String id) async {
    final doc = await _firestore.collection('books').doc(id).get();
    if (!doc.exists) return null;
    return Book.fromFirestore(doc);
  }

  Future<void> updateBookStatus(String bookId, String status) async {
    await _firestore.collection('books').doc(bookId).update({'status': status});
  }

  bool isAllowedCategory(String category,
      {String listingType = listingTypeBook}) {
    return isAllowedListingCategory(listingType, category);
  }

  String? validateListingCategory(
    String category, {
    String listingType = listingTypeBook,
  }) {
    if (listingType == listingTypeCampusLifeBeta && !campusLifeBetaEnabled) {
      return '大学生活用品 β版は現在準備中です。';
    }
    if (isAllowedCategory(category, listingType: listingType)) return null;
    if (prohibitedBookCategories.contains(category)) {
      return 'このカテゴリの商品は出品できません。';
    }
    return '出品カテゴリを選択してください。';
  }
}
