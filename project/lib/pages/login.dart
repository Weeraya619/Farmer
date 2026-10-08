import 'package:flutter/material.dart';
import 'package:project/main.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import 'home.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool obscurePassword = true;
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วน')),
      );
      return;
    }

    setState(() => isLoading = true);

    final error = await authService.signIn(email: email, password: password);

    if (!mounted) return;
    setState(() => isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 32),
                CircleAvatar(
                  radius: 60,
                  backgroundColor: AppColors.primaryLight,
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/bull.png',
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('เข้าสู่ระบบ', style: AppTextStyles.heading),
                Text(
                  'เข้าสู่ระบบเพื่อดูข้อมูลฟาร์ม',
                  style: AppTextStyles.bodySecondary,
                ),
                const SizedBox(height: 28),

                _LabeledField(
                  label: 'อีเมลหรือชื่อผู้ใช้',
                  controller: emailController,
                  hintText: 'name@example.com',
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'รหัสผ่าน',
                  controller: passwordController,
                  hintText: 'กรอกรหัสผ่าน',
                  obscureText: obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () =>
                        setState(() => obscurePassword = !obscurePassword),
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textOnPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isLoading ? 'กำลังเข้าสู่ระบบ...' : 'เข้าสู่ระบบ',
                      style: AppTextStyles.button,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/registerpage'),
                  child: Text(
                    'ยังไม่มีบัญชี สร้างบัญชีใหม่',
                    style: AppTextStyles.bodySecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ช่องกรอกข้อมูลที่มี label อยู่ด้านบนเสมอ (ไม่ใช่แค่ placeholder)
/// ตามที่ตกลงกันไว้เรื่อง accessibility สำหรับผู้ใช้ทุกวัย
class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final Widget? suffixIcon;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: AppTextStyles.body.copyWith(
                color: AppColors.textMuted,
              ),
              suffixIcon: suffixIcon,
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
