import 'package:flutter/material.dart';
import '/widgets/theme.dart';
import '/widgets/header.dart';
import '/widgets/button.dart';
import 'expense_income.dart';
import 'existing_cow_record.dart';
import 'cow_purchase_wizard.dart';

/// จุดรวมการบันทึกข้อมูลฟาร์มทั้งหมด — รายรับ-รายจ่าย, วัวที่มีอยู่แล้ว, วัวที่ซื้อมาใหม่
class FarmRecordPage extends StatelessWidget {
  final String farmId;
  const FarmRecordPage({super.key, required this.farmId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(farmName: 'บันทึกข้อมูลฟาร์ม', farmId: farmId),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MenuButton(
              icon: Icons.receipt_long_outlined,
              label: 'บันทึกรายรับ-รายจ่าย',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ExpenseIncomePage(farmId: farmId)),
                );
              },
            ),
            const SizedBox(height: 10),
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
            MenuButton(
              icon: Icons.shopping_cart_outlined,
              label: 'บันทึกวัวที่ซื้อมาใหม่',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CowPurchaseWizard(farmId: farmId)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}