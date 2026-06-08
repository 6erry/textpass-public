import 'package:flutter/material.dart';

class AppSelectionOption<T> {
  const AppSelectionOption({
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final T value;
  final IconData? icon;
}

class AppSelectionDialog<T> extends StatelessWidget {
  const AppSelectionDialog({
    super.key,
    required this.title,
    required this.options,
    required this.selectedValue,
  });

  final String title;
  final List<AppSelectionOption<T>> options;
  final T? selectedValue;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: options.map((option) {
                    final isSelected = option.value == selectedValue;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: isSelected
                            ? primary.withValues(alpha: 0.08)
                            : const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.of(context).pop(option.value),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? primary.withValues(alpha: 0.35)
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                if (option.icon != null) ...[
                                  Icon(
                                    option.icon,
                                    size: 22,
                                    color: isSelected
                                        ? primary
                                        : Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Text(
                                    option.label,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      color: const Color(0xFF1F2937),
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check, color: primary, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<T?> showAppSelectionDialog<T>({
  required BuildContext context,
  required String title,
  required List<AppSelectionOption<T>> options,
  T? selectedValue,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => AppSelectionDialog<T>(
      title: title,
      options: options,
      selectedValue: selectedValue,
    ),
  );
}
