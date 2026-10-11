import 'package:flutter/material.dart';
import 'package:project/services/farm_service.dart';
import 'package:project/widgets/theme.dart';
import 'package:project/widgets/text.dart';
import 'package:project/widgets/header.dart';
import 'package:project/widgets/card.dart';

/// หน้า "ขอเข้าฟาร์ม" สำหรับคนที่อยากเป็นพนักงานของฟาร์มคนอื่น
/// ใส่ username ของเจ้าของ → เห็นรายชื่อฟาร์มของเจ้าของคนนั้น → เลือกแล้วกดขอ
/// เจ้าของจะเห็นคำขอในหน้า "จัดการฟาร์ม" และต้องกดยืนยันก่อน
class JoinFarmPage extends StatefulWidget {
  final FarmService farmService;
  const JoinFarmPage({super.key, required this.farmService});

  @override
  State<JoinFarmPage> createState() => _JoinFarmPageState();
}

class _JoinFarmPageState extends State<JoinFarmPage> {
  final usernameController = TextEditingController();

  List<Map<String, dynamic>> foundFarms = [];
  List<Map<String, dynamic>> myRequests = [];
  bool isSearching = false;
  bool hasSearched = false;
  String? searchError;
  final Set<String> sendingFarmIds = {};

  @override
  void initState() {
    super.initState();
    _loadMyRequests();
  }

  @override
  void dispose() {
    usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadMyRequests() async {
    final result = await widget.farmService.getMyJoinRequests();
    if (!mounted) return;
    setState(() => myRequests = result.data ?? []);
  }

  Future<void> _search() async {
    final username = usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => searchError = 'กรุณากรอกชื่อผู้ใช้ของเจ้าของฟาร์ม');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      isSearching = true;
      searchError = null;
      foundFarms = [];
    });

    final result = await widget.farmService.searchOwnerFarms(username);
    if (!mounted) return;

    setState(() {
      isSearching = false;
      hasSearched = true;
      searchError = result.ok ? null : result.error;
      foundFarms = result.data ?? [];
    });
  }

  Future<void> _sendRequest(Map<String, dynamic> farm) async {
    final farmId = '${farm['farmId']}';
    setState(() => sendingFarmIds.add(farmId));

    final error = await widget.farmService.sendJoinRequest(farmId);
    if (!mounted) return;

    setState(() {
      sendingFarmIds.remove(farmId);
      if (error == null) farm['pending'] = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'ส่งคำขอแล้ว รอเจ้าของฟาร์มยืนยัน')),
    );
    if (error == null) _loadMyRequests();
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'approved':
        return 'อนุมัติแล้ว';
      case 'rejected':
        return 'ไม่อนุมัติ';
      default:
        return 'รอเจ้าของยืนยัน';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.danger;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppHeader(farmName: 'ขอเข้าฟาร์ม'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'ค้นหาเจ้าของฟาร์ม',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('กรอกชื่อผู้ใช้ (username) ของเจ้าของฟาร์ม แล้วเลือกฟาร์มที่ต้องการเข้าร่วมเป็นพนักงาน', style: AppTextStyles.caption),
                  const SizedBox(height: 10),
                  TextField(
                    controller: usernameController,
                    style: AppTextStyles.body,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'ชื่อผู้ใช้ของเจ้าของฟาร์ม',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: isSearching ? null : _search,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(isSearching ? 'กำลังค้นหา...' : 'ค้นหา', style: AppTextStyles.button.copyWith(color: Colors.white)),
                    ),
                  ),
                  if (searchError != null) ...[
                    const SizedBox(height: 10),
                    Text(searchError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                  ],
                ],
              ),
            ),
            if (hasSearched && searchError == null)
              foundFarms.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'ไม่พบฟาร์มที่ขอเข้าได้ (อาจเป็นฟาร์มที่คุณเป็นสมาชิกอยู่แล้ว)',
                        style: AppTextStyles.bodySecondary,
                      ),
                    )
                  : SectionCard(
                      title: 'ฟาร์มของเจ้าของคนนี้',
                      child: Column(
                        children: foundFarms.map((farm) {
                          final pending = farm['pending'] == true;
                          final sending = sendingFarmIds.contains('${farm['farmId']}');
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${farm['farmName'] ?? '-'}',
                                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: (pending || sending) ? null : () => _sendRequest(farm),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                  child: Text(
                                    pending ? 'รอการยืนยัน' : (sending ? 'กำลังส่ง...' : 'ขอเข้าฟาร์ม'),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            if (myRequests.isNotEmpty)
              SectionCard(
                title: 'คำขอของฉัน',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...myRequests.map((r) {
                      final status = r['status'] as String?;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text('${r['farmName'] ?? '-'}', style: AppTextStyles.body)),
                            Text(
                              _statusLabel(status),
                              style: AppTextStyles.caption.copyWith(color: _statusColor(status), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    Text('เมื่อได้รับอนุมัติแล้ว ให้ดึงหน้าบัญชีลงเพื่อรีเฟรช ฟาร์มจะขึ้นในรายการ', style: AppTextStyles.caption),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}