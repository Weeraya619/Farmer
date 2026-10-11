import 'package:flutter/material.dart';
import 'package:project/main.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import '/widgets/header.dart';
import '/widgets/bottomnav.dart';
import 'package:project/services/farm_service.dart';
import 'package:project/services/farm_permissions.dart';
import 'farm_manage.dart';
import 'join_farm.dart';
import 'login.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final farmService = FarmService();
  bool isCreatingFarm = false;

  // คำขอเข้าฟาร์มที่รอยืนยัน (ของทุกฟาร์มที่เป็น owner) ใช้ทำจุดแจ้งเตือนบนปุ่ม "จัดการ"
  List<Map<String, dynamic>> incomingRequests = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await farmService.loadFarms();
    final incoming = await farmService.getIncomingRequests();
    if (!mounted) return;
    setState(() => incomingRequests = incoming.data ?? []);
  }

  int _pendingCountFor(String farmId) =>
      incomingRequests.where((r) => r['farmId'] == farmId).length;

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

  Future<void> _openManage(Map<String, dynamic> farm) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FarmManagePage(
          farmService: farmService,
          farmId: '${farm['farm_id']}',
          farmName: '${farm['farm_name'] ?? '-'}',
        ),
      ),
    );
    if (mounted) _loadAll(); // กลับมาแล้วรีเฟรช เผื่ออนุมัติ/ตั้งค่าไป
  }

  Future<void> _openJoinFarm() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => JoinFarmPage(farmService: farmService)),
    );
    if (mounted) _loadAll();
  }

  Future<void> _leaveFarm(Map<String, dynamic> farm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ออกจากฟาร์มนี้?'),
        content: Text('คุณจะเข้าถึงข้อมูลของ "${farm['farm_name']}" ไม่ได้อีก ต้องส่งคำขอเข้าฟาร์มใหม่ถ้าอยากกลับมา'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ออกจากฟาร์ม', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final error = await farmService.leaveFarm('${farm['farm_id']}');
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'ออกจากฟาร์มแล้ว')),
    );
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

  Widget _farmCard(Map<String, dynamic> farm) {
    final farmId = '${farm['farm_id']}';
    final isSelected = farm['farm_id'] == farmService.selectedFarmId;
    final perms = FarmPermissions.of(farmId);
    final pendingCount = perms.isOwner ? _pendingCountFor(farmId) : 0;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farm['farm_name'] ?? '-',
                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(perms.roleLabel, style: AppTextStyles.caption),
                  ],
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
          if (perms.isOwner || !perms.isPrimaryOwner) const SizedBox(height: 4),
          Row(
            children: [
              if (perms.isOwner)
                OutlinedButton.icon(
                  onPressed: () => _openManage(farm),
                  icon: Badge(
                    isLabelVisible: pendingCount > 0,
                    label: Text('$pendingCount'),
                    child: const Icon(Icons.settings_outlined, size: 18),
                  ),
                  label: Text(pendingCount > 0 ? 'จัดการฟาร์ม (มีคำขอใหม่)' : 'จัดการฟาร์ม'),
                ),
              const Spacer(),
              // เจ้าของหลักออกจากฟาร์มเองไม่ได้ — คนอื่นออกได้
              if (!perms.isPrimaryOwner)
                TextButton(
                  onPressed: () => _leaveFarm(farm),
                  child: const Text('ออกจากฟาร์ม', style: TextStyle(color: AppColors.danger)),
                ),
            ],
          ),
        ],
      ),
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
            : RefreshIndicator(
                onRefresh: _loadAll,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
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
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _openJoinFarm,
                              icon: const Icon(Icons.group_add_outlined),
                              label: const Text('ขอเข้าฟาร์ม'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('รายการฟาร์ม', style: AppTextStyles.bodySecondary),
                    const SizedBox(height: 10),
                    if (!farmService.hasFarmData)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'ยังไม่มีฟาร์ม กดปุ่มด้านบนเพื่อเริ่มต้น',
                            style: AppTextStyles.bodySecondary,
                          ),
                        ),
                      )
                    else
                      ...farmService.farms.map(_farmCard),
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