import 'dart:convert';

import 'package:crypto/crypto.dart';

String normalizeClassIdentityPart(String value) {
  return value
      .toLowerCase()
      .replaceAll('　', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[\u2010-\u2015ー－]'), '-')
      .replaceAll(RegExp(r'[【】「」『』]'), '')
      .trim();
}

String buildClassKey({
  required String universityId,
  required String title,
  required String teacher,
}) {
  final normalizedUniversity = normalizeClassIdentityPart(universityId);
  final normalizedTitle = normalizeClassIdentityPart(title);
  final normalizedTeacher = normalizeClassIdentityPart(teacher);
  final source = '$normalizedUniversity|$normalizedTitle|$normalizedTeacher';
  final digest = sha1.convert(utf8.encode(source)).toString().substring(0, 20);
  final prefix =
      normalizedUniversity.replaceAll(RegExp(r'[^a-z0-9]+'), '_').trim();
  return '${prefix}_$digest';
}
