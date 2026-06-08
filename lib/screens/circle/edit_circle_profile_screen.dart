import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../models/circle.dart';
import '../../services/circle_service.dart';
import 'package:textpass/utils/app_toast.dart';

class EditCircleProfileScreen extends StatefulWidget {
  final Circle circle;

  const EditCircleProfileScreen({super.key, required this.circle});

  @override
  State<EditCircleProfileScreen> createState() =>
      _EditCircleProfileScreenState();
}

class _EditCircleProfileScreenState extends State<EditCircleProfileScreen> {
  final _circleService = CircleService();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _descController;
  late TextEditingController _activityDaysController;
  late TextEditingController _placeController;
  late TextEditingController _memberCountController;
  late TextEditingController _genderRatioController;
  late TextEditingController _websiteUrlController;
  late TextEditingController _xIdController;
  late TextEditingController _instagramIdController;

  File? _imageFile;
  final _picker = ImagePicker();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController(text: widget.circle.description);
    // Convert List<String> to comma separated string for editing
    _activityDaysController =
        TextEditingController(text: widget.circle.activityDays.join(', '));
    _placeController = TextEditingController(text: widget.circle.place);
    _memberCountController =
        TextEditingController(text: widget.circle.memberCount);
    _genderRatioController =
        TextEditingController(text: widget.circle.genderRatio);
    _websiteUrlController =
        TextEditingController(text: widget.circle.websiteUrl);
    _xIdController = TextEditingController(text: widget.circle.xId);
    _instagramIdController =
        TextEditingController(text: widget.circle.instagramId);
  }

  @override
  void dispose() {
    _descController.dispose();
    _activityDaysController.dispose();
    _placeController.dispose();
    _memberCountController.dispose();
    _genderRatioController.dispose();
    _websiteUrlController.dispose();
    _xIdController.dispose();
    _instagramIdController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      String? iconUrl = widget.circle.iconUrl;

      if (_imageFile != null) {
        iconUrl = await _circleService.uploadCircleIcon(
            _imageFile!, widget.circle.id);
      }

      // Convert comma separated string back to List<String>
      List<String> activityDays = _activityDaysController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      await _circleService.updateCircleProfile(
        widget.circle.id,
        description: _descController.text,
        activityDays: activityDays,
        place: _placeController.text,
        memberCount: _memberCountController.text,
        genderRatio: _genderRatioController.text,
        websiteUrl: _websiteUrlController.text.isEmpty
            ? null
            : _websiteUrlController.text,
        iconUrl: iconUrl,
        xId: _xIdController.text.isEmpty ? null : _xIdController.text,
        instagramId: _instagramIdController.text.isEmpty
            ? null
            : _instagramIdController.text,
      );

      if (mounted) {
        AppToast.show(context, 'プロフィールを更新しました');
        Navigator.pop(context, true); // Return true to indicate update
      }
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('プロフィール編集',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeaderImage(),
                    const SizedBox(height: 32),
                    _buildSectionTitle('紹介文'),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _descController,
                      label: 'サークルの紹介文',
                      icon: Icons.description,
                      maxLines: 5,
                      hint: 'サークルの活動内容や雰囲気を詳しく書きましょう',
                    ),
                    const SizedBox(height: 32),
                    _buildSectionTitle('基本データ'),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _activityDaysController,
                      label: '活動日',
                      icon: Icons.calendar_today,
                      hint: '例: 毎週月曜, 毎週木曜',
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      controller: _placeController,
                      label: '活動場所',
                      icon: Icons.place,
                      hint: '例: サークル会館 201',
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _memberCountController,
                            label: '構成人数',
                            icon: Icons.people,
                            hint: '例: 50名',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _genderRatioController,
                            label: '男女比',
                            icon: Icons.wc,
                            hint: '例: 男6 : 女4',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      controller: _websiteUrlController,
                      label: 'リンク',
                      icon: Icons.link,
                      hint: '公式サイトやSNSのURL',
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('SNS (IDを入力)'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _xIdController,
                            label: 'X (Twitter)',
                            icon: Icons.alternate_email,
                            hint: '@なしで入力',
                            prefixText: '@',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _instagramIdController,
                            label: 'Instagram',
                            icon: Icons.camera_alt_outlined,
                            hint: 'IDのみ入力',
                            prefixText: '@',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange, // Main color
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '保存して更新する',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeaderImage() {
    return Center(
      child: GestureDetector(
        onTap: _pickImage,
        child: Stack(
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: _imageFile != null
                  ? FileImage(_imageFile!)
                  : (widget.circle.iconUrl != null
                      ? NetworkImage(widget.circle.iconUrl!) as ImageProvider
                      : null),
              child: (_imageFile == null && widget.circle.iconUrl == null)
                  ? Icon(Icons.groups, size: 60, color: Colors.grey.shade400)
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.camera_alt, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    String? hint,
    TextInputType? keyboardType,
    String? prefixText,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.orange, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        alignLabelWithHint: maxLines > 1,
      ),
      validator: (value) {
        // Optional validation logic if needed
        return null;
      },
    );
  }
}
