import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';
import '../models/circle.dart';
import '../services/event_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../utils/legal_notices.dart';
import 'circle/circle_list_screen.dart';
import 'event/event_detail_screen.dart';

import '../widgets/empty_state_widget.dart';
import 'package:textpass/utils/app_toast.dart';

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  DateTime _selectedDate = DateTime.now();
  CircleCategory? _selectedCategory;
  final _eventService = EventService();
  final _notificationService = NotificationService();
  late final Stream<List<Event>> _eventsStream;

  List<String> _likedEventIds = [];

  @override
  void initState() {
    super.initState();
    _eventsStream = _eventService.getEvents();
    _loadLikedEvents();
  }

  Future<void> _loadLikedEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _likedEventIds =
              List<String>.from(doc.data()?['likedEventIds'] ?? []);
        });
      }
    }
  }

  Future<void> _toggleLike(Event event) async {
    final isLiked = _likedEventIds.contains(event.id);
    final newStatus = !isLiked;

    try {
      await _eventService.toggleLike(event.id, newStatus);

      if (newStatus) {
        await _notificationService.scheduleEventNotification(event);
      } else {
        await _notificationService.cancelEventNotification(event.id);
      }

      setState(() {
        if (newStatus) {
          _likedEventIds.add(event.id);
        } else {
          _likedEventIds.remove(event.id);
        }
      });
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('新歓・サークル'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'イベント'),
              Tab(text: 'サークル'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildEventsTab(),
            const CircleListScreen(),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsTab() {
    return StreamBuilder<List<String>>(
      stream: UserService().blockedUserIdsStream,
      builder: (context, blockedSnapshot) {
        final blockedUserIds = blockedSnapshot.data ?? [];

        return StreamBuilder<List<Event>>(
          stream: _eventsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const EmptyStateWidget(
                icon: Icons.event_busy,
                title: 'イベントを取得できませんでした',
                message: '時間をおいて再度お試しください。',
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final events = snapshot.data ?? [];

            return Column(
              children: [
                _buildDateSelector(events),
                _buildCategoryFilter(),
                Expanded(
                  child: _buildEventList(events, blockedUserIds),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDateSelector(List<Event> events) {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 14, // Next 2 weeks
        itemBuilder: (context, index) {
          final date = DateTime.now().add(Duration(days: index));
          final isSelected = DateUtils.isSameDay(date, _selectedDate);

          // Check if there are events on this day
          final hasEvents =
              events.any((event) => DateUtils.isSameDay(event.startAt, date));

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDate = date;
              });
            },
            child: Opacity(
              opacity: isSelected || hasEvents ? 1.0 : 0.4,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 60,
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('E', 'ja').format(date),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      date.day.toString(),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (hasEvents && !isSelected)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                      )
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: CircleCategory.values.length + 1, // +1 for "All"
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSelected = _selectedCategory == null;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('すべて',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                selected: isSelected,
                showCheckmark: false,
                selectedColor:
                    Theme.of(context).primaryColor.withValues(alpha: 0.15),
                backgroundColor: Colors.grey.shade100,
                side: BorderSide(color: Colors.grey.shade200),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                labelStyle: TextStyle(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.black87,
                ),
                onSelected: (selected) {
                  setState(() {
                    _selectedCategory = null;
                  });
                },
              ),
            );
          }
          final category = CircleCategory.values[index - 1];
          final isSelected = _selectedCategory == category;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(category.label,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              selected: isSelected,
              showCheckmark: false,
              selectedColor:
                  Theme.of(context).primaryColor.withValues(alpha: 0.15),
              backgroundColor: Colors.grey.shade100,
              side: BorderSide(color: Colors.grey.shade200),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              labelStyle: TextStyle(
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.black87,
              ),
              onSelected: (selected) {
                setState(() {
                  _selectedCategory = selected ? category : null;
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEventList(List<Event> events, List<String> blockedUserIds) {
    final filteredEvents = events.where((event) {
      final matchesDate = DateUtils.isSameDay(event.startAt, _selectedDate);
      final matchesCategory =
          _selectedCategory == null || event.category == _selectedCategory;
      return matchesDate && matchesCategory;
    }).toList();

    if (filteredEvents.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.event_busy,
        title: 'イベントが見つかりません',
        message: '別の日付またはカテゴリを選択してください。',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredEvents.length,
      itemBuilder: (context, index) {
        final event = filteredEvents[index];

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('circles')
              .doc(event.circleId)
              .get(),
          builder: (context, circleSnapshot) {
            if (!circleSnapshot.hasData) {
              return const SizedBox(); // Hide until loaded
            }

            final circleData =
                circleSnapshot.data!.data() as Map<String, dynamic>?;
            if (circleData == null) return const SizedBox();

            final adminUids = List<String>.from(
              circleData['admin_uids'] ?? circleData['adminUids'] ?? [],
            );
            final isBlocked =
                adminUids.any((uid) => blockedUserIds.contains(uid));

            if (isBlocked) {
              return const SizedBox.shrink();
            }

            final isLiked = _likedEventIds.contains(event.id);

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color:
                    event.isActivePromotion ? Colors.red.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: event.isActivePromotion
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.35)
                      : Colors.grey.shade200,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EventDetailScreen(event: event),
                      ),
                    );
                    _loadLikedEvents();
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          Container(
                            height: 160,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                            ),
                            child: event.imageUrl != null
                                ? Image.network(
                                    event.imageUrl!,
                                    width: double.infinity,
                                    height: 160,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(
                                          child: Icon(Icons.broken_image,
                                              size: 50, color: Colors.grey));
                                    },
                                  )
                                : const Center(
                                    child: Icon(Icons.image,
                                        size: 50, color: Colors.grey)),
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 20,
                              child: IconButton(
                                icon: Icon(
                                  isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 20,
                                  color: isLiked
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey.shade600,
                                ),
                                onPressed: () => _toggleLike(event),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Row(
                              children: [
                                if (event.isActivePromotion) ...[
                                  PrBadge(label: event.promotionLabel),
                                  const SizedBox(width: 6),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    event.category.label,
                                    style: TextStyle(
                                        color: Theme.of(context).primaryColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (event.isActivePromotion) ...[
                              const SizedBox(height: 10),
                              const InformationCard(
                                title: 'PR掲載',
                                message: prDisclaimerNotice,
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.calendar_today,
                                    size: 16, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text(
                                  DateFormat('yyyy/MM/dd HH:mm')
                                      .format(event.startAt),
                                  style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.location_on,
                                    size: 16, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    event.location,
                                    style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
