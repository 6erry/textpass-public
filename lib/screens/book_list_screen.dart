import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/book.dart';
import '../models/event.dart';
import '../models/user_class.dart';
import '../services/event_service.dart';
import '../services/timetable_service.dart';
import '../widgets/book_card.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/todo_icon_button.dart';
import 'add_book_screen.dart';
import 'event/event_detail_screen.dart';
import 'notification_screen.dart';
import 'search_screen.dart';

class BookListScreen extends StatefulWidget {
  const BookListScreen({super.key});

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

enum SortOrder { newest, priceHigh, priceLow }

class _BookListScreenState extends State<BookListScreen> {
  final SortOrder _sortOrder = SortOrder.newest;
  late final Future<String?> _universityFuture;
  final _timetableService = TimetableService();
  final _eventService = EventService();

  @override
  void initState() {
    super.initState();
    _universityFuture = _loadUniversityId();
  }

  Future<String?> _loadUniversityId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    return doc.data()?['universityId'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<String?>(
        future: _universityFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('ユーザー情報の取得に失敗しました'));
          }

          final universityId = snapshot.data;
          if (universityId == null || universityId.isEmpty) {
            return const Center(
              child: Text('大学認証が完了していません。プロフィール設定を確認してください'),
            );
          }

          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null) {
            return const Center(child: Text('ログインしてください'));
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .snapshots(),
            builder: (context, userDocSnapshot) {
              if (userDocSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final blockedUserIds = List<String>.from(
                userDocSnapshot.data?.data()?['blockedUserIds'] ?? [],
              );

              return CustomScrollView(
                slivers: [
                  _buildSliverAppBar(context),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildNextClassSection(),
                          const SizedBox(height: 24),
                          _buildTodaysEventsSection(),
                          const SizedBox(height: 24),
                          const Text(
                            '新着の教科書',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildBookGrid(universityId, blockedUserIds),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      floating: true,
      titleSpacing: 16,
      title: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const SearchScreen(),
            ),
          );
        },
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.grey.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                'なにをお探しですか？',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        const TodoIconButton(),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.black87),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NotificationScreen(),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildNextClassSection() {
    return FutureBuilder<UserClass?>(
      future: _timetableService.getNextClass(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              height: 100, child: Center(child: CircularProgressIndicator()));
        }

        final nextClass = snapshot.data;
        if (nextClass == null) {
          // Optional: Show "No more classes today" or nothing.
          // User requested "今日の授業は終了しました" or hidden.
          // Let's show a small message.
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('今日の授業は終了しました',
                style: TextStyle(color: Colors.grey)),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '次の授業',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                // Navigate to Timetable tab (Index 1)
                // This requires access to the MainScreen's state or a global key/provider.
                // For now, we can't easily switch tabs from here without context of MainScreen.
                // We'll just leave it as visual info or maybe show detail dialog.
                // Ideally, use a callback or Provider to switch tabs.
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${nextClass.day}曜 ${nextClass.period}限',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            nextClass.room.isNotEmpty ? nextClass.room : '教室未定',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      nextClass.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nextClass.teacher,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTodaysEventsSection() {
    return StreamBuilder<List<Event>>(
      stream: _eventService.getTodaysEvents(),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final events = snapshot.data!;
        if (events.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '今日のイベント',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  return Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EventDetailScreen(event: event),
                          ),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: DecorationImage(
                                  image: event.imageUrl != null
                                      ? NetworkImage(event.imageUrl!)
                                      : const AssetImage(
                                              'assets/images/placeholder.png')
                                          as ImageProvider, // Fallback?
                                  fit: BoxFit.cover,
                                  onError: (exception,
                                      stackTrace) {}, // Handle error gracefully
                                ),
                                color: Colors.grey.shade200,
                              ),
                              child: event.imageUrl == null
                                  ? const Center(
                                      child:
                                          Icon(Icons.event, color: Colors.grey))
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            DateFormat('HH:mm').format(event.startAt),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBookGrid(String universityId, List<String> blockedUserIds) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('books')
          .where('universityId', isEqualTo: universityId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Center(
                child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            )),
          );
        }
        if (snapshot.hasError) {
          return const SliverToBoxAdapter(
            child: Center(child: Text('データの取得に失敗しました')),
          );
        }

        final books = snapshot.data?.docs
                .map((doc) {
                  final data = doc.data();
                  final ownerId = data['userId'] as String? ?? '';
                  if (blockedUserIds.contains(ownerId)) {
                    return null;
                  }
                  if (blockedUserIds.contains(ownerId)) {
                    return null;
                  }
                  return Book.fromFirestore(doc);
                })
                .whereType<Book>()
                .toList() ??
            [];

        if (books.isEmpty) {
          return SliverToBoxAdapter(
            child: EmptyStateWidget(
              icon: Icons.library_books,
              title: '教科書が出品されていません',
              message: '現在、販売中の教科書はありません。\n出品されるのを待ちましょう！',
              buttonText: '出品する',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddBookScreen()),
                );
              },
            ),
          );
        }

        // Sort logic
        switch (_sortOrder) {
          case SortOrder.priceHigh:
            books.sort((a, b) => b.price.compareTo(a.price));
            break;
          case SortOrder.priceLow:
            books.sort((a, b) => a.price.compareTo(b.price));
            break;
          case SortOrder.newest:
            break;
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.75,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return BookCard(book: books[index]);
              },
              childCount: books.length,
            ),
          ),
        );
      },
    );
  }
}
