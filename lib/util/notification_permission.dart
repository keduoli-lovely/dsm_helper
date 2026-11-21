import 'package:flutter/services.dart';

class NotificationPermission {
  static const MethodChannel _channel = MethodChannel('dsm_helper/permissions');

  static Future<void> request() async {
    try {
      await _channel.invokeMethod('requestNotifications');
    } catch (_) {
      // 平台未实现时静默忽略，不影响主流程。
    }
  }
}
