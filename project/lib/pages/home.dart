import 'package:flutter/material.dart';
import 'package:project/main.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import '/widgets/header.dart';
import '/widgets/bottomnav.dart';
import '/widgets/card.dart';
import '/widgets/button.dart';
import '/widgets/statuspill.dart';
import '/widgets/date_util.dart';
import '/services/farm_service.dart';
import '/services/sensor_service.dart';
import 'login.dart';
import 'account.dart';
import 'cow_list.dart';
import 'farm_record.dart';
import 'finance_summary.dart';
import 'sensor_monitor.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final farmService = FarmService();
  final sensorService = SensorService();

  Map<String, dynamic>? latestReading;
  bool isLoadingExtra = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await farmService.loadFarms();

    if (farmService.selectedFarmId == null) {
      setState(() {});
      return;
    }

    setState(() => isLoadingExtra = true);
    final farmId = farmService.selectedFarmId!;

    final reading = await sensorService.getLatest(farmId);

    if (!mounted) return;
    setState(() {
      latestReading = reading;
      isLoadingExtra = false;
    });
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
        farmName: farmService.selectedFarmName ?? 'ฟาร์มของฉัน',
        farmId: farmService.selectedFarmId,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: farmService.isLoading
              ? const Center(child: CircularProgressIndicator())
              : farmService.errorMessage != null
                  ? _ErrorState(
                      message: farmService.errorMessage!,
                      onRetry: _loadAll,
                      onReLogin: farmService.errorMessage!.contains('เซสชัน') ? _logout : null,
                    )
                  : !farmService.hasFarmData
                      ? _EmptyFarmState(onRefresh: _loadAll)
                      : _buildContent(),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 0,
        onTap: (i) async {
          if (i == 1) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AccountPage()),
            );
            // กลับมาจากหน้าบัญชี อาจมีการเพิ่ม/เปลี่ยนฟาร์ม โหลดข้อมูลใหม่
            _loadAll();
          }
        },
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: isLoadingExtra
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                )
              : latestReading == null
                  ? Text('ยังไม่มีข้อมูล sensor เข้ามา', style: AppTextStyles.bodySecondary)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'อุณหภูมิ/ความชื้นล่าสุด ${formatThaiDateTime(latestReading!['climateTimestamp'])}',
                          style: AppTextStyles.caption,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: MetricCard(
                                label: 'อุณหภูมิ',
                                value: '${latestReading!['airTemperature'] ?? '-'}',
                                unit: '°C',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: MetricCard(
                                label: 'ความชื้น',
                                value: '${latestReading!['humidity'] ?? '-'}',
                                unit: '%',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        StatusPill(
                          label: _waterStatusLabel(latestReading!['turbidity']),
                          type: _waterStatusType(latestReading!['turbidity']),
                          icon: Icons.water_drop_outlined,
                        ),
                        if (latestReading!['waterTimestamp'] != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'ข้อมูลน้ำล่าสุด ${formatThaiDateTime(latestReading!['waterTimestamp'])}',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ],
                    ),
        ),
        const SizedBox(height: 20),
        Text('เมนูหลัก', style: AppTextStyles.bodySecondary),
        const SizedBox(height: 10),
        MenuButton(
          icon: Icons.edit_outlined,
          label: 'บันทึกข้อมูลฟาร์ม',
          onTap: () {
            if (farmService.selectedFarmId == null) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FarmRecordPage(farmId: farmService.selectedFarmId!),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        MenuButton(
          icon: Icons.bar_chart_outlined,
          label: 'ดูรายรับ-รายจ่าย',
          onTap: () {
            if (farmService.selectedFarmId == null) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FinanceSummaryPage(farmId: farmService.selectedFarmId!),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        MenuButton(
          icon: Icons.sensors_outlined,
          label: 'ติดตามเฝ้าระวังสิ่งแวดล้อมวัว',
          onTap: () {
            if (farmService.selectedFarmId == null) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SensorMonitorPage(farmId: farmService.selectedFarmId!),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        MenuButton(
          icon: Icons.pets_outlined,
          label: 'ข้อมูลวัวในฟาร์ม',
          onTap: () {
            if (farmService.selectedFarmId == null) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CowListPage(farmId: farmService.selectedFarmId!),
              ),
            );
          },
        ),
      ],
    );
  }

  String _waterStatusLabel(dynamic turbidity) {
    if (turbidity == null) return 'ไม่มีข้อมูลความขุ่นน้ำ';
    final value = double.tryParse('$turbidity') ?? 0;
    return value > 5 ? 'น้ำขุ่นผิดปกติ' : 'น้ำสะอาด ปกติดี';
  }

  StatusType _waterStatusType(dynamic turbidity) {
    if (turbidity == null) return StatusType.warning;
    final value = double.tryParse('$turbidity') ?? 0;
    return value > 5 ? StatusType.danger : StatusType.success;
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onReLogin;

  const _ErrorState({required this.message, required this.onRetry, this.onReLogin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(message, style: AppTextStyles.body, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onReLogin ?? onRetry,
              child: Text(onReLogin != null ? 'เข้าสู่ระบบใหม่' : 'ลองอีกครั้ง'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFarmState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyFarmState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pets_outlined, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text('ยังไม่มีฟาร์มในบัญชีนี้', style: AppTextStyles.body),
            const SizedBox(height: 4),
            Text('เริ่มต้นด้วยการสร้างฟาร์มแรก', style: AppTextStyles.bodySecondary),
          ],
        ),
      ),
    );
  }
}