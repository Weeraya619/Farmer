import 'package:flutter/material.dart';
import 'theme.dart';

/// กำหนด hierarchy ของตัวอักษรทั้งแอปไว้ที่เดียว
/// ขนาดฐานใหญ่กว่ามาตรฐานทั่วไปเล็กน้อย เพื่อรองรับกลุ่มผู้ใช้อายุ 60+
class AppTextStyles {
  AppTextStyles._();

  static const String fontFamily = 'Prompt'; // เปลี่ยนเป็น font ที่ใช้จริงในโปรเจกต์

  static const TextStyle heading = TextStyle(
    fontFamily: fontFamily,
    fontSize: 21,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle subheading = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  // ตัวเลขสำคัญ เช่น อุณหภูมิ, ความชื้น ใน MetricCard
  static const TextStyle metricValue = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );
}