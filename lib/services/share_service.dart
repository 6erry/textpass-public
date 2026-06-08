import 'package:share_plus/share_plus.dart';
import '../models/book.dart';
import '../models/event.dart';
import '../models/circle.dart';

class ShareService {
  static const String _scheme = 'textlink';

  Future<void> shareBook(Book book) async {
    final url = '$_scheme://item/${book.id}';
    final text = '【TextPass】${book.title}が出品されています\n$url';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> shareEvent(Event event) async {
    final url = '$_scheme://event/${event.id}';
    final text = '【TextPass】イベント「${event.title}」\n$url';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> shareCircle(Circle circle) async {
    final url = '$_scheme://circle/${circle.id}';
    final text = '【TextPass】サークル「${circle.name}」\n$url';
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
