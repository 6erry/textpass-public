import 'package:flutter/material.dart';

class AppToast {
  /// 一般的なメッセージを表示（青/グレー系）
  static void show(BuildContext context, String message, {Duration? duration}) {
    _showToast(context, message, type: _ToastType.info, duration: duration);
  }

  /// 成功メッセージを表示（緑系）
  static void showSuccess(BuildContext context, String message,
      {Duration? duration}) {
    _showToast(context, message, type: _ToastType.success, duration: duration);
  }

  /// エラーメッセージを表示（赤系）
  static void showError(BuildContext context, String message,
      {Duration? duration}) {
    _showToast(context, message, type: _ToastType.error, duration: duration);
  }

  static void _showToast(
    BuildContext context,
    String message, {
    required _ToastType type,
    Duration? duration,
  }) {
    // 既存のSnackBarを削除
    ScaffoldMessenger.of(context).removeCurrentSnackBar();

    final theme = Theme.of(context);

    // タイプごとの色とアイコン定義
    Color backgroundColor;
    Color textColor;
    IconData icon;
    Color iconColor;

    switch (type) {
      case _ToastType.success:
        backgroundColor = Colors.white;
        textColor = const Color(0xFF1A1A1A);
        icon = Icons.check_circle_rounded;
        iconColor = const Color(0xFF4CAF50); // Green
        break;
      case _ToastType.error:
        backgroundColor = Colors.white;
        textColor = const Color(0xFF1A1A1A);
        icon = Icons.error_rounded;
        iconColor = const Color(0xFFE53935); // Red
        break;
      case _ToastType.info:
        backgroundColor = Colors.white;
        textColor = const Color(0xFF1A1A1A);
        icon = Icons.info_rounded;
        iconColor = theme.primaryColor; // App Primary color
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        padding: EdgeInsets.zero,
        duration: duration ?? const Duration(seconds: 3),
        content: Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                offset: const Offset(0, 4),
                blurRadius: 10,
              ),
            ],
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ToastType {
  info,
  success,
  error,
}
