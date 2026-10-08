import 'package:flutter/material.dart';
import 'theme.dart';
import 'text.dart';

/// ปุ่มเมนูใหญ่ มีไอคอนซ้าย + ข้อความ ใช้ในหน้าหลัก
/// ใช้แบบ: MenuButton(icon: Icons.edit, label: 'บันทึกข้อมูลฟาร์ม', onTap: () {})
class MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const MenuButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: AppColors.primary),
              const SizedBox(width: 14),
              Text(label, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}