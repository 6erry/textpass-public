import 'package:flutter/material.dart';
import '../screens/bundle_requests_screen.dart';
import '../screens/chat_screen.dart';

class AppRouter {
  static const String chatRoom = '/chat_room';
  static const String bundleRequests = '/bundle_requests';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case chatRoom:
        final args = settings.arguments;
        if (args is String) {
          return MaterialPageRoute(
            builder: (_) => ChatScreen(chatRoomId: args),
          );
        }
        return _errorRoute();
      case bundleRequests:
        return MaterialPageRoute(
          builder: (_) => const BundleRequestsScreen(),
        );
      default:
        return null; // Let MaterialApp handle unknown routes (or return null to fall through)
    }
  }

  static Route<dynamic> _errorRoute() {
    return MaterialPageRoute(builder: (_) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Error'),
        ),
        body: const Center(
          child: Text('ERROR: Invalid Route or Arguments'),
        ),
      );
    });
  }
}
