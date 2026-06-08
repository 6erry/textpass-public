import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/book.dart';
import '../screens/book_detail_screen.dart';

class BookCard extends StatelessWidget {
  const BookCard({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormatter =
        NumberFormat.currency(locale: 'ja_JP', symbol: '¥');

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookDetailScreen(book: book),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Container (Square 1:1)
          AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Builder(
                    builder: (context) {
                      final url =
                          book.imageUrls.isNotEmpty ? book.imageUrls.first : '';
                      if (url.isEmpty) {
                        return Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(
                              Icons.image,
                              size: 32,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      }
                      if (url.startsWith('http')) {
                        return Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color: Colors.grey.shade200,
                            child: Icon(
                              Icons.broken_image,
                              size: 32,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        );
                      } else {
                        // Handle local files (path or file URI)
                        try {
                          final trimmedUrl = url.trim();
                          File file;
                          if (trimmedUrl.startsWith('file:')) {
                            file = File.fromUri(Uri.parse(trimmedUrl));
                          } else {
                            file = File(trimmedUrl);
                          }

                          return Image.file(
                            file,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: Icon(Icons.image_not_supported),
                              ),
                            ),
                          );
                        } catch (e) {
                          return Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.image_not_supported),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                // Price Tag Overlay (Bottom Left)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomLeft: Radius.circular(4),
                      ),
                    ),
                    child: Text(
                      book.price == 0
                          ? '¥0'
                          : currencyFormatter.format(book.price),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                // Sold Banner (Top Left)
                if (book.status == 'sold' || book.status == 'trading')
                  Positioned(
                    top: 0,
                    left: 0,
                    child: CustomPaint(
                      size: const Size(40, 40),
                      painter: _SoldTrianglePainter(
                        color: Colors.red,
                      ),
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(top: 6, left: 2),
                        child: Transform.rotate(
                          angle: -math.pi / 4,
                          child: const Text(
                            'SOLD',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Title
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.black87,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoldTrianglePainter extends CustomPainter {
  final Color color;

  _SoldTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
