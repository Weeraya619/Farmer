import 'package:flutter/material.dart';
import 'package:project/main.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<void> _openChangePassword() async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ChangePasswordDialog(),
    );

    if (success == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปลี่ยนรหัสผ่านสำเร็จ')),
      );
    }
  }

  Widget _infoRow(String label, String value) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption),
            const SizedBox(height: 4),
            Text(value, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;
    final username = authService.username ?? '-';
    final email = '${user?['email'] ?? '-'}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: Text('ข้อมูลส่วนตัว', style: AppTextStyles.subheading),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primaryLight,
                child: const Icon(Icons.person_outline, size: 40, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Column(
                children: [
                  _infoRow('ชื่อผู้ใช้', username),
                  const Divider(height: 1, color: AppColors.border),
                  _infoRow('อีเมล', email),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _openChangePassword,
                icon: const Icon(Icons.lock_outline),
                label: const Text('เปลี่ยนรหัสผ่าน'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// กล่องโต้ตอบเปลี่ยนรหัสผ่าน: กรอกรหัสปัจจุบัน แล้วกรอกรหัสใหม่ 2 ครั้งให้ตรงกัน
/// pop(true) เมื่อเปลี่ยนสำเร็จ
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();
  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();
  bool isSaving = false;
  String? errorText;

  @override
  void dispose() {
    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentPassword = currentController.text.trim();
    final newPassword = newController.text.trim();
    final confirm = confirmController.text.trim();

    if (currentPassword.isEmpty || newPassword.isEmpty || confirm.isEmpty) {
      setState(() => errorText = 'กรุณากรอกข้อมูลให้ครบถ้วน');
      return;
    }
    if (newPassword.length < 6) {
      setState(() => errorText = 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร');
      return;
    }
    if (newPassword != confirm) {
      setState(() => errorText = 'รหัสผ่านและการยืนยันรหัสผ่านไม่ตรงกัน');
      return;
    }
    if (newPassword == currentPassword) {
      setState(() => errorText = 'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านปัจจุบัน');
      return;
    }

    setState(() {
      isSaving = true;
      errorText = null;
    });

    final error = await authService.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );

    if (!mounted) return;
    if (error != null) {
      setState(() {
        isSaving = false;
        errorText = error;
      });
      return;
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('เปลี่ยนรหัสผ่าน', style: AppTextStyles.subheading),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: currentController,
            obscureText: true,
            style: AppTextStyles.body,
            decoration: const InputDecoration(hintText: 'รหัสผ่านปัจจุบัน'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: newController,
            obscureText: true,
            style: AppTextStyles.body,
            decoration: const InputDecoration(hintText: 'รหัสผ่านใหม่ (อย่างน้อย 6 ตัวอักษร)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmController,
            obscureText: true,
            style: AppTextStyles.body,
            decoration: const InputDecoration(hintText: 'ยืนยันรหัสผ่านใหม่'),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 12),
            Text(errorText!, style: AppTextStyles.caption.copyWith(color: AppColors.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: isSaving ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(
            isSaving ? 'กำลังบันทึก...' : 'บันทึก',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}