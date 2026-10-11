import 'package:flutter/material.dart';
import '/widgets/theme.dart';
import '/widgets/header.dart';
import '/widgets/button.dart';
import '/widgets/permission_gate.dart';
import 'package:project/services/farm_permissions.dart';
import 'expense_income.dart';
import 'existing_cow_record.dart';
import 'cow_purchase_wizard.dart';

/// จุดรวมการบันทึกข้อมูลฟาร์มทั้งหมด — รายรับ-รายจ่าย, วัวที่มีอยู่แล้ว, วัวที่ซื้อมาใหม่
/// พนักงานที่ไม่มีสิทธิ์จะเห็นปุ่มจางและกดแล้วมีข้อความอธิบาย (สิทธิ์จริงบังคับที่ backend)
class FarmRecordPage extends StatelessWidget {
  final String farmId;
  const FarmRecordPage({super.key, required this.farmId});

  @override
  Widget build(BuildContext context) {
    final perms = FarmPermissions.of(farmId);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(farmName: 'บันทึกข้อมูลฟาร์ม', farmId: farmId),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PermissionGate(
              allowed: perms.canFinance,
              message: 'เจ้าของฟาร์มยังไม่เปิดสิทธิ์การเงินให้พนักงาน',
              child: MenuButton(
                icon: Icons.receipt_long_outlined,
                label: 'บันทึกรายรับ-รายจ่าย',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ExpenseIncomePage(farmId: farmId)),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            // บันทึกวัวที่มีอยู่แล้วไม่มีราคา จึงไม่ผูกกับสิทธิ์การเงิน
            MenuButton(
              icon: Icons.pets_outlined,
              label: 'บันทึกวัวที่มีอยู่แล้ว',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ExistingCowRecordPage(farmId: farmId)),
                );
              },
            ),
            const SizedBox(height: 10),
            PermissionGate(
              allowed: perms.canBuyCow,
              message: 'เจ้าของฟาร์มยังไม่เปิดสิทธิ์ซื้อวัวให้พนักงาน',
              child: MenuButton(
                icon: Icons.shopping_cart_outlined,
                label: 'บันทึกวัวที่ซื้อมาใหม่',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => CowPurchaseWizard(farmId: farmId)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}