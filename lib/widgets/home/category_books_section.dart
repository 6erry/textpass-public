import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/book.dart';
import '../../screens/book_detail_screen.dart';

class CategoryBooksSection extends StatelessWidget {
  final String title;
  final List<String> keywords;
  final String universityId;
  final List<String> blockedUserIds;

  const CategoryBooksSection({
    super.key,
    required this.title,
    required this.keywords,
    required this.universityId,
    required this.blockedUserIds,
  });

  @override
  Widget build(BuildContext context) {
    if (universityId.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('books')
          .where('universityId', isEqualTo: universityId)
          .orderBy('createdAt', descending: true)
          .limit(50) // Fetch latest 50 to filter locally
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        var books = snapshot.data!.docs
            .map((doc) => Book.fromFirestore(doc))
            .where((book) => !blockedUserIds.contains(book.userId))
            .toList();

        // If keywords are provided, filter books that match any keyword in title or courseName
        if (keywords.isNotEmpty) {
          books = books.where((book) {
            final lowerTitle = book.title.toLowerCase();
            final lowerCourse = book.courseName.toLowerCase();
            return keywords.any((keyword) {
              final lowerKeyword = keyword.toLowerCase();
              return lowerTitle.contains(lowerKeyword) ||
                  lowerCourse.contains(lowerKeyword);
            });
          }).toList();
        }

        if (books.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        return SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // TODO: Navigate to a full list page filtered by this category
                      },
                      child: const Text('すべて見る >'),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 140, // fixed height for horizontal scroll
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: books.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8), // slightly tighter gap
                  itemBuilder: (context, index) {
                    return _CategoryBookThumbnail(book: books[index]);
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryBookThumbnail extends StatelessWidget {
  final Book book;

  const _CategoryBookThumbnail({required this.book});

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
        width: 140, // Fixed width for horizontal items
        child: AspectRatio(
          aspectRatio: 1.0, // Force square shape like Mercari
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
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
