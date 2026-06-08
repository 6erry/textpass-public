import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/book.dart';
import 'book_detail_screen.dart';

import 'qr_scanner_screen.dart';
import 'review_screen.dart';
import '../services/report_service.dart';
import '../services/chat_service.dart';
import '../services/transaction_service.dart';
import '../utils/legal_notices.dart';

import '../widgets/app_custom_input_dialog.dart';
import 'package:textpass/utils/app_toast.dart';

class TransactionScreen extends StatefulWidget {
  const TransactionScreen({
    super.key,
    required this.chatRoomId,
    required this.book,
  });

  final String chatRoomId;
  final Book book;

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _navigateToBookDetail() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookDetailScreen(book: widget.book),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    if (user == null) {
      return const Scaffold(body: Center(child: Text('ログインが必要です')));
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('取引画面'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'cancel') {
                _cancelTransaction();
              } else if (value == 'report') {
                _showReportDialog();
              } else if (value == 'no_show') {
                _submitQuickTransactionReport('相手が来ない');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'cancel',
                child: Text('取引をキャンセルする', style: TextStyle(color: Colors.red)),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Text('通報する'),
              ),
              const PopupMenuItem(
                value: 'no_show',
                child: Text('相手が来ない'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat Interface
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .doc(widget.chatRoomId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                // If no messages, we still show the header (Empty state for messages only)
                // But with the new design, the header is Item 0 (or last item in reverse list).

                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  // Add 1 for the Header
                  itemCount: docs.length + 1,
                  itemBuilder: (context, index) {
                    // If we are at the end of the list (visual top), show Header
                    if (index == docs.length) {
                      return Column(
                        children: [
                          _buildHeader(user, theme),
                          const Divider(height: 1),
                          if (docs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 32),
                              child: Text('メッセージはまだありません。\n取引の相談をしましょう。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey)),
                            ),
                        ],
                      );
                    }

                    final data = docs[index].data();
                    final isMe = data['senderId'] == user.uid;
                    return _MessageBubble(
                      message: data['text'] ?? '',
                      isMe: isMe,
                      timestamp: data['createdAt'] as Timestamp?,
                    );
                  },
                );
              },
            ),
          ),

          // Message Input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'メッセージを入力',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    child: IconButton(
                      icon:
                          const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: () => _sendMessage(user.uid),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage(String userId) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    try {
      // Fetch chat room data to find peerUid
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .get();

      if (!chatDoc.exists) return;

      final data = chatDoc.data()!;
      final buyerId = data['buyerId'] as String;
      final sellerId = data['sellerId'] as String;
      final peerUid = userId == buyerId ? sellerId : buyerId;

      await ChatService().sendMessage(
        chatRoomId: widget.chatRoomId,
        text: text,
        peerUid: peerUid,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '送信に失敗しました');
      }
    }
  }

  Widget _buildHeader(User user, ThemeData theme) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('chat_rooms')
                .doc(widget.chatRoomId)
                .snapshots(),
            builder: (context, snapshot) {
              final chat = snapshot.data?.data() ?? {};
              final bookIds = List<String>.from(chat['bookIds'] ?? []);
              final isBundle = chat['isBundle'] == true && bookIds.length > 1;
              return InkWell(
                onTap: isBundle ? null : _navigateToBookDetail,
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        widget.book.imageUrls.isNotEmpty
                            ? widget.book.imageUrls.first
                            : '',
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.book, color: Colors.grey),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isBundle
                                ? 'まとめ買い ${bookIds.length}冊'
                                : widget.book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            isBundle
                                ? '合計 ¥${chat['totalPrice'] ?? chat['price'] ?? widget.book.price}'
                                : '¥${widget.book.price}',
                            style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        const CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.grey,
                          child:
                              Icon(Icons.person, size: 20, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text('相手', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Action Center (Status & QR)
          _TransactionStatusView(
            chatRoomId: widget.chatRoomId,
            currentUserId: user.uid,
            book: widget.book,
          ),
        ],
      ),
    );
  }

  Future<void> _showReportDialog() async {
    final reasons = [
      '禁止物の出品',
      '代理出品・転売の疑い',
      '不適切な内容',
      '大学公式と誤認させる表現',
      '迷惑行為',
      '詐欺・トラブル',
      'その他',
    ];

    final descriptionController = TextEditingController();
    String? selectedReason;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AppCustomInputDialog(
            title: '通報',
            icon: Icons.report_problem_outlined,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('通報の理由',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: reasons.map((r) {
                    return DropdownMenuItem(
                      value: r,
                      child: Text(r, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedReason = value);
                  },
                  hint: const Text('理由を選択してください'),
                ),
                const SizedBox(height: 16),
                const Text('詳細（任意）',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    hintText: '詳細を入力してください',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: selectedReason == null
                    ? null
                    : () async {
                        Navigator.pop(context);
                        final description = descriptionController.text;
                        final currentContext = context;
                        try {
                          final chatDoc = await FirebaseFirestore.instance
                              .collection('chat_rooms')
                              .doc(widget.chatRoomId)
                              .get();

                          if (!chatDoc.exists) return;

                          final data = chatDoc.data()!;
                          final currentUid =
                              FirebaseAuth.instance.currentUser!.uid;
                          final buyerId = data['buyerId'] as String;
                          final sellerId = data['sellerId'] as String;
                          final peerUid =
                              currentUid == buyerId ? sellerId : buyerId;

                          await ReportService().submitReport(
                            type: 'transaction',
                            reason: selectedReason!,
                            targetUserId: peerUid,
                            description: description,
                            transactionId: widget.chatRoomId,
                          );

                          if (!currentContext.mounted) return;
                          AppToast.show(currentContext, '通報を受け付けました');
                        } catch (e) {
                          if (!currentContext.mounted) return;
                          AppToast.show(currentContext, 'エラーが発生しました: $e');
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('送信'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitQuickTransactionReport(String reason) async {
    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .get();
      if (!chatDoc.exists) return;
      final data = chatDoc.data()!;
      final currentUid = FirebaseAuth.instance.currentUser!.uid;
      final buyerId = data['buyerId'] as String;
      final sellerId = data['sellerId'] as String;
      final peerUid = currentUid == buyerId ? sellerId : buyerId;
      await ReportService().submitReport(
        type: 'transaction',
        reason: reason,
        targetUserId: peerUid,
        description: '取引画面のクイック相談から送信',
        transactionId: widget.chatRoomId,
      );
      if (!mounted) return;
      AppToast.show(context, '運営への相談として記録しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '送信に失敗しました: $e');
    }
  }

  Future<void> _cancelTransaction() async {
    // Check if already completed
    final chatDoc = await FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.chatRoomId)
        .get();

    if (chatDoc.exists && chatDoc.data()?['status'] == 'completed') {
      if (!mounted) return;
      AppToast.show(context, '取引完了後はキャンセルできません');
      return;
    }

    if (!mounted) return;

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppCustomInputDialog(
        title: '取引のキャンセル申請',
        icon: Icons.cancel_outlined,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('取引のキャンセルを申請しますか？\n相手が同意すると、自動的に返金され、商品は「販売中」に戻ります。'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'キャンセル理由',
                hintText: '例: 商品の状態が説明と異なるため',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('いいえ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('申請する', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await TransactionService().requestCancellation(
        chatRoomId: widget.chatRoomId,
        reason: reasonController.text,
      );

      if (!mounted) return;
      AppToast.show(context, 'キャンセル申請を送信しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '申請に失敗しました: $e');
    }
  }
}

class _TransactionStatusView extends StatefulWidget {
  const _TransactionStatusView({
    required this.chatRoomId,
    required this.currentUserId,
    required this.book,
  });

  final String chatRoomId;
  final String currentUserId;
  final Book book;

  @override
  State<_TransactionStatusView> createState() => _TransactionStatusViewState();
}

class _TransactionStatusViewState extends State<_TransactionStatusView> {
  final _placeController = TextEditingController();
  DateTime? _selectedDate;

  @override
  void dispose() {
    _placeController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null) return;

    if (!mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;

    setState(() {
      _selectedDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submitProposal() async {
    if (_placeController.text.isEmpty || _selectedDate == null) {
      AppToast.show(context, '場所と日時を入力してください');
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .update({
        'meetingPlace': _placeController.text,
        'meetingTime': Timestamp.fromDate(_selectedDate!),
        'meetingStatus': 'pending',
        'proposerId': widget.currentUserId,
      });
      if (!mounted) return;
      AppToast.show(context, '提案を送信しました');
    } catch (e) {
      AppToast.show(context, 'エラーが発生しました: $e');
    }
  }

  Future<void> _respondToProposal(bool accept) async {
    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .update({
        'meetingStatus': accept ? 'agreed' : 'rejected',
        if (!accept) ...{
          'meetingPlace': FieldValue.delete(),
          'meetingTime': FieldValue.delete(),
          'proposerId': FieldValue.delete(),
        }
      });
      if (!mounted) return;
      AppToast.show(context, accept ? '提案を承認しました' : '提案を却下しました');
    } catch (e) {
      AppToast.show(context, 'エラーが発生しました: $e');
    }
  }

  Future<void> _cancelProposal() async {
    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .update({
        'meetingStatus': 'rejected',
        'meetingPlace': FieldValue.delete(),
        'meetingTime': FieldValue.delete(),
        'proposerId': FieldValue.delete(),
      });
      if (!mounted) return;
      AppToast.show(context, '提案を取り下げました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'エラーが発生しました: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final status = data['status'] as String? ?? 'paid';
        final meetingStatus = data['meetingStatus'] as String? ?? 'initial';
        final isBuyer = widget.currentUserId == data['buyerId'];
        final isSeller = widget.currentUserId == data['sellerId'];

        if (status == 'cancelled') {
          return _buildCancelledView();
        }

        if (status == 'completed') {
          return _buildCompletedView(
              context, isBuyer ? data['sellerId'] : data['buyerId']);
        }

        // Paid / Trading status
        return Column(
          children: [
            if (data['cancellationStatus'] == 'requesting')
              _buildCancellationRequestBanner(data, isBuyer, isSeller),
            _buildPaymentStatusView(),
            const SizedBox(height: 16),
            if (meetingStatus == 'agreed')
              _buildAgreedView(data, isBuyer, isSeller)
            else if (meetingStatus == 'pending' && data['proposerId'] != null)
              _buildPendingView(data)
            else
              _buildProposalForm(),
          ],
        );
      },
    );
  }

  Widget _buildCancellationRequestBanner(
      Map<String, dynamic> data, bool isBuyer, bool isSeller) {
    final requesterId = data['cancellationRequesterId'] as String?;
    final reason = data['cancellationReason'] as String? ?? '理由なし';
    final isMeRequester = requesterId == widget.currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                isMeRequester ? 'キャンセル申請中です' : 'キャンセル申請が届いています',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('理由: $reason'),
          if (!isMeRequester) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _rejectCancellation,
                    child: const Text('拒否'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (data['paymentIntentId'] == null) {
                        AppToast.show(context, '返金に必要な情報が見つかりません');
                        return;
                      }
                      _approveCancellation();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('承認して返金'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _approveCancellation() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      await TransactionService().approveCancellation(
        chatRoomId: widget.chatRoomId,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.show(context, 'キャンセルを承認し、返金処理を行いました');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.show(context, '承認に失敗しました: $e');
    }
  }

  Future<void> _rejectCancellation() async {
    try {
      await TransactionService().rejectCancellation(widget.chatRoomId);
      if (!mounted) return;
      AppToast.show(context, 'キャンセル申請を拒否しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '拒否に失敗しました: $e');
    }
  }

  Widget _buildCancelledView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        children: [
          Icon(Icons.cancel, color: Colors.grey, size: 40),
          SizedBox(height: 8),
          Text(
            'この取引はキャンセルされました',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStatusView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: const Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.blue, size: 24),
              SizedBox(width: 8),
              Text('支払いが完了しています',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProposalForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('受け渡し場所と日時を提案',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          const InformationCard(
            title: '受け渡しについて',
            message: handoverSafetyNotice,
            icon: Icons.place_outlined,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _placeController,
            decoration: const InputDecoration(
              labelText: '場所メモ',
              hintText: '例: 人目のある場所で相談',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDateTime,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: '日時',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(
                _selectedDate == null
                    ? '日時を選択'
                    : DateFormat('MM/dd HH:mm').format(_selectedDate!),
                style: TextStyle(
                  color: _selectedDate == null ? Colors.grey : Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitProposal,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
              ),
              child: const Text('提案する'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingView(Map<String, dynamic> data) {
    final isProposer = data['proposerId'] == widget.currentUserId;
    final place = data['meetingPlace'] ?? '';
    final time = (data['meetingTime'] as Timestamp?)?.toDate();
    final timeStr =
        time != null ? DateFormat('MM/dd HH:mm').format(time) : '未定';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        children: [
          Text(isProposer ? '相手の承認待ちです' : '受け渡し条件の提案が届きました',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                  fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on, size: 20, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(place, style: const TextStyle(fontSize: 16))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.access_time, size: 20, color: Colors.grey),
              const SizedBox(width: 8),
              Text(timeStr, style: const TextStyle(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          if (isProposer)
            OutlinedButton(
              onPressed: _cancelProposal,
              child: const Text('提案を取り下げる'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _respondToProposal(false),
                    child: const Text('却下'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _respondToProposal(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('承認'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAgreedView(
      Map<String, dynamic> data, bool isBuyer, bool isSeller) {
    final place = data['meetingPlace'] ?? '';
    final time = (data['meetingTime'] as Timestamp?)?.toDate();
    final timeStr =
        time != null ? DateFormat('MM/dd HH:mm').format(time) : '未定';

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            children: [
              Text('受け渡し条件が決定しました',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                      fontSize: 16)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(place, style: const TextStyle(fontSize: 16))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(timeStr, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (isBuyer)
          ElevatedButton.icon(
            onPressed: () => _showQrDialog(context),
            icon: const Icon(Icons.qr_code, size: 20),
            label: const Text('受取確認 (QR表示)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              minimumSize: const Size(double.infinity, 50),
            ),
          )
        else if (isSeller)
          ElevatedButton.icon(
            onPressed: () => _openScanner(context),
            icon: const Icon(Icons.qr_code_scanner, size: 20),
            label: const Text('受渡確認 (QRスキャン)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
      ],
    );
  }

  Widget _buildCompletedView(BuildContext context, String partnerId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('transactionId', isEqualTo: widget.chatRoomId)
          .where('reviewerId', isEqualTo: widget.currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        final hasReviewed = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.grey, size: 48),
              const SizedBox(height: 12),
              const Text(
                '取引完了',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'この取引は完了しました。\nご利用ありがとうございました。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              if (!hasReviewed)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReviewScreen(
                            transactionId: widget.chatRoomId,
                            revieweeId: partnerId,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('取引相手を評価する'),
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 16, color: Colors.orange),
                      SizedBox(width: 4),
                      Text(
                        '評価済み',
                        style: TextStyle(
                            color: Colors.orange, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
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
            title: '受取確認QR',
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
                      data: widget.chatRoomId,
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

  void _openScanner(BuildContext context) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(expectedData: widget.chatRoomId),
      ),
    );

    if (result == true && context.mounted) {
      // QR scan successful
      final batch = FirebaseFirestore.instance.batch();

      final chatRef = FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId);

      // Need to fetch chat room data to get buyer and seller IDs for the reviews
      final chatDataRaw = await chatRef.get();
      if (!chatDataRaw.exists) return; // Edge case safeguard
      final chatData = chatDataRaw.data()!;
      final buyerId = chatData['buyerId'] as String;
      final sellerId = chatData['sellerId'] as String;

      batch.update(chatRef, {
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'pendingReviews': [buyerId, sellerId],
        'bookExists': true,
      });

      final currentContext = context;
      await batch.commit();

      if (!currentContext.mounted) return;
      AppToast.show(currentContext, '受渡が完了しました！取引完了です。');
    }
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.timestamp,
  });

  final String message;
  final bool isMe;
  final Timestamp? timestamp;

  @override
  Widget build(BuildContext context) {
    final timeStr = timestamp != null
        ? DateFormat('HH:mm').format(timestamp!.toDate())
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            // Partner Avatar Stub
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey,
              child: Icon(Icons.person, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe ? Colors.red.shade50 : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isMe
                        ? const Radius.circular(16)
                        : const Radius.circular(4),
                    bottomRight: isMe
                        ? const Radius.circular(4)
                        : const Radius.circular(16),
                  ),
                  border: Border.all(
                      color: isMe ? Colors.red.shade100 : Colors.grey.shade200),
                ),
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                timeStr,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
