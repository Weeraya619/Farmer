import 'package:flutter/material.dart';
import 'package:project/main.dart';
import 'package:project/services/farm_service.dart';
import 'package:project/services/farm_permissions.dart';
import 'package:project/widgets/theme.dart';
import 'package:project/widgets/text.dart';
import 'package:project/widgets/header.dart';
import 'package:project/widgets/card.dart';

/// หน้า "จัดการฟาร์ม" (เห็นเฉพาะ owner) รวม 3 ส่วนไว้หน้าเดียว:
/// 1) สวิตช์สิทธิ์ของพนักงาน (ทั้งฟาร์ม ไม่แยกรายคน)
/// 2) คำขอเข้าฟาร์มที่รอยืนยัน
/// 3) รายชื่อสมาชิก — เลื่อน/ลดขั้นเจ้าของร่วม (เจ้าของหลักเท่านั้น) และเอาออก
class FarmManagePage extends StatefulWidget {
  final FarmService farmService;
  final String farmId;
  final String farmName;

  const FarmManagePage({
    super.key,
    required this.farmService,
    required this.farmId,
    required this.farmName,
  });

  @override
  State<FarmManagePage> createState() => _FarmManagePageState();
}

class _FarmManagePageState extends State<FarmManagePage> {
  late bool financeOn;
  late bool buyOn;
  late bool sellOn;
  bool isSavingSettings = false;

  List<Map<String, dynamic>> members = [];
  List<Map<String, dynamic>> requests = [];
  bool isLoading = true;
  String? errorMessage;

  FarmPermissions get _perms => FarmPermissions.of(widget.farmId);
  bool get _isPrimary => _perms.isPrimaryOwner;
  String? get _myUsername => authService.currentUser?['username']?.toString();

  @override
  void initState() {
    super.initState();
    final perms = _perms;
    financeOn = perms.workerFinanceEnabled;
    buyOn = perms.workerBuyCowEnabled;
    sellOn = perms.workerSellCowEnabled;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final results = await Future.wait([
      widget.farmService.getMembers(widget.farmId),
      widget.farmService.getIncomingRequests(),
    ]);
    if (!mounted) return;

    final membersResult = results[0];
    final requestsResult = results[1];

    setState(() {
      isLoading = false;
      errorMessage = membersResult.ok ? null : membersResult.error;
      members = membersResult.data ?? [];
      requests = (requestsResult.data ?? []).where((r) => r['farmId'] == widget.farmId).toList();
    });
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(String title, String content, {String okLabel = 'ยืนยัน', bool danger = false}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(okLabel, style: TextStyle(color: danger ? AppColors.danger : AppColors.primary)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ---------- สวิตช์สิทธิ์ ----------

  Future<void> _saveSetting({bool? finance, bool? buyCow, bool? sellCow}) async {
    final prevFinance = financeOn;
    final prevBuy = buyOn;
    final prevSell = sellOn;

    setState(() {
      if (finance != null) financeOn = finance;
      if (buyCow != null) buyOn = buyCow;
      if (sellCow != null) sellOn = sellCow;
      isSavingSettings = true;
    });

    final error = await widget.farmService.updateSettings(
      widget.farmId,
      finance: finance,
      buyCow: buyCow,
      sellCow: sellCow,
    );
    if (!mounted) return;

    setState(() {
      isSavingSettings = false;
      if (error != null) {
        financeOn = prevFinance;
        buyOn = prevBuy;
        sellOn = prevSell;
      }
    });
    if (error != null) _showMessage(error);
  }

  // ---------- คำขอเข้าฟาร์ม ----------

  Future<void> _decide(Map<String, dynamic> request, {required bool approve}) async {
    final username = request['username'] ?? '-';
    final ok = await _confirm(
      approve ? 'อนุมัติคำขอ?' : 'ปฏิเสธคำขอ?',
      approve
          ? '"$username" จะเข้าร่วมฟาร์มนี้ในฐานะพนักงาน'
          : '"$username" จะไม่ได้เข้าร่วมฟาร์มนี้',
      okLabel: approve ? 'อนุมัติ' : 'ปฏิเสธ',
      danger: !approve,
    );
    if (!ok) return;

    final error = await widget.farmService.decideJoinRequest('${request['requestId']}', approve: approve);
    if (!mounted) return;
    if (error != null) {
      _showMessage(error);
    } else {
      _showMessage(approve ? 'อนุมัติแล้ว' : 'ปฏิเสธแล้ว');
    }
    _load();
  }

  // ---------- สมาชิก ----------

  Future<void> _changeRole(Map<String, dynamic> member, String newRole) async {
    final username = member['username'] ?? '-';
    final promote = newRole == 'owner';
    final ok = await _confirm(
      promote ? 'เลื่อนเป็นเจ้าของร่วม?' : 'ลดเป็นพนักงาน?',
      promote
          ? '"$username" จะทำได้เกือบทุกอย่างเท่าเจ้าของ (การเงิน ซื้อ-ขายวัว อุปกรณ์ ตั้งค่า อนุมัติสมาชิก)'
          : '"$username" จะกลับเป็นพนักงาน และถูกจำกัดสิทธิ์ตามสวิตช์ของฟาร์ม',
      okLabel: promote ? 'เลื่อนขั้น' : 'ลดขั้น',
      danger: !promote,
    );
    if (!ok) return;

    final error = await widget.farmService.changeMemberRole(widget.farmId, '${member['userId']}', newRole);
    if (!mounted) return;
    if (error != null) _showMessage(error);
    _load();
  }

  Future<void> _remove(Map<String, dynamic> member) async {
    final username = member['username'] ?? '-';
    final ok = await _confirm(
      'เอาออกจากฟาร์ม?',
      '"$username" จะเข้าถึงข้อมูลฟาร์มนี้ไม่ได้อีก (ต้องส่งคำขอเข้าฟาร์มใหม่ถ้าอยากกลับมา)',
      okLabel: 'เอาออก',
      danger: true,
    );
    if (!ok) return;

    final error = await widget.farmService.removeMember(widget.farmId, '${member['userId']}');
    if (!mounted) return;
    if (error != null) _showMessage(error);
    _load();
  }

  String _roleLabel(Map<String, dynamic> member) {
    if (member['isPrimaryOwner'] == true) return 'เจ้าของหลัก';
    return member['role'] == 'owner' ? 'เจ้าของร่วม' : 'พนักงาน';
  }

  List<PopupMenuEntry<String>> _menuFor(Map<String, dynamic> member) {
    final isSelf = member['username'] == _myUsername;
    if (isSelf || member['isPrimaryOwner'] == true) return [];

    final isCoOwner = member['role'] == 'owner';
    final items = <PopupMenuEntry<String>>[];

    if (_isPrimary) {
      items.add(PopupMenuItem(
        value: isCoOwner ? 'demote' : 'promote',
        child: Text(isCoOwner ? 'ลดเป็นพนักงาน' : 'เลื่อนเป็นเจ้าของร่วม'),
      ));
    }
    // เจ้าของร่วมเอาพนักงานออกได้ แต่เอาเจ้าของร่วมด้วยกันออกได้เฉพาะเจ้าของหลัก
    if (!isCoOwner || _isPrimary) {
      items.add(const PopupMenuItem(value: 'remove', child: Text('เอาออกจากฟาร์ม')));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(farmName: 'จัดการฟาร์ม', farmId: widget.farmId),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.farmName, style: AppTextStyles.heading),
              const SizedBox(height: 12),
              _buildSettingsCard(),
              _buildRequestsCard(),
              _buildMembersCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return SectionCard(
      title: 'สิทธิ์ของพนักงาน',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ตั้งค่านี้ใช้กับพนักงานทุกคนในฟาร์ม เจ้าของและเจ้าของร่วมทำได้ทุกอย่างเสมอ', style: AppTextStyles.caption),
          const SizedBox(height: 4),
          SwitchListTile(
            value: financeOn,
            onChanged: isSavingSettings ? null : (v) => _saveSetting(finance: v),
            contentPadding: EdgeInsets.zero,
            title: Text('ดูและบันทึกข้อมูลการเงิน', style: AppTextStyles.body),
            subtitle: Text(
              'ปิดอยู่: พนักงานมองไม่เห็นและบันทึกการเงินไม่ได้ รวมถึงการซื้อ-ขายวัว',
              style: AppTextStyles.caption,
            ),
          ),
          SwitchListTile(
            value: buyOn,
            onChanged: (!financeOn || isSavingSettings) ? null : (v) => _saveSetting(buyCow: v),
            contentPadding: EdgeInsets.zero,
            title: Text('บันทึกการซื้อวัว', style: AppTextStyles.body),
            subtitle: Text(financeOn ? 'พนักงานบันทึกซื้อวัวได้' : 'ต้องเปิดสิทธิ์การเงินก่อน', style: AppTextStyles.caption),
          ),
          SwitchListTile(
            value: sellOn,
            onChanged: (!financeOn || isSavingSettings) ? null : (v) => _saveSetting(sellCow: v),
            contentPadding: EdgeInsets.zero,
            title: Text('บันทึกการขายวัว', style: AppTextStyles.body),
            subtitle: Text(financeOn ? 'พนักงานบันทึกขายวัวได้' : 'ต้องเปิดสิทธิ์การเงินก่อน', style: AppTextStyles.caption),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsCard() {
    return SectionCard(
      title: 'คำขอเข้าฟาร์ม (${requests.length})',
      child: isLoading
          ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          : requests.isEmpty
              ? Text('ไม่มีคำขอที่รอยืนยัน', style: AppTextStyles.bodySecondary)
              : Column(
                  children: requests.map((r) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${r['username'] ?? '-'}', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                                Text('ขอเข้าเป็นพนักงาน', style: AppTextStyles.caption),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _decide(r, approve: false),
                            child: const Text('ปฏิเสธ', style: TextStyle(color: AppColors.danger)),
                          ),
                          ElevatedButton(
                            onPressed: () => _decide(r, approve: true),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                            child: const Text('อนุมัติ', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
    );
  }

  Widget _buildMembersCard() {
    return SectionCard(
      title: 'สมาชิกฟาร์ม (${members.length})',
      child: isLoading
          ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          : errorMessage != null
              ? Text(errorMessage!, style: const TextStyle(color: AppColors.danger))
              : Column(
                  children: members.map((m) {
                    final isSelf = m['username'] == _myUsername;
                    final menu = _menuFor(m);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${m['username'] ?? '-'}${isSelf ? ' (คุณ)' : ''}',
                                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(_roleLabel(m), style: AppTextStyles.caption),
                              ],
                            ),
                          ),
                          if (menu.isNotEmpty)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
                              itemBuilder: (context) => menu,
                              onSelected: (action) {
                                if (action == 'promote') _changeRole(m, 'owner');
                                if (action == 'demote') _changeRole(m, 'worker');
                                if (action == 'remove') _remove(m);
                              },
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}