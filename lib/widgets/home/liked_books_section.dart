import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/book.dart';
import '../../screens/book_detail_screen.dart';

class LikedBooksSection extends StatelessWidget {
  const LikedBooksSection({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
        final favoriteBookIds =
            (userData?['favoriteBookIds'] as List<dynamic>? ?? [])
                .map((id) => id.toString())
                .toList();

        if (favoriteBookIds.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        // To prevent query limit errors (Firebase `in` clause max 10 elements),
        // we take the first 10 liked item IDs for this section.
        final queryIds = favoriteBookIds.take(10).toList();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('books')
              .where(FieldPath.documentId, whereIn: queryIds)
              .snapshots(),
          builder: (context, bookSnapshot) {
            if (!bookSnapshot.hasData) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            final docs = bookSnapshot.data!.docs;
            if (docs.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            // Map and sort in the order of favoriteBookIds (optional, but good for UX)
            final books = docs.map((doc) => Book.fromFirestore(doc)).toList();
            books.sort((a, b) => favoriteBookIds
                .indexOf(a.id)
                .compareTo(favoriteBookIds.indexOf(b.id)));

            return SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'いいね！した商品',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 140, // fixed height for horizontal scroll
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: books.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        return _LikedBookThumbnail(book: books[index]);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _LikedBookThumbnail extends StatelessWidget {
  final Book book;

  const _LikedBookThumbnail({required this.book});

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
      child: SizedBox(
        width: 140,
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade200,
                  image: book.imageUrls.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(book.imageUrls.first),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: book.imageUrls.isEmpty
                    ? const Icon(Icons.book, color: Colors.grey)
                    : null,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    currencyFormatter.format(book.price),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
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
        ),
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
