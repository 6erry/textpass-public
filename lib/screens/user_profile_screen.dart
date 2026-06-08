import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/book.dart';
import 'book_detail_screen.dart';
import 'reviews_list_screen.dart';
import '../widgets/block_action_button.dart';
import 'package:textpass/utils/app_toast.dart';
import 'package:intl/intl.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _userFuture;
  late Future<QuerySnapshot<Map<String, dynamic>>> _reviewsFuture;
  bool _showOnlyOnSale = false;

  @override
  void initState() {
    super.initState();
    _userFuture =
        FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
    _reviewsFuture = FirebaseFirestore.instance
        .collection('reviews')
        .where('revieweeId', isEqualTo: widget.userId)
        .get();
  }

  Future<void> _openEditProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      AppToast.show(context, 'ログイン状態を確認してください。');
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data() ?? {};

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final displayName =
          user.displayName ?? data['displayName'] as String? ?? '';
      final photoUrl = user.photoURL ?? data['photoURL'] as String?;
      final bio = data['bio'] as String? ?? '';

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditProfileScreen(
            userId: user.uid,
            initialDisplayName: displayName,
            initialPhotoUrl: photoUrl,
            initialBio: bio,
          ),
        ),
      );
      setState(() {
        _userFuture = FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .get();
      });
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      AppToast.show(context, 'プロフィール情報の取得に失敗しました: $e');
    }
  }

  Widget _buildStatItem(String label, String value) {
    return Row(
      children: [
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isOwnProfile = currentUserId == widget.userId;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(
              isOwnProfile ? 'マイページ' : 'プロフィール',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
            pinned: true,
            actions: [
              if (!isOwnProfile) BlockActionButton(targetUserId: widget.userId),
            ],
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: _userFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final data = snapshot.data?.data() ?? {};
                final displayName = data['displayName'] as String? ?? 'ユーザー';
                final photoUrl = data['photoURL'] as String?;
                final bio = data['bio'] as String? ?? '';
                final isVerified = data['isStudentVerified'] == true ||
                    data['isContactEmailVerified'] == true ||
                    (data['email']?.toString().endsWith('.ac.jp') ?? false);
                final transactionCount =
                    (data['transactionCount'] as num?)?.toInt() ?? 0;
                final averageRating =
                    (data['averageRating'] as num?)?.toDouble();
                final positiveReviewRate =
                    (data['positiveReviewRate'] as num?)?.toDouble();

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: photoUrl != null
                                ? NetworkImage(photoUrl)
                                : null,
                            child: photoUrl == null
                                ? Icon(Icons.person,
                                    size: 36, color: Colors.grey.shade400)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if (isVerified)
                                      const _TrustBadge(
                                        icon: Icons.verified_user_outlined,
                                        label: '大学メール認証済み',
                                      ),
                                    _TrustBadge(
                                      icon: Icons.handshake_outlined,
                                      label: '取引完了 $transactionCount件',
                                    ),
                                    if (averageRating != null)
                                      _TrustBadge(
                                        icon: Icons.star_outline,
                                        label:
                                            '平均 ${averageRating.toStringAsFixed(1)}',
                                      ),
                                    if (positiveReviewRate != null)
                                      _TrustBadge(
                                        icon: Icons.thumb_up_alt_outlined,
                                        label:
                                            '良い評価 ${(positiveReviewRate * 100).round()}%',
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                FutureBuilder<
                                    QuerySnapshot<Map<String, dynamic>>>(
                                  future: _reviewsFuture,
                                  builder: (context, snapshot) {
                                    final docs = snapshot.data?.docs ?? [];
                                    final ratings = docs
                                        .map((d) =>
                                            (d.data()['rating'] as num?)
                                                ?.toDouble() ??
                                            0.0)
                                        .toList();
                                    final average = ratings.isEmpty
                                        ? 0.0
                                        : ratings.reduce((a, b) => a + b) /
                                            ratings.length;

                                    return InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ReviewsListScreen(
                                                userId: widget.userId),
                                          ),
                                        );
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: List.generate(5, (index) {
                                              return Icon(
                                                index < average.round()
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                color: Colors.amber,
                                                size: 16,
                                              );
                                            }),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            docs.length.toString(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isOwnProfile)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _openEditProfile,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              side: BorderSide(color: Colors.grey.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                            ),
                            child: const Text('プロフィールを編集',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      const SizedBox(height: 16),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('books')
                              .where('userId', isEqualTo: widget.userId)
                              .snapshots(),
                          builder: (context, bookSnapshot) {
                            final int listingCount =
                                bookSnapshot.data?.docs.length ?? 0;
                            return Row(
                              children: [
                                _buildStatItem('出品', listingCount.toString()),
                                const SizedBox(width: 16),
                                _buildStatItem('フォロワー', '0'),
                                const SizedBox(width: 16),
                                _buildStatItem('フォロー中', '0'),
                              ],
                            );
                          }),
                      const SizedBox(height: 16),
                      if (bio.isNotEmpty)
                        Text(
                          bio,
                          style: const TextStyle(
                              fontSize: 14, height: 1.5, color: Colors.black87),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              color: Colors.grey.shade100,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _showOnlyOnSale,
                      onChanged: (value) {
                        setState(() {
                          _showOnlyOnSale = value ?? false;
                        });
                      },
                      activeColor: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('販売中のみ表示',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.black54)),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 2)),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('books')
                .where('userId', isEqualTo: widget.userId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return const SliverToBoxAdapter(
                  child: Center(child: Text('出品情報の取得に失敗しました。')),
                );
              }

              var docs = snapshot.data?.docs ?? [];

              if (_showOnlyOnSale) {
                docs = docs.where((doc) {
                  final status = doc.data()['status'] as String?;
                  return status != 'sold' && status != 'trading';
                }).toList();
              }

              if (docs.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(
                      child: Text('出品中の商品はありません',
                          style: TextStyle(color: Colors.grey.shade500)),
                    ),
                  ),
                );
              }

              final books = docs.map((doc) => Book.fromFirestore(doc)).toList();

              return SliverPadding(
                padding: const EdgeInsets.all(2), // tight padding
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                    childAspectRatio:
                        1.0, // perfect square for modern profile grid
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return _ProfileBookThumbnail(book: books[index]);
                    },
                    childCount: books.length,
                  ),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.userId,
    required this.initialDisplayName,
    required this.initialBio,
    this.initialPhotoUrl,
  });

  final String userId;
  final String initialDisplayName;
  final String initialBio;
  final String? initialPhotoUrl;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  File? _imageFile;
  String? _photoUrl;
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _displayNameController =
        TextEditingController(text: widget.initialDisplayName);
    _bioController = TextEditingController(text: widget.initialBio);
    _photoUrl = widget.initialPhotoUrl;
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final data = snapshot.data();
      if (data != null) {
        final fetchedName = data['displayName'] as String?;
        final fetchedBio = data['bio'] as String?;
        final fetchedPhoto = data['photoURL'] as String?;
        if (fetchedName != null && fetchedName.isNotEmpty) {
          _displayNameController.text = fetchedName;
        }
        if (fetchedBio != null) {
          _bioController.text = fetchedBio;
        }
        setState(() {
          _photoUrl = fetchedPhoto ?? _photoUrl;
        });
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'プロフィール情報の取得に失敗しました: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() {
      _imageFile = File(pickedFile.path);
    });
  }

  Future<void> _saveChanges() async {
    final displayName = _displayNameController.text.trim();
    final bio = _bioController.text.trim();

    if (displayName.isEmpty) {
      AppToast.show(context, '表示名を入力してください。');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != widget.userId) {
      AppToast.show(context, 'ログイン状態を確認してください。');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      String? photoUrl = _photoUrl;
      if (_imageFile != null) {
        final ref =
            FirebaseStorage.instance.ref().child('profile_images').child(
                  '${widget.userId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
                );
        await ref.putFile(_imageFile!);
        photoUrl = await ref.getDownloadURL();
      }

      await user.updateDisplayName(displayName);
      if (photoUrl != null) {
        await user.updatePhotoURL(photoUrl);
      }
      await user.reload();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set(
        <String, dynamic>{
          'displayName': displayName,
          'bio': bio,
          if (photoUrl != null) 'photoURL': photoUrl,
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'プロフィールの更新に失敗しました: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider<Object>? avatarImage;
    if (_imageFile != null) {
      avatarImage = FileImage(_imageFile!);
    } else if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      avatarImage = NetworkImage(_photoUrl!);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('プロフィール編集',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _isSaving,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: avatarImage,
                            child: avatarImage == null
                                ? const Icon(Icons.person,
                                    size: 60, color: Colors.grey)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _isSaving ? null : _pickImage,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildTextField(
                      controller: _displayNameController,
                      label: '表示名',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      controller: _bioController,
                      label: '自己紹介',
                      icon: Icons.description_outlined,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                '保存する',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.grey),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _ProfileBookThumbnail extends StatelessWidget {
  final Book book;

  const _ProfileBookThumbnail({required this.book});

  @override
  Widget build(BuildContext context) {
    final NumberFormat currencyFormatter =
        NumberFormat.currency(locale: 'ja_JP', symbol: '¥');
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.grey.shade200,
            child: book.imageUrls.isNotEmpty
                ? Image.network(book.imageUrls.first, fit: BoxFit.cover)
                : const Icon(Icons.book, color: Colors.grey),
          ),
          if (book.status == 'sold')
            Positioned(
              top: 0,
              left: 0,
              child: CustomPaint(
                painter: _SoldBadgePainter(),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Align(
                    alignment: const Alignment(-0.5, -0.5),
                    child: Transform.rotate(
                      angle: -0.785398, // -45 degrees in radians
                      child: const Text(
                        'SOLD',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius:
                    const BorderRadius.only(topRight: Radius.circular(8)),
              ),
              child: Text(
                currencyFormatter.format(book.price),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          // Like (Heart) Icon Overlay
          const Positioned(
            top: 4,
            right: 4,
            child: Icon(
              Icons.favorite_border,
              color: Colors.white,
              size: 20,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoldBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
