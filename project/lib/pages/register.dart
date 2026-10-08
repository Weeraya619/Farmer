import 'package:flutter/material.dart';
import 'package:project/main.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool obscurePassword = true;
  bool isLoading = false;

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final username = usernameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วน')),
      );
      return;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร')),
      );
      return;
    }

    setState(() => isLoading = true);

    final error = await authService.signUp(
      email: email,
      password: password,
      username: username,
    );

    if (!mounted) return;
    setState(() => isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('สร้างบัญชีสำเร็จ กรุณาเข้าสู่ระบบ')),
    );
    Navigator.pushReplacementNamed(context, '/loginpage');
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
                  radius: 40,
                  backgroundColor: AppColors.primaryLight,
                  child: const Icon(Icons.pets, size: 40, color: AppColors.primary),
                ),
                const SizedBox(height: 16),
                Text('สร้างบัญชี', style: AppTextStyles.heading),
                const SizedBox(height: 28),

                _field('ชื่อผู้ใช้', usernameController, 'กรอกชื่อผู้ใช้'),
                const SizedBox(height: 16),
                _field('อีเมล', emailController, 'name@example.com'),
                const SizedBox(height: 16),
                _field(
                  'รหัสผ่าน',
                  passwordController,
                  'อย่างน้อย 6 ตัวอักษร',
                  obscureText: obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () => setState(() => obscurePassword = !obscurePassword),
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textOnPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isLoading ? 'กำลังสร้างบัญชี...' : 'สร้างบัญชี',
                      style: AppTextStyles.button,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/loginpage'),
                  child: Text('มีบัญชีอยู่แล้ว เข้าสู่ระบบ', style: AppTextStyles.bodySecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String hint, {
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
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
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}