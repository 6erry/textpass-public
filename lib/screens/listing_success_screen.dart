import 'package:flutter/material.dart';

import '../models/book.dart';
import '../widgets/book_card.dart';
import 'book_detail_screen.dart';

class ListingSuccessScreen extends StatelessWidget {
  const ListingSuccessScreen({super.key, required this.book, this.onComplete});

  final Book book;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('出品完了'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 48), // Add top spacing since it's scrollable
            const Text(
              '出品が完了しました！',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: SizedBox(
                width: 160, // Constrain width to prevent excessive height
                height: 220,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BookDetailScreen(book: book),
                      ),
                    );
                  },
                  child: BookCard(book: book),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (onComplete != null) {
                    onComplete!();
                    // Also pop this screen?
                    // If we are in a tab, we probably want to pop this screen AND switch tab.
                    // But ListingSuccessScreen was pushed.
                    // So we should pop.
                    Navigator.of(context).pop();
                  } else {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('ホームに戻る'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
