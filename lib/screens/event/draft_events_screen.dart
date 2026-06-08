import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/event.dart';
import '../../services/event_service.dart';
import '../../widgets/empty_state_widget.dart';
import 'create_event_screen.dart';

class DraftEventsScreen extends StatelessWidget {
  final String circleId;

  const DraftEventsScreen({super.key, required this.circleId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下書き一覧'),
      ),
      body: StreamBuilder<List<Event>>(
        stream: EventService().getDraftEvents(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('エラーが発生しました: ${snapshot.error}'));
          }

          final events = (snapshot.data ?? [])
              .where((event) => event.circleId == circleId)
              .toList();

          if (events.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.drafts_outlined,
              title: '下書きはありません',
              message: '作成中のイベントはありません。',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(
                    event.title.isEmpty ? '(無題のイベント)' : event.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '作成日: ${DateFormat('yyyy/MM/dd HH:mm').format(event.createdAt)}',
                  ),
                  trailing: const Icon(Icons.edit),
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateEventScreen(eventToEdit: event),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
