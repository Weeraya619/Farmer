import 'package:flutter/material.dart';
import 'theme.dart';

enum StatusType { success, warning, danger }

/// ป้ายสถานะ เช่น สถานะน้ำ (สะอาด/สกปรก), สถานะ device (active/inactive)
/// ใช้แบบ: StatusPill(label: 'น้ำสะอาด ปกติดี', type: StatusType.success, icon: Icons.water_drop)
class StatusPill extends StatelessWidget {
  final String label;
  final StatusType type;
  final IconData? icon;

  const StatusPill({
    super.key,
    required this.label,
    required this.type,
    this.icon,
  });

  (Color, Color) get _colors {
    switch (type) {
      case StatusType.success:
        return (AppColors.successBg, AppColors.success);
      case StatusType.warning:
        return (AppColors.warningBg, AppColors.warning);
      case StatusType.danger:
        return (AppColors.dangerBg, AppColors.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}