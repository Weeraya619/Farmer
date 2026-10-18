import 'package:flutter/material.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import '/widgets/header.dart';
import '/widgets/card.dart';
import '/services/cow_service.dart';
import '/services/farm_permissions.dart';

enum _ViewTab { active, sold }

/// หน้าดูภาพรวมวัวในฟาร์ม — การ์ดสรุปด้านบน + แท็บแยกวัวที่ยังอยู่/ขายแล้ว
/// วัวที่ยังอยู่ในฟาร์มแยกเป็นล็อต (ตามวันที่ซื้อ) + ส่วนวัวที่มีอยู่แล้ว เรียงใหม่→เก่าทั้งคู่
/// วัวที่ขายแล้วเรียงตามวันที่ขาย ใหม่→เก่า ไม่แยกล็อต
/// พนักงานที่ไม่มีสิทธิ์การเงินจะไม่เห็นราคาซื้อ/ขาย (backend ตัดฟิลด์ราคาออกอยู่แล้ว)
class CowListPage extends StatefulWidget {
  final String farmId;
  const CowListPage({super.key, required this.farmId});

  @override
  State<CowListPage> createState() => _CowListPageState();
}

class _CowListPageState extends State<CowListPage> {
  final cowService = CowService();

  List<Map<String, dynamic>> allCows = [];
  bool isLoading = true;
  _ViewTab tab = _ViewTab.active;

  // เห็นราคาได้เฉพาะคนที่มีสิทธิ์การเงิน (backend ก็ตัดฟิลด์ราคาออกให้คนที่ไม่มีสิทธิ์อยู่แล้ว)
  bool get _canSeePrice => FarmPermissions.of(widget.farmId).canFinance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    final cows = await cowService.getCows(widget.farmId);
    if (!mounted) return;
    setState(() {
      allCows = cows;
      isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _activeCows =>
      allCows.where((c) => c['sale_date'] == null).toList();

  List<Map<String, dynamic>> get _soldCows {
    final sold = allCows.where((c) => c['sale_date'] != null).toList();
    sold.sort((a, b) => '${b['sale_date']}'.compareTo('${a['sale_date']}'));
    return sold;
  }

  // จัดกลุ่มวัว active ที่ซื้อมาใหม่เป็นล็อตตามวันที่ซื้อ เรียงใหม่สุดก่อน
  Map<String, List<Map<String, dynamic>>> get _activeLots {
    final purchased = _activeCows.where((c) => c['origin_type'] == 'ซื้อมาใหม่').toList();
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final cow in purchased) {
      final date = '${cow['purchase_date'] ?? 'ไม่ระบุวันที่'}';
      grouped.putIfAbsent(date, () => []).add(cow);
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in sortedKeys) k: grouped[k]!};
  }

  List<Map<String, dynamic>> get _activeExisting =>
      _activeCows.where((c) => c['origin_type'] != 'ซื้อมาใหม่').toList();

  /// แปลงตัวเลขราคาเป็นข้อความมีจุลภาค เช่น 23000 -> 23,000
  /// คืน null ถ้าไม่มีราคา (ฟิลด์ว่าง หรือ backend ตัดทิ้งเพราะไม่มีสิทธิ์)
  String? _fmtMoney(dynamic v) {
    if (v == null) return null;
    final n = num.tryParse('$v');
    if (n == null) return null;
    return n.round().toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (m) => ',',
        );
  }

  /// บรรทัดราคาของวัวแต่ละตัว เช่น "ซื้อ 23,000 บาท • ขาย 32,000 บาท"
  /// ไม่มีสิทธิ์ดูราคา หรือไม่มีราคาทั้งคู่ (เช่นวัวที่มีอยู่แล้ว) จะคืน null
  String? _priceLine(Map<String, dynamic> cow) {
    if (!_canSeePrice) return null;
    final buy = _fmtMoney(cow['purchase_price']);
    final sell = _fmtMoney(cow['sale_price']);
    final parts = [
      if (buy != null) 'ซื้อ $buy บาท',
      if (sell != null) 'ขาย $sell บาท',
    ];
    return parts.isEmpty ? null : parts.join(' • ');
  }

  Future<void> _showEditDialog(Map<String, dynamic> cow) async {
    final nicknameController = TextEditingController(text: cow['nickname'] ?? '');
    String status = cow['death_date'] != null
        ? 'ตาย'
        : (cow['health_status'] == 'ป่วย' ? 'ป่วย' : 'ปกติ');
    final purchasePrice = _canSeePrice ? _fmtMoney(cow['purchase_price']) : null;
    final salePrice = _canSeePrice ? _fmtMoney(cow['sale_price']) : null;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('แก้ไขข้อมูลวัว'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nicknameController,
                decoration: const InputDecoration(labelText: 'ชื่อเล่น'),
              ),
              const SizedBox(height: 16),
              Text('สถานะ', style: AppTextStyles.bodySecondary),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: ['ปกติ', 'ป่วย', 'ตาย'].map((s) {
                  return ChoiceChip(
                    label: Text(s),
                    selected: status == s,
                    onSelected: (_) => setDialogState(() => status = s),
                  );
                }).toList(),
              ),
              if (purchasePrice != null || salePrice != null) ...[
                const SizedBox(height: 16),
                Text('ราคา', style: AppTextStyles.bodySecondary),
                const SizedBox(height: 4),
                if (purchasePrice != null)
                  Text('ราคาซื้อ $purchasePrice บาท', style: AppTextStyles.body),
                if (salePrice != null)
                  Text('ราคาขาย $salePrice บาท', style: AppTextStyles.body),
                const SizedBox(height: 2),
                Text('ราคาเป็นค่าเฉลี่ยต่อตัวจากยอดรวมที่บันทึก', style: AppTextStyles.caption),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                final error = await cowService.updateCow(
                  cowId: '${cow['cow_id']}',
                  nickname: nicknameController.text.trim(),
                  healthStatus: status == 'ป่วย' ? 'ป่วย' : 'ปกติ',
                  isDead: status == 'ตาย',
                );
                if (!context.mounted) return;
                if (error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                  Navigator.pop(context, false);
                } else {
                  Navigator.pop(context, true);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('บันทึก', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == true) _load();
  }

  String _cowRowLabel(Map<String, dynamic> cow) {
    final gender = cow['gender'] == 'male' ? 'ตัวผู้' : 'ตัวเมีย';
    final pregnancy = cow['pregnancy_status'] == 'ท้อง' ? ' • ท้อง' : '';
    final nickname = (cow['nickname'] != null && cow['nickname'] != '') ? cow['nickname'] : null;
    return [if (nickname != null) nickname, gender].join(' • ') + pregnancy;
  }

  @override
  Widget build(BuildContext context) {
    final aliveActive = _activeCows.where((c) => c['death_date'] == null).toList();
    final total = aliveActive.length;
    final male = aliveActive.where((c) => c['gender'] == 'male').length;
    final female = aliveActive.where((c) => c['gender'] == 'female').length;
    final pregnant = aliveActive.where((c) => c['pregnancy_status'] == 'ท้อง').length;

    // ขายแล้ว = ขายแล้วและไม่ได้ตาย (วัวตายที่ขายแล้วไปนับในช่อง "ตาย (ขายแล้ว)")
    final soldAlive = allCows.where((c) => c['sale_date'] != null && c['death_date'] == null).length;
    final deadSold = allCows.where((c) => c['death_date'] != null && c['sale_date'] != null).length;
    final deadNotSold = allCows.where((c) => c['death_date'] != null && c['sale_date'] == null).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(farmName: 'ข้อมูลวัวในฟาร์ม', farmId: widget.farmId),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SectionCard(
                      title: 'ภาพรวมวันนี้',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _summaryStat('ทั้งหมด', total),
                              _summaryStat('ตัวผู้', male),
                              _summaryStat('ตัวเมีย', female),
                              _summaryStat('ท้อง', pregnant),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1, color: AppColors.border),
                          ),
                          Row(
                            children: [
                              _summaryStat('ขายแล้ว', soldAlive),
                              _summaryStat('ตาย (ขายแล้ว)', deadSold),
                              _summaryStat('ตาย (ยังไม่ขาย)', deadNotSold),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _tabButton('อยู่ในฟาร์ม (${_activeCows.length})', _ViewTab.active)),
                        const SizedBox(width: 8),
                        Expanded(child: _tabButton('ขายแล้ว (${_soldCows.length})', _ViewTab.sold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (tab == _ViewTab.active) ..._buildActiveList() else ..._buildSoldList(),
                    const SizedBox(height: 60), // กันปุ่ม + บังรายการล่างสุด
                  ],
                ),
              ),
      ),
    );
  }

  Widget _summaryStat(String label, int value) {
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: AppTextStyles.metricValue),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }

  Widget _tabButton(String label, _ViewTab value) {
    final selected = tab == value;
    return InkWell(
      onTap: () => setState(() => tab = value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: AppTextStyles.body.copyWith(color: selected ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ),
    );
  }

  List<Widget> _buildActiveList() {
    if (_activeCows.isEmpty) {
      return [Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('ยังไม่มีวัวในฟาร์ม', style: AppTextStyles.bodySecondary)))];
    }

    final widgets = <Widget>[];

    for (final entry in _activeLots.entries) {
      widgets.add(SectionCard(
        title: 'ล็อตวันที่ ${entry.key} (${entry.value.length} ตัว)',
        child: Column(children: entry.value.map(_cowRow).toList()),
      ));
    }

    if (_activeExisting.isNotEmpty) {
      widgets.add(SectionCard(
        title: 'วัวที่มีอยู่แล้ว (${_activeExisting.length} ตัว)',
        child: Column(children: _activeExisting.map(_cowRow).toList()),
      ));
    }

    return widgets;
  }

  List<Widget> _buildSoldList() {
    if (_soldCows.isEmpty) {
      return [Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('ยังไม่มีวัวที่ขาย', style: AppTextStyles.bodySecondary)))];
    }
    return [
      SectionCard(
        child: Column(
          children: _soldCows.map((cow) {
            // พนักงานที่ปิดการเงินไม่เห็นราคา (_priceLine คืน null ให้เอง)
            final price = _priceLine(cow);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              isThreeLine: price != null,
              title: Text(_cowRowLabel(cow), style: AppTextStyles.body),
              subtitle: Text(
                'ขายเมื่อ ${cow['sale_date']}${price != null ? '\n$price' : ''}',
                style: AppTextStyles.caption,
              ),
            );
          }).toList(),
        ),
      ),
    ];
  }

  Widget _cowRow(Map<String, dynamic> cow) {
    final isDead = cow['death_date'] != null;
    final isSick = cow['health_status'] == 'ป่วย';
    final price = _priceLine(cow);

    return InkWell(
      onTap: () => _showEditDialog(cow),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(_cowRowLabel(cow), style: AppTextStyles.body)),
                      if (isDead)
                        _statusTag('ตาย', AppColors.dangerBg, AppColors.danger)
                      else if (isSick)
                        _statusTag('ป่วย', AppColors.warningBg, AppColors.warning),
                    ],
                  ),
                  if (price != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(price, style: AppTextStyles.caption),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _statusTag(String label, Color bg, Color fg) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}