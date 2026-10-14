import 'dart:async';
import 'package:flutter/material.dart';
import 'theme.dart';

class AppFeedback {
  static Timer? _timer;

  // แบบที่ 1: แถบแจ้งเตือนใต้ header หายเองอัตโนมัติ (เหมาะกับการบันทึกทั่วไป)
  static void success(BuildContext context, String message) {
    _banner(context, message, AppColors.primary, Icons.check_circle, 3);
  }

  static void error(BuildContext context, String message) {
    _banner(context, message, AppColors.danger, Icons.error, 5);
  }

  static void _banner(
    BuildContext context,
    String message,
    Color color,
    IconData icon,
    int seconds,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    _timer?.cancel();
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: color,
        leading: Icon(icon, color: Colors.white),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('ปิด', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    _timer = Timer(
      Duration(seconds: seconds),
      messenger.hideCurrentMaterialBanner,
    );
  }

  // แบบที่ 2: popup ให้กดตกลง (เหมาะกับเรื่องสำคัญ เช่น ลบ, เปลี่ยน ESP32)
  static Future<void> successDialog(BuildContext context, String message) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.primary, size: 48),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'ตกลง',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}