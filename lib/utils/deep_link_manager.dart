import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/book.dart';
import '../models/event.dart';

import '../screens/book_detail_screen.dart';
import '../screens/event/event_detail_screen.dart';
import '../screens/circle/circle_detail_screen.dart';

class DeepLinkManager {
  final GlobalKey<NavigatorState> navigatorKey;
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  DeepLinkManager(this.navigatorKey);

  Future<void> init() async {
    _appLinks = AppLinks();

    // Check initial link
    final appLink = await _appLinks.getInitialLink();
    if (appLink != null) {
      handleLink(appLink);
    }

    // Listen for new links
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      handleLink(uri);
    });
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  void handleLink(Uri uri) {
    if (uri.scheme == 'textpass') {
      // Stripe Connect redirects back to textpass://connect-callback.
      // The onboarding screens refresh their status when the app resumes.
      return;
    }
    if (uri.scheme != 'textlink') return;

    // Uri parsing: textlink://item/123
    // host: item
    // pathSegments: [123]

    String type = uri.host;
    String? id;
    if (uri.pathSegments.isNotEmpty) {
      id = uri.pathSegments.first;
    }

    if (id == null) return;

    if (type == 'item') {
      _navigateToBook(id);
    } else if (type == 'event') {
      _navigateToEvent(id);
    } else if (type == 'circle') {
      _navigateToCircle(id);
    }
  }

  void _navigateToBook(String id) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => _FetchingScreen(
          collection: 'books',
          docId: id,
          builder: (doc) => BookDetailScreen(book: Book.fromFirestore(doc)),
        ),
      ),
    );
  }

  void _navigateToEvent(String id) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => _FetchingScreen(
          collection: 'events',
          docId: id,
          builder: (doc) => EventDetailScreen(event: Event.fromFirestore(doc)),
        ),
      ),
    );
  }

  void _navigateToCircle(String id) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => CircleDetailScreen(circleId: id),
      ),
    );
  }
}

class _FetchingScreen extends StatelessWidget {
  final String collection;
  final String docId;
  final Widget Function(DocumentSnapshot<Map<String, dynamic>>) builder;

  const _FetchingScreen({
    required this.collection,
    required this.docId,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('読み込み中'),
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future:
            FirebaseFirestore.instance.collection(collection).doc(docId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('エラーが発生しました: ${snapshot.error}'));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('データが見つかりませんでした'));
          }

          return builder(snapshot.data!);
        },
      ),
    );
  }
}
