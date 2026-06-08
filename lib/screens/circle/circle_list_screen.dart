import 'package:flutter/material.dart';

import '../../models/circle.dart';
import '../../services/circle_service.dart';
import 'circle_detail_screen.dart';

enum _CircleBroadCategory { all, culture, sports }

class CircleListScreen extends StatefulWidget {
  const CircleListScreen({super.key});

  @override
  State<CircleListScreen> createState() => _CircleListScreenState();
}

class _CircleListScreenState extends State<CircleListScreen> {
  final _circleService = CircleService();
  final _searchController = TextEditingController();
  late Future<List<Circle>> _circlesFuture;

  _CircleBroadCategory _broadCategory = _CircleBroadCategory.all;
  CircleCategory? _detailCategory;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _circlesFuture = _circleService.getCircles();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _circlesFuture = _circleService.getCircles();
    });
    await _circlesFuture;
  }

  List<CircleCategory> get _detailOptions {
    switch (_broadCategory) {
      case _CircleBroadCategory.sports:
        return const [CircleCategory.sports];
      case _CircleBroadCategory.culture:
        return CircleCategory.values
            .where((category) => category != CircleCategory.sports)
            .toList();
      case _CircleBroadCategory.all:
        return CircleCategory.values;
    }
  }

  List<Circle> _filterCircles(List<Circle> circles) {
    return circles.where((circle) {
      final matchesBroad = switch (_broadCategory) {
        _CircleBroadCategory.all => true,
        _CircleBroadCategory.sports => circle.category == CircleCategory.sports,
        _CircleBroadCategory.culture =>
          circle.category != CircleCategory.sports,
      };
      final matchesDetail =
          _detailCategory == null || circle.category == _detailCategory;
      final matchesQuery = _query.isEmpty ||
          circle.name.toLowerCase().contains(_query) ||
          circle.description.toLowerCase().contains(_query) ||
          (circle.place ?? '').toLowerCase().contains(_query);
      return matchesBroad && matchesDetail && matchesQuery;
    }).toList()
      ..sort((a, b) {
        final activeCompare = _statusRank(a).compareTo(_statusRank(b));
        if (activeCompare != 0) return activeCompare;
        return a.name.compareTo(b.name);
      });
  }

  int _statusRank(Circle circle) => circle.status == 'active' ? 0 : 1;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Circle>>(
        future: _circlesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('サークル情報を取得できませんでした: ${snapshot.error}'));
          }

          final circles = snapshot.data ?? [];
          final filtered = _filterCircles(circles);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildSearchAndFilters(circles)),
              if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      '条件に一致するサークルはありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        index == 0 ? 8 : 0,
                        16,
                        index == filtered.length - 1 ? 24 : 0,
                      ),
                      child: _CircleListCard(circle: filtered[index]),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchAndFilters(List<Circle> circles) {
    final activeCount =
        circles.where((circle) => circle.status == 'active').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'サークル一覧',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '公開中 $activeCount件 / 登録 ${circles.length}件',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'サークル名・活動場所で検索',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFFF7F7F7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          _buildBroadCategorySegments(),
          const SizedBox(height: 10),
          _buildDetailChips(),
        ],
      ),
    );
  }

  Widget _buildBroadCategorySegments() {
    return SegmentedButton<_CircleBroadCategory>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: _CircleBroadCategory.all, label: Text('すべて')),
        ButtonSegment(value: _CircleBroadCategory.culture, label: Text('文化')),
        ButtonSegment(value: _CircleBroadCategory.sports, label: Text('体育')),
      ],
      selected: {_broadCategory},
      onSelectionChanged: (selection) {
        setState(() {
          _broadCategory = selection.first;
          if (_detailCategory != null &&
              !_detailOptions.contains(_detailCategory)) {
            _detailCategory = null;
          }
        });
      },
    );
  }

  Widget _buildDetailChips() {
    final options = _detailOptions;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('すべて'),
              selected: _detailCategory == null,
              showCheckmark: false,
              onSelected: (_) => setState(() => _detailCategory = null),
            ),
          ),
          ...options.map(
            (category) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(category.label),
                selected: _detailCategory == category,
                showCheckmark: false,
                onSelected: (_) => setState(() => _detailCategory = category),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleListCard extends StatelessWidget {
  const _CircleListCard({required this.circle});

  final Circle circle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CircleDetailScreen(circleId: circle.id),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.grey.shade100,
                backgroundImage: circle.iconUrl != null
                    ? NetworkImage(circle.iconUrl!)
                    : null,
                child: circle.iconUrl == null
                    ? Icon(Icons.groups_2_outlined, color: Colors.grey.shade600)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            circle.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _CategoryBadge(label: circle.category.label),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      circle.description.isEmpty
                          ? _fallbackDescription(circle)
                          : circle.description,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.place_outlined,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            circle.place?.isNotEmpty == true
                                ? circle.place!
                                : '活動場所未設定',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          circle.status == 'active' ? '公開中' : '準備中',
                          style: TextStyle(
                            color: circle.status == 'active'
                                ? Colors.green.shade700
                                : Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
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
  }

  String _fallbackDescription(Circle circle) {
    if (circle.activityDays.isNotEmpty) {
      return '活動日: ${circle.activityDays.join(', ')}';
    }
    return '詳細情報はまだ登録されていません';
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.grey.shade700,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
