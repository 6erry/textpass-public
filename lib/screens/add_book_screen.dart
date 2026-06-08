import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../models/book.dart';
import '../models/syllabus.dart';
import '../models/user_class.dart';
import '../services/book_service.dart';
import '../services/syllabus_service.dart';
import '../services/timetable_service.dart';
import '../utils/legal_notices.dart';

import '../widgets/app_custom_dialog.dart';
import '../widgets/app_selection_dialog.dart';

import 'package:textpass/utils/app_toast.dart';

class AddBookScreen extends StatefulWidget {
  const AddBookScreen({super.key, this.book, this.onListingComplete});

  final Book? book;
  final VoidCallback? onListingComplete;

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _BookImage {
  final File? file;
  final String? url;

  _BookImage({this.file, this.url});

  bool get isFile => file != null;
}

class _AddBookScreenState extends State<AddBookScreen> {
  final _isbnController = TextEditingController();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _courseController = TextEditingController();
  final _priceController = TextEditingController();
  final _conditionNoteController = TextEditingController();
  final _includedItemsController = TextEditingController();
  final _cautionNoteController = TextEditingController();

  List<_BookImage> _images = [];
  bool _isLoading = false;
  bool _isPickingImage = false;
  bool _isFetchingIsbn = false;
  bool _isFree = false;
  bool _ownershipConfirmed = false;
  bool _prohibitedConfirmed = false;
  bool _isWorkingConfirmed = false;
  String _listingType = listingTypeBook;
  String _category = '教科書';
  String _condition = 'good';
  String _writingLevel = 'none';
  String _handoverType = '要相談';
  List<String> _selectedHandoverDays = [];

  final List<String> _handoverTypes = [
    '要相談',
    '平日なら可',
    '土日なら可',
    '特定の曜日なら可',
  ];

  bool get _isEditing => widget.book != null;

  bool get _requiresRelatedCourse => _listingType == listingTypeBook;

  bool get _canSubmit {
    return _missingSubmitRequirements.isEmpty;
  }

  List<String> get _missingSubmitRequirements {
    final missing = <String>[];
    if (_isLoading) return const ['処理中'];
    if (_images.isEmpty) missing.add('写真');
    if (_titleController.text.trim().isEmpty) {
      missing.add(_listingType == listingTypeBook ? 'タイトル' : '商品名');
    }
    if (_requiresRelatedCourse && _courseController.text.trim().isEmpty) {
      missing.add('関連授業');
    }
    if (BookService().validateListingCategory(
          _category,
          listingType: _listingType,
        ) !=
        null) {
      missing.add('カテゴリ');
    }
    if (!conditionLabels.containsKey(_condition)) missing.add('状態');
    if (_listingType == listingTypeBook &&
        !writingLevelLabels.containsKey(_writingLevel)) {
      missing.add('書き込み');
    }
    if (_listingType == listingTypeAcademicSupply) {
      if (!_isWorkingConfirmed) missing.add('使用確認');
      if (_includedItemsController.text.trim().isEmpty) missing.add('付属品');
    }
    if (_handoverType == '特定の曜日なら可' && _selectedHandoverDays.isEmpty) {
      missing.add('曜日');
    }
    if (!_isFree) {
      final price = int.tryParse(_priceController.text.trim());
      if (price == null || price < 300 || price > 99999) {
        missing.add('価格');
      }
    }
    if (!_ownershipConfirmed) missing.add('確認チェック');
    if (!_prohibitedConfirmed) missing.add('禁止物確認');
    return missing;
  }

  @override
  void initState() {
    super.initState();

    final book = widget.book;
    if (book != null) {
      _titleController.text = book.title;
      _authorController.text = book.author;
      _courseController.text = book.courseName;
      _priceController.text = book.price.toString();
      _images = book.imageUrls.map((url) => _BookImage(url: url)).toList();
      _isbnController.text = book.isbn ?? '';
      _listingType = book.listingType;
      _condition = book.condition;
      _conditionNoteController.text = book.conditionNote ?? '';
      _writingLevel = book.writingLevel ?? 'none';
      _isWorkingConfirmed = book.isWorkingConfirmed ?? false;
      _includedItemsController.text = book.includedItems?.join('、') ?? '';
      _cautionNoteController.text = book.cautionNote ?? '';
      if (book.price == 0) {
        _isFree = true;
      }
      final categories = allowedCategoriesForListingType(_listingType);
      _category = isAllowedListingCategory(_listingType, book.category)
          ? book.category
          : (categories.isNotEmpty ? categories.first : '教科書');
      _ownershipConfirmed = true;
      _prohibitedConfirmed = true;

      final type = normalizeHandoverType(book.handoverType);
      // Handle legacy or formatted string
      if (_handoverTypes.contains(type)) {
        _handoverType = type;
      } else if (type == '何曜日なら可') {
        _handoverType = '特定の曜日なら可';
      } else {
        // Assume format like "月・水"
        _handoverType = '特定の曜日なら可';
        _selectedHandoverDays =
            type.split('・').where((s) => s.isNotEmpty).toList();
      }
    }

    _titleController.addListener(_handleRequiredFieldChanged);
    _authorController.addListener(_handleRequiredFieldChanged);
    _courseController.addListener(_handleRequiredFieldChanged);
    _priceController.addListener(_handleRequiredFieldChanged);
    _includedItemsController.addListener(_handleRequiredFieldChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleRequiredFieldChanged);
    _authorController.removeListener(_handleRequiredFieldChanged);
    _courseController.removeListener(_handleRequiredFieldChanged);
    _priceController.removeListener(_handleRequiredFieldChanged);
    _includedItemsController.removeListener(_handleRequiredFieldChanged);
    _isbnController.dispose();
    _titleController.dispose();
    _authorController.dispose();
    _courseController.dispose();
    _priceController.dispose();
    _conditionNoteController.dispose();
    _includedItemsController.dispose();
    _cautionNoteController.dispose();
    super.dispose();
  }

  void _handleRequiredFieldChanged() {
    if (mounted) setState(() {});
  }

  List<String> _parseIncludedItems(String raw) {
    return raw
        .split(RegExp(r'[,、\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _setListingType(String listingType) {
    if (_isLoading || listingType == _listingType) return;
    if (listingType == listingTypeCampusLifeBeta && !campusLifeBetaEnabled) {
      AppToast.show(context, '大学生活用品 β版は現在準備中です。');
      return;
    }
    final categories = allowedCategoriesForListingType(listingType);
    setState(() {
      _listingType = listingType;
      _category = categories.isNotEmpty ? categories.first : '教科書';
      if (listingType != listingTypeBook) {
        _courseController.clear();
      }
    });
  }

  List<String> _generateSearchKeywords(String title) {
    final normalized = title.toLowerCase().trim();
    if (normalized.isEmpty) return const [];

    final keywords = <String>{};
    final length = normalized.length;

    for (var start = 0; start < length; start++) {
      for (var end = start + 1; end <= length; end++) {
        final substring = normalized.substring(start, end).trim();
        if (substring.isNotEmpty) {
          keywords.add(substring);
        }
      }
    }

    return keywords.toList();
  }

  // --- Image picking ---
  Future<void> _pickImage() async {
    if (_isLoading || _isPickingImage) return;

    final source = await showAppSelectionDialog<ImageSource>(
      context: context,
      title: '画像を追加',
      selectedValue: null,
      options: const [
        AppSelectionOption(
          label: 'カメラで撮影',
          value: ImageSource.camera,
          icon: Icons.camera_alt_outlined,
        ),
        AppSelectionOption(
          label: 'アルバムから選択',
          value: ImageSource.gallery,
          icon: Icons.photo_library_outlined,
        ),
      ],
    );
    if (source == null) return;
    _pickFromSource(source);
  }

  Future<void> _pickFromSource(ImageSource source) async {
    _isPickingImage = true;
    try {
      final picker = ImagePicker();

      if (source == ImageSource.camera) {
        final pickedFile = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1080,
          imageQuality: 90,
        );

        if (pickedFile == null) return;

        // Crop logic for Camera
        final croppedFile = await _cropImage(File(pickedFile.path));
        if (croppedFile != null && mounted) {
          setState(() {
            _images.add(_BookImage(file: croppedFile));
          });
        }
      } else {
        // Gallery (Multi-pick, no crop for efficiency unless requested)
        final pickedFiles = await picker.pickMultiImage(
          maxWidth: 1080,
          imageQuality: 85,
        );

        if (!mounted || pickedFiles.isEmpty) return;

        setState(() {
          _images
              .addAll(pickedFiles.map((e) => _BookImage(file: File(e.path))));
        });
      }
    } catch (e) {
      debugPrint('Image picker error: $e');
      if (mounted) {
        AppToast.show(context, '画像の取得に失敗しました');
      }
    } finally {
      _isPickingImage = false;
    }
  }

  Future<File?> _cropImage(File imageFile) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '編集',
            toolbarColor: Colors.deepOrange,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: '編集',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: false,
          ),
        ],
      );
      if (croppedFile != null) {
        return File(croppedFile.path);
      }
    } catch (e) {
      debugPrint('Crop error: $e');
    }
    return null;
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  // --- ISBN helpers ---
  String? _normalizeIsbn(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (digits.length == 13 || digits.length == 10) {
      return digits.toUpperCase();
    }
    return null;
  }

  Future<void> _scanIsbn() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const _IsbnScannerPage(),
        fullscreenDialog: true,
      ),
    );
    if (result == null) return;
    _isbnController.text = result;
    await _fetchBookInfo();
  }

  Future<void> _fetchBookInfo() async {
    final normalized = _normalizeIsbn(_isbnController.text);
    if (normalized == null) {
      AppToast.show(context, 'ISBNを正しく入力・スキャンしてください');
      return;
    }

    setState(() {
      _isFetchingIsbn = true;
    });

    try {
      final gotOpenBd = await _fetchFromOpenBd(normalized);
      final gotNdl = gotOpenBd ? true : await _fetchFromNdl(normalized);
      final gotGbooks =
          gotOpenBd || gotNdl ? true : await _fetchFromGoogleBooks(normalized);

      if (!gotOpenBd && !gotNdl && !gotGbooks) {
        if (!mounted) return;
        AppToast.show(context, '書誌情報の取得に失敗しました');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingIsbn = false;
        });
      }
    }
  }

  Future<bool> _fetchFromOpenBd(String isbn) async {
    try {
      final uri = Uri.parse('https://api.openbd.jp/v1/get?isbn=$isbn');
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw Exception('openBD取得に失敗しました (${response.statusCode})');
      }

      final decoded = jsonDecode(body);
      if (decoded is! List || decoded.isEmpty || decoded[0] == null) {
        return false;
      }

      final Map<String, dynamic> volume =
          Map<String, dynamic>.from(decoded[0] as Map);

      final summary = volume['summary'] as Map<String, dynamic>? ?? {};
      final title = summary['title'] as String?;
      final author = summary['author'] as String?;
      final cover = summary['cover'] as String?;
      final price = _extractOpenBdPrice(volume);

      _applyBookData(
        title: title,
        author: author,
        cover: cover,
        price: price,
        source: 'openBD',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fetchFromGoogleBooks(String isbn) async {
    try {
      final uri =
          Uri.parse('https://www.googleapis.com/books/v1/volumes?q=isbn:$isbn');
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw Exception('Google Books取得に失敗しました (${response.statusCode})');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map || (decoded['totalItems'] as num? ?? 0) == 0) {
        return false;
      }

      final items = decoded['items'];
      if (items is! List || items.isEmpty) return false;
      final volumeInfo =
          (items.first as Map)['volumeInfo'] as Map<String, dynamic>? ?? {};
      final saleInfo =
          (items.first as Map)['saleInfo'] as Map<String, dynamic>? ?? {};

      final title = volumeInfo['title'] as String?;
      final authors = volumeInfo['authors'];
      final author = authors is List && authors.isNotEmpty
          ? authors.first.toString()
          : null;
      final imageLinks =
          volumeInfo['imageLinks'] as Map<String, dynamic>? ?? {};
      final cover = imageLinks['thumbnail'] as String?;

      int? price;
      final listPrice = saleInfo['listPrice'];
      if (listPrice is Map && listPrice['amount'] != null) {
        price = (listPrice['amount'] as num).toInt();
      }

      _applyBookData(
        title: title,
        author: author,
        cover: cover,
        price: price,
        source: 'Google Books',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fetchFromNdl(String isbn) async {
    try {
      final uri = Uri.parse(
          'https://ndlsearch.ndl.go.jp/api/sru?operation=searchRetrieve&recordPacking=json&query=isbn=$isbn&recordSchema=dcndl_simple');
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw Exception('NDL Search取得に失敗しました (${response.statusCode})');
      }

      final decoded = jsonDecode(body);
      final sr = decoded is Map<String, dynamic>
          ? decoded['searchRetrieveResponse'] as Map<String, dynamic>?
          : null;
      final records = sr?['records'];
      if (records is! List || records.isEmpty) return false;

      final record = records.first;
      final recordData = record is Map ? record['recordData'] : null;
      final dc = recordData is Map
          ? (recordData['dc'] ?? recordData['oai_dc:dc'])
          : null;
      if (dc is! Map) return false;

      String? firstVal(dynamic value) {
        if (value is List && value.isNotEmpty) return value.first.toString();
        if (value is String) return value;
        return null;
      }

      final title = firstVal(dc['title']) ?? firstVal(dc['dc:title']);
      final creator = firstVal(dc['creator']) ?? firstVal(dc['dc:creator']);
      final publisher =
          firstVal(dc['publisher']) ?? firstVal(dc['dc:publisher']);

      // NDLには表紙URLはほぼ無いので cover, price は無し
      _applyBookData(
        title: title,
        author: creator ?? publisher, // せめて出版者を著者枠に
        cover: null,
        price: null,
        source: 'NDL Search',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  int? _extractOpenBdPrice(Map<String, dynamic> volume) {
    final summary = volume['summary'] as Map<String, dynamic>?;
    final summaryPrice = summary?['price'];
    if (summaryPrice is num) return summaryPrice.toInt();

    final onix = volume['onix'] as Map<String, dynamic>?;
    final productSupply = onix?['ProductSupply'];
    if (productSupply is Map<String, dynamic>) {
      final supplyDetail = productSupply['SupplyDetail'];
      if (supplyDetail is Map<String, dynamic>) {
        final prices = supplyDetail['Price'];
        if (prices is List && prices.isNotEmpty) {
          final first = prices.first;
          if (first is Map && first['PriceAmount'] != null) {
            return int.tryParse(first['PriceAmount'].toString());
          }
        }
      }
    }
    return null;
  }

  void _applyBookData({
    required String source,
    String? title,
    String? author,
    String? cover,
    int? price,
  }) {
    setState(() {
      if (title != null && title.isNotEmpty) {
        _titleController.text = title;
      }
      if (author != null && author.isNotEmpty) {
        _authorController.text = author;
      }
      if (cover != null && cover.isNotEmpty && _images.isEmpty) {
        _images.add(_BookImage(url: cover));
      }
      if (price != null && price > 0 && _priceController.text.trim().isEmpty) {
        if (!_isFree) {
          final half = (price * 0.5).floor();
          _priceController.text = half > 0 ? half.toString() : price.toString();
        }
      }
    });

    final sourceLabel = source.isNotEmpty ? ' ($source)' : '';
    AppToast.show(context, 'ISBNから書誌情報をセットしました$sourceLabel');
  }

  // --- Submit ---
  Future<void> _submit() async {
    if (_isLoading) return;

    _log('submit tapped');
    FocusScope.of(context).unfocus();

    final title = _titleController.text.trim();
    final author = _authorController.text.trim();
    final courseName =
        _requiresRelatedCourse ? _courseController.text.trim() : '';
    final priceText = _priceController.text.trim();

    if (!_canSubmit) {
      AppToast.show(context, '必須項目を入力してください');
      return;
    }

    setState(() {
      _isLoading = true;
    });
    _log('loading spinner on');

    final categoryError = BookService().validateListingCategory(
      _category,
      listingType: _listingType,
    );
    if (categoryError != null) {
      AppToast.show(context, categoryError);
      setState(() {
        _isLoading = false;
      });
      return;
    }

    if (!_ownershipConfirmed) {
      AppToast.show(context, '本人所有・不要品であることを確認してください');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    if (!_prohibitedConfirmed) {
      AppToast.show(context, '禁止物ではないことを確認してください');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    if (!_validateListingContent(title, courseName)) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // Price Validation
    final price = int.tryParse(priceText) ?? 0;
    if (!_isFree) {
      if (price < 300 || price > 99999) {
        AppToast.show(context, '価格は300円〜99,999円の間で設定してください');
        setState(() {
          _isLoading = false;
        });
        return;
      }
    }

    if (_images.isEmpty ||
        title.isEmpty ||
        (_requiresRelatedCourse && courseName.isEmpty) ||
        (!_isFree && priceText.isEmpty)) {
      AppToast.show(context, '必須項目を入力してください（画像は少なくとも1枚必要です）');
      setState(() {
        _isLoading = false;
      });
      _log('validation failed');
      return;
    }

    if (_handoverType == '特定の曜日なら可' && _selectedHandoverDays.isEmpty) {
      AppToast.show(context, '手渡し可能な曜日を選択してください');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final universityId = userDoc.data()?['universityId'] as String? ?? '';

      List<String> finalImageUrls = [];

      // Process images in order
      for (final image in _images) {
        if (image.isFile) {
          // Upload new image
          final file = image.file!;
          _log('reading raw bytes from ${file.path}');
          final originalBytes = await file.readAsBytes();
          _log('raw size: ${originalBytes.lengthInBytes} bytes');

          final compressedBytes =
              await compute(_resizeAndCompressImage, originalBytes);
          _log('compressed size: ${compressedBytes.length} bytes');

          final fileName =
              'book_images/${user.uid}_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4()}.jpg';
          final imageRef = FirebaseStorage.instance.ref(fileName);

          _log('upload start: $fileName');
          await imageRef.putData(
            compressedBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          _log('upload complete');

          final url = await imageRef.getDownloadURL();
          finalImageUrls.add(url);
          _log('download URL ready: $url');
        } else {
          // Keep existing URL
          finalImageUrls.add(image.url!);
        }
      }

      final price = int.tryParse(priceText) ?? 0;
      final initialStatus = _isEditing ? widget.book?.status : 'available';
      final searchKeywords = _generateSearchKeywords(title);
      final feeRate = feeRateForListingType(_listingType);
      const buyerFee = 100;
      final includedItems = _parseIncludedItems(_includedItemsController.text);
      final handoverType = _handoverType == '特定の曜日なら可'
          ? _selectedHandoverDays.join('・')
          : _handoverType;

      final bookData = <String, Object?>{
        'title': title,
        'author': author,
        'courseName': courseName,
        'price': price,
        'listingType': _listingType,
        'category': _category,
        'condition': _condition,
        'conditionNote': _conditionNoteController.text.trim(),
        'hasWriting':
            _listingType == listingTypeBook ? _writingLevel != 'none' : null,
        'writingLevel': _listingType == listingTypeBook ? _writingLevel : null,
        'isWorkingConfirmed': _listingType == listingTypeAcademicSupply
            ? _isWorkingConfirmed
            : null,
        'includedItems': _listingType == listingTypeAcademicSupply
            ? includedItems
            : <String>[],
        'cautionNote': _cautionNoteController.text.trim(),
        'feeRate': feeRate,
        'buyerFee': buyerFee,
        'prohibitedCheckConfirmed': _prohibitedConfirmed,
        'ownershipCheckConfirmed': _ownershipConfirmed,
        'purchaseMode': purchaseModeInstant,
        if (!_isEditing) 'moderationStatus': 'active',
        'imageUrls': finalImageUrls,
        'userId': user.uid,
        'universityId': universityId,
        'searchKeywords': searchKeywords,
        'isbn': _isbnController.text.trim(),
        'handoverType': handoverType,
        if (initialStatus != null) 'status': initialStatus,
      };

      if (_isEditing) {
        bookData['updatedAt'] = FieldValue.serverTimestamp();
        final docRef =
            FirebaseFirestore.instance.collection('books').doc(widget.book!.id);

        _log('updating Firestore document ${widget.book!.id}');
        await docRef.update(bookData);
        _log('firestore update success: ${widget.book!.id}');

        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _images = finalImageUrls.map((url) => _BookImage(url: url)).toList();
        });
        // If editing, usually we are pushed, so popping is correct.
        // But let's be safe.
        Navigator.of(context).pop(
          Book(
            id: widget.book!.id,
            title: title,
            price: price,
            imageUrls: finalImageUrls,
            author: author,
            courseName: courseName,
            userId: user.uid,
            status: initialStatus,
            isbn: _isbnController.text.trim(),
            universityId: universityId,
            listingType: _listingType,
            category: _category,
            condition: _condition,
            conditionNote: _conditionNoteController.text.trim(),
            hasWriting: _listingType == listingTypeBook
                ? _writingLevel != 'none'
                : null,
            writingLevel:
                _listingType == listingTypeBook ? _writingLevel : null,
            isWorkingConfirmed: _listingType == listingTypeAcademicSupply
                ? _isWorkingConfirmed
                : null,
            includedItems: _listingType == listingTypeAcademicSupply
                ? includedItems
                : const [],
            cautionNote: _cautionNoteController.text.trim(),
            feeRate: feeRate,
            buyerFee: buyerFee,
            prohibitedCheckConfirmed: _prohibitedConfirmed,
            ownershipCheckConfirmed: _ownershipConfirmed,
            purchaseMode: purchaseModeInstant,
            createdAt: widget.book?.createdAt ?? DateTime.now(),
            updatedAt: DateTime.now(),
            handoverType: handoverType,
            likeCount: widget.book?.likeCount ?? 0,
            commentCount: widget.book?.commentCount ?? 0,
          ),
        );
      } else {
        bookData['createdAt'] = FieldValue.serverTimestamp();

        _log('writing Firestore document');
        final docRef =
            await FirebaseFirestore.instance.collection('books').add(bookData);
        _log('firestore write success: ${docRef.id}');

        final newBook = Book(
          id: docRef.id,
          title: title,
          price: price,
          imageUrls: finalImageUrls,
          author: author,
          courseName: courseName,
          userId: user.uid,
          status: initialStatus,
          isbn: _isbnController.text.trim(),
          universityId: universityId,
          listingType: _listingType,
          category: _category,
          condition: _condition,
          conditionNote: _conditionNoteController.text.trim(),
          hasWriting:
              _listingType == listingTypeBook ? _writingLevel != 'none' : null,
          writingLevel: _listingType == listingTypeBook ? _writingLevel : null,
          isWorkingConfirmed: _listingType == listingTypeAcademicSupply
              ? _isWorkingConfirmed
              : null,
          includedItems: _listingType == listingTypeAcademicSupply
              ? includedItems
              : const [],
          cautionNote: _cautionNoteController.text.trim(),
          feeRate: feeRate,
          buyerFee: buyerFee,
          prohibitedCheckConfirmed: _prohibitedConfirmed,
          ownershipCheckConfirmed: _ownershipConfirmed,
          purchaseMode: purchaseModeInstant,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          handoverType: handoverType,
          likeCount: 0,
          commentCount: 0,
        );

        if (!mounted) return;

        setState(() {
          _isLoading = false;
          _images.clear();
          _titleController.clear();
          _authorController.clear();
          _courseController.clear();
          _priceController.clear();
          _isbnController.clear();
          _conditionNoteController.clear();
          _includedItemsController.clear();
          _cautionNoteController.clear();
          _ownershipConfirmed = false;
          _prohibitedConfirmed = false;
        });
        _log('form reset completed');

        if (mounted) {
          AppToast.show(context, '出品しました');

          if (widget.onListingComplete != null) {
            _log('calling onListingComplete callback');
            widget.onListingComplete!();
          } else {
            _log('attempting to pop');
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop(newBook);
            } else {
              _log('cannot pop - stack empty?');
              // If we can't pop, we might want to redirect to home?
              // But this case should only happen if pushed.
            }
          }
        }
        _log('listing completed');
        _log('link syllabus screen pushed');
      }
    } catch (e, stackTrace) {
      debugPrint('[AddBook] error: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      final message = e is FirebaseException && e.message != null
          ? e.message!
          : e.toString();
      AppToast.show(context, 'エラーが発生しました: $message');
    }
  }

  bool _validateListingContent(String title, String courseName) {
    final prohibitedPattern = RegExp(r'(過去問|試験問題|解答|答え|レポート|宿題|出席|代行|卒論)');
    if (prohibitedPattern.hasMatch(title) ||
        prohibitedPattern.hasMatch(courseName)) {
      showDialog(
        context: context,
        builder: (context) => AppCustomDialog(
          title: '出品できません',
          message:
              '学習倫理に反する物品（過去問、完成済みレポート、出席代行など）は出品できません。\n\n大学の規則や学習倫理を遵守してください。',
          icon: Icons.error_outline,
          confirmText: '確認',
          confirmColor: Colors.red,
          onConfirm: () => Navigator.of(context).pop(),
        ),
      );
      return false;
    }
    return true;
  }

  InputDecoration _buildInputDecoration({
    required String label,
    required String hint,
    String? helperText,
    Widget? suffix,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      suffixIcon: suffix,
      prefixIcon:
          prefixIcon != null ? Icon(prefixIcon, color: Colors.grey) : null,
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _buildListingTypeSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: listingTypeBook,
          label: Text('本・教材'),
          icon: Icon(Icons.menu_book_outlined),
        ),
        ButtonSegment(
          value: listingTypeAcademicSupply,
          label: Text('授業用品'),
          icon: Icon(Icons.science_outlined),
        ),
      ],
      selected: {_listingType},
      onSelectionChanged: (values) => _setListingType(values.first),
    );
  }

  Widget _buildFeeHint() {
    final percent = (feeRateForListingType(_listingType) * 100).round();
    final label = listingTypeLabels[_listingType] ?? 'このカテゴリ';
    return InformationCard(
      title: '$labelの手数料',
      message: '$labelカテゴリは販売手数料$percent%。手渡しだから送料もかかりません。',
      icon: Icons.payments_outlined,
    );
  }

  Widget _buildIsbnQuickFillCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.qr_code_scanner,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'バーコードでかんたん出品',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'ISBNを読み取ると、タイトル・著者・表紙候補を自動入力します。',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _isbnController,
            keyboardType: TextInputType.number,
            decoration: _buildInputDecoration(
              label: 'ISBN',
              hint: '978...',
              prefixIcon: Icons.menu_book_outlined,
              suffix: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'バーコードを読み取る',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _isLoading || _isFetchingIsbn ? null : _scanIsbn,
                  ),
                  IconButton(
                    tooltip: 'ISBNから書誌情報を反映',
                    icon: _isFetchingIsbn
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    onPressed:
                        _isLoading || _isFetchingIsbn ? null : _fetchBookInfo,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseSelector() {
    if (!_requiresRelatedCourse) return const SizedBox.shrink();
    final selectedCourse = _courseController.text.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selectedCourse.isEmpty
              ? Colors.transparent
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school_outlined, color: Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  selectedCourse.isEmpty ? '関連授業を選択（必須）' : selectedCourse,
                  style: TextStyle(
                    color: selectedCourse.isEmpty
                        ? Colors.grey.shade700
                        : Colors.black,
                    fontWeight: selectedCourse.isEmpty
                        ? FontWeight.w500
                        : FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (selectedCourse.isNotEmpty)
                IconButton(
                  tooltip: '選択を解除',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() => _courseController.clear());
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '自分の時間割、またはシラバス検索から授業を選びます。',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _showTimetableCoursePicker,
                icon: const Icon(Icons.calendar_view_week_outlined),
                label: const Text('時間割から選ぶ'),
              ),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _showSyllabusCoursePicker,
                icon: const Icon(Icons.search),
                label: const Text('シラバス検索'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showTimetableCoursePicker() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppToast.show(context, 'ログインが必要です');
      return;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('timetable')
        .get();
    if (!mounted) return;

    final classes = snapshot.docs
        .map(UserClass.fromFirestore)
        .where((userClass) => userClass.title.trim().isNotEmpty)
        .toList();

    if (classes.isEmpty) {
      AppToast.show(context, '時間割に登録された授業がありません');
      return;
    }

    final selected = await showModalBottomSheet<_CourseOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TimetableCoursePicker(classes: classes),
    );
    if (selected == null || !mounted) return;
    setState(() => _courseController.text = selected.title);
  }

  Future<void> _showSyllabusCoursePicker() async {
    final selected = await showModalBottomSheet<_CourseOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _SyllabusCoursePicker(),
    );
    if (selected == null || !mounted) return;
    setState(() => _courseController.text = selected.title);
  }

  Widget _buildConditionFields() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _condition,
          decoration: _buildInputDecoration(
            label: '状態（必須）',
            hint: '選択してください',
            prefixIcon: Icons.verified_outlined,
          ),
          items: conditionLabels.entries.map((entry) {
            return DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _condition = value;
            });
          },
        ),
        const SizedBox(height: 16),
        if (_listingType == listingTypeBook) ...[
          DropdownButtonFormField<String>(
            initialValue: _writingLevel,
            decoration: _buildInputDecoration(
              label: '書き込みの有無（必須）',
              hint: '選択してください',
              prefixIcon: Icons.edit_note_outlined,
            ),
            items: writingLevelLabels.entries.map((entry) {
              return DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _writingLevel = value;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        if (_listingType == listingTypeAcademicSupply) ...[
          CheckboxListTile(
            value: _isWorkingConfirmed,
            onChanged: (value) {
              setState(() {
                _isWorkingConfirmed = value ?? false;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('使用できることを確認しました（必須）'),
            subtitle: const Text('電卓・実験用品などは、動作や欠品を確認してから出品してください。'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _includedItemsController,
            decoration: _buildInputDecoration(
              label: '付属品（必須）',
              hint: '例: ケース、説明書、替え芯',
              prefixIcon: Icons.inventory_2_outlined,
            ),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _conditionNoteController,
          decoration: _buildInputDecoration(
            label: '状態の詳細（任意）',
            hint: _listingType == listingTypeBook
                ? '例: 表紙に少し折れあり'
                : '例: 使用感あり、動作確認済み',
            prefixIcon: Icons.notes_outlined,
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cautionNoteController,
          decoration: _buildInputDecoration(
            label: '注意事項（任意）',
            hint: '購入前に伝えておきたいこと',
            prefixIcon: Icons.info_outline,
          ),
          maxLines: 2,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBarTitle = _isEditing ? '出品内容を編集' : '出品';
    final submitLabel = _isEditing ? '変更する' : '出品する';
    final missingRequirements =
        _missingSubmitRequirements.where((item) => item != '処理中').toList();

    final canPop = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          appBarTitle,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image Picker Section
                  Container(
                    height: 200,
                    color: Colors.grey.shade200,
                    child: ReorderableListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(8),
                      onReorder: (int oldIndex, int newIndex) {
                        setState(() {
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          final item = _images.removeAt(oldIndex);
                          _images.insert(newIndex, item);
                        });
                      },
                      header: GestureDetector(
                        onTap: _isLoading ? null : _pickImage,
                        child: Container(
                          width: 150,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo_outlined,
                                size: 40,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '写真を追加',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '(${_images.length}/10)',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      children: _images.asMap().entries.map((entry) {
                        final index = entry.key;
                        final image = entry.value;
                        final isThumbnail = index == 0;

                        return Container(
                          key: ValueKey(image),
                          width: 150,
                          margin: const EdgeInsets.only(right: 8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  image: DecorationImage(
                                    image: image.isFile
                                        ? FileImage(image.file!)
                                            as ImageProvider
                                        : NetworkImage(image.url!),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              if (isThumbnail)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(8),
                                        bottomRight: Radius.circular(8),
                                      ),
                                    ),
                                    child: const Text(
                                      'サムネイル',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removeImage(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // Form Fields
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '商品情報',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _listingType == listingTypeBook
                              ? '写真・タイトル・関連授業・カテゴリ・状態・価格・受け渡し目安は必須です。'
                              : '写真・商品名・カテゴリ・状態・価格・受け渡し目安は必須です。授業用品は関連授業の選択なしで出品できます。',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _FormGroupLabel('出品タイプ'),
                        const SizedBox(height: 10),
                        _buildListingTypeSelector(),
                        const SizedBox(height: 12),
                        _buildFeeHint(),
                        const SizedBox(height: 24),
                        if (_listingType == listingTypeBook) ...[
                          _buildIsbnQuickFillCard(),
                          const SizedBox(height: 24),
                        ],
                        const _FormGroupLabel('必須項目'),
                        const SizedBox(height: 10),
                        if (_listingType == listingTypeBook) ...[
                          _buildCourseSelector(),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: _titleController,
                          decoration: _buildInputDecoration(
                            label: _listingType == listingTypeBook
                                ? 'タイトル（必須）'
                                : '商品名（必須）',
                            hint: _listingType == listingTypeBook
                                ? '例: 線形代数入門'
                                : '例: 関数電卓',
                            prefixIcon: Icons.title,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _authorController,
                          decoration: _buildInputDecoration(
                            label: _listingType == listingTypeBook
                                ? '著者（任意）'
                                : '型番・メーカー（任意）',
                            hint: _listingType == listingTypeBook
                                ? '例: 山田太郎'
                                : '例: fx-JP900',
                            prefixIcon: Icons.person_outline,
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          key: ValueKey('category_$_listingType'),
                          initialValue: _category,
                          decoration: _buildInputDecoration(
                            label: 'カテゴリ（必須）',
                            hint: '選択してください',
                            prefixIcon: Icons.category_outlined,
                          ),
                          items: allowedCategoriesForListingType(_listingType)
                              .map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _category = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildConditionFields(),
                        const SizedBox(height: 12),
                        const InformationCard(
                          title: '出品できるもの',
                          message: prohibitedListingNotice,
                          icon: Icons.rule_outlined,
                        ),
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: SwitchListTile(
                            title: const Text(
                              '0円で譲る',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              '購入者はシステム手数料（¥100）のみ支払います',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            value: _isFree,
                            activeThumbColor:
                                Theme.of(context).colorScheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _isFree = value;
                                if (_isFree) {
                                  _priceController.text = '0';
                                } else {
                                  _priceController.clear();
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          enabled: !_isFree,
                          validator: (value) {
                            if (_isFree) return null;
                            if (value == null || value.isEmpty) {
                              return '価格を入力してください';
                            }
                            final price = int.tryParse(value);
                            if (price == null) return '有効な数値を入力してください';
                            if (price < 300 || price > 99999) {
                              return '価格は300円〜99,999円の間で設定してください';
                            }
                            return null;
                          },
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          decoration: _buildInputDecoration(
                            label: '価格（必須）',
                            hint: '例: 1500',
                            helperText: '※通常出品は300円〜99,999円',
                            prefixIcon: Icons.currency_yen,
                          ).copyWith(
                            fillColor: _isFree
                                ? Colors.grey.shade100
                                : Colors.grey.shade100,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const InformationCard(
                          title: '受け渡しについて',
                          message: handoverSafetyNotice,
                          icon: Icons.place_outlined,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _handoverType,
                          decoration: _buildInputDecoration(
                            label: '受け渡し相談の目安（必須）',
                            hint: '選択してください',
                            prefixIcon: Icons.schedule,
                          ),
                          items: _handoverTypes.map((type) {
                            return DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _handoverType = value;
                              });
                            }
                          },
                        ),
                        if (_handoverType == '特定の曜日なら可') ...[
                          const SizedBox(height: 16),
                          const Text(
                            '手渡し可能な曜日を選択',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children:
                                ['月', '火', '水', '木', '金', '土', '日'].map((day) {
                              final isSelected =
                                  _selectedHandoverDays.contains(day);
                              return FilterChip(
                                label: Text(day),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedHandoverDays.add(day);
                                    } else {
                                      _selectedHandoverDays.remove(day);
                                    }
                                    // Sort based on week order
                                    final weekOrder = [
                                      '月',
                                      '火',
                                      '水',
                                      '木',
                                      '金',
                                      '土',
                                      '日'
                                    ];
                                    _selectedHandoverDays.sort((a, b) =>
                                        weekOrder.indexOf(a) -
                                        weekOrder.indexOf(b));
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 20),
                        CheckboxListTile(
                          value: _ownershipConfirmed,
                          onChanged: (value) {
                            setState(() {
                              _ownershipConfirmed = value ?? false;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            listingOwnershipNotice,
                            style: TextStyle(fontSize: 13, height: 1.45),
                          ),
                        ),
                        CheckboxListTile(
                          value: _prohibitedConfirmed,
                          onChanged: (value) {
                            setState(() {
                              _prohibitedConfirmed = value ?? false;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'この商品はTekipaで出品できるカテゴリに該当し、禁止物ではないことを確認しました。',
                            style: TextStyle(fontSize: 13, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '出品することで、利用規約に同意したものとみなされます。',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 100), // Space for bottom bar
                ],
              ),
            ),
          ),

          // Fixed Bottom Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (missingRequirements.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '未入力: ${missingRequirements.join('、')}',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canSubmit ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade600,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              submitLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormGroupLabel extends StatelessWidget {
  const _FormGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _CourseOption {
  const _CourseOption({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
}

class _TimetableCoursePicker extends StatefulWidget {
  const _TimetableCoursePicker({required this.classes});

  final List<UserClass> classes;

  @override
  State<_TimetableCoursePicker> createState() => _TimetableCoursePickerState();
}

class _TimetableCoursePickerState extends State<_TimetableCoursePicker> {
  late int _selectedYear;
  String _selectedSemester = 'all';

  @override
  void initState() {
    super.initState();
    final currentYear = TimetableService().currentAcademicYear();
    final years = widget.classes.map((userClass) => userClass.year).toSet();
    _selectedYear = years.contains(currentYear)
        ? currentYear
        : (years.toList()..sort()).last;
  }

  List<int> get _years {
    final years = widget.classes.map((userClass) => userClass.year).toSet();
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  List<String> get _semesters {
    final values = widget.classes
        .where((userClass) => userClass.year == _selectedYear)
        .map((userClass) => userClass.semester)
        .where((semester) => semester.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['all', ...values];
  }

  List<_CourseOption> get _options {
    final seen = <String>{};
    final classes = widget.classes.where((userClass) {
      if (userClass.year != _selectedYear) return false;
      if (_selectedSemester != 'all' &&
          userClass.semester != _selectedSemester) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final dayCompare = _dayOrder(a.day).compareTo(_dayOrder(b.day));
        if (dayCompare != 0) return dayCompare;
        final periodCompare = a.period.compareTo(b.period);
        if (periodCompare != 0) return periodCompare;
        return a.title.compareTo(b.title);
      });

    final options = <_CourseOption>[];
    for (final userClass in classes) {
      final key =
          '${userClass.year}|${userClass.semester}|${userClass.title}|${userClass.teacher}';
      if (!seen.add(key)) continue;
      final parts = <String>[
        '${userClass.year}年度',
        _semesterLabel(userClass.semester),
        _slotLabel(userClass.day, userClass.period),
        if (userClass.teacher.trim().isNotEmpty) userClass.teacher.trim(),
      ];
      options.add(_CourseOption(
        title: userClass.title,
        subtitle: parts.join(' / '),
      ));
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final semesters = _semesters;
    if (!semesters.contains(_selectedSemester)) {
      _selectedSemester = 'all';
    }
    final options = _options;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.86,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '時間割から関連授業を選択',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _selectedYear,
                      decoration: const InputDecoration(
                        labelText: '年度',
                        border: OutlineInputBorder(),
                      ),
                      items: _years
                          .map((year) => DropdownMenuItem(
                                value: year,
                                child: Text('$year年度'),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedYear = value;
                          _selectedSemester = 'all';
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedSemester,
                      decoration: const InputDecoration(
                        labelText: '学期',
                        border: OutlineInputBorder(),
                      ),
                      items: semesters
                          .map((semester) => DropdownMenuItem(
                                value: semester,
                                child: Text(semester == 'all'
                                    ? 'すべて'
                                    : _semesterLabel(semester)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedSemester = value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: options.isEmpty
                    ? const Center(child: Text('この条件の授業はありません'))
                    : ListView.separated(
                        itemCount: options.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final option = options[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              option.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(option.subtitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).pop(option),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyllabusCoursePicker extends StatefulWidget {
  const _SyllabusCoursePicker();

  @override
  State<_SyllabusCoursePicker> createState() => _SyllabusCoursePickerState();
}

class _SyllabusCoursePickerState extends State<_SyllabusCoursePicker> {
  final _searchController = TextEditingController();
  final _syllabusService = SyllabusService();
  late int _selectedYear;
  bool _isSearching = false;
  bool _hasSearched = false;
  List<Syllabus> _results = [];

  @override
  void initState() {
    super.initState();
    _selectedYear = TimetableService().currentAcademicYear();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<int> get _yearOptions {
    final current = TimetableService().currentAcademicYear();
    return [current + 1, current, current - 1, current - 2];
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      AppToast.show(context, '授業名または教員名を入力してください');
      return;
    }
    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });
    try {
      final results = await _syllabusService.searchSyllabusByText(
        query,
        year: _selectedYear,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      AppToast.show(context, '検索に失敗しました: $e');
    }
  }

  String _syllabusSubtitle(Syllabus syllabus) {
    final slots = _syllabusService.getAddSlots(
      syllabus,
      targetYear: _selectedYear,
    );
    final schedule = slots.map((slot) => _slotLabel(slot.day, slot.period));
    final parts = <String>[
      if (schedule.isNotEmpty)
        slots.length == 1 ? schedule.first : '複数コマ: ${schedule.join('・')}',
      if (syllabus.teacher.trim().isNotEmpty) syllabus.teacher.trim(),
    ];
    return parts.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'シラバスから関連授業を選択',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 126,
                    child: DropdownButtonFormField<int>(
                      initialValue: _selectedYear,
                      decoration: const InputDecoration(
                        labelText: '年度',
                        border: OutlineInputBorder(),
                      ),
                      items: _yearOptions
                          .map((year) => DropdownMenuItem(
                                value: year,
                                child: Text('$year'),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedYear = value;
                          _results = [];
                          _hasSearched = false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: '授業名・教員名',
                        hintText: '例: 線形代数',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSearching ? null : _search,
                  icon: _isSearching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text('検索'),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? Center(
                            child: Text(
                              _hasSearched
                                  ? '授業が見つかりませんでした'
                                  : '授業名や教員名で検索してください',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _results.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final syllabus = _results[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  syllabus.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(_syllabusSubtitle(syllabus)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).pop(
                                  _CourseOption(
                                    title: syllabus.title,
                                    subtitle: _syllabusSubtitle(syllabus),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int _dayOrder(String day) {
  const order = {
    'Mon': 1,
    'Tue': 2,
    'Wed': 3,
    'Thu': 4,
    'Fri': 5,
    'Sat': 6,
    'Sun': 7,
  };
  return order[day] ?? 99;
}

String _dayLabel(String day) {
  const labels = {
    'Mon': '月',
    'Tue': '火',
    'Wed': '水',
    'Thu': '木',
    'Fri': '金',
    'Sat': '土',
    'Sun': '日',
  };
  return labels[day] ?? day;
}

String _slotLabel(String day, int period) {
  if (day.isEmpty || period <= 0) return '';
  return '${_dayLabel(day)}$period';
}

String _semesterLabel(String semester) {
  const labels = {
    '1': '前期',
    '2': '後期',
    'spring': '前期',
    'summer': '前期',
    'fall': '後期',
    'winter': '後期',
    'spring_group': '前期',
    'fall_group': '後期',
    '1q': '1ターム',
    '2q': '2ターム',
    '3q': '3ターム',
    '4q': '4ターム',
    'year_round': '通年',
    'intensive': '集中',
    '0': '集中/その他',
  };
  return labels[semester] ?? semester;
}

void _log(String message) {
  if (kDebugMode) {
    debugPrint('[AddBook] $message');
  }
}

Uint8List _resizeAndCompressImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('画像データの読み込みに失敗しました');
  }

  final resized =
      decoded.width > 1080 ? img.copyResize(decoded, width: 1080) : decoded;

  return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
}

class _IsbnScannerPage extends StatefulWidget {
  const _IsbnScannerPage();

  @override
  State<_IsbnScannerPage> createState() => _IsbnScannerPageState();
}

class _IsbnScannerPageState extends State<_IsbnScannerPage> {
  bool _isDone = false;

  void _handleBarcodes(BarcodeCapture capture) {
    if (_isDone) return;
    if (capture.barcodes.isEmpty) return;

    final raw = capture.barcodes.first.rawValue ?? '';
    final digits = raw.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (digits.length != 13 && digits.length != 10) return;

    _isDone = true;
    Navigator.of(context).pop(digits.toUpperCase());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ISBNスキャン'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: MobileScannerController(
              facing: CameraFacing.back,
              detectionSpeed: DetectionSpeed.normal,
              formats: const [
                BarcodeFormat.ean13,
                BarcodeFormat.ean8,
                BarcodeFormat.upcA,
                BarcodeFormat.upcE,
              ],
            ),
            onDetect: _handleBarcodes,
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'バーコードを枠内に合わせてください',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 220,
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.red.withValues(alpha: 0.8), width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
