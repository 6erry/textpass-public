import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/book.dart';
import '../models/comment.dart';
import '../models/syllabus.dart';
import '../models/user_class.dart';
import '../services/report_service.dart';
import '../services/share_service.dart';
import '../services/user_service.dart';
import '../utils/legal_notices.dart';
import '../widgets/app_custom_dialog.dart';
import '../widgets/app_custom_input_dialog.dart';
import '../widgets/full_screen_image_gallery.dart';
import 'add_book_screen.dart';
import 'class_detail_screen.dart';
// import 'comment_list_screen.dart'; // No longer needed if full inline
import 'payment_screen.dart';
import 'bundle_request_screen.dart';
import 'transaction_screen.dart';
import 'user_profile_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class BookDetailScreen extends StatefulWidget {
  const BookDetailScreen({
    super.key,
    required this.book,
    this.bundleSelectionMode = false,
    this.isSelectedForBundle = false,
    this.onBundleSelectionChanged,
  });

  final Book book;
  final bool bundleSelectionMode;
  final bool isSelectedForBundle;
  final ValueChanged<bool>? onBundleSelectionChanged;

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  bool _isDeleting = false;
  bool _isFavorite = false;
  bool _isUpdatingFavorite = false;
  bool _isSoldLocally = false;
  bool _isReporting = false;
  bool _isBlocking = false;
  late bool _isSelectedForBundle;
  int _currentImageIndex = 0;
  final _commentController = TextEditingController(); // Added
  bool _isSendingComment = false; // Added

  bool get _isOwner {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.uid == widget.book.userId;
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _isSoldLocally = widget.book.status == 'sold';
    _isSelectedForBundle = widget.isSelectedForBundle;
    _loadFavoriteStatus();
  }

  Future<void> _postComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppToast.show(context, 'コメントするにはログインが必要です');
      return;
    }

    setState(() {
      _isSendingComment = true;
    });

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data();
      final userName = userData?['displayName'] as String? ?? '名無しユーザー';
      final photoUrl = userData?['photoURL'] as String?;

      final commentData = {
        'userId': user.uid,
        'userName': userName,
        'userPhotoUrl': photoUrl,
        'content': content,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final bookRef =
            FirebaseFirestore.instance.collection('books').doc(widget.book.id);
        final commentsRef = bookRef.collection('comments').doc();

        transaction.set(commentsRef, commentData);
        transaction.update(bookRef, {
          'commentCount': FieldValue.increment(1),
        });
      });

      _commentController.clear();
      if (!mounted) return;
      AppToast.show(context, 'コメントを投稿しました');
      // Close keyboard
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'コメントの送信に失敗しました: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingComment = false;
        });
      }
    }
  }

  List<String> _universityAliases(String universityId) {
    if (universityId == 'hokudai' || universityId == 'hokudai.ac.jp') {
      return const ['hokudai.ac.jp', 'hokudai'];
    }
    return [universityId];
  }

  Future<Syllabus?> _findSyllabusForBook(Book book) async {
    final title = book.courseName.trim();
    if (title.isEmpty) return null;

    for (final universityId in _universityAliases(book.universityId)) {
      final snapshot = await FirebaseFirestore.instance
          .collection('syllabus_master')
          .where('universityId', isEqualTo: universityId)
          .where('title', isEqualTo: title)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        return Syllabus.fromFirestore(snapshot.docs.first);
      }
    }
    return null;
  }

  Future<void> _openCourseDetail(Book book) async {
    final courseName = book.courseName.trim();
    if (courseName.isEmpty) return;

    Syllabus? syllabus;
    try {
      syllabus = await _findSyllabusForBook(book);
    } catch (e) {
      debugPrint('Failed to load syllabus for book: $e');
    }
    if (!mounted) return;

    final userClass = UserClass(
      id: 'preview',
      title: courseName,
      teacher: syllabus?.teacher ?? '',
      room: syllabus?.classroom ?? '',
      day: syllabus?.day ?? '',
      period: (syllabus?.period ?? 0) > 0 ? syllabus!.period : 1,
      colorValue: Colors.blue.shade100.toARGB32(),
      textbook: syllabus?.textbook ?? '',
      isNotificationEnabled: false,
      semester: syllabus?.semester ?? '',
      year: syllabus?.year ?? DateTime.now().year,
      classKey: syllabus?.classKey,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ClassDetailScreen(
          userClass: userClass,
          previewSyllabus: syllabus,
        ),
      ),
    );
  }

  void _openFullScreenGallery(int index, List<String> images) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImageGallery(
          imageUrls: images,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final currencyFormatter =
        NumberFormat.currency(locale: 'ja_JP', symbol: '¥');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('books')
          .doc(widget.book.id)
          .snapshots(),
      builder: (context, snapshot) {
        final bookData = snapshot.data?.data();
        final currentBook =
            bookData != null ? Book.fromFirestore(snapshot.data!) : widget.book;

        final currentStatus =
            bookData?['status'] as String? ?? widget.book.status;
        final isSold = currentStatus == 'sold' ||
            currentStatus == 'trading' ||
            _isSoldLocally;

        final imageUrls =
            currentBook.imageUrls.isNotEmpty ? currentBook.imageUrls : [''];

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined, color: Colors.black),
                onPressed: () {
                  ShareService().shareBook(currentBook);
                },
              ),
              if (_isOwner)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.black),
                  onSelected: (value) {
                    if (value == 'edit') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AddBookScreen(book: currentBook),
                        ),
                      );
                    } else if (value == 'delete') {
                      _confirmAndDelete();
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('編集する'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('削除する', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              if (!_isOwner)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.black),
                  onSelected: (value) {
                    if (value == 'report') {
                      _showReportDialog();
                    } else if (value == 'block') {
                      _confirmBlock();
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'report',
                      child: Text('通報する', style: TextStyle(color: Colors.red)),
                    ),
                    const PopupMenuItem<String>(
                      value: 'block',
                      child: Text('この出品者をブロック'),
                    ),
                  ],
                ),
            ],
          ),
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImageSection(imageUrls, currentBook),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            currentBook.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 8),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                currentBook.price == 0
                                    ? '0円'
                                    : currencyFormatter
                                        .format(currentBook.price),
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: _isUpdatingFavorite
                                        ? null
                                        : _toggleFavorite,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _isFavorite
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                            color: _isFavorite
                                                ? Colors.red
                                                : Colors.grey,
                                            size: 28,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${widget.book.likeCount + (_isFavorite ? 1 : 0)}',
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black54),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  InkWell(
                                    onTap: () {},
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.chat_bubble_outline,
                                              color: Colors.grey, size: 26),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${currentBook.commentCount}',
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black54),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  listingTypeLabels[currentBook.listingType] ??
                                      '本・教材',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.red.withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  currentBook.category,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color:
                                          Colors.blue.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.handshake,
                                        size: 16, color: Colors.blue),
                                    const SizedBox(width: 4),
                                    Text(
                                      currentBook.handoverType,
                                      style: const TextStyle(
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.access_time,
                                        size: 16, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      timeago.format(currentBook.createdAt,
                                          locale: 'ja'),
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const InformationCard(
                            title: '受け渡しについて',
                            message: handoverSafetyNotice,
                            icon: Icons.place_outlined,
                          ),

                          const Divider(height: 32),

                          Text(
                            '商品の説明',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _ProductInfoCard(
                            children: [
                              if (currentBook.courseName.trim().isNotEmpty)
                                _ProductInfoRow(
                                  icon: Icons.school_outlined,
                                  label: '講義名',
                                  value: currentBook.courseName,
                                  tappable: true,
                                  onTap: () => _openCourseDetail(currentBook),
                                ),
                              if (currentBook.author.trim().isNotEmpty)
                                _ProductInfoRow(
                                  icon:
                                      currentBook.listingType == listingTypeBook
                                          ? Icons.person_outline
                                          : Icons.tag_outlined,
                                  label:
                                      currentBook.listingType == listingTypeBook
                                          ? '著者'
                                          : '型番・メーカー',
                                  value: currentBook.author,
                                ),
                              _ProductInfoRow(
                                icon: Icons.verified_outlined,
                                label: '状態',
                                value: conditionLabels[currentBook.condition] ??
                                    '目立った傷や汚れなし',
                              ),
                              if (currentBook.listingType == listingTypeBook &&
                                  currentBook.writingLevel != null)
                                _ProductInfoRow(
                                  icon: Icons.edit_note_outlined,
                                  label: '書き込み',
                                  value: writingLevelLabels[
                                          currentBook.writingLevel] ??
                                      '未設定',
                                ),
                              if (currentBook.listingType ==
                                      listingTypeAcademicSupply &&
                                  (currentBook.includedItems?.isNotEmpty ??
                                      false))
                                _ProductInfoRow(
                                  icon: Icons.inventory_2_outlined,
                                  label: '付属品',
                                  value: currentBook.includedItems!.join('、'),
                                ),
                              if ((currentBook.conditionNote ?? '')
                                  .trim()
                                  .isNotEmpty)
                                _ProductInfoRow(
                                  icon: Icons.notes_outlined,
                                  label: '状態メモ',
                                  value: currentBook.conditionNote!.trim(),
                                ),
                              if ((currentBook.cautionNote ?? '')
                                  .trim()
                                  .isNotEmpty)
                                _ProductInfoRow(
                                  icon: Icons.info_outline,
                                  label: '注意事項',
                                  value: currentBook.cautionNote!.trim(),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          const Divider(height: 32),

                          Text(
                            '出品者',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserProfileScreen(
                                      userId: currentBook.userId),
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.grey.shade200,
                                  child: const Icon(Icons.person,
                                      color: Colors.grey),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FutureBuilder<
                                      DocumentSnapshot<Map<String, dynamic>>>(
                                    future: FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(currentBook.userId)
                                        .get(),
                                    builder: (context, snapshot) {
                                      final userData =
                                          snapshot.data?.data() ?? {};
                                      final name =
                                          userData['displayName'] as String? ??
                                              'ユーザー';
                                      final transactionCount =
                                          (userData['transactionCount'] as num?)
                                                  ?.toInt() ??
                                              0;
                                      final averageRating =
                                          (userData['averageRating'] as num?)
                                              ?.toDouble();
                                      final verified = userData[
                                                  'isStudentVerified'] ==
                                              true ||
                                          userData['isContactEmailVerified'] ==
                                              true;
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: theme.textTheme.bodyLarge
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              if (verified)
                                                const _MiniTrustChip(
                                                  label: '大学メール認証済み',
                                                ),
                                              _MiniTrustChip(
                                                label:
                                                    '取引完了 $transactionCount件',
                                              ),
                                              if (averageRating != null)
                                                _MiniTrustChip(
                                                  label:
                                                      '評価 ${averageRating.toStringAsFixed(1)}',
                                                ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                const Icon(Icons.chevron_right,
                                    color: Colors.grey),
                              ],
                            ),
                          ),

                          const Divider(height: 32),

                          if (_isOwner &&
                              currentBook.purchaseMode ==
                                  purchaseModeApprovalRequired) ...[
                            _buildPurchaseRequestList(currentBook),
                            const Divider(height: 32),
                          ],

                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.chat_bubble_outline,
                                        size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'コメント (${currentBook.commentCount})',
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('books')
                                      .doc(widget.book.id)
                                      .collection('comments')
                                      .orderBy('createdAt', descending: false)
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                          child: CircularProgressIndicator());
                                    }

                                    final docs = snapshot.data?.docs ?? [];

                                    if (docs.isEmpty) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: Center(
                                          child: Text(
                                            'まだコメントはありません',
                                            textAlign: TextAlign.center,
                                            style:
                                                TextStyle(color: Colors.grey),
                                          ),
                                        ),
                                      );
                                    }

                                    return Column(
                                      children: docs.map((doc) {
                                        final comment =
                                            Comment.fromFirestore(doc);
                                        final isMe = comment.userId ==
                                            FirebaseAuth
                                                .instance.currentUser?.uid;

                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 16),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              CircleAvatar(
                                                radius: 20,
                                                backgroundImage: comment
                                                            .userPhotoUrl !=
                                                        null
                                                    ? NetworkImage(
                                                        comment.userPhotoUrl!)
                                                    : null,
                                                child: comment.userPhotoUrl ==
                                                        null
                                                    ? const Icon(Icons.person,
                                                        color: Colors.grey)
                                                    : null,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          comment.userName,
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        Text(
                                                          timeago.format(
                                                              comment.createdAt,
                                                              locale: 'ja'),
                                                          style: TextStyle(
                                                              color: Colors.grey
                                                                  .shade600,
                                                              fontSize: 12),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      decoration: BoxDecoration(
                                                        color: isMe
                                                            ? Colors
                                                                .blue.shade50
                                                            : Colors
                                                                .grey.shade100,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      child: Text(
                                                        comment.content,
                                                        style: const TextStyle(
                                                            fontSize: 15),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _commentController,
                                        decoration: InputDecoration(
                                          hintText: 'コメントを入力',
                                          filled: true,
                                          fillColor: Colors.grey.shade100,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: BorderSide.none,
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 20, vertical: 10),
                                        ),
                                        minLines: 1,
                                        maxLines: 4,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: _isSendingComment
                                          ? null
                                          : _postComment,
                                      icon: _isSendingComment
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            )
                                          : Icon(Icons.send,
                                              color: Theme.of(context)
                                                  .primaryColor),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_isDeleting || _isReporting || _isBlocking)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
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
                    child: Row(
                      children: [
                        if (!_isOwner) ...[
                          Expanded(
                            child: FutureBuilder<String?>(
                              future: _checkExistingTransaction(user!.uid),
                              builder: (context, snapshot) {
                                final chatRoomId = snapshot.data;
                                final bool canNavigateToTransaction =
                                    !widget.bundleSelectionMode &&
                                        isSold &&
                                        chatRoomId != null;
                                final bool isSoldOutForOthers =
                                    isSold && chatRoomId == null;
                                final bool disablePrimary =
                                    isSoldOutForOthers &&
                                        !widget.bundleSelectionMode;

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: canNavigateToTransaction
                                            ? () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        TransactionScreen(
                                                      chatRoomId: chatRoomId,
                                                      book: currentBook,
                                                    ),
                                                  ),
                                                );
                                              }
                                            : (disablePrimary
                                                ? null
                                                : (widget.bundleSelectionMode
                                                    ? _toggleBundleSelection
                                                    : (currentBook
                                                                .purchaseMode ==
                                                            purchaseModeApprovalRequired
                                                        ? () =>
                                                            _showPurchaseRequestDialog(
                                                              currentBook,
                                                            )
                                                        : _navigateToPurchaseScreen))),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: disablePrimary
                                              ? Colors.grey
                                              : (canNavigateToTransaction
                                                  ? Colors.blue
                                                  : Colors.red),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          shadowColor: Colors.transparent,
                                        ),
                                        child: Text(
                                          canNavigateToTransaction
                                              ? '取引画面へ'
                                              : (disablePrimary
                                                  ? '売り切れ'
                                                  : (widget.bundleSelectionMode
                                                      ? (_isSelectedForBundle
                                                          ? 'まとめ買いから外す'
                                                          : 'まとめ買いに追加')
                                                      : (currentBook
                                                                  .purchaseMode ==
                                                              purchaseModeApprovalRequired
                                                          ? '購入申請を送る'
                                                          : '購入手続きへ'))),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (!widget.bundleSelectionMode &&
                                        !isSoldOutForOthers &&
                                        !canNavigateToTransaction) ...[
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: _navigateToBundleRequest,
                                          icon: const Icon(Icons.library_books),
                                          label: const Text('この出品者の商品をまとめて購入'),
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                        ] else if (!_isSoldLocally &&
                            currentStatus != 'sold' &&
                            currentStatus != 'trading') ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AddBookScreen(book: currentBook),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                side: const BorderSide(color: Colors.red),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                '商品を編集する',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPurchaseRequestList(Book book) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '購入申請',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('purchase_requests')
              .where('bookId', isEqualTo: book.id)
              .snapshots(),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            final pending = docs.where((doc) {
              if (doc.data()['sellerId'] != book.userId) return false;
              final status = doc.data()['status'] as String? ?? 'pending';
              return status == 'pending' || status == 'approved';
            }).toList();
            if (pending.isEmpty) {
              return Text(
                '現在、購入申請はありません。',
                style: TextStyle(color: Colors.grey.shade700),
              );
            }
            return Column(
              children: pending.map((doc) {
                final data = doc.data();
                final status = data['status'] as String? ?? 'pending';
                final message = data['message'] as String? ?? '';
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status == 'approved' ? '承認済みの申請' : '承認待ちの申請',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(message),
                      ],
                      if (status == 'pending') ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    _updatePurchaseRequest(doc.id, 'rejected'),
                                child: const Text('拒否'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () =>
                                    _updatePurchaseRequest(doc.id, 'approved'),
                                child: const Text('承認'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _updatePurchaseRequest(String requestId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('purchase_requests')
          .doc(requestId)
          .update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      AppToast.show(context, status == 'approved' ? '承認しました' : '拒否しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '更新に失敗しました: $e');
    }
  }

  Widget _buildImageSection(List<String> imageUrls, Book currentBook) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Hero(
        tag:
            imageUrls.isNotEmpty ? imageUrls[0] : 'book_card_${currentBook.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            height: 300,
            color: Colors.grey.shade100,
            child: Stack(
              children: [
                PageView.builder(
                  itemCount: imageUrls.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentImageIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final url = imageUrls[index].trim();
                    Widget imageWidget;
                    if (url.startsWith('http')) {
                      imageWidget = Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child: Icon(Icons.broken_image,
                              size: 64, color: Colors.grey),
                        ),
                      );
                    } else if (url.startsWith('file:')) {
                      imageWidget = Image.file(
                        File.fromUri(Uri.parse(url)),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child: Icon(Icons.broken_image,
                              size: 64, color: Colors.grey),
                        ),
                      );
                    } else {
                      imageWidget = Image.file(
                        File(url),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child: Icon(Icons.broken_image,
                              size: 64, color: Colors.grey),
                        ),
                      );
                    }

                    return GestureDetector(
                      onTap: () => _openFullScreenGallery(index, imageUrls),
                      child: imageWidget,
                    );
                  },
                ),
                if (imageUrls.length > 1)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentImageIndex + 1} / ${imageUrls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadFavoriteStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (!mounted || data == null) return;

      final favoriteBookIds =
          (data['favoriteBookIds'] as List<dynamic>? ?? const [])
              .map((id) => id.toString())
              .toList();

      setState(() {
        _isFavorite = favoriteBookIds.contains(widget.book.id);
      });
    } catch (_) {
      // Ignore errors
    }
  }

  Future<void> _toggleFavorite() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppToast.show(context, 'お気に入り機能を使うにはログインしてください');
      return;
    }

    setState(() {
      _isUpdatingFavorite = true;
    });

    try {
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      if (_isFavorite) {
        await userRef.update({
          'favoriteBookIds': FieldValue.arrayRemove([widget.book.id])
        });
      } else {
        await userRef.update({
          'favoriteBookIds': FieldValue.arrayUnion([widget.book.id])
        });
      }

      setState(() {
        _isFavorite = !_isFavorite;
      });
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'エラーが発生しました: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingFavorite = false;
        });
      }
    }
  }

  Future<void> _confirmAndDelete() async {
    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: '削除の確認',
        message: '本当に削除しますか？',
        icon: Icons.delete_forever,
        confirmText: '削除',
        confirmColor: Colors.red,
        onConfirm: () async {
          Navigator.of(context).pop();
          await _deleteBook();
        },
      ),
    );
  }

  Future<void> _showReportDialog() async {
    final reasons = [
      '禁止物の出品',
      '代理出品・転売の疑い',
      '不適切な内容',
      '大学公式と誤認させる表現',
      '迷惑行為',
      '詐欺・トラブル',
      'その他',
    ];

    final descriptionController = TextEditingController();
    String? selectedReason;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          return AppCustomInputDialog(
            title: '通報',
            icon: Icons.report_problem_outlined,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('通報の理由',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: reasons.map((r) {
                    return DropdownMenuItem(
                      value: r,
                      child: Text(r, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedReason = value);
                  },
                  hint: const Text('理由を選択してください'),
                ),
                const SizedBox(height: 16),
                const Text('詳細（任意）',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    hintText: '詳細を入力してください',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: selectedReason == null
                    ? null
                    : () async {
                        Navigator.pop(dialogContext);
                        final description = descriptionController.text;
                        setState(() {
                          _isReporting = true;
                        });

                        try {
                          await ReportService().submitReport(
                            type: 'listing',
                            reason: selectedReason!,
                            targetUserId: widget.book.userId,
                            targetBookId: widget.book.id,
                            description: description,
                          );

                          if (!mounted) return;
                          AppToast.show(context, '通報を受け付けました。確認します。');
                        } catch (e) {
                          if (!mounted) return;
                          AppToast.show(context, '通報に失敗しました: $e');
                        } finally {
                          if (mounted) {
                            setState(() {
                              _isReporting = false;
                            });
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('送信'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmBlock() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final hasActive =
        await UserService().hasActiveTransaction(widget.book.userId);
    if (hasActive) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AppCustomDialog(
          title: 'ブロックできません',
          message: '取引中のユーザーはブロックできません。\n取引を完了またはキャンセルしてからお試しください。',
          icon: Icons.error_outline,
          confirmText: 'OK',
          onConfirm: () => Navigator.pop(context),
        ),
      );
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AppCustomDialog(
        title: 'ブロックしますか？',
        message: 'この出品者の出品やチャットを非表示にします。',
        icon: Icons.block,
        confirmText: 'ブロック',
        confirmColor: Colors.red,
        onConfirm: () async {
          Navigator.pop(dialogContext);
          setState(() {
            _isBlocking = true;
          });

          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set(
              {
                'blockedUserIds': FieldValue.arrayUnion([widget.book.userId]),
              },
              SetOptions(merge: true),
            );
            if (!mounted) return;
            AppToast.show(context, 'ブロックしました。');
            if (mounted) {
              Navigator.of(context).pop();
            }
          } catch (e) {
            if (!mounted) return;
            AppToast.show(context, 'ブロックに失敗しました: $e');
          } finally {
            if (mounted) {
              setState(() {
                _isBlocking = false;
              });
            }
          }
        },
      ),
    );
  }

  void _navigateToPurchaseScreen() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppToast.show(context, '購入手続きを行うにはログインしてください。');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PurchaseScreen(book: widget.book),
      ),
    );
  }

  Future<void> _showPurchaseRequestDialog(Book book) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppToast.show(context, '購入申請にはログインが必要です。');
      return;
    }
    if (user.uid == book.userId) {
      AppToast.show(context, '自分の出品には購入申請できません。');
      return;
    }

    final existingRequest = await FirebaseFirestore.instance
        .collection('purchase_requests')
        .doc('${book.id}_${user.uid}')
        .get();
    final existingStatus = existingRequest.data()?['status'] as String?;
    if (existingStatus == 'approved') {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PurchaseScreen(book: book),
        ),
      );
      return;
    }
    if (existingStatus == 'pending') {
      if (!mounted) return;
      AppToast.show(context, '購入申請は送信済みです。出品者の承認をお待ちください。');
      return;
    }

    if (!mounted) return;
    final messageController = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => AppCustomInputDialog(
        title: '購入申請',
        icon: Icons.verified_user_outlined,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'この商品は出品者の承認後に購入できます。受け渡しの希望などがあれば添えて送れます。',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'メッセージ（任意）',
                hintText: '例: 購入希望です。よろしくお願いします。',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('閉じる'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('申請する'),
          ),
        ],
      ),
    );

    if (sent != true) return;

    try {
      final requestId = '${book.id}_${user.uid}';
      final now = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance
          .collection('purchase_requests')
          .doc(requestId)
          .set({
        'bookId': book.id,
        'buyerId': user.uid,
        'sellerId': book.userId,
        'message': messageController.text.trim(),
        'status': 'pending',
        'universityId': book.universityId,
        'createdAt': now,
        'updatedAt': now,
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 3)),
        ),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(book.userId)
          .collection('notifications')
          .add({
        'type': 'purchase_request',
        'title': '購入申請が届きました',
        'body': '${book.title}に購入申請があります',
        'relatedId': book.id,
        'fromUid': user.uid,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      AppToast.show(context, '購入申請を送信しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '購入申請の送信に失敗しました: $e');
    }
  }

  void _navigateToBundleRequest() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppToast.show(context, 'まとめ買い依頼にはログインが必要です。');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BundleRequestScreen(initialBook: widget.book),
      ),
    );
  }

  void _toggleBundleSelection() {
    final nextValue = !_isSelectedForBundle;
    setState(() {
      _isSelectedForBundle = nextValue;
    });
    widget.onBundleSelectionChanged?.call(nextValue);
    AppToast.show(context, nextValue ? 'まとめ買いに追加しました' : 'まとめ買いから外しました');
  }

  Future<String?> _checkExistingTransaction(String userId) async {
    if (widget.book.status != 'sold' && widget.book.status != 'trading') {
      return null;
    }

    try {
      final buyerQuery = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .where('bookId', isEqualTo: widget.book.id)
          .where('buyerId', isEqualTo: userId)
          .limit(1)
          .get();

      if (buyerQuery.docs.isNotEmpty) {
        return buyerQuery.docs.first.id;
      }

      if (widget.book.userId == userId) {
        final sellerQuery = await FirebaseFirestore.instance
            .collection('chat_rooms')
            .where('bookId', isEqualTo: widget.book.id)
            .where('sellerId', isEqualTo: userId)
            .limit(1)
            .get();

        if (sellerQuery.docs.isNotEmpty) {
          return sellerQuery.docs.first.id;
        }
      }
    } catch (e) {
      debugPrint('Error checking transaction: $e');
    }
    return null;
  }

  Future<void> _deleteBook() async {
    setState(() {
      _isDeleting = true;
    });

    try {
      // Delete all images
      for (final url in widget.book.imageUrls) {
        if (url.isNotEmpty) {
          try {
            final imageRef = FirebaseStorage.instance.refFromURL(url);
            await imageRef.delete();
          } catch (e) {
            debugPrint('Error deleting image $url: $e');
          }
        }
      }

      await FirebaseFirestore.instance
          .collection('books')
          .doc(widget.book.id)
          .delete();

      if (!mounted) return;

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
      });
      AppToast.show(context, '削除に失敗しました: $e');
    }
  }
}

class _ProductInfoCard extends StatelessWidget {
  const _ProductInfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, color: Colors.grey.shade200),
          ],
        ],
      ),
    );
  }
}

class _ProductInfoRow extends StatelessWidget {
  const _ProductInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.tappable = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool tappable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.45,
          fontWeight: FontWeight.w700,
          color: tappable ? primary : Colors.black87,
          decoration: tappable ? TextDecoration.underline : null,
          decorationColor: tappable ? primary : null,
        );

    return InkWell(
      onTap: tappable ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: tappable ? primary : Colors.grey),
            const SizedBox(width: 10),
            SizedBox(
              width: 86,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: valueStyle,
              ),
            ),
            if (tappable) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 20, color: primary),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniTrustChip extends StatelessWidget {
  const _MiniTrustChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
