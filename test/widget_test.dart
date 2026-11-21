import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsm_helper/theme/app_theme.dart';

void main() {
  test('主题构建成功', () {
    expect(AppTheme.light().colorScheme.primary, isNotNull);
    expect(AppTheme.dark().brightness, Brightness.dark);
  });
}
