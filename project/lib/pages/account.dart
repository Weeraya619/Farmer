import 'package:flutter/material.dart';
import 'package:project/main.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import '/widgets/header.dart';
import '/widgets/bottomnav.dart';
import 'package:project/services/farm_service.dart';
import 'login.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final farmService = FarmService();
  bool isCreatingFarm = false;

  @override
  void initState() {
    super.initState();
    farmService.loadFarms().then((_) => setState(() {}));
  }

  Future<void> _showAddFarmDialog() async {
    final controller = TextEditingController();
    final farmName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('เพิ่มฟาร์มใหม่', style: AppTextStyles.subheading),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTextStyles.body,
          decoration: const InputDecoration(hintText: 'ชื่อฟาร์ม'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('สร้าง', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (farmName == null || farmName.isEmpty) return;

    setState(() => isCreatingFarm = true);
    final error = await farmService.createFarm(farmName);
    if (!mounted) return;
    setState(() => isCreatingFarm = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เพิ่มฟาร์ม "$farmName" สำเร็จ')),
      );
    }
  }

  Future<void> _logout() async {
    await authService.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(
        farmName: authService.currentUser?['username'] ?? 'บัญชีของฉัน',
        farmId: farmService.selectedFarmId,
      ),
      body: SafeArea(
        child: farmService.isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: isCreatingFarm ? null : _showAddFarmDialog,
                      icon: isCreatingFarm
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.add, color: Colors.white),
                      label: Text(
                        isCreatingFarm ? 'กำลังสร้าง...' : 'เพิ่มฟาร์ม',
                        style: AppTextStyles.button.copyWith(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('รายการฟาร์ม', style: AppTextStyles.bodySecondary),
                  const SizedBox(height: 10),
                  if (!farmService.hasFarmData)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text('ยังไม่มีฟาร์ม กดปุ่มด้านบนเพื่อเริ่มต้น', style: AppTextStyles.bodySecondary),
                      ),
                    )
                  else
                    ...farmService.farms.map((farm) {
                      final isSelected = farm['farm_id'] == farmService.selectedFarmId;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primaryLight : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.border,
                            width: isSelected ? 1.5 : 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                farm['farm_name'] ?? '-',
                                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (isSelected)
                              Text('(กำลังใช้งาน)', style: AppTextStyles.caption.copyWith(color: AppColors.primary))
                            else
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    farmService.selectedFarm = farm;
                                  });
                                },
                                child: const Text('เลือก'),
                              ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  Text('การตั้งค่า', style: AppTextStyles.bodySecondary),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          title: Text('ความปลอดภัย', style: AppTextStyles.body),
                          trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                          onTap: () {},
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        ListTile(
                          title: Text('ออกจากระบบ', style: AppTextStyles.body.copyWith(color: AppColors.danger)),
                          onTap: _logout,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 1,
        onTap: (i) {
          if (i == 0) Navigator.pop(context);
        },
      ),
    );
  }
}