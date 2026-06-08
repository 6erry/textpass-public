import 'package:flutter/material.dart';
import 'circle_member_list_screen.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/circle.dart';
import '../../services/circle_service.dart';
import '../../widgets/app_custom_input_dialog.dart';
import '../../widgets/app_selection_dialog.dart';
import '../add_book_screen.dart';
import 'edit_circle_profile_screen.dart';
import 'circle_detail_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class CircleOnboardingScreen extends StatefulWidget {
  const CircleOnboardingScreen({super.key});

  @override
  State<CircleOnboardingScreen> createState() => _CircleOnboardingScreenState();
}

class _CircleOnboardingScreenState extends State<CircleOnboardingScreen> {
  final _circleService = CircleService();
  final _nameController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final _displayIdController = TextEditingController();
  final _descController = TextEditingController();

  CircleCategory _selectedCategory = CircleCategory.other;
  bool _isLoading = true;
  Circle? _myCircle;

  @override
  void initState() {
    super.initState();
    _checkCircleStatus();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _inviteCodeController.dispose();
    _displayIdController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _checkCircleStatus() async {
    try {
      final circle = await _circleService.getUserCircle();
      if (mounted) {
        setState(() {
          _myCircle = circle;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createCircle() async {
    if (_nameController.text.isEmpty || _displayIdController.text.isEmpty) {
      AppToast.show(context, 'サークル名とIDは必須です');
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Check if display ID is available
      final existing =
          await _circleService.findCircleByDisplayId(_displayIdController.text);
      if (existing != null) {
        throw Exception('このIDは既に使用されています');
      }

      await _circleService.createCircle(
        name: _nameController.text,
        universityDomain: 'hokudai.ac.jp', // Fixed for MVP
        displayId: _displayIdController.text,
        category: _selectedCategory,
        description: _descController.text,
      );
      await _checkCircleStatus();
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'エラー: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _joinCircle() async {
    if (_inviteCodeController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await _circleService.joinCircle(_inviteCodeController.text);
      await _checkCircleStatus();
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'エラー: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_myCircle != null) {
      return _buildStatusScreen();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('サークル登録')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'イベントを投稿するには\nサークル登録が必要です',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.add_circle_outline, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('新しくサークルを作る',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildTextField(
                    controller: _nameController,
                    label: 'サークル名 *',
                    icon: Icons.group,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _displayIdController,
                    label: 'サークルID (英数字) *',
                    hint: '例: hokudai_keion',
                    icon: Icons.alternate_email,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9_]')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _selectCategory,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'カテゴリ',
                        prefixIcon:
                            const Icon(Icons.category, color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(_selectedCategory.label)),
                          const Icon(Icons.expand_more, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _descController,
                    label: '活動内容など',
                    icon: Icons.description,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _createCircle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'サークルを作成',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.login, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('招待コードで参加する',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildTextField(
                    controller: _inviteCodeController,
                    label: '招待コード (6桁)',
                    icon: Icons.vpn_key,
                    maxLength: 6,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _joinCircle,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side: const BorderSide(color: Colors.blue),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('サークルに参加',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.orange),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
    );
  }

  Widget _buildStatusScreen() {
    bool isActive = _myCircle!.status == 'active';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('サークル管理'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildDashboardHeader(isActive),
                  const SizedBox(height: 24),
                  if (isActive) _buildActionGrid(),
                  if (!isActive) _buildPendingState(),
                ],
              ),
            ),
          ),
          if (isActive) _buildTextbookCta(),
        ],
      ),
    );
  }

  Future<void> _selectCategory() async {
    final selected = await showAppSelectionDialog<CircleCategory>(
      context: context,
      title: 'カテゴリを選択',
      selectedValue: _selectedCategory,
      options: CircleCategory.values
          .map(
            (category) => AppSelectionOption(
              label: category.label,
              value: category,
              icon: Icons.category_outlined,
            ),
          )
          .toList(),
    );
    if (selected != null) {
      setState(() => _selectedCategory = selected);
    }
  }

  Widget _buildDashboardHeader(bool isActive) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CircleDetailScreen(circleId: _myCircle!.id),
                ),
              );
            },
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 72,
                    height: 72,
                    color: Colors.grey.shade100,
                    child: _myCircle!.iconUrl != null
                        ? Image.network(_myCircle!.iconUrl!, fit: BoxFit.cover)
                        : const Icon(Icons.groups_2_outlined,
                            size: 34, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _myCircle!.name,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                tooltip: 'サークルプロフィールを編集',
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          EditCircleProfileScreen(circle: _myCircle!),
                    ),
                  );
                  if (result == true) {
                    _checkCircleStatus();
                  }
                },
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      isActive ? Colors.green.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isActive ? '承認済み' : '申請中',
                  style: TextStyle(
                    color: isActive
                        ? Colors.green.shade800
                        : Colors.orange.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 1,
        mainAxisSpacing: 10,
        childAspectRatio: 5.2,
        children: [
          _buildActionCard(
            icon: Icons.home_work_outlined,
            label: 'サークルページ',
            color: Colors.orange,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CircleDetailScreen(circleId: _myCircle!.id),
                ),
              );
            },
          ),
          _buildActionCard(
            icon: Icons.event_note,
            label: 'イベント管理',
            color: Colors.blue,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CircleDetailScreen(circleId: _myCircle!.id),
                ),
              );
            },
          ),
          _buildActionCard(
            icon: Icons.person_add_alt,
            label: 'メンバー招待',
            color: Colors.green,
            onTap: _showInviteModal,
          ),
          _buildActionCard(
            icon: Icons.people_outline,
            label: 'メンバー確認',
            color: Colors.purple,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CircleMemberListScreen(circle: _myCircle!),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingState() {
    final remaining = (3 - _myCircle!.memberUids.length).clamp(0, 3);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.pending_actions, size: 36, color: Colors.orange),
          const SizedBox(height: 16),
          const Text(
            'サークル機能の有効化待ち',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            remaining == 0
                ? '管理者条件を満たしています。承認までお待ちください。'
                : 'メンバーがあと$remaining人参加すると、イベント作成などの機能を使えます。',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, height: 1.5),
          ),
          const SizedBox(height: 24),
          _buildInviteCard(),
        ],
      ),
    );
  }

  Widget _buildInviteCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          const Text('招待コード', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText(
            _myCircle!.inviteCode ?? '',
            style: const TextStyle(
                fontSize: 24, letterSpacing: 4, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('招待コードを共有'),
            onPressed: () {
              SharePlus.instance.share(
                ShareParams(
                  text:
                      '${_myCircle!.name}への招待\n招待コード: ${_myCircle!.inviteCode}',
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showInviteModal() {
    showDialog(
      context: context,
      builder: (context) => AppCustomInputDialog(
        title: 'メンバーを招待',
        icon: Icons.person_add_alt,
        content: _buildInviteCard(),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextbookCta() {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddBookScreen()),
            );
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, color: Colors.blueGrey),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '教科書を出品',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'サークルで使わなくなった教材を登録できます',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
