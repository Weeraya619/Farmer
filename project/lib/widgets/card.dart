import 'package:flutter/material.dart';
import 'theme.dart';
import 'text.dart';

/// การ์ดขาวที่ครอบเนื้อหาแต่ละส่วน (กราฟ, รายจ่าย ฯลฯ)
/// ใช้แบบ: SectionCard(title: 'รายจ่าย', child: PieChart(...))
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: AppTextStyles.subheading),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// การ์ดตัวเลขเดี่ยว เช่น อุณหภูมิ, ความชื้น, TDS
/// ใช้แบบ: MetricCard(label: 'อุณหภูมิ', value: '31.2', unit: '°C')
class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData? icon;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
              ],
              Text(label, style: AppTextStyles.bodySecondary),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: AppTextStyles.metricValue),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(unit!, style: AppTextStyles.bodySecondary),
              ],
            ],
          ),
        ],
      ),
    );
  }
}