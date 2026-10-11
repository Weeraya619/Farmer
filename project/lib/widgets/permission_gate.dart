import 'package:flutter/material.dart';

/// ครอบปุ่ม/เมนูที่ต้องมีสิทธิ์ — ถ้าไม่มีสิทธิ์จะจางลง กดแล้วขึ้นข้อความอธิบายแทนการทำงาน
/// (เป็นแค่ฉากหน้า สิทธิ์จริงบังคับที่ backend)
class PermissionGate extends StatelessWidget {
  final bool allowed;
  final String message;
  final Widget child;

  const PermissionGate({
    super.key,
    required this.allowed,
    required this.child,
    this.message = 'เจ้าของฟาร์มยังไม่เปิดสิทธิ์นี้ให้พนักงาน',
  });

  @override
  Widget build(BuildContext context) {
    if (allowed) return child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      },
      child: Opacity(
        opacity: 0.45,
        child: AbsorbPointer(child: child),
      ),
    );
  }
}