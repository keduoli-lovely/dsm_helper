import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 根据邮箱生成 Gravatar 地址；没有头像时 Gravatar 会返回 404，由 UI 回退到首字母头像。
String? gravatarUrl(String? email) {
  final value = email?.trim().toLowerCase() ?? '';
  if (value.isEmpty || !value.contains('@')) return null;
  final hash = md5.convert(utf8.encode(value)).toString();
  return 'https://www.gravatar.com/avatar/$hash?d=404&s=200';
}
