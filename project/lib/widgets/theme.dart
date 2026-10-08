import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const Color primary = Color(0xFF0F6E56);
  static const Color primaryLight = Color(0xFFE1F5EE);
  static const Color primaryDark = Color(0xFF085041);

  // พื้นหลัง / พื้นผิว
  static const Color background = Color(0xFFFCFBF7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF4F3EE);

  // ตัวอักษร
  static const Color textPrimary = Color(0xFF2C2C2A);
  static const Color textSecondary = Color(0xFF5F5E5A);
  static const Color textMuted = Color(0xFF888780);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // เส้นขอบ
  static const Color border = Color(0xFFE3E1D9);

  // สถานะ (ใช้กับ StatusPill, การแจ้งเตือน)
  static const Color success = Color(0xFF3B6D11);
  static const Color successBg = Color(0xFFEAF3DE);
  static const Color warning = Color(0xFF854F0B);
  static const Color warningBg = Color(0xFFFAEEDA);
  static const Color danger = Color(0xFFA32D2D);
  static const Color dangerBg = Color(0xFFFCEBEB);
}