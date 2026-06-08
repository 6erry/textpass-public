import 'dart:io';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'main_screen.dart';
import 'package:textpass/utils/app_toast.dart';
import 'package:textpass/services/remote_config_service.dart';
import 'package:textpass/widgets/auth_gate.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  // New fields
  final TextEditingController _realNameKanjiController =
      TextEditingController();
  final TextEditingController _realNameKanaController = TextEditingController();
  final TextEditingController _universityEmailController =
      TextEditingController(); // For social login users
  final TextEditingController _contactEmailController = TextEditingController();
  bool _useUniversityEmailForContact = true;

  DateTime? _birthDate;

  String? _selectedFaculty;
  final List<String> _faculties = [
    '文学部',
    '法学部',
    '経済学部',
    '教育学部',
    '理学部',
    '医学部',
    '歯学部',
    '薬学部',
    '工学部',
    '農学部',
    '獣医学部',
    '水産学部',
    'その他',
  ];

  String? _selectedGrade;
  final List<String> _grades = [
    '学部1年',
    '学部2年',
    '学部3年',
    '学部4年',
    '修士1年',
    '修士2年',
    '博士課程',
    'その他',
  ];

  File? _imageFile;
  bool _isSaving = false;
  // bool _isVerificationDialogOpen = false; // Removed: Legacy polling dialog no longer used
  String? _universityId;

  // --- OTP Verification State ---
  final TextEditingController _otpController = TextEditingController();
  bool _isOtpSent = false;
  String? _sentOtpEmail;
  String? _sentOtpUniversityId;
  // ------------------------------

  /// If true, the user is coming from Social Login and needs to input their university email.
  bool _needsUniversityVerification = false;
  bool _isFreshmanProvisional = false;
  bool _isStudentVerified = false;

  Timer? _accountCheckTimer;

  @override
  void initState() {
    super.initState();
    _fetchUniversityId();
    _startAccountCheck();
  }

  void _startAccountCheck() {
    // Initial check
    _checkAccountStatus();
    // Periodic check (e.g. every 10 seconds)
    _accountCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkAccountStatus();
    });
  }

  Future<void> _checkAccountStatus() async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // // print('ProfileSetup: Periodic account check running...');
    // Uncommenting this would flood logs, but user wants to know if it's running.
    // I'll add it once for now. No, user cannot see my internal logs easily unless I ask.
    // I will enable it so I can ask user to check or I can check via 'read_terminal' if I could (I can't read user's terminal in real time easily).
    // Actually, I can use `AppToast` for DEBUG? No.
    // I will add the print.
    // print('ProfileSetup: Periodic account check for ${user.uid}...');

    try {
      // NOTE: Do NOT call user.reload() here. It triggers AuthGate rebuilds via userChanges(),
      // which destroys this widget and clears user input.

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));

      if (!doc.exists) {
        // print('ProfileSetup: User doc does not exist (server). Force logout.');
        if (mounted) {
          _handleAuthError('アカウント情報が見つかりません。\n再ログインしてください。');
        }
      }
    } catch (e) {
      // print('ProfileSetup: Account check error: $e');
      if (e is FirebaseException && e.code == 'permission-denied') {
        // print(
        //     'ProfileSetup: Permission denied (likely deleted). Force logout.');
        if (mounted) {
          _handleAuthError('アカウント情報が見つかりません(Error)。\n再ログインしてください。');
        }
      }
    }
  }

  Future<void> _handleAuthError(String message) async {
    // UI Feedback
    if (mounted) {
      AppToast.showError(context, message,
          duration: const Duration(seconds: 4));

      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _fetchUniversityId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Check Firestore first
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data != null && data['universityId'] != null) {
        final verificationStatus = data['verificationStatus'] as String?;
        final isFreshmanProvisional =
            verificationStatus == 'provisional_freshman' ||
                data['isFreshmanProvisional'] == true;
        final isStudentVerified = data['isStudentVerified'] as bool? ?? false;
        if (mounted) {
          setState(() {
            _universityId = data['universityId'];
            _isFreshmanProvisional = isFreshmanProvisional;
            _isStudentVerified = isStudentVerified;
            if (isFreshmanProvisional && !isStudentVerified) {
              _needsUniversityVerification = false;
              _useUniversityEmailForContact = false;
              _contactEmailController.text =
                  data['contactEmail'] as String? ?? user.email ?? '';
            }
          });
        }
        return;
      }
    } catch (e) {
      // print('ProfileSetupScreen: fetch error $e');
      // If error occurs here, it might be permission denied or network.
      // We don't necessarily logout unless it is strict.
      // But _checkAccountStatus handles strict existence.
    }

    // 2. Derive from email if not in Firestore (Standard Email Login)
    final email = user.email;
    if (email != null) {
      if (!mounted) {
        return; // FIX: Ensure widget is mounted before accessing controllers
      }
      // PREFILL Contact Email logic
      // If Firestore didn't have contactEmail (new user), use auth email by default
      if (_contactEmailController.text.isEmpty) {
        // If social login (user.email is gmail etc), prefill contactEmail.
        // If standard login (user.email is ac.jp), prefill too, but checkbox will override?
        // User wants checkbox: "Notify to university email".
        // If checked, contactEmail is disabled and overridden by univ email on save.
        // Initial state:
        // For Social Login: user.email is Gmail. Checkbox should default to FALSE? Or user decides.
        // For Standard Login: user.email is Univ Email. Checkbox defaults to TRUE?
        // Let's decide based on domain.

        final domain = email.split('@').last;
        final approvedDomains = RemoteConfigService().getApprovedDomains();
        bool isUnivEmail = false;
        for (final approved in approvedDomains) {
          if (domain.endsWith(approved)) {
            isUnivEmail = true;
            break;
          }
        }

        if (isUnivEmail) {
          // Standard Email Login case
          if (mounted) {
            setState(() {
              _useUniversityEmailForContact = true;
              _contactEmailController.text = email; // Visual help
            });
          }
        } else {
          // Social Login case
          if (mounted) {
            setState(() {
              _useUniversityEmailForContact = false;
              _contactEmailController.text = email;
            });
          }
        }
      }

      final domain = email.split('@').last;

      final approvedDomains = RemoteConfigService().getApprovedDomains();

      bool isValidDomain = false;
      String? matchedDomain;

      for (final approved in approvedDomains) {
        if (domain.endsWith(approved)) {
          isValidDomain = true;
          matchedDomain = approved;
          break;
        }
      }

      if (isValidDomain) {
        if (mounted) {
          setState(() {
            _universityId = matchedDomain;
          });
        }
      } else {
        // Social Login Case
        if (mounted) {
          setState(() {
            _needsUniversityVerification = true;
            _universityId = null;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _accountCheckTimer?.cancel();
    _nicknameController.dispose();
    _departmentController.dispose();
    _realNameKanjiController.dispose();
    _realNameKanaController.dispose();
    _universityEmailController.dispose();
    _contactEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール設定'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _isSaving ? null : _pickImage,
                child: CircleAvatar(
                  radius: 60,
                  backgroundImage:
                      _imageFile != null ? FileImage(_imageFile!) : null,
                  child: _imageFile == null
                      ? const Icon(Icons.person, size: 60)
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              const Text('プロフィール画像', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              TextField(
                controller: _nicknameController,
                decoration: InputDecoration(
                  labelText: 'ニックネーム',
                  helperText: 'アプリ内で表示される名前です',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 16),
              // --- Contact Email Section ---
              TextField(
                controller: _contactEmailController,
                enabled: !_useUniversityEmailForContact,
                decoration: InputDecoration(
                  labelText: '連絡用メールアドレス',
                  helperText: '取引や運営からの通知が届きます',
                  filled: true,
                  fillColor: _useUniversityEmailForContact
                      ? Colors.grey.shade200
                      : Colors.grey.shade100,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  '大学用メールアドレスに通知する',
                  style: TextStyle(fontSize: 14),
                ),
                value: _useUniversityEmailForContact,
                onChanged: (value) {
                  setState(() {
                    _useUniversityEmailForContact = value ?? false;
                    if (_useUniversityEmailForContact) {
                      // Logic handled at save time, but maybe clear or set text?
                      // If university email is known, we could set it.
                      // If verification is needed, we don't know it yet fully (input controller).
                      // We'll handle exact value at save. Here just toggle UI.
                    }
                  });
                },
              ),
              const SizedBox(height: 16),

              // --- Social Login Support ---
              // Show if verification is needed OR if it was done (universityId exists but not full login)
              // Actually, simply: if not using university email logic (standard logic is handled at top),
              // but we want to show this section for Social Login users.
              // Logic: If _needsUniversityVerification was true initially, we keep showing this.
              // OR logic: If user is verified but not Univ Login (Social Login), show it as disabled.
              if (!_isFreshmanProvisional &&
                  (_needsUniversityVerification ||
                      (_universityId != null && _isStudentVerified))) ...[
                TextField(
                  controller: _universityEmailController,
                  enabled: !_isOtpSent &&
                      _universityId == null, // Disable if sent or Verified
                  decoration: InputDecoration(
                    labelText: '大学メールアドレス',
                    helperText: _universityId != null
                        ? '認証済み'
                        : '在学確認のため、大学のメールアドレスを入力してください',
                    helperMaxLines: 3,
                    filled: true,
                    fillColor: (_universityId != null)
                        ? Colors.grey.shade200
                        : Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
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
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),

                // Show Send Button only if NOT verified yet
                if (_universityId == null) ...[
                  if (!_isOtpSent) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _sendOtp,
                        icon: const Icon(Icons.send),
                        label: const Text('認証コードを送信'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        '※認証コードが記載されたメールが送信されます。',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ] else ...[
                    // OTP Input Section
                    TextField(
                      controller: _otpController,
                      decoration: InputDecoration(
                        labelText: '認証コード (6桁)',
                        helperText: 'メールに記載された数字を入力してください',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
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
                          borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _verifyOtp,
                        icon: const Icon(Icons.check_circle),
                        label: const Text('認証する'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isOtpSent = false;
                        });
                      },
                      child: const Text('メールアドレスを修正する'),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
              ],
              // --- New Fields (Private) ---
              TextField(
                controller: _realNameKanjiController,
// ... (rest is unchanged until _pickImage) ...

                decoration: InputDecoration(
                  labelText: '氏名（漢字）',
                  helperText: '非公開・本人確認用（例：北大 太郎）',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _realNameKanaController,
                decoration: InputDecoration(
                  labelText: '氏名（カナ）',
                  helperText: '非公開・本人確認用（例：ホクダイ タロウ）',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _pickBirthDate,
                child: AbsorbPointer(
                  child: TextField(
                    controller: TextEditingController(
                      text: _birthDate == null
                          ? ''
                          : '${_birthDate!.year}/${_birthDate!.month}/${_birthDate!.day}',
                    ),
                    decoration: InputDecoration(
                      labelText: '生年月日',
                      helperText: '非公開・本人確認用',
                      suffixIcon: const Icon(Icons.calendar_today),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
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
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // --- Existing Fields ---
              DropdownButtonFormField<String>(
                initialValue: _selectedFaculty,
                decoration: InputDecoration(
                  labelText: '学部',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                items: _faculties.map((faculty) {
                  return DropdownMenuItem(
                    value: faculty,
                    child: Text(faculty),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedFaculty = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _departmentController,
                decoration: InputDecoration(
                  labelText: '学科',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedGrade,
                decoration: InputDecoration(
                  labelText: '学年',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                items: _grades.map((grade) {
                  return DropdownMenuItem(
                    value: grade,
                    child: Text(grade),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedGrade = value;
                  });
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'はじめる',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initialDate = DateTime(now.year - 18, 1, 1); // Approx 18 years old
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: '生年月日を選択',
      locale: const Locale('ja', 'JP'),
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() {
      _imageFile = File(pickedFile.path);
    });
  }

  Future<void> _sendOtp() async {
    final universityEmailInput =
        _universityEmailController.text.trim().toLowerCase();

    if (universityEmailInput.isEmpty) {
      if (mounted) _showSnackBar('大学メールアドレスを入力してください。');
      return;
    }

    final domain = universityEmailInput.split('@').last;
    final approvedDomains = RemoteConfigService().getApprovedDomains();

    bool isValidDomain = false;
    String? matchedDomain; // Capture matching domain
    for (final approved in approvedDomains) {
      if (domain.endsWith(approved)) {
        isValidDomain = true;
        matchedDomain = approved; // Capture
        break;
      }
    }

    if (!isValidDomain) {
      if (mounted) _showSnackBar('この大学ドメインは許可されていません。');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFunctions.instance.httpsCallable('sendOtp').call({
        'email': universityEmailInput,
        'purpose': 'student',
        'universityId': matchedDomain, // Save normalized ID (root domain)
      });

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _isOtpSent = true;
        _sentOtpEmail = universityEmailInput;
        _sentOtpUniversityId = matchedDomain;
      });
      // Using AppToast if possible, or local helper
      if (mounted) _showSnackBar('認証メールを送信しました。コードを入力してください。');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        _showSnackBar('エラーが発生しました: $e');
      }
    }
  }

  Future<void> _verifyOtp() async {
    final inputCode = _otpController.text.trim();
    if (inputCode.length != 6) {
      if (mounted) _showSnackBar('6桁のコードを入力してください。');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final targetEmail = _sentOtpEmail;
      final normalizedUniversityId = _sentOtpUniversityId;
      if (targetEmail == null || normalizedUniversityId == null) {
        throw Exception('認証データが見つかりません。再送信してください。');
      }
      if (_universityEmailController.text.trim().toLowerCase() != targetEmail) {
        throw Exception('メールアドレスが一致しません。最初からやり直してください。');
      }

      await FirebaseFunctions.instance.httpsCallable('verifyOtp').call({
        'email': targetEmail,
        'code': inputCode,
        'purpose': 'student',
        'universityId': normalizedUniversityId,
      });

      final domain = normalizedUniversityId;

      if (mounted) {
        setState(() {
          _isSaving = false;
          _needsUniversityVerification = false; // Hides the verification UI
          _universityId = domain;
        });
        _showSnackBar('大学メール認証に成功しました！残りの項目を入力して完了してください。');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        var msg = e.toString();
        if (msg.startsWith('Exception: ')) msg = msg.substring(11);
        _showSnackBar(msg);
      }
    }
  }

  Future<void> _submit() async {
    // Check if verification is still needed
    if (_needsUniversityVerification) {
      _showSnackBar('大学メールアドレスの認証を完了させてください。');
      return;
    }

    final nickname = _nicknameController.text.trim();
    final department = _departmentController.text.trim();
    final realNameKanji = _realNameKanjiController.text.trim();
    final realNameKana = _realNameKanaController.text.trim();

    if (nickname.isEmpty) {
      _showSnackBar('ニックネームを入力してください。');
      return;
    }

    // --- Private Info Fields ---
    if (realNameKanji.isEmpty) {
      _showSnackBar('氏名（漢字）を入力してください。');
      return;
    }
    if (realNameKana.isEmpty) {
      _showSnackBar('氏名（カナ）を入力してください。');
      return;
    }
    if (_birthDate == null) {
      _showSnackBar('生年月日を選択してください。');
      return;
    }

    if (_selectedFaculty == null) {
      _showSnackBar('学部を選択してください。');
      return;
    }
    if (department.isEmpty) {
      _showSnackBar('学科を入力してください。');
      return;
    }
    if (_selectedGrade == null) {
      _showSnackBar('学年を選択してください。');
      return;
    }

    // --- Contact Email Validation ---
    if (!_useUniversityEmailForContact &&
        _contactEmailController.text.trim().isEmpty) {
      _showSnackBar('連絡用メールアドレスを入力してください。');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('ログインを確認してください。');
      return;
    }

    // University ID Check
    // Reuse logic from initState: if user.email is valid, _universityId should be set or correctable.
    if (_universityId == null) {
      await _fetchUniversityId();
      if (_universityId == null) {
        _showSnackBar('大学情報の確認に失敗しました。');
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    try {
      String? photoUrl;
      if (_imageFile != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('profile_images')
            .child('${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(_imageFile!);
        photoUrl = await ref.getDownloadURL();
      }

      await user.updateDisplayName(nickname);
      if (photoUrl != null) {
        await user.updatePhotoURL(photoUrl);
      }
      // Note: reload() might be needed to reflect changes locally, but usually updateDisplayName updates the object.
      // await user.reload();

      // Determine correct emails
      // universityEmail:
      // - Social Login: Was set during OTP verification (already in Firestore, but we can preserve it or use local var if we tracked it).
      // - Email Login: user.email (since it's ac.jp).
      // Logic: If _universityEmailController was used (Social), we might not have it in a var easily unless we fetched it.
      // But wait, _verifyOtp saves it to proper field. We don't need to re-save it if it's already there?
      // Standard login: user.email is the university email. So we SHOULD save it as universityEmail just in case.

      // But if social login, user.email is gmail.
      // We must avoid overwriting universityEmail with gmail.
      // We can check domain again.
      final domain = user.email!.split('@').last;
      final approvedDomains = RemoteConfigService().getApprovedDomains();
      bool isUnivEmailLogin = false;
      for (final approved in approvedDomains) {
        if (domain.endsWith(approved)) {
          isUnivEmailLogin = true;
          break;
        }
      }

      String? finalUnivEmail;
      if (isUnivEmailLogin) {
        finalUnivEmail = user.email;
      } else {
        // Social Login -> universityEmail should already be set in Firestore by _verifyOtp or previous sessions.
        // We shouldn't overwrite it with null or gmail here.
        // We can leave it alone (merge will preserve) OR fetching it would be safer.
        // However, if this is strict "First Setup", we might want to ensure it's set?
        // _verifyOtp sets 'universityEmail'. So let's NOT touch 'universityEmail' in this set() call for Social Login users,
        // to avoid accidental overwrite.
        // Or better: validUnivEmail variable.
      }

      // Contact Email
      String finalContactEmail;
      if (_useUniversityEmailForContact) {
        // If Standard Login: use user.email
        // If Social Login: We need the Verified University Email.
        // We don't have it easily in a variable here if we didn't fetch it explicitly in _submit.
        // BUT, for Social Login, "Notify to University Email" presumably means the one they JUST verified.
        // Which is in _universityEmailController.text (if they just verified)?
        // Or if they came back later?
        // _universityEmailController only shows if _needsUniversityVerification was true.

        if (isUnivEmailLogin) {
          finalContactEmail = user.email!;
        } else {
          // Social Login
          // If they just verified, it's in logic somewhere?
          // Actually, if they checked "Use Univ Email", they expect messages to go to the ac.jp address.
          // We really need that address.
          // _verifyOtp saves it to Firestore.
          // Let's rely on _universityEmailController logic if visible?
          // If not visible (already verified in previous session or fetched in initState),
          // we might not have the string value in memory!
          // `_fetchUniversityId` only fetches ID, not email.

          // CRITICAL fix: We need to ensure we know the university email if we are to use it as contact email.
          // But actually, we can just save `contactEmail` same as `universityEmail` in the data map?
          // If we don't have `universityEmail` value inhand, we can't save it to `contactEmail` field.

          // If `_universityEmailController` is populated (because we just verified), use it.
          if (_universityEmailController.text.isNotEmpty) {
            finalContactEmail = _universityEmailController.text.trim();
          } else {
            // If controller empty, maybe we fetched verification data before?
            // Or maybe we should fetch it now to be safe.
            final doc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
            finalUnivEmail = doc.data()?['universityEmail'];
            finalContactEmail = finalUnivEmail ??
                user.email!; // Fallback (shouldn't happen if logic flows right)
          }
        }
      } else {
        finalContactEmail = _contactEmailController.text.trim();
      }

      final data = {
        'nickname': nickname, // Using 'nickname' field as per AppUser model
        'faculty': _selectedFaculty,
        'department': department,
        'grade': _selectedGrade,
        'universityId': _universityId,
        'isProfileComplete': true,
        'createdAt': FieldValue.serverTimestamp(), // Ensure createdAt exists
        // Private fields
        'realNameKanji': realNameKanji,
        'realNameKana': realNameKana,
        'birthDate': Timestamp.fromDate(_birthDate!),

        'contactEmail': finalContactEmail,
      };

      // Only set universityEmail if we are Standard Login (to be safe/explicit)
      if (isUnivEmailLogin) {
        data['universityEmail'] = user.email!;
      }

      if (photoUrl != null) {
        data['photoUrl'] =
            photoUrl; // Using 'photoUrl' field as per AppUser model
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            data,
            SetOptions(merge: true),
          );

      if (!mounted) return;

      // Force navigation to MainScreen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      _showSnackBar('プロフィール保存に失敗しました: $e');
    }
  }

  void _showSnackBar(String message) {
    AppToast.show(context, message);
  }
}
