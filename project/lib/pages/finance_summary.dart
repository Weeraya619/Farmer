import 'package:flutter/material.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import '/widgets/header.dart';
import '/widgets/card.dart';
import '/services/finance_service.dart';

enum _PeriodType { month, quarter, year }

const _thaiMonths = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
];

const _thaiMonthsShort = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

/// หน้าดูสรุปรายรับ-รายจ่าย
/// ด้านบน: กราฟแท่งกำไร/ขาดทุนรายเดือนของทั้งปีที่กำลังดูอยู่ (ไม่ผูกกับตัวเลือกเดือน/ไตรมาส/ปีด้านล่าง)
/// ด้านล่าง: สรุปยอด + รายการย่อย แยกดูได้ตามเดือน/ไตรมาส/ปีตามที่เลือก
/// ตอนเปลี่ยนช่วงเวลา ข้อมูลเก่าจะค้างอยู่จนกว่าข้อมูลใหม่จะมาถึง ไม่ล้างจอเป็นหน้าเปล่าๆ ก่อน
class FinanceSummaryPage extends StatefulWidget {
  final String farmId;
  const FinanceSummaryPage({super.key, required this.farmId});

  @override
  State<FinanceSummaryPage> createState() => _FinanceSummaryPageState();
}

class _FinanceSummaryPageState extends State<FinanceSummaryPage> {
  final financeService = FinanceService();

  _PeriodType periodType = _PeriodType.month;
  DateTime anchor = DateTime.now();

  List<Map<String, dynamic>> entries = [];
  List<double> monthlyProfit = List.filled(12, 0); // กำไร/ขาดทุนสุทธิ 12 เดือนของปีที่ดูอยู่
  bool isLoadingList = true;
  bool isLoadingChart = true;

  @override
  void initState() {
    super.initState();
    _loadList();
    _loadChart();
  }

  DateTimeRange get _range {
    switch (periodType) {
      case _PeriodType.month:
        final start = DateTime(anchor.year, anchor.month, 1);
        final end = DateTime(anchor.year, anchor.month + 1, 0);
        return DateTimeRange(start: start, end: end);
      case _PeriodType.quarter:
        final q = (anchor.month - 1) ~/ 3;
        final startMonth = q * 3 + 1;
        final start = DateTime(anchor.year, startMonth, 1);
        final end = DateTime(anchor.year, startMonth + 3, 0);
        return DateTimeRange(start: start, end: end);
      case _PeriodType.year:
        return DateTimeRange(start: DateTime(anchor.year, 1, 1), end: DateTime(anchor.year, 12, 31));
    }
  }

  String get _periodLabel {
    final buddhistYear = anchor.year + 543;
    switch (periodType) {
      case _PeriodType.month:
        return '${_thaiMonths[anchor.month - 1]} $buddhistYear';
      case _PeriodType.quarter:
        final q = ((anchor.month - 1) ~/ 3) + 1;
        return 'ไตรมาส $q ปี $buddhistYear';
      case _PeriodType.year:
        return 'ปี $buddhistYear';
    }
  }

  int get _chartYear => anchor.year;

  void _shiftPeriod(int direction) {
    final previousYear = anchor.year;
    setState(() {
      switch (periodType) {
        case _PeriodType.month:
          anchor = DateTime(anchor.year, anchor.month + direction, 1);
        case _PeriodType.quarter:
          anchor = DateTime(anchor.year, anchor.month + (direction * 3), 1);
        case _PeriodType.year:
          anchor = DateTime(anchor.year + direction, anchor.month, 1);
      }
    });
    _loadList();
    if (anchor.year != previousYear) _loadChart(); // ข้ามปี ต้องโหลดกราฟใหม่ด้วย
  }

  Future<void> _loadList() async {
    setState(() => isLoadingList = true);
    final range = _range;
    final data = await financeService.getFinances(
      widget.farmId,
      from: range.start.toIso8601String().split('T').first,
      to: range.end.toIso8601String().split('T').first,
    );
    if (!mounted) return;
    setState(() {
      entries = data;
      isLoadingList = false;
    });
  }

  Future<void> _loadChart() async {
    setState(() => isLoadingChart = true);
    final year = _chartYear;
    final data = await financeService.getFinances(
      widget.farmId,
      from: '$year-01-01',
      to: '$year-12-31',
    );
    if (!mounted) return;

    final profits = List.filled(12, 0.0);
    for (final e in data) {
      final dateStr = '${e['record_date'] ?? ''}';
      final month = int.tryParse(dateStr.length >= 7 ? dateStr.substring(5, 7) : '');
      if (month == null || month < 1 || month > 12) continue;
      final income = _num(e['cow_sale']);
      final expense = _num(e['cow_purchase']) + _num(e['feed']) + _num(e['medicine']);
      profits[month - 1] += income - expense;
    }

    setState(() {
      monthlyProfit = profits;
      isLoadingChart = false;
    });
  }

  double _num(dynamic v) => double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final totalIncome = entries.fold<double>(0, (sum, e) => sum + _num(e['cow_sale']));
    final totalExpense = entries.fold<double>(
      0,
      (sum, e) => sum + _num(e['cow_purchase']) + _num(e['feed']) + _num(e['medicine']),
    );
    final profit = totalIncome - totalExpense;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(farmName: 'ดูรายรับ-รายจ่าย', farmId: widget.farmId),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([_loadList(), _loadChart()]);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: 'กำไร/ขาดทุนรายเดือน ปี ${_chartYear + 543}',
                child: _MonthlyProfitChart(values: monthlyProfit, isLoading: isLoadingChart),
              ),
              const SizedBox(height: 4),
              _periodTypeSelector(),
              const SizedBox(height: 10),
              _periodNav(),
              const SizedBox(height: 4),
              // แถบโหลดบางๆ แทนที่จะล้างหน้าเป็น spinner เต็มจอ กันคนสูงอายุตกใจ
              SizedBox(
                height: 3,
                child: isLoadingList
                    ? const LinearProgressIndicator(minHeight: 3, backgroundColor: Colors.transparent)
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              SectionCard(
                child: Column(
                  children: [
                    _summaryRow('รายรับรวม', totalIncome, AppColors.success),
                    const SizedBox(height: 8),
                    _summaryRow('รายจ่ายรวม', totalExpense, AppColors.danger),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: AppColors.border),
                    ),
                    _summaryRow(
                      profit >= 0 ? 'กำไรสุทธิ' : 'ขาดทุนสุทธิ',
                      profit.abs(),
                      profit >= 0 ? AppColors.success : AppColors.danger,
                      bold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('รายการทั้งหมด', style: AppTextStyles.bodySecondary),
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty && !isLoadingList)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('ไม่มีรายการในช่วงนี้', style: AppTextStyles.bodySecondary)),
                )
              else
                SectionCard(
                  child: Column(children: entries.map(_entryRow).toList()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodTypeSelector() {
    return Row(
      children: [
        Expanded(child: _typeButton('รายเดือน', _PeriodType.month)),
        const SizedBox(width: 8),
        Expanded(child: _typeButton('รายไตรมาส', _PeriodType.quarter)),
        const SizedBox(width: 8),
        Expanded(child: _typeButton('รายปี', _PeriodType.year)),
      ],
    );
  }

  Widget _typeButton(String label, _PeriodType type) {
    final selected = periodType == type;
    return InkWell(
      onTap: isLoadingList
          ? null
          : () {
              setState(() => periodType = type);
              _loadList();
            },
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

  Widget _periodNav() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(onPressed: isLoadingList ? null : () => _shiftPeriod(-1), icon: const Icon(Icons.chevron_left)),
        Text(_periodLabel, style: AppTextStyles.subheading),
        IconButton(onPressed: isLoadingList ? null : () => _shiftPeriod(1), icon: const Icon(Icons.chevron_right)),
      ],
    );
  }

  Widget _summaryRow(String label, double amount, Color color, {bool bold = false}) {
    return Row(
      children: [
        Text(label, style: bold ? AppTextStyles.subheading : AppTextStyles.body),
        const Spacer(),
        Text(
          '${amount.toStringAsFixed(0)} บาท',
          style: (bold ? AppTextStyles.subheading : AppTextStyles.body).copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _entryRow(Map<String, dynamic> entry) {
    String label;
    double amount;
    Color color;

    if (_num(entry['cow_sale']) > 0) {
      label = 'ขายวัว';
      amount = _num(entry['cow_sale']);
      color = AppColors.success;
    } else if (_num(entry['cow_purchase']) > 0) {
      label = 'ซื้อวัว';
      amount = _num(entry['cow_purchase']);
      color = AppColors.danger;
    } else if (_num(entry['feed']) > 0) {
      label = entry['note'] != null && entry['note'] != '' ? entry['note'] : 'ค่าอาหาร';
      amount = _num(entry['feed']);
      color = AppColors.danger;
    } else {
      label = entry['note'] != null && entry['note'] != '' ? entry['note'] : 'ค่ายา';
      amount = _num(entry['medicine']);
      color = AppColors.danger;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.body),
                Text('${entry['record_date'] ?? '-'}', style: AppTextStyles.caption),
              ],
            ),
          ),
          Text(
            '${color == AppColors.success ? '+' : '-'}${amount.toStringAsFixed(0)} บาท',
            style: AppTextStyles.body.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// กราฟแท่งกำไร/ขาดทุนสุทธิ 12 เดือน วาดด้วย widget ธรรมดา ไม่พึ่ง package เสริม
/// แท่งสีเขียวขึ้นด้านบนเส้นกลาง = กำไร, แท่งสีแดงลงด้านล่างเส้นกลาง = ขาดทุน
class _MonthlyProfitChart extends StatelessWidget {
  final List<double> values; // 12 ค่า ม.ค.-ธ.ค.
  final bool isLoading;

  const _MonthlyProfitChart({required this.values, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final maxAbs = values.map((v) => v.abs()).fold<double>(0, (a, b) => a > b ? a : b);
    const chartHeight = 140.0;
    const dividerHeight = 1.0;
    const halfHeight = (chartHeight - dividerHeight) / 2;

    return Opacity(
      opacity: isLoading ? 0.4 : 1,
      child: SizedBox(
        height: chartHeight + 20,
        child: Column(
          children: [
            SizedBox(
              height: chartHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(12, (i) {
                  final value = values[i];
                  final barHeight = maxAbs == 0 ? 0.0 : (value.abs() / maxAbs) * (halfHeight - 4);
                  final isProfit = value >= 0;
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: halfHeight,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: isProfit ? barHeight : 0,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                          ),
                        ),
                        Container(height: dividerHeight, color: AppColors.border),
                        SizedBox(
                          height: halfHeight,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              height: isProfit ? 0 : barHeight,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: List.generate(12, (i) {
                return Expanded(
                  child: Text(
                    _thaiMonthsShort[i],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}