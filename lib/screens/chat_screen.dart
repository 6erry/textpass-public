import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'qr_scanner_screen.dart';
import 'rating_screen.dart';
import '../widgets/block_action_button.dart';

import '../widgets/app_custom_input_dialog.dart';
import 'package:textpass/utils/app_toast.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatRoomId});

  final String chatRoomId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('ログインが必要です')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(body: Center(child: Text('取引情報が見つかりません')));
        }

        final chatData = snapshot.data!.data() ?? {};
        final buyerId = chatData['buyerId'] as String?;
        final sellerId = chatData['sellerId'] as String?;
        final otherUserId = currentUser.uid == buyerId ? sellerId : buyerId;

        if (otherUserId == null) {
          return const Scaffold(body: Center(child: Text('相手ユーザーが見つかりません')));
        }

        // デバッグログ
        // print('ChatScreen: Current=${currentUser.uid}, Other=$otherUserId');

        // Check if I blocked them - Listen directly to User Document
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            final userData = userSnapshot.data?.data();
            final myBlocked =
                List<String>.from(userData?['blockedUserIds'] ?? []);
            final iBlockedThem = myBlocked.contains(otherUserId);

            // Check if they blocked me
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(otherUserId)
                  .snapshots(),
              builder: (context, otherUserSnap) {
                final otherUserData =
                    otherUserSnap.data?.data() as Map<String, dynamic>?;
                final blockedByThemList =
                    List<String>.from(otherUserData?['blockedUserIds'] ?? []);
                final theyBlockedMe =
                    blockedByThemList.contains(currentUser.uid);

                final isBlocked = iBlockedThem || theyBlockedMe;

                return Scaffold(
                  appBar: AppBar(
                    title: const Text('取引メッセージ'),
                    actions: [
                      BlockActionButton(
                        targetUserId: otherUserId,
                        transactionId: widget.chatRoomId,
                      ),
                    ],
                  ),
                  body: Column(
                    children: [
                      _StatusBanner(
                        chatData: chatData,
                        currentUserId: currentUser.uid,
                        chatRoomId: widget.chatRoomId,
                      ),
                      Expanded(
                        child:
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('chat_rooms')
                              .doc(widget.chatRoomId)
                              .collection('messages')
                              .orderBy('createdAt')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            final docs = snapshot.data?.docs ?? [];
                            if (docs.isEmpty) {
                              return const Center(
                                child: Text('まだメッセージはありません。'),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 16),
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final data = docs[index].data();
                                final senderId =
                                    data['senderId'] as String? ?? '';
                                final text = data['text'] as String? ?? '';
                                final isMe = senderId == currentUser.uid;

                                return Align(
                                  alignment: isMe
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                          : Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(12),
                                        topRight: const Radius.circular(12),
                                        bottomLeft: isMe
                                            ? const Radius.circular(12)
                                            : const Radius.circular(4),
                                        bottomRight: isMe
                                            ? const Radius.circular(4)
                                            : const Radius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      text,
                                      style: TextStyle(
                                        color: isMe
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onPrimaryContainer
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isBlocked) ...[
                                _TemplateMessageBar(
                                  onSelected: _insertTemplate,
                                ),
                                const SizedBox(height: 8),
                                _HandoverStatusBar(
                                  chatRoomId: widget.chatRoomId,
                                  chatData: chatData,
                                  currentUserId: currentUser.uid,
                                  onStatusText: _sendStatusMessage,
                                ),
                                const SizedBox(height: 8),
                              ],
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _messageController,
                                      enabled: !isBlocked,
                                      decoration: InputDecoration(
                                        hintText: isBlocked
                                            ? 'このユーザーとはチャットできません'
                                            : 'メッセージを入力',
                                        border: const OutlineInputBorder(),
                                        filled: isBlocked,
                                        fillColor: isBlocked
                                            ? Colors.grey.shade200
                                            : null,
                                      ),
                                      minLines: 1,
                                      maxLines: 4,
                                    ),
                                  ),
                                  if (!isBlocked) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: _sendMessage,
                                      icon: const Icon(Icons.send),
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final text = _messageController.text.trim();

    if (currentUser == null) {
      AppToast.show(context, 'メッセージを送信するにはログインしてください。');
      return;
    }

    if (text.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .collection('messages')
          .add({
        'text': text,
        'senderId': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _messageController.clear();
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'メッセージの送信に失敗しました。');
    }
  }

  void _insertTemplate(String text) {
    final current = _messageController.text.trim();
    _messageController.text = current.isEmpty ? text : '$current\n$text';
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: _messageController.text.length),
    );
  }

  Future<void> _sendStatusMessage(String text) async {
    _messageController.text = text;
    await _sendMessage();
  }
}

class _TemplateMessageBar extends StatelessWidget {
  const _TemplateMessageBar({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _templates = [
    '購入ありがとうございます。受け渡し日時を相談したいです。',
    'この候補でどうですか？',
    '承知しました。よろしくお願いします。',
    '本日、予定通り向かいます。',
    '到着しました。',
    '5分ほど遅れます。すみません。',
    '商品を確認しました。',
    '受け渡しありがとうございました。',
    '日程を変更できますか？',
    '申し訳ありません、今回はキャンセルしたいです。',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final text = _templates[index];
          return ActionChip(
            label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            onPressed: () => onSelected(text),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _templates.length,
      ),
    );
  }
}

class _HandoverStatusBar extends StatelessWidget {
  const _HandoverStatusBar({
    required this.chatRoomId,
    required this.chatData,
    required this.currentUserId,
    required this.onStatusText,
  });

  final String chatRoomId;
  final Map<String, dynamic> chatData;
  final String currentUserId;
  final ValueChanged<String> onStatusText;

  static const _statuses = {
    'on_my_way': '今向かっています',
    'arrived': '到着しました',
    'waiting': '待っています',
    'late_5': '5分ほど遅れます',
    'late_10': '10分ほど遅れます',
    'need_reschedule': '日程変更したいです',
    'completed_handover': '受け渡し完了',
  };

  bool get _isAroundHandover {
    final meetingTime = chatData['meetingTime'];
    if (meetingTime is! Timestamp) return false;
    final diff = meetingTime.toDate().difference(DateTime.now()).abs();
    return diff <= const Duration(hours: 24);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAroundHandover) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _statuses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = _statuses.entries.elementAt(index);
          return ActionChip(
            avatar: const Icon(Icons.location_on_outlined, size: 16),
            label: Text(entry.value),
            onPressed: () async {
              final isBuyer = chatData['buyerId'] == currentUserId;
              final fieldPrefix = isBuyer ? 'buyer' : 'seller';
              await FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .doc(chatRoomId)
                  .update({
                '${fieldPrefix}HandoverStatus': entry.key,
                '${fieldPrefix}HandoverStatusUpdatedAt':
                    FieldValue.serverTimestamp(),
              });
              onStatusText(entry.value);
            },
          );
        },
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.chatData,
    required this.currentUserId,
    required this.chatRoomId,
  });

  final Map<String, dynamic> chatData;
  final String? currentUserId;
  final String chatRoomId;

  bool get _isParticipant =>
      currentUserId == chatData['buyerId'] ||
      currentUserId == chatData['sellerId'];

  @override
  Widget build(BuildContext context) {
    final buyerId = chatData['buyerId'] as String? ?? '';
    final sellerId = chatData['sellerId'] as String? ?? '';
    final buyerConfirmed = chatData['buyerConfirmed'] as bool? ?? false;
    final sellerConfirmed = chatData['sellerConfirmed'] as bool? ?? false;
    final buyerRated = chatData['buyerRated'] as bool? ?? false;
    final sellerRated = chatData['sellerRated'] as bool? ?? false;

    final isBuyer = currentUserId == buyerId;
    final isSeller = currentUserId == sellerId;

    String message;
    Widget? actionButton;

    if (buyerConfirmed && sellerConfirmed) {
      if (!_isParticipant) {
        message = '取引完了';
      } else {
        final hasRated = isBuyer ? buyerRated : sellerRated;
        if (hasRated) {
          message = '評価済みです。ありがとうございました。';
        } else {
          message = '取引が完了しました。評価をお願いします。';
          actionButton = ElevatedButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => RatingScreen(chatRoomId: chatRoomId),
                ),
              );
              if (result == true && context.mounted) {
                AppToast.show(context, 'レビューを送信しました。');
              }
            },
            child: const Text('この取引を評価する'),
          );
        }
      }
    } else if (isBuyer) {
      if (sellerConfirmed) {
        message = '相手が確認しました。手渡し完了後、ボタンを押してください。';
      } else if (buyerConfirmed) {
        message = '相手の確認を待っています';
      } else {
        message = '手渡し完了後、ボタンを押してください。';
      }
      actionButton = ElevatedButton(
        onPressed: () => _showQrDialog(context),
        child: const Text('QRコードを表示'),
      );
    } else if (isSeller) {
      if (sellerConfirmed) {
        message = '相手の確認を待っています';
      } else if (buyerConfirmed) {
        message = '相手が確認しました。手渡し完了後、ボタンを押してください。';
      } else {
        message = '手渡し完了後、ボタンを押してください。';
      }
      actionButton = ElevatedButton(
        onPressed: () => _openScanner(context),
        child: const Text('QRコードをスキャン'),
      );
    } else {
      message = '取引参加者のみ詳細を確認できます。';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (actionButton != null) ...[
            const SizedBox(height: 8),
            actionButton,
          ],
        ],
      ),
    );
  }

  Future<void> _showQrDialog(BuildContext context) async {
    var received = false;
    var checked = false;
    var complete = false;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AppCustomInputDialog(
            title: '手渡し完了確認',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'QR完了後は取引完了として扱われます。商品状態に不安がある場合は、完了前に相手と相談してください。',
                  style: TextStyle(height: 1.5),
                ),
                CheckboxListTile(
                  value: received,
                  onChanged: (value) =>
                      setState(() => received = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('商品を受け取りました'),
                ),
                CheckboxListTile(
                  value: checked,
                  onChanged: (value) =>
                      setState(() => checked = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('状態を確認しました'),
                ),
                CheckboxListTile(
                  value: complete,
                  onChanged: (value) =>
                      setState(() => complete = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('問題がなければ取引を完了します'),
                ),
                if (received && checked && complete) ...[
                  const SizedBox(height: 8),
                  SizedBox.square(
                    dimension: 200,
                    child: QrImageView(
                      data: chatRoomId,
                      version: QrVersions.auto,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('閉じる'),
              ),
            ],
          );
        });
      },
    );
  }

  void _openScanner(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(expectedData: chatRoomId),
      ),
    );
  }
}
