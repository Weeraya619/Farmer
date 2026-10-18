import 'package:flutter/material.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import '/widgets/header.dart';
import '/widgets/card.dart';
import '/widgets/statuspill.dart';
import '/services/device_service.dart';
import '/widgets/trend_chart.dart';
import '/services/sensor_service.dart';
import '/widgets/date_util.dart';
import '/services/farm_permissions.dart';
import '/widgets/feedback.dart';

/// ข้อมูลรายชั่วโมงสำหรับกราฟ: อุณหภูมิเฉลี่ยของทุกอุปกรณ์ในชั่วโมงนั้น + ค่า THI
class _HourBucket {
  final DateTime hour; // เวลาต้นชั่วโมง (เวลาท้องถิ่น)
  final Map<String, double> tempByDevice = {}; // device_id -> อุณหภูมิล่าสุดของอุปกรณ์นั้นในชั่วโมงนี้
  double? thi;

  _HourBucket(this.hour);

  double? get avgTemp {
    if (tempByDevice.isEmpty) return null;
    return tempByDevice.values.reduce((a, b) => a + b) / tempByDevice.length;
  }
}

/// หน้าติดตามเฝ้าระวังสิ่งแวดล้อมวัว
/// บนสุด: กราฟแนวโน้มอุณหภูมิ+THI ย้อนหลัง 24 ชั่วโมง
/// กลาง: สรุปจำนวนอุปกรณ์ทั้งหมด แยกตามชุด
/// ล่าง: การ์ดอุปกรณ์แบบย่อ (ไม่โชว์ MAC) กดเข้าไปดูรายละเอียดที่ปลอดภัยได้
class SensorMonitorPage extends StatefulWidget {
  final String farmId;
  const SensorMonitorPage({super.key, required this.farmId});

  @override
  State<SensorMonitorPage> createState() => _SensorMonitorPageState();
}

class _SensorMonitorPageState extends State<SensorMonitorPage> {
  final deviceService = DeviceService();
  final sensorService = SensorService();

  List<Map<String, dynamic>> devices = [];
  List<_HourBucket> trendHistory = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    final deviceList = await deviceService.getDevices(widget.farmId);

    // ดึงประวัติทั้งฟาร์ม (ไม่เจาะจง device) แล้วค่อยรวมทีหลัง
    // เพราะถ้าเจาะจง device ตัวเดียว จะได้ค่าของบอร์ดเดียว ไม่ตรงกับ THI ที่คำนวณจากทุกบอร์ด
    // limit 100 พอครอบคลุม 24 ชม. แม้มีอุปกรณ์หลายตัวส่งชั่วโมงละครั้ง
    final rawHistory = await sensorService.getHistory(widget.farmId, limit: 100);

    // จัดกลุ่มตามชั่วโมง: เก็บอุณหภูมิ "ล่าสุดของแต่ละอุปกรณ์" ในชั่วโมงนั้น แล้วเฉลี่ยข้ามอุปกรณ์
    // (กันอุปกรณ์ที่ส่งซ้ำในชั่วโมงเดียวกันถูกนับเกินน้ำหนัก)
    // ค่า THI ใช้ของแถวที่ใหม่สุดในชั่วโมงนั้น ซึ่ง backend คำนวณจากค่าเฉลี่ยทุกบอร์ดอยู่แล้ว
    final Map<int, _HourBucket> buckets = {};
    for (final row in rawHistory) {
      // rawHistory เรียงใหม่→เก่า ตัวแรกที่เจอของแต่ละ (ชั่วโมง, อุปกรณ์) คือค่าล่าสุด
      final t = DateTime.tryParse('${row['sensor_timestamp']}')?.toLocal();
      if (t == null) continue;
      final hourStart = DateTime(t.year, t.month, t.day, t.hour);
      final bucket = buckets.putIfAbsent(
        hourStart.millisecondsSinceEpoch,
        () => _HourBucket(hourStart),
      );

      final temp = row['air_temperature'];
      final deviceId = '${row['device_id']}';
      if (temp is num && !bucket.tempByDevice.containsKey(deviceId)) {
        bucket.tempByDevice[deviceId] = temp.toDouble();
      }

      final thi = row['thi'];
      if (thi is num && bucket.thi == null) {
        bucket.thi = thi.toDouble();
      }
    }

    final hours = buckets.values
        .where((b) => b.avgTemp != null || b.thi != null)
        .toList()
      ..sort((a, b) => b.hour.compareTo(a.hour));
    final last24 = hours.take(24).toList();

    if (!mounted) return;
    setState(() {
      devices = deviceList;
      trendHistory = last24.reversed
          .toList(); // กลับให้เรียงเก่า→ใหม่ สำหรับกราฟ
      isLoading = false;
    });
  }

  Future<void> _showRegisterDialog() async {
    final macController = TextEditingController();
    final nameController = TextEditingController();
    bool isSaving = false;
    String? errorText;

    final registered = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ลงทะเบียนอุปกรณ์ใหม่'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: macController,
                  decoration: const InputDecoration(
                    labelText: 'MAC Address',
                    hintText: 'AA:BB:CC:DD:EE:FF',
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 4),
                Text(
                  'ดูได้จากสติกเกอร์บนตัวเครื่อง',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'ชื่ออุปกรณ์',
                    hintText: 'เช่น เซนเซอร์น้ำ คอกที่ 1',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ไม่ต้องเลือกชนิดเซนเซอร์ — ตัว ESP32 จะแจ้งให้ระบบรู้เองตอนเชื่อมต่อครั้งแรก',
                  style: AppTextStyles.caption,
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      final error = await deviceService.registerDevice(
                        farmId: widget.farmId,
                        macAddress: macController.text.trim(),
                        name: nameController.text.trim(),
                      );
                      if (error != null) {
                        setDialogState(() {
                          isSaving = false;
                          errorText = error;
                        });
                        return;
                      }
                      if (context.mounted) Navigator.pop(context, true);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: Text(
                isSaving ? 'กำลังบันทึก...' : 'ลงทะเบียน',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (registered == true) {
      if (mounted) AppFeedback.success(context, 'ลงทะเบียนอุปกรณ์สำเร็จ');
      _load();
    }
  }

  Future<void> _showDeviceDetail(Map<String, dynamic> device) async {
    final replaced = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true, // ให้ sheet สูงตามเนื้อหาได้ ไม่ถูกจำกัดที่ ~9/16 ของจอ
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _DeviceDetailSheet(device: device),
    );
    if (replaced == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(
        farmName: 'ติดตามเฝ้าระวังสิ่งแวดล้อมวัว',
        farmId: widget.farmId,
      ),
      floatingActionButton: FarmPermissions.of(widget.farmId).canManageDevices
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: _showRegisterDialog,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (trendHistory.isNotEmpty) _buildTrendSection(),
                    const SizedBox(height: 8),
                    _buildSummaryCard(),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'อุปกรณ์ทั้งหมด',
                        style: AppTextStyles.bodySecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (devices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(
                                Icons.sensors_outlined,
                                size: 40,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'ยังไม่มีอุปกรณ์ที่ลงทะเบียน',
                                style: AppTextStyles.bodySecondary,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                FarmPermissions.of(
                                      widget.farmId,
                                    ).canManageDevices
                                    ? 'กดปุ่ม + เพื่อเริ่มลงทะเบียนอุปกรณ์แรก'
                                    : 'ให้เจ้าของฟาร์มเป็นผู้ลงทะเบียนอุปกรณ์',
                                style: AppTextStyles.caption,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...devices.map(_deviceCard),
                  ],
                ),
              ),
      ),
    );
  }

  String _hourLabel(_HourBucket b) =>
      '${b.hour.hour.toString().padLeft(2, '0')}:00';

  Widget _buildTrendSection() {
    // แต่ละกราฟกรองชั่วโมงที่ไม่มีค่าออกพร้อมป้ายเวลาของตัวเอง
    // ทำให้จำนวนค่ากับจำนวนป้ายเท่ากันเสมอ ไม่เลื่อนไม่ตรงกัน
    final tempBuckets = trendHistory.where((b) => b.avgTemp != null).toList();
    final thiBuckets = trendHistory.where((b) => b.thi != null).toList();

    return SectionCard(
      title: 'แนวโน้มย้อนหลัง 24 ชั่วโมง',
      child: Column(
        children: [
          TrendLineChart(
            title: 'อุณหภูมิ (เฉลี่ยทุกอุปกรณ์)',
            values: tempBuckets.map((b) => b.avgTemp!).toList(),
            labels: tempBuckets.map(_hourLabel).toList(),
            unit: '°C',
            color: AppColors.danger,
          ),
          const SizedBox(height: 20),
          TrendLineChart(
            title: 'ค่า THI (ความเครียดจากความร้อน)',
            values: thiBuckets.map((b) => b.thi!).toList(),
            labels: thiBuckets.map(_hourLabel).toList(),
            unit: '',
            color: AppColors.warning,
            warningThreshold: 72,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final dhtOnlyCount = devices.where((d) {
      final sensors = (d['sensors'] as List?)?.cast<String>() ?? [];
      return sensors.length == 1 && sensors.contains('dht22');
    }).length;
    final waterCount = devices.where((d) {
      final sensors = (d['sensors'] as List?)?.cast<String>() ?? [];
      return sensors.contains('turbidity') || sensors.contains('tds');
    }).length;
    final activeCount = devices.where((d) => d['status'] == 'active').length;

    return SectionCard(
      child: Row(
        children: [
          _summaryStat('ทั้งหมด', '${devices.length} ชุด'),
          _summaryStat('เชื่อมต่อแล้ว', '$activeCount ชุด'),
          _summaryStat('DHT22 อย่างเดียว', '$dhtOnlyCount ชุด'),
          _summaryStat('วัดน้ำ', '$waterCount ชุด'),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppTextStyles.subheading),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _deviceCard(Map<String, dynamic> device) {
    final status = device['status'];
    final statusLabel = switch (status) {
      'pending' => 'รอเชื่อมต่อ',
      'active' => 'เชื่อมต่อแล้ว',
      'inactive' => 'ปิดใช้งาน',
      'maintenance' => 'ซ่อมบำรุง',
      _ => 'ไม่ทราบสถานะ',
    };
    final statusType = switch (status) {
      'active' => StatusType.success,
      'pending' => StatusType.warning,
      _ => StatusType.danger,
    };
    final sensors = (device['sensors'] as List?)?.join(', ') ?? '-';

    return InkWell(
      onTap: () => _showDeviceDetail(device),
      borderRadius: BorderRadius.circular(16),
      child: SectionCard(
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primaryLight,
              child: const Icon(
                Icons.sensors,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device['name'] ?? '-',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('เซนเซอร์: $sensors', style: AppTextStyles.caption),
                ],
              ),
            ),
            StatusPill(label: statusLabel, type: statusType),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// รายละเอียดอุปกรณ์แบบปลอดภัย — MAC address ซ่อนไว้เป็นค่าเริ่มต้น กดดูได้ถ้าจำเป็นจริงๆ
class _DeviceDetailSheet extends StatefulWidget {
  final Map<String, dynamic> device;
  const _DeviceDetailSheet({required this.device});

  @override
  State<_DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends State<_DeviceDetailSheet> {
  final deviceService = DeviceService();
  bool showFullMac = false;
  bool isReplacing = false;

  String _maskedMac(String mac) {
    final parts = mac.split(':');
    if (parts.length != 6) return mac;
    return '${parts[0]}:${parts[1]}:XX:XX:XX:${parts[5]}';
  }

  Future<void> _showReplaceDialog() async {
    final macController = TextEditingController();
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('เปลี่ยน ESP32'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ใช้ตอน ESP32 ตัวเดิมเสีย แต่ sensor ยังใช้ได้ดี — ประวัติข้อมูลทั้งหมดของอุปกรณ์นี้จะยังอยู่ต่อเนื่อง ไม่หายไปไหน',
                style: AppTextStyles.bodySecondary,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: macController,
                decoration: const InputDecoration(
                  labelText: 'MAC Address ของบอร์ดใหม่',
                  hintText: 'AA:BB:CC:DD:EE:FF',
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                setDialogState(() => errorText = null);
                final error = await deviceService.replaceMac(
                  deviceId: '${widget.device['device_id']}',
                  newMacAddress: macController.text.trim(),
                );
                if (error != null) {
                  setDialogState(() => errorText = error);
                  return;
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text(
                'ยืนยันเปลี่ยน',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      // เรื่องสำคัญ ใช้ dialog ให้ผู้ใช้กดตกลงรับทราบก่อน
      await AppFeedback.successDialog(
        context,
        'เปลี่ยน ESP32 สำเร็จ\nรอบอร์ดใหม่เชื่อมต่อครั้งแรก',
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        true,
      ); // ปิด bottom sheet แล้วบอก parent ให้ reload
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final mac = '${device['mac_address'] ?? '-'}';
    final sensors = (device['sensors'] as List?)?.join(', ') ?? '-';

    // SafeArea กันปุ่มล่างสุดโดน system nav bar บัง
    // SingleChildScrollView กันเนื้อหาล้นจอบนเครื่องจอเล็ก
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device['name'] ?? '-', style: AppTextStyles.heading),
            const SizedBox(height: 16),
            _detailRow(
              'เซนเซอร์',
              sensors.isEmpty ? 'ยังไม่ทราบ (รอเชื่อมต่อครั้งแรก)' : sensors,
            ),
            _detailRow(
              'ข้อมูลล่าสุด',
              formatThaiDateTime(device['last_seen_at']),
            ),
            _detailRow(
              'เชื่อมต่อเมื่อ',
              formatThaiDateTime(device['paired_at']),
            ),
            if (device['last_error'] != null)
              _detailRow('ข้อผิดพลาดล่าสุด', '${device['last_error']}'),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('MAC Address', style: AppTextStyles.bodySecondary),
                const SizedBox(width: 8),
                Text(
                  showFullMac ? mac : _maskedMac(mac),
                  style: AppTextStyles.body.copyWith(fontFamily: 'monospace'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => showFullMac = !showFullMac),
                  child: Text(showFullMac ? 'ซ่อน' : 'แสดง'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'แสดงเฉพาะเมื่อจำเป็น เช่น ตอนติดต่อขอความช่วยเหลือทางเทคนิค',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 16),
            // ปุ่มเดียว แสดงเฉพาะคนที่มีสิทธิ์จัดการอุปกรณ์
            if (FarmPermissions.of('${device['farm_id']}').canManageDevices)
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _showReplaceDialog,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('เปลี่ยน ESP32 (บอร์ดเสีย)'),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: AppTextStyles.bodySecondary),
          ),
          Expanded(child: Text(value, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}