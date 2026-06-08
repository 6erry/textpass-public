import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import '../models/book.dart';
import '../services/fuzzy_search_service.dart';
import '../services/search_history_service.dart';
import '../services/user_service.dart';
import '../widgets/app_selection_dialog.dart';
import '../widgets/book_card.dart';
import 'package:textpass/utils/app_toast.dart';

enum SortOrder { newest, priceHigh, priceLow }

class SearchScreen extends StatefulWidget {
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final SearchHistoryService _historyService = SearchHistoryService();
  final UserService _userService = UserService();
  final FuzzySearchService _fuzzySearchService = FuzzySearchService();
  final BehaviorSubject<String> _searchSubject = BehaviorSubject<String>();

  List<String> _searchHistory = [];
  List<String> _savedSearches = [];
  List<String> _suggestions = [];
  List<Book> _results = [];

  bool _isSearching = false;
  bool _showHistory = true;
  bool _showSuggestions = false;
  bool _isProgrammaticUpdate =
      false; // Flag to ignore listener during programmatic updates
  String? _fuzzySuggestion;
  SortOrder _sortOrder = SortOrder.newest;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadSavedSearches();

    // Setup debounce for suggestions
    _searchSubject
        .debounceTime(const Duration(milliseconds: 500))
        .listen((query) {
      if (query.isNotEmpty) {
        _fetchSuggestions(query);
      } else {
        setState(() {
          _suggestions = [];
          _showSuggestions = false;
          _showHistory = true;
        });
      }
    });

    _controller.addListener(() {
      if (_isProgrammaticUpdate) return; // Skip if updated programmatically

      _searchSubject.add(_controller.text);
      if (_controller.text.isEmpty) {
        setState(() {
          _showHistory = true;
          _showSuggestions = false;
          _results = []; // Clear results when empty
        });
      } else {
        setState(() {
          _showHistory = false;
          _showSuggestions = true;
        });
      }
    });

    if (widget.initialQuery != null) {
      _isProgrammaticUpdate = true;
      _controller.text = widget.initialQuery!;
      _isProgrammaticUpdate = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleSearch(widget.initialQuery!);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchSubject.close();
    super.dispose();
  }

  Future<void> _loadSavedSearches() async {
    final saved = await _userService.getSavedSearches();
    if (mounted) {
      setState(() {
        _savedSearches = saved;
      });
    }
  }

  Future<void> _toggleSavedSearch() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;

    try {
      final isAdded = await _userService.toggleSavedSearch(keyword);
      await _loadSavedSearches(); // Reload to update UI

      if (mounted) {
        AppToast.show(
            context, isAdded ? '検索条件を保存しました。新着通知が届きます' : '検索条件を削除しました');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'エラーが発生しました: $e');
      }
    }
  }

  Future<void> _loadHistory() async {
    final history = await _historyService.getHistory();
    if (mounted) {
      setState(() {
        _searchHistory = history;
      });
    }
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.isEmpty) return;

    try {
      // Use searchKeywords for partial matching
      // Note: searchKeywords contains all substrings of the title.
      final snapshot = await FirebaseFirestore.instance
          .collection('books')
          .where('searchKeywords', arrayContains: query.toLowerCase())
          .limit(10)
          .get();

      final suggestions = snapshot.docs
          .map((doc) => doc.data()['title'] as String)
          .toSet()
          .toList();

      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _showSuggestions = true;
        });
      }
    } catch (e) {
      // print('Error fetching suggestions: $e');
    }
  }

  Future<void> _handleSearch(String rawKeyword) async {
    final keyword = rawKeyword.trim();
    if (keyword.isEmpty) return;

    setState(() {
      _isSearching = true;
      _showHistory = false;
      _showSuggestions = false;
      _fuzzySuggestion = null;

      _isProgrammaticUpdate = true;
      _controller.text = keyword;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: keyword.length),
      );
      _isProgrammaticUpdate = false;
    });

    await _historyService.addHistory(keyword);
    await _loadHistory(); // Reload history to reflect update

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      List<String> blockedUserIds = [];
      if (currentUser != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        blockedUserIds =
            List<String>.from(userDoc.data()?['blockedUserIds'] ?? []);
      }

      // Search by array-contains 'searchKeywords' OR simple title match
      // For this implementation, we'll stick to the existing logic or improve it.
      // Let's use the existing logic: searchKeywords arrayContains

      // Check if keyword looks like an ISBN
      final isIsbn = RegExp(r'^\d{10}(\d{3})?$').hasMatch(keyword);

      Query<Map<String, dynamic>> query;
      if (isIsbn) {
        query = FirebaseFirestore.instance
            .collection('books')
            .where('isbn', isEqualTo: keyword);
      } else {
        query = FirebaseFirestore.instance
            .collection('books')
            .where('searchKeywords', arrayContains: keyword.toLowerCase());
      }

      var snapshot = await query.get();
      var books = _mapSnapshotToBooks(snapshot, blockedUserIds);

      // Fallback if empty (legacy support or fuzzy search trigger)
      if (books.isEmpty) {
        // Try fuzzy search
        final suggestion = await _fuzzySearchService.findClosestMatch(keyword);
        if (suggestion != null && suggestion != keyword) {
          setState(() {
            _fuzzySuggestion = suggestion;
          });
        }

        // Also try legacy title contains search (client-side filtering)
        // This is heavy but ensures we find something if possible
        final allBooksSnapshot = await FirebaseFirestore.instance
            .collection('books')
            .orderBy('createdAt', descending: true)
            .limit(100) // Limit to recent 100 to avoid reading too much
            .get();

        books = _mapSnapshotToBooks(allBooksSnapshot, blockedUserIds)
            .where((book) =>
                book.title.toLowerCase().contains(keyword.toLowerCase()))
            .toList();
      }

      if (mounted) {
        setState(() {
          _results = _sortBooks(books);
          _isSearching = false;
        });
      }
    } catch (e) {
      // print('Search error: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
          _results = [];
        });
        AppToast.show(context, '検索エラー: $e');
      }
    }
  }

  List<Book> _mapSnapshotToBooks(
      QuerySnapshot snapshot, List<String> blockedUserIds) {
    return snapshot.docs
        .map((doc) {
          return Book.fromFirestore(doc);
        })
        .where((book) => !blockedUserIds.contains(book.userId))
        .toList();
  }

  List<Book> _sortBooks(List<Book> books) {
    final sorted = List<Book>.from(books);
    switch (_sortOrder) {
      case SortOrder.priceHigh:
        sorted.sort((a, b) => b.price.compareTo(a.price));
        break;
      case SortOrder.priceLow:
        sorted.sort((a, b) => a.price.compareTo(b.price));
        break;
      case SortOrder.newest:
        // Assuming id or implicit order is roughly newest if no createdAt
        break;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '何をお探しですか？',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: _handleSearch,
        ),
      ),
      body: Column(
        children: [
          // Control Panel Chips
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                ActionChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort, size: 16, color: Colors.grey.shade700),
                      const SizedBox(width: 4),
                      Text(_getSortLabel(_sortOrder)),
                    ],
                  ),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey.shade300),
                  onPressed: _showSortOptions,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _savedSearches.contains(_controller.text.trim())
                            ? Icons.check
                            : Icons.add,
                        size: 16,
                        color: _savedSearches.contains(_controller.text.trim())
                            ? Colors.white
                            : Colors.grey.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _savedSearches.contains(_controller.text.trim())
                            ? '保存済み'
                            : '条件を保存',
                        style: TextStyle(
                          color:
                              _savedSearches.contains(_controller.text.trim())
                                  ? Colors.white
                                  : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  backgroundColor:
                      _savedSearches.contains(_controller.text.trim())
                          ? Theme.of(context).primaryColor
                          : Colors.white,
                  side: BorderSide(
                    color: _savedSearches.contains(_controller.text.trim())
                        ? Colors.transparent
                        : Colors.grey.shade300,
                  ),
                  onPressed: _toggleSavedSearch,
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  String _getSortLabel(SortOrder order) {
    switch (order) {
      case SortOrder.newest:
        return '新しい順';
      case SortOrder.priceHigh:
        return '価格が高い順';
      case SortOrder.priceLow:
        return '価格が安い順';
    }
  }

  Future<void> _showSortOptions() async {
    final selected = await showAppSelectionDialog<SortOrder>(
      context: context,
      title: '並び替え',
      selectedValue: _sortOrder,
      options: const [
        AppSelectionOption(
          label: '新しい順',
          value: SortOrder.newest,
          icon: Icons.sort,
        ),
        AppSelectionOption(
          label: '価格が高い順',
          value: SortOrder.priceHigh,
          icon: Icons.arrow_upward,
        ),
        AppSelectionOption(
          label: '価格が安い順',
          value: SortOrder.priceLow,
          icon: Icons.arrow_downward,
        ),
      ],
    );
    if (selected == null || selected == _sortOrder || !mounted) return;
    setState(() {
      _sortOrder = selected;
      _results = _sortBooks(_results);
    });
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_showHistory && _controller.text.isEmpty) {
      return _buildHistoryView();
    }

    if (_showSuggestions) {
      return _buildSuggestionsView();
    }

    return _buildResultsView();
  }

  Widget _buildHistoryView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Saved Searches Section
          if (_savedSearches.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('保存した検索条件',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _savedSearches.length,
              itemBuilder: (context, index) {
                final keyword = _savedSearches[index];
                return ListTile(
                  leading: Icon(Icons.bookmark,
                      color: Theme.of(context).primaryColor),
                  title: Text(keyword),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _handleSearch(keyword),
                );
              },
            ),
            const Divider(),
          ],

          // Recent History Section
          if (_searchHistory.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('最近の検索',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () async {
                      await _historyService.clearHistory();
                      _loadHistory();
                    },
                    child: const Text('すべて削除'),
                  ),
                ],
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchHistory.length,
              itemBuilder: (context, index) {
                final keyword = _searchHistory[index];
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(keyword),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await _historyService.removeHistory(keyword);
                      _loadHistory();
                    },
                  ),
                  onTap: () => _handleSearch(keyword),
                );
              },
            ),
          ] else if (_savedSearches.isEmpty) ...[
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: Text('検索履歴はありません')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionsView() {
    if (_suggestions.isEmpty) {
      return Container(); // Or show "No suggestions"
    }

    return ListView.builder(
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return ListTile(
          leading: const Icon(Icons.search),
          title: Text(suggestion),
          onTap: () => _handleSearch(suggestion),
        );
      },
    );
  }

  Widget _buildResultsView() {
    return Column(
      children: [
        if (_fuzzySuggestion != null)
          Container(
            width: double.infinity,
            color: Colors.orange.shade50,
            padding: const EdgeInsets.all(12),
            child: InkWell(
              onTap: () => _handleSearch(_fuzzySuggestion!),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.black87),
                        children: [
                          const TextSpan(text: '検索結果がありませんでした。\nもしかして: '),
                          TextSpan(
                            text: _fuzzySuggestion,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          const TextSpan(text: ' ?'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _results.isEmpty
              ? const Center(child: Text('一致する本は見つかりませんでした。'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    return BookCard(book: _results[index]);
                  },
                ),
        ),
      ],
    );
  }
}
